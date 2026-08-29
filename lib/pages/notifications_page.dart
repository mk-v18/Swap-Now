import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../chats/notification_service.dart';

// ─── Brand colours (kept in sync with homepage.dart) ───────────────────────
const Color _kPrimary = Color(0xFF5800B3);
const Color _kPrimaryDark = Color(0xFF26004D);

// Every non-chat notification `type` the Cloud Functions send (see
// notification_service.dart's private sets, and functions/index.js).
// Chat messages carry a message-content type instead (text/image/video/
// audio/location) and are deliberately excluded from this inbox — the
// chat screen itself is already the place to review those.
const Set<String> _kNonChatTypes = {
  'swap_request',
  'swap_accepted',
  'swap_declined',
  'exchange_completed',
  'exchange_cancelled',
  'help_query',
  'ad_request_submitted',
  'ad_request_approved',
  'ad_request_rejected',
  'new_suggestion',
};

bool _isNonChatDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  final routeData =
  (data['data'] is Map) ? Map<String, dynamic>.from(data['data'] as Map) : {};
  final type = (routeData['type'] as String?) ?? 'text';
  return _kNonChatTypes.contains(type);
}

/// In-app history of every push notification sent to this user — swap
/// request/accept/decline, exchange completed/cancelled, help queries, ad
/// request updates, and suggestions. Chat message notifications are
/// excluded (see `_kNonChatTypes`). Backed by `users/{uid}/notifications`,
/// which Cloud Functions writes to alongside every push it sends (see
/// functions/index.js — `_writeNotificationDoc`).
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? get _collection {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications');
  }

  Future<void> _markAllRead(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final unread = docs.where((d) => (d.data()['read'] as bool?) != true);
    if (unread.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in unread) {
      batch.update(doc.reference, {'read': true});
    }
    try {
      await batch.commit();
    } catch (e) {
      if (kDebugMode) debugPrint('[Notifications] Mark all read failed: $e');
    }
  }

  Future<void> _onTapNotification(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    if ((data['read'] as bool?) != true) {
      doc.reference.update({'read': true}).catchError((_) {});
    }
    final routeData = (data['data'] is Map)
        ? Map<String, dynamic>.from(data['data'] as Map)
        : <String, dynamic>{};
    NotificationService().routeFromNotificationData(routeData);
  }

  Future<void> _deleteNotification(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    try {
      await doc.reference.delete();
    } catch (e) {
      if (kDebugMode) debugPrint('[Notifications] Delete failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = _collection;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFF0ECFF)),
        ),
        leading: IconButton(
          icon:
          const Icon(Icons.arrow_back_ios, color: Colors.black, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (collection != null)
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: collection
                  .orderBy('createdAt', descending: true)
                  .limit(200)
                  .snapshots(),
              builder: (context, snap) {
                final docs =
                (snap.data?.docs ?? []).where(_isNonChatDoc).toList();
                final hasUnread =
                docs.any((d) => (d.data()['read'] as bool?) != true);
                if (!hasUnread) return const SizedBox.shrink();
                return TextButton(
                  onPressed: () => _markAllRead(docs),
                  child: const Text(
                    'Mark all read',
                    style: TextStyle(
                      color: _kPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: collection == null
          ? const _EmptyState(
        icon: Icons.person_off_outlined,
        title: 'Not signed in',
        subtitle: 'Sign in to see your notifications.',
      )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: collection
            .orderBy('createdAt', descending: true)
            .limit(200)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _EmptyState(
              icon: Icons.error_outline,
              title: 'Could not load notifications',
              subtitle: 'Please try again in a moment.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _kPrimary),
            );
          }
          final docs = snapshot.data!.docs.where(_isNonChatDoc).toList();
          if (docs.isEmpty) {
            return const _EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'No notifications yet',
              subtitle:
              "You'll see swaps, messages, and updates here.",
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: docs.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 72,
              color: Colors.grey.shade200,
            ),
            itemBuilder: (context, i) {
              final doc = docs[i];
              return _NotificationTile(
                doc: doc,
                onTap: () => _onTapNotification(doc),
                onDismiss: () => _deleteNotification(doc),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Layered tinted badge — soft outer ring + solid inner
              // circle, matching the empty-state pattern used across
              // chats/wishlist/payments/listings/support.
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 128,
                    height: 128,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kPrimary.withOpacity(0.06),
                    ),
                  ),
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kPrimary.withOpacity(0.10),
                    ),
                  ),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kPrimary.withOpacity(0.14),
                    ),
                    child: Icon(icon, size: 30, color: _kPrimaryDark),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _kPrimaryDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Types that come through with title/body already set server-side, per
// notification_service.dart's private sets — kept here only to pick an
// icon/colour, never used for routing (routing is delegated back to
// NotificationService).
const Set<String> _kSwapTypes = {
  'swap_request',
  'swap_accepted',
  'swap_declined',
  'exchange_completed',
  'exchange_cancelled',
};
const Set<String> _kAdTypes = {
  'ad_request_submitted',
  'ad_request_approved',
  'ad_request_rejected',
};

class _NotificationTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotificationTile({
    required this.doc,
    required this.onTap,
    required this.onDismiss,
  });

  (IconData, Color) _iconFor(String type) {
    if (_kSwapTypes.contains(type)) {
      if (type == 'exchange_completed') {
        return (Icons.check_circle_outline, const Color(0xFF2E7D32));
      }
      if (type == 'exchange_cancelled' || type == 'swap_declined') {
        return (Icons.cancel_outlined, const Color(0xFFC62828));
      }
      return (Icons.swap_horiz_rounded, _kPrimary);
    }
    if (_kAdTypes.contains(type)) {
      return (Icons.campaign_outlined, const Color(0xFFEF6C00));
    }
    if (type == 'help_query') {
      return (Icons.help_outline_rounded, const Color(0xFF00838F));
    }
    if (type == 'new_suggestion') {
      return (Icons.lightbulb_outline_rounded, const Color(0xFFF9A825));
    }
    // Chat / default.
    return (Icons.chat_bubble_outline_rounded, _kPrimary);
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final title = (data['title'] as String?)?.trim().isNotEmpty == true
        ? data['title'] as String
        : 'Notification';
    final body = (data['body'] as String?) ?? '';
    final isRead = (data['read'] as bool?) == true;
    final routeData =
    (data['data'] is Map) ? Map<String, dynamic>.from(data['data'] as Map) : {};
    final type = (routeData['type'] as String?) ?? 'text';
    final createdAt = data['createdAt'];
    String timeLabel = '';
    if (createdAt is Timestamp) {
      timeLabel = timeago.format(createdAt.toDate(), locale: 'en_short');
    }

    final (icon, color) = _iconFor(type);

    return Dismissible(
      key: ValueKey(doc.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: const Color(0xFFC62828),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDismiss(),
      child: Material(
        color: isRead ? Colors.white : _kPrimary.withOpacity(0.06),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight:
                                isRead ? FontWeight.w600 : FontWeight.w800,
                                color: _kPrimaryDark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timeLabel,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!isRead) ...[
                  const SizedBox(width: 8),
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: _kPrimary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}