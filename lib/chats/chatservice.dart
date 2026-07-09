import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ChatService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;

  // ── CREATE / GET CHAT ─────────────────────────────────────────────────────
  Future<String> getOrCreateChat(String user1, String user2) async {
    final query = await _firestore
        .collection('chats')
        .where('participants', arrayContains: user1)
        .get();

    for (var doc in query.docs) {
      final participants = List<String>.from(doc['participants'] ?? []);
      if (participants.contains(user2)) return doc.id;
    }

    final newChat = await _firestore.collection('chats').add({
      'participants': [user1, user2],
      'lastMessage': '',
      'timestamp': FieldValue.serverTimestamp(),
      'typing': {},
    });
    return newChat.id;
  }

  // ── UPLOAD FILE ───────────────────────────────────────────────────────────
  Future<String> uploadFile({
    required File file,
    required String path,
    required Function(double) onProgress,
  }) async {
    final ref = _storage.ref().child(path);
    final uploadTask = ref.putFile(file);

    // Cancel the subscription after upload completes to avoid a memory leak
    // when the caller's widget is disposed before the task finishes.
    final sub = uploadTask.snapshotEvents.listen((event) {
      final total = event.totalBytes;
      final transferred = event.bytesTransferred;
      if (total > 0) onProgress(transferred / total);
    });

    try {
      final snapshot = await uploadTask.whenComplete(() {});
      return await snapshot.ref.getDownloadURL();
    } finally {
      await sub.cancel();
    }
  }

  // ── SEND MESSAGE ──────────────────────────────────────────────────────────
  Future<void> sendMessage({
    required String chatId,
    required String receiverId,
    required String type,
    String? text,
    String? fileUrl,
    Map<String, dynamic>? extra,
    bool encrypted = false,
    String? plainTextPreview,
  }) async {
    final currentUser = _auth.currentUser!;
    final messageRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc();

    await messageRef.set({
      'senderId': currentUser.uid,
      'receiverId': receiverId,
      'type': type,
      'text': text ?? '',
      'fileUrl': fileUrl ?? '',
      'extra': extra ?? {},
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'sent',
      'encrypted': encrypted,
    });

    String preview;
    switch (type) {
      case 'text':
        preview = plainTextPreview ?? text ?? '';
        break;
      case 'image':
        preview = '📷 Photo';
        break;
      case 'video':
        preview = '🎥 Video';
        break;
      case 'audio':
        preview = '🎤 Voice message';
        break;
      case 'location':
        preview = '📍 Location';
        break;
      default:
        preview = '';
    }

    await _firestore.collection('chats').doc(chatId).update({
      'lastMessage': preview,
      'lastSenderId': currentUser.uid,
      'lastStatus': 'sent',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ── MARK SEEN ─────────────────────────────────────────────────────────────
  Future<void> markMessagesAsSeen(String chatId) async {
    final currentUser = _auth.currentUser!;
    final query = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('receiverId', isEqualTo: currentUser.uid)
        .where('status', isNotEqualTo: 'seen')
        .get();

    if (query.docs.isEmpty) return;

    // Firestore batch is limited to 500 ops — chunk if needed
    final chunks = <List<QueryDocumentSnapshot>>[];
    for (var i = 0; i < query.docs.length; i += 499) {
      chunks.add(query.docs.sublist(
          i, i + 499 > query.docs.length ? query.docs.length : i + 499));
    }
    for (final chunk in chunks) {
      final batch = _firestore.batch();
      for (var doc in chunk) {
        batch.update(doc.reference, {'status': 'seen'});
      }
      await batch.commit();
    }

    await _firestore.collection('chats').doc(chatId).update({
      'lastStatus': 'seen',
    });
  }

  // ── STREAMS ───────────────────────────────────────────────────────────────
  Stream<QuerySnapshot> getMessages(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> getUserChats() {
    final user = _auth.currentUser!;
    return _firestore
        .collection('chats')
        .where('participants', arrayContains: user.uid)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Stream<int> getUnseenCount(String chatId, String userId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('receiverId', isEqualTo: userId)
        .where('status', isNotEqualTo: 'seen')
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// Admin: counts messages NOT sent by admin that are unseen
  Stream<int> getUnseenCountAdmin(String chatId) {
    final adminUid = _auth.currentUser?.uid ?? '';
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('status', isNotEqualTo: 'seen')
        .snapshots()
        .map((snap) => snap.docs
        .where((d) => (d.data()['senderId'] ?? '') != adminUid)
        .length);
  }

  /// Admin: mark all non-admin messages in chat as seen (chunked batches).
  Future<void> markAllMessagesAsSeenAdmin(String chatId) async {
    final adminUid = _auth.currentUser?.uid ?? '';
    final query = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('status', isNotEqualTo: 'seen')
        .get();
    if (query.docs.isEmpty) return;

    // Filter to only non-admin messages, then chunk into batches of 499.
    final toUpdate = query.docs
        .where((d) => (d.data()['senderId'] ?? '') != adminUid)
        .toList();
    for (var i = 0; i < toUpdate.length; i += 499) {
      final chunk = toUpdate.sublist(
          i, i + 499 > toUpdate.length ? toUpdate.length : i + 499);
      final batch = _firestore.batch();
      for (var doc in chunk) {
        batch.update(doc.reference, {'status': 'seen'});
      }
      await batch.commit();
    }

    await _firestore
        .collection('chats')
        .doc(chatId)
        .update({'lastStatus': 'seen'});
  }

  // ── DELETE ────────────────────────────────────────────────────────────────
  Future<void> deleteMessages(String chatId, List<String> messageIds) async {
    // Chunk into batches of 499
    for (var i = 0; i < messageIds.length; i += 499) {
      final chunk = messageIds.sublist(
          i, i + 499 > messageIds.length ? messageIds.length : i + 499);
      final batch = _firestore.batch();
      for (final id in chunk) {
        batch.delete(_firestore
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .doc(id));
      }
      await batch.commit();
    }
  }

  /// Deletes all messages in the chat via batched writes, then deletes the chat doc.
  Future<void> deleteChat(String chatId) async {
    const batchSize = 499;
    final chatRef = _firestore.collection('chats').doc(chatId);
    QuerySnapshot messages;
    do {
      messages =
      await chatRef.collection('messages').limit(batchSize).get();
      if (messages.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final doc in messages.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } while (messages.docs.length == batchSize);
    await chatRef.delete();
  }

  // ── ADMIN LOOKUP ─────────────────────────────────────────────────────────
  static String? _cachedAdminUid;

  static Future<String?> getAdminUid() async {
    if (_cachedAdminUid != null) return _cachedAdminUid;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'admin')
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    _cachedAdminUid = snap.docs.first.id;
    return _cachedAdminUid;
  }

  /// For admin — ALL chats across all users, ordered by latest, with pagination
  Stream<QuerySnapshot> getAllChats({int limit = 30}) {
    return _firestore
        .collection('chats')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }

  // ── TYPING & PRESENCE ─────────────────────────────────────────────────────
  Future<void> setTyping(String chatId, String userId, bool typing) async {
    await _firestore.collection('chats').doc(chatId).set(
      {'typing': {userId: typing}},
      SetOptions(merge: true),
    );
  }

  Future<void> setUserPresence(String userId, {required bool online}) async {
    await _firestore.collection('users').doc(userId).set({
      'online': online,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ── REPORTS ───────────────────────────────────────────────────────────────

  /// Submit a report against [reportedUserId] from the current user.
  /// [reason] is a free-text explanation.
  Future<void> reportUser({
    required String reportedUserId,
    required String reportedUserName,
    required String chatId,
    required String reason,
    String? exampleMessageId,
  }) async {
    final reporter = _auth.currentUser!;

    // Auth's email/displayName can be null (phone auth, some Google flows),
    // so pull both from the reporter's Firestore profile as a backup —
    // we want name AND email shown separately in the admin panel, not
    // one falling back to the other.
    String reporterName = reporter.displayName ?? '';
    String reporterEmail = reporter.email ?? '';

    if (reporterName.isEmpty || reporterEmail.isEmpty) {
      try {
        final userDoc = await _firestore.collection('users').doc(reporter.uid).get();
        final userData = userDoc.data();
        if (reporterName.isEmpty) {
          reporterName = (userData?['name'] as String?) ??
              (userData?['displayName'] as String?) ??
              '';
        }
        if (reporterEmail.isEmpty) {
          reporterEmail = (userData?['email'] as String?) ?? '';
        }
      } catch (_) {
        // ignore — fields stay empty, UI will show a fallback label
      }
    }

    if (reporterName.isEmpty) reporterName = 'Unknown';
    if (reporterEmail.isEmpty) reporterEmail = reporter.phoneNumber ?? 'No email';

    await _firestore.collection('reports').add({
      'reporterId': reporter.uid,
      'reporterName': reporterName,
      'reporterEmail': reporterEmail,
      'reportedUserId': reportedUserId,
      'reportedUserName': reportedUserName,
      'chatId': chatId,
      'reason': reason,
      'exampleMessageId': exampleMessageId ?? '',
      'status': 'pending', // pending | reviewed | dismissed | actioned
      'adminNote': '',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Admin: stream of all reports ordered by newest first.
  /// NOTE: Firestore requires a composite index on (status ASC, timestamp DESC).
  /// Add it in Firebase Console → Firestore → Indexes, or deploy via
  /// firestore.indexes.json:
  ///   { "collectionGroup": "reports",
  ///     "queryScope": "COLLECTION",
  ///     "fields": [
  ///       { "fieldPath": "status",    "order": "ASCENDING" },
  ///       { "fieldPath": "timestamp", "order": "DESCENDING" }
  ///     ] }
  Stream<QuerySnapshot> getAllReports({String? statusFilter}) {
    // where() MUST come before orderBy() when filtering on a different field.
    Query query = _firestore.collection('reports');
    if (statusFilter != null) {
      query = query.where('status', isEqualTo: statusFilter);
    }
    return query.orderBy('timestamp', descending: true).snapshots();
  }

  /// Admin: update a report's status and optional note.
  Future<void> updateReport(
      String reportId, {
        required String status,
        String adminNote = '',
      }) async {
    await _firestore.collection('reports').doc(reportId).update({
      'status': status,
      'adminNote': adminNote,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': _auth.currentUser?.uid ?? '',
    });
  }

  /// Admin: ban a user (sets banned:true on their user doc).
  Future<void> banUser(String userId) async {
    await _firestore.collection('users').doc(userId).update({
      'banned': true,
      'bannedAt': FieldValue.serverTimestamp(),
      'bannedBy': _auth.currentUser?.uid ?? '',
    });
  }

  /// Admin: unban a user.
  Future<void> unbanUser(String userId) async {
    await _firestore.collection('users').doc(userId).update({
      'banned': false,
      'bannedAt': FieldValue.delete(),
      'bannedBy': FieldValue.delete(),
    });
  }
}