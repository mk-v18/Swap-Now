import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'chatscreen.dart';
import 'swap_request_service.dart';

class _T {
  static const purple = Color(0xFF6A1B9A);
  static const deepPurple = Color(0xFF4A148C);
  static const lightPurple = Color(0xFFEDE7F6);
  static const teal = Color(0xFF00796B);
  static const tealLight = Color(0xFFE0F2F1);
  static const textDark = Color(0xFF1A1A2E);
  static const textLight = Color(0xFF9999AA);
  static const textMid = Color(0xFF555566);
}

/// Inbox of swap requests:
/// - "Incoming": requests awaiting my response
/// - "Active": accepted swaps (either side) — reopens the chat even if
///   nobody sent a message yet, and now lets either side resolve the swap
///   directly (Successful / Cancel Swap) instead of only from the product
///   page.
/// - "Sent": requests I made, with live status
class SwapRequestsPage extends StatefulWidget {
  // NEW: which tab to open on when this page is reached via a swap
  // notification tap — 0 = Incoming, 1 = Active, 2 = Sent. Defaults to 0
  // for normal in-app navigation (e.g. tapping "Requests" from the nav bar).
  final int initialTab;

  const SwapRequestsPage({super.key, this.initialTab = 0});

  @override
  State<SwapRequestsPage> createState() => _SwapRequestsPageState();
}

class _SwapRequestsPageState extends State<SwapRequestsPage>
    with SingleTickerProviderStateMixin {
  final _service = SwapRequestService();
  // NEW: initialIndex now reads from widget.initialTab. Clamped defensively
  // in case a malformed/future push payload ever sends an out-of-range tab.
  late final TabController _tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 2),
  );
  final Set<String> _busyIds = {}; // requests currently being acted on

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('Requests',
            style: TextStyle(
                color: Colors.black, fontWeight: FontWeight.w600, fontSize: 18)),
        bottom: TabBar(
          controller: _tabs,
          labelColor: _T.deepPurple,
          unselectedLabelColor: _T.textLight,
          indicatorColor: _T.deepPurple,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [Tab(text: 'Incoming'), Tab(text: 'Active'), Tab(text: 'Sent')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_buildIncoming(), _buildActive(), _buildSent()],
      ),
    );
  }

  // ── INCOMING ────────────────────────────────────────────────────────────
  Widget _buildIncoming() {
    return StreamBuilder<QuerySnapshot>(
      stream: _service.incomingRequests(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return _emptyState('No pending requests', Icons.inbox_outlined);

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            return _incomingCard(doc.id, data);
          },
        );
      },
    );
  }

  Widget _incomingCard(String requestId, Map<String, dynamic> data) {
    final fromName = data['fromUserName'] ?? 'User';
    final fromImage = data['fromUserImage'] ?? '';
    final listedProduct = Map<String, dynamic>.from(data['listedProduct'] ?? {});
    final offered = ((data['offeredProducts'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final busy = _busyIds.contains(requestId);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _T.lightPurple, width: 1.5),
                ),
                child: CircleAvatar(
                  radius: 17,
                  backgroundColor: _T.lightPurple,
                  backgroundImage: fromImage.isNotEmpty ? NetworkImage(fromImage) : null,
                  child: fromImage.isEmpty
                      ? const Icon(Icons.person, color: _T.deepPurple, size: 17)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 13.5, color: _T.textDark, height: 1.3),
                    children: [
                      TextSpan(text: fromName, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const TextSpan(text: ' wants to swap for your item'),
                    ],
                  ),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _T.deepPurple),
                ),
            ],
          ),

          const SizedBox(height: 14),

          // Swap flow — connected visually instead of floating icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                _productRow('They want', listedProduct, _T.deepPurple),
                if (offered.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.swap_vert_rounded, size: 14, color: _T.textLight),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Divider(color: Colors.grey.shade200, height: 1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...offered.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _productRow('Offering', p, _T.deepPurple,onView: () => _showProductPreview(p)),
                  )),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => _decline(requestId),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: busy ? null : () => _accept(requestId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _T.deepPurple,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: busy
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text('Accept', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _accept(String requestId) async {
    setState(() => _busyIds.add(requestId));
    try {
      final chatId = await _service.acceptRequest(requestId);
      if (!mounted) return;
      final doc = await FirebaseFirestore.instance.collection('swapRequests').doc(requestId).get();
      final data = doc.data() as Map<String, dynamic>;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chatId,
            receiverId: data['fromUserId'],
            receiverName: data['fromUserName'] ?? 'User',
            receiverImage: data['fromUserImage'] ?? '',
          ),
        ),
      );
    } catch (e) {
      if (mounted) _snack('Could not accept: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(requestId));
    }
  }

  Future<void> _decline(String requestId) async {
    setState(() => _busyIds.add(requestId));
    try {
      await _service.declineRequest(requestId);
      if (mounted) _snack('Request declined');
    } catch (e) {
      if (mounted) _snack('Could not decline: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(requestId));
    }
  }

  // ── ACTIVE (accepted, either side) ──────────────────────────────────────
  // Each active swap exposes "Successful" / "Cancel Swap" directly, so
  // resolving a swap no longer has to happen from ProductDetailPage.
  Widget _buildActive() {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<QuerySnapshot>(
      stream: _service.myActiveSwaps(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return _emptyState('No active swaps yet', Icons.swap_horiz_rounded);
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final requestId = docs[i].id;
            final data = docs[i].data() as Map<String, dynamic>;
            final isFrom = data['fromUserId'] == myUid;
            final otherId = isFrom ? data['toUserId'] : data['fromUserId'];
            final otherName = (isFrom ? data['toUserName'] : data['fromUserName']) ?? 'User';
            final otherImage = (isFrom ? data['toUserImage'] : data['fromUserImage']) ?? '';
            final listedProduct = Map<String, dynamic>.from(data['listedProduct'] ?? {});
            // Needed to pass through to markExchangeSuccessful/cancelSwap.
            final offeredProducts = ((data['offeredProducts'] as List?) ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            final chatId = data['chatId'] as String?;
            final busy = _busyIds.contains(requestId);

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tapping just this row opens the chat — kept as its own
                  // GestureDetector (rather than wrapping the whole card) so
                  // it doesn't fight the buttons below for the tap.
                  GestureDetector(
                    onTap: chatId == null
                        ? null
                        : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          chatId: chatId,
                          receiverId: otherId,
                          receiverName: otherName,
                          receiverImage: otherImage,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: _T.tealLight,
                          backgroundImage: otherImage.isNotEmpty ? NetworkImage(otherImage) : null,
                          child: otherImage.isEmpty
                              ? const Icon(Icons.person, color: _T.teal, size: 18)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: _productRow('With $otherName', listedProduct, _T.teal)),
                        if (busy)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _T.deepPurple),
                          )
                        else
                          const Text("Message", style:(TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _T.deepPurple))),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  Divider(height: 1, color: Colors.grey.shade100),
                  const SizedBox(height: 12),

                  // Resolve actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => _cancelSwap(
                            requestId: requestId,
                            otherId: otherId,
                            otherName: otherName,
                            listedProduct: listedProduct,
                            offeredProducts: offeredProducts,
                            chatId: chatId,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                          child: const Text('Cancel Swap',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: busy
                              ? null
                              : () => _markSuccessful(
                            requestId: requestId,
                            otherId: otherId,
                            otherName: otherName,
                            listedProduct: listedProduct,
                            offeredProducts: offeredProducts,
                            chatId: chatId,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _T.teal,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                          child: const Text('Successful',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Confirms, then marks the swap successful and logs it to
  /// exchangeHistory (surfaced in ExchangeHistoryPage).
  Future<void> _markSuccessful({
    required String requestId,
    required String otherId,
    required String otherName,
    required Map<String, dynamic> listedProduct,
    required List<Map<String, dynamic>> offeredProducts,
    String? chatId,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _T.teal.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_rounded, color: _T.teal, size: 32),
            ),
            const SizedBox(height: 16),
            const Text(
              'Confirm exchange',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: Text(
          'Mark your exchange with $otherName as successfully completed?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.4),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _T.teal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyIds.add(requestId));
    try {
      await _service.markExchangeSuccessful(
        requestId: requestId,
        otherUserId: otherId,
        otherUserName: otherName,
        listedProduct: listedProduct,
        offeredProducts: offeredProducts,
        chatId: chatId,
      );
      if (mounted) _snack('Exchange marked as successful 🎉');
    } catch (e) {
      if (mounted) _snack('Could not complete exchange: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(requestId));
    }
  }

  /// Confirms, then cancels the swap and logs it to exchangeHistory
  /// (surfaced in ExchangeHistoryPage as a cancelled entry).
  Future<void> _cancelSwap({
    required String requestId,
    required String otherId,
    required String otherName,
    required Map<String, dynamic> listedProduct,
    required List<Map<String, dynamic>> offeredProducts,
    String? chatId,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 32),
            ),
            const SizedBox(height: 16),
            const Text(
              'Cancel swap',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: Text(
          'Cancel the swap with $otherName? This moves it to your exchange history as cancelled and cannot be undone.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.4),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Cancel Swap', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyIds.add(requestId));
    try {
      await _service.cancelSwap(
        requestId: requestId,
        otherUserId: otherId,
        otherUserName: otherName,
        listedProduct: listedProduct,
        offeredProducts: offeredProducts,
        chatId: chatId,
      );
      if (mounted) _snack('Swap cancelled');
    } catch (e) {
      if (mounted) _snack('Could not cancel swap: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(requestId));
    }
  }

  // ── SENT ────────────────────────────────────────────────────────────────
  Widget _buildSent() {
    return StreamBuilder<QuerySnapshot>(
      stream: _service.sentRequests(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return _emptyState('No requests sent yet', Icons.send_outlined);

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            return _sentCard(doc.id, data);
          },
        );
      },
    );
  }

  Widget _sentCard(String requestId, Map<String, dynamic> data) {
    final toName = data['toUserName'] ?? 'User';
    final status = (data['status'] ?? 'pending') as String;
    final listedProduct = Map<String, dynamic>.from(data['listedProduct'] ?? {});

    Color badgeColor;
    String label;
    switch (status) {
      case 'accepted':
        badgeColor = _T.teal;
        label = 'Accepted';
        break;
      case 'declined':
        badgeColor = Colors.redAccent;
        label = 'Declined';
        break;
      case 'completed':
        badgeColor = _T.deepPurple;
        label = 'Completed';
        break;
      case 'cancelled':
        badgeColor = Colors.redAccent;
        label = 'Cancelled';
        break;
      default:
        badgeColor = Colors.orange;
        label = 'Pending';
    }

    return GestureDetector(
      onTap: status == 'accepted' || status == 'completed'
          ? () => _openChatFor(data)
          : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Expanded(child: _productRow('To $toName', listedProduct, _T.deepPurple)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(label,
                  style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openChatFor(Map<String, dynamic> data) async {
    final chatId = data['chatId'] as String?;
    if (chatId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chatId,
          receiverId: data['toUserId'],
          receiverName: data['toUserName'] ?? 'User',
          receiverImage: data['toUserImage'] ?? '',
        ),
      ),
    );
  }

  // ── SHARED WIDGETS ────────────────────────────────────────────────────────
  Widget _productRow(String label, Map<String, dynamic> product, Color color, {VoidCallback? onView}) {
    final images = (product['images'] as List?) ?? [];
    final imageUrl = images.isNotEmpty ? images[0] as String : null;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 34, height: 34,
            color: Colors.grey[200],
            child: imageUrl != null
                ? Image.network(imageUrl, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported, size: 16))
                : const Icon(Icons.image_not_supported, size: 16, color: Colors.grey),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10.5, color: _T.textLight)),
              Text(product['title'] ?? 'Product',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _T.textDark)),
            ],
          ),
        ),
        if (onView != null) ...[
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onView,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility_outlined, size: 14, color: color),
                    const SizedBox(width: 4),
                    Text('View',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── PRODUCT PREVIEW ──────────────────────────────────────────────────────
  void _showProductPreview(Map<String, dynamic> product) {
    final images = (product['images'] as List?) ?? [];
    final imageUrl = images.isNotEmpty ? images[0] as String : null;
    final condition = (product['condition'] ?? '') as String;
    final category = (product['category'] ?? '') as String;
    final location = (product['location'] ?? '') as String;
    final description = (product['description'] ?? '') as String;
    final hasMeta = condition.isNotEmpty || category.isNotEmpty || location.isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.68,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListView(
            controller: scroll,
            padding: EdgeInsets.zero,
            children: [
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 1.4,
                    child: imageUrl != null
                        ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[200],
                        child: const Icon(Icons.image_not_supported,
                            size: 40, color: Colors.grey),
                      ),
                    )
                        : Container(
                      color: Colors.grey[200],
                      child: const Icon(Icons.image_not_supported,
                          size: 40, color: Colors.grey),
                    ),
                  ),
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black.withOpacity(0), Colors.black.withOpacity(0.08)],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 14, right: 14,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product['title'] ?? 'Product',
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: _T.textDark,
                            letterSpacing: -0.3,
                            height: 1.25)),

                    if (condition.isNotEmpty || category.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (condition.isNotEmpty)
                            _detailChip(Icons.verified_rounded, condition, _T.purple, _T.lightPurple),
                          if (category.isNotEmpty)
                            _detailChip(Icons.category_rounded, category, _T.teal, _T.tealLight),
                        ],
                      ),
                    ],

                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _detailRow(
                        icon: Icons.location_on_rounded,
                        color: const Color(0xFFE53935),
                        label: 'Location',
                        value: location,
                      ),
                    ],

                    if (description.isNotEmpty) ...[
                      SizedBox(height: hasMeta ? 18 : 4),
                      Row(children: const [
                        Icon(Icons.notes_rounded, color: _T.purple, size: 17),
                        SizedBox(width: 8),
                        Text('Description',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w700, color: _T.textDark)),
                      ]),
                      const SizedBox(height: 8),
                      Text(description,
                          style: const TextStyle(fontSize: 13.5, color: _T.textMid, height: 1.6)),
                    ],

                    if (!hasMeta && description.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(children: [
                          Icon(Icons.info_outline_rounded, size: 15, color: Colors.grey[400]),
                          const SizedBox(width: 6),
                          Text('No further details were included with this listing.',
                              style: TextStyle(fontSize: 12.5, color: Colors.grey[500])),
                        ]),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailChip(IconData icon, String text, Color fg, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: fg),
      const SizedBox(width: 5),
      Text(text, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _detailRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 10.5, color: _T.textLight, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(fontSize: 13.5, color: _T.textDark, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState(String label, IconData icon) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 44, color: Colors.grey[350]),
        const SizedBox(height: 10),
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 13.5)),
      ],
    ),
  );

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? const Color(0xFFB00020) : Colors.black87,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}