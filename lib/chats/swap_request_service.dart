import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chatservice.dart';

/// Handles the swap-request lifecycle:
/// create (pending, with dedup check) → accept (creates chat, sets intent)
/// / decline, plus an "active swaps" stream so an accepted chat stays
/// reachable even if the user backs out without sending a message, and
/// logging completed OR cancelled exchanges to history.
///
/// FIRESTORE RULES NOTE:
///   List-style queries (acceptedRequestsForProduct, myActiveSwaps, the
///   dedup check) all filter on `participants` (arrayContains) because
///   Firestore security rules can only authorize a *list* query if the rule
///   can be proven true from the query's own filters — it can't evaluate
///   `fromUserId == auth.uid || toUserId == auth.uid` per document before
///   deciding whether to run the query. `participants` lets the rule be
///   `request.auth.uid in resource.data.participants`, which Firestore CAN
///   verify directly against the query filter.
///
/// FIRESTORE INDEXES NEEDED (Console → Firestore → Indexes, or
/// firestore.indexes.json — Firestore will also throw a console error with
/// a direct "create index" link the first time each query runs):
///   swapRequests: (toUserId ASC, status ASC, createdAt DESC)
///   swapRequests: (fromUserId ASC, createdAt DESC)
///   swapRequests: (participants ARRAY_CONTAINS, fromUserId ASC, listedProduct.id ASC, status ASC)
///   swapRequests: (participants ARRAY_CONTAINS, status ASC, respondedAt DESC)
///   exchangeHistory: (participants ARRAY_CONTAINS, completedAt DESC)
///
///   NOTE: the third index above changed shape (added `fromUserId ASC`) as
///   part of the "same user can send multiple requests for the same
///   product" fix — see getMyActiveRequestForProduct / _hasActiveRequest
///   below. If you already deployed the old 3-field version, Firestore
///   will prompt for a new composite index the first time this runs;
///   follow the console link (or update firestore.indexes.json) rather
///   than reusing the old index.
///
/// FIRESTORE RULES NEEDED for swapRequests:
///   match /swapRequests/{requestId} {
///     allow read: if request.auth != null &&
///       request.auth.uid in resource.data.participants;
///     allow create: if request.auth != null &&
///       request.auth.uid == request.resource.data.fromUserId &&
///       request.resource.data.participants ==
///         [request.resource.data.fromUserId, request.resource.data.toUserId];
///     allow update: if request.auth != null &&
///       request.auth.uid in resource.data.participants;
///   }
class SwapRequestService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _chatService = ChatService();

  // ── CREATE ────────────────────────────────────────────────────────────────

  /// FIX(dedup): returns MY OWN pending/accepted request for this product,
  /// if one exists — as a full data map (with its doc id under 'id'),
  /// not just a bool. This is what lets the product page show "Request
  /// already sent" / "Continue chat" up front, instead of only detecting
  /// the duplicate after the user has re-selected an item and gone
  /// through the whole swap + safety-sheet flow again.
  ///
  /// Filters on `fromUserId == me` in addition to `participants
  /// arrayContains me` so this only ever matches requests *I sent* — not
  /// a request someone else sent *to* me for the same product (which
  /// would also have me in `participants`). That case shouldn't currently
  /// be reachable (sellers are blocked from swapping their own listing),
  /// but the explicit filter keeps this method correct even if that
  /// changes later, and makes the intent unambiguous at the call site.
  Future<Map<String, dynamic>?> getMyActiveRequestForProduct(
      String productId) async {
    if (productId.isEmpty) return null; // can't look up without a real id
    final me = _auth.currentUser?.uid;
    if (me == null) return null;

    final results = await Future.wait([
      _firestore
          .collection('swapRequests')
          .where('participants', arrayContains: me)
          .where('fromUserId', isEqualTo: me)
          .where('listedProduct.id', isEqualTo: productId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get(),
      _firestore
          .collection('swapRequests')
          .where('participants', arrayContains: me)
          .where('fromUserId', isEqualTo: me)
          .where('listedProduct.id', isEqualTo: productId)
          .where('status', isEqualTo: 'accepted')
          .limit(1)
          .get(),
    ]);

    for (final snap in results) {
      if (snap.docs.isNotEmpty) {
        final doc = snap.docs.first;
        return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
      }
    }
    return null;
  }

  /// Returns true if I already have a pending or accepted swap request for
  /// this product. Kept as a server-side backstop inside createSwapRequest
  /// (race conditions, stale UI, a second device, etc.) — the product page
  /// now also checks this up front via getMyActiveRequestForProduct so the
  /// user isn't even offered the flow again in the common case.
  Future<bool> _hasActiveRequest(String productId) async {
    final existing = await getMyActiveRequestForProduct(productId);
    return existing != null;
  }

  /// Throws if I already have an active (pending/accepted) request for this
  /// product — prevents spamming the same seller from repeat visits to the
  /// product page.
  Future<String> createSwapRequest({
    required String toUserId,
    required String toUserName,
    required String toUserImage,
    required Map<String, dynamic> listedProduct, // must include a real 'id'
    required List<Map<String, dynamic>> offeredProducts,
  }) async {
    final me = _auth.currentUser!;
    final productId = (listedProduct['id'] as String?) ?? '';

    if (await _hasActiveRequest(productId)) {
      throw Exception('You already have an active swap request for this item.');
    }

    final meDoc = await _firestore.collection('users').doc(me.uid).get();
    final meData = meDoc.data();
    final meName = (meData?['name'] as String?) ?? 'User';
    final meImage = (meData?['profileImage'] as String?) ?? '';

    final ref = await _firestore.collection('swapRequests').add({
      'fromUserId': me.uid,
      'fromUserName': meName,
      'fromUserImage': meImage,
      'toUserId': toUserId,
      'toUserName': toUserName,
      'toUserImage': toUserImage,
      // Required so list-style queries can be authorized by a Firestore
      // rule without per-document evaluation.
      'participants': [me.uid, toUserId],
      'listedProduct': listedProduct,
      'offeredProducts': offeredProducts,
      // pending | accepted | declined | completed | cancelled
      'status': 'pending',
      'chatId': null,
      'createdAt': FieldValue.serverTimestamp(),
      'respondedAt': null,
      'completedAt': null,
    });
    return ref.id;
  }

  // ── STREAMS ───────────────────────────────────────────────────────────────

  /// Requests other people have sent ME, awaiting my response.
  Stream<QuerySnapshot> incomingRequests() {
    final uid = _auth.currentUser!.uid;
    return _firestore
        .collection('swapRequests')
        .where('toUserId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Requests I've sent, with their current status.
  Stream<QuerySnapshot> sentRequests() {
    final uid = _auth.currentUser!.uid;
    return _firestore
        .collection('swapRequests')
        .where('fromUserId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Accepted swaps where I'm a participant on EITHER side — this is the
  /// reentry point so an accepted chat is never "lost" just because the
  /// user backed out without sending a message. Once a swap is resolved
  /// (marked successful OR cancelled) its status changes away from
  /// 'accepted' so it drops out of this list and shows up in
  /// myExchangeHistory() instead.
  Stream<QuerySnapshot> myActiveSwaps() {
    final uid = _auth.currentUser!.uid;
    return _firestore
        .collection('swapRequests')
        .where('participants', arrayContains: uid)
        .where('status', isEqualTo: 'accepted')
        .orderBy('respondedAt', descending: true)
        .snapshots();
  }

  /// Accepted requests tied to a specific product where I'm a participant
  /// (either side).
  Stream<QuerySnapshot> acceptedRequestsForProduct(String productId) {
    final uid = _auth.currentUser!.uid;
    return _firestore
        .collection('swapRequests')
        .where('listedProduct.id', isEqualTo: productId)
        .where('status', isEqualTo: 'accepted')
        .where('participants', arrayContains: uid)
        .snapshots();
  }

  /// Both completed AND cancelled swaps land here (distinguished by the
  /// `status` field on the exchangeHistory doc) so ExchangeHistoryPage can
  /// show a single combined timeline.
  Stream<QuerySnapshot> myExchangeHistory() {
    final uid = _auth.currentUser!.uid;
    return _firestore
        .collection('exchangeHistory')
        .where('participants', arrayContains: uid)
        .orderBy('completedAt', descending: true)
        .snapshots();
  }

  // ── ACCEPT / DECLINE ──────────────────────────────────────────────────────

  /// Receiver accepts → creates/reuses the chat, writes the swap intent
  /// (same shape ChatScreen already renders), marks request accepted.
  /// Returns the chatId so the caller can navigate straight there.
  Future<String> acceptRequest(String requestId) async {
    final doc = await _firestore.collection('swapRequests').doc(requestId).get();
    if (!doc.exists) throw Exception('Request no longer exists.');
    final data = doc.data()!;
    if (data['status'] != 'pending') throw Exception('Request already handled.');

    final fromUserId = data['fromUserId'] as String;
    final toUserId = data['toUserId'] as String;
    final myUid = _auth.currentUser!.uid;
    final otherUid = myUid == fromUserId ? toUserId : fromUserId;

    // myUid MUST be first — getOrCreateChat's query filters by
    // arrayContains on this param, and Firestore rules require that
    // value to be request.auth.uid or the query itself gets denied.
    final chatId = await _chatService.getOrCreateChat(myUid, otherUid);

    await _firestore.collection('chats').doc(chatId).set({
      'intent': {
        'type': 'swap',
        'listedProduct': data['listedProduct'],
        'swapProducts': data['offeredProducts'],
        'updatedAt': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));

    await _firestore.collection('swapRequests').doc(requestId).update({
      'status': 'accepted',
      'chatId': chatId,
      'respondedAt': FieldValue.serverTimestamp(),
    });

    return chatId;
  }

  Future<void> declineRequest(String requestId) async {
    await _firestore.collection('swapRequests').doc(requestId).update({
      'status': 'declined',
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── EXCHANGE RESOLUTION (successful / cancelled) ────────────────────────

  /// Marks an accepted swap as successfully completed. Writes a matching
  /// exchangeHistory doc (status: 'completed') and flips the swapRequests
  /// doc's status so it drops out of myActiveSwaps().
  Future<void> markExchangeSuccessful({
    required String requestId,
    required String otherUserId,
    required String otherUserName,
    required Map<String, dynamic> listedProduct,
    required List<Map<String, dynamic>> offeredProducts,
    String? chatId,
  }) async {
    final me = _auth.currentUser!;
    final myName = me.displayName ?? 'You';

    await _firestore.collection('exchangeHistory').add({
      'participants': [me.uid, otherUserId],
      'participantNames': {me.uid: myName, otherUserId: otherUserName},
      'requestId': requestId,
      'chatId': chatId,
      'listedProduct': listedProduct,
      'offeredProducts': offeredProducts,
      // Distinguishes this from a cancelled entry in ExchangeHistoryPage.
      'status': 'completed',
      'completedBy': me.uid,
      'completedAt': FieldValue.serverTimestamp(),
    });

    await _firestore.collection('swapRequests').doc(requestId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  /// NEW: cancels an accepted swap instead of completing it (either side can
  /// cancel). Mirrors markExchangeSuccessful's shape so both show up in the
  /// same myExchangeHistory() stream, just tagged status: 'cancelled'.
  Future<void> cancelSwap({
    required String requestId,
    required String otherUserId,
    required String otherUserName,
    required Map<String, dynamic> listedProduct,
    required List<Map<String, dynamic>> offeredProducts,
    String? chatId,
  }) async {
    final me = _auth.currentUser!;
    final myName = me.displayName ?? 'You';

    await _firestore.collection('exchangeHistory').add({
      'participants': [me.uid, otherUserId],
      'participantNames': {me.uid: myName, otherUserId: otherUserName},
      'requestId': requestId,
      'chatId': chatId,
      'listedProduct': listedProduct,
      'offeredProducts': offeredProducts,
      'status': 'cancelled',
      // Reuse 'completedBy'/'completedAt' field names (rather than adding
      // cancelledBy/cancelledAt) so myExchangeHistory()'s single
      // orderBy('completedAt') keeps sorting both kinds of entries.
      'completedBy': me.uid,
      'completedAt': FieldValue.serverTimestamp(),
    });

    await _firestore.collection('swapRequests').doc(requestId).update({
      'status': 'cancelled',
      'completedAt': FieldValue.serverTimestamp(),
    });
  }
}