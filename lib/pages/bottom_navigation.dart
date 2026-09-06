import 'package:amoeba/chats/swap_requests_page.dart';
import 'package:amoeba/pages/chatspage.dart';
import 'package:amoeba/pages/homepage.dart';
import 'package:amoeba/pages/profilepage_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/svg.dart';
import '../user_product/product_page.dart';

// Every non-chat notification `type` the Cloud Functions send (see
// notification_service.dart). Chat messages carry a message-content type
// instead (text/image/video/audio/location) and fall through to "else",
// which is what buckets them under the Chats tab badge instead of Requests.
// Kept in sync with the (now-removed) notifications_page.dart's
// `_kNonChatTypes` / homepage.dart's `_kNonChatNotificationTypes`.
//
// help_query, ad_request_submitted, and new_suggestion are admin-only —
// they're written to the *admin's* notifications doc, never a regular
// user's, and are badged separately on the admin panel's "Queries" tab
// (see admin_bottom_nav.dart's `_kAdminQueryNotificationTypes`). They're
// still listed here so a regular user's Requests badge would swallow them
// as a harmless fallback if that ever changed.
const Set<String> _kNonChatNotificationTypes = {
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

// ─── Responsive Layout Helper ────────────────────────────────────────────────
class _RL {
  final double w;
  const _RL(this.w);

  // Breakpoints
  bool get isMobile => w < 600;
  bool get isTablet => w >= 600 && w < 1024;
  bool get isDesktop => w >= 1024;

  // Nav bar total height
  double get navBarHeight {
    if (isDesktop) return 90.0;
    if (isTablet) return 80.0;
    return 70.0;
  }

  // Outer horizontal margin
  double get navMarginH {
    if (isDesktop) return w * 0.15;
    if (isTablet) return 24.0;
    return 10.0;
  }

  // Outer vertical margin
  double get navMarginV {
    if (isDesktop) return 12.0;
    if (isTablet) return 10.0;
    return 8.0;
  }

  // Inner vertical padding
  double get navPaddingV {
    if (isDesktop) return 10.0;
    if (isTablet) return 8.0;
    return 6.0;
  }

  // Container corner radius
  double get navRadius {
    if (isDesktop) return 32.0;
    if (isTablet) return 28.0;
    return 24.0;
  }

  // Active item corner radius
  double get itemRadius {
    if (isDesktop) return 20.0;
    if (isTablet) return 18.0;
    return 16.0;
  }

  // Horizontal margin between nav items
  double get itemMarginH {
    if (isDesktop) return 8.0;
    if (isTablet) return 6.0;
    return 4.0;
  }

  // Vertical padding inside each nav item
  double get itemPaddingV {
    if (isDesktop) return 10.0;
    if (isTablet) return 8.0;
    return 7.0;
  }

  // SVG icon size
  double get iconSize {
    if (isDesktop) return 28.0;
    if (isTablet) return 25.0;
    return 22.0;
  }

  // Gap between icon and label
  double get iconLabelGap {
    if (isDesktop) return 4.0;
    if (isTablet) return 3.0;
    return 2.0;
  }

  // Label font size
  double get labelSize {
    if (isDesktop) return 13.0;
    if (isTablet) return 11.5;
    return 10.0;
  }
}
// ─────────────────────────────────────────────────────────────────────────────

class BottomNavigation extends StatefulWidget {
  const BottomNavigation({super.key});

  @override
  State<BottomNavigation> createState() => _BottomNavigationState();
}

class _BottomNavigationState extends State<BottomNavigation> {
  int _selectedIndex = 0;
  late final String currentUserId;

  // ✅ Pages created once in initState, never recreated on rebuild
  late final List<Widget> _pages;

  final List<String> _iconPaths = [
    "assets/icons/home.svg",
    "assets/icons/chat.svg",
    "assets/icons/add.svg",
    "assets/icons/request.svg",
    "assets/icons/user.svg",
  ];

  final List<String> _labels = [
    "Home",
    "Chats",
    "Add",
    "Requests",
    "Profile",
  ];

  @override
  void initState() {
    super.initState();
    currentUserId = FirebaseAuth.instance.currentUser!.uid;

    // ✅ Built once — prevents pages from being recreated on every tab switch
    _pages = [
      const HomePage(),
      ChatsPage(),
      const UserProductListingPage(),
      const SwapRequestsPage(),
      const ProfilePageScreen(),
    ];
  }

  // ── Notification badges (replaces the old in-app NotificationsPage) ──────
  // Same `users/{uid}/notifications` collection that used to feed that page
  // and the homepage bell. OS/task-bar push notifications are untouched —
  // this only drives the little numbers on the Chats/Requests tabs.
  CollectionReference<Map<String, dynamic>> get _notificationsCollection =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('notifications');

  bool _isChatType(Map<String, dynamic> data) {
    final routeData = (data['data'] is Map)
        ? Map<String, dynamic>.from(data['data'] as Map)
        : <String, dynamic>{};
    final type = routeData['type'] as String? ?? 'text';
    return !_kNonChatNotificationTypes.contains(type);
  }

  void _onTapNavItem(int index) {
    setState(() => _selectedIndex = index);
    // Opening a tab clears the badge for that category — mirrors what
    // tapping into NotificationsPage / marking-all-read used to do.
    if (index == 1) {
      _markCategoryRead(chat: true);
    } else if (index == 3) {
      _markCategoryRead(chat: false);
    }
  }

  Future<void> _markCategoryRead({required bool chat}) async {
    try {
      final snap = await _notificationsCollection
          .where('read', isEqualTo: false)
          .get();
      final toMark = snap.docs.where((d) => _isChatType(d.data()) == chat);
      if (toMark.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in toMark) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } catch (_) {
      // Best-effort — badges just won't clear this time, no crash.
    }
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    final rl = _RL(width);

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _notificationsCollection
              .where('read', isEqualTo: false)
              .snapshots(),
          builder: (context, snap) {
            final unreadDocs = snap.data?.docs ?? const [];
            int chatCount = 0;
            int requestCount = 0;
            for (final doc in unreadDocs) {
              if (_isChatType(doc.data())) {
                chatCount++;
              } else {
                requestCount++;
              }
            }
            // index → badge count (only Chats [1] and Requests [3] get one).
            final badgeCounts = <int, int>{1: chatCount, 3: requestCount};

            return Container(
              margin: EdgeInsets.symmetric(
                horizontal: rl.navMarginH,
                vertical: rl.navMarginV,
              ),
              padding: EdgeInsets.symmetric(vertical: rl.navPaddingV),
              height: rl.navBarHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(rl.navRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: List.generate(_iconPaths.length, (index) {
                  final isSelected = _selectedIndex == index;
                  final badgeCount = badgeCounts[index] ?? 0;

                  return Expanded(
                    child: GestureDetector(
                      // ✅ Fix: make the ENTIRE tile tappable, not just the
                      // pixels its child happens to paint. Without this,
                      // unselected tabs (decoration: null) have "dead" areas
                      // in their padding/gaps that swallow the first tap.
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _onTapNavItem(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin:
                        EdgeInsets.symmetric(horizontal: rl.itemMarginH),
                        padding:
                        EdgeInsets.symmetric(vertical: rl.itemPaddingV),
                        decoration: isSelected
                            ? BoxDecoration(
                          color: const Color(0xFF5800B3),
                          borderRadius: BorderRadius.circular(rl.itemRadius),
                        )
                            : null,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                SvgPicture.asset(
                                  _iconPaths[index],
                                  height: rl.iconSize,
                                  colorFilter: ColorFilter.mode(
                                    isSelected
                                        ? Colors.white
                                        : const Color(0xFF5800B3),
                                    BlendMode.srcIn,
                                  ),
                                ),
                                if (badgeCount > 0)
                                  Positioned(
                                    right: -8,
                                    top: -4,
                                    child: _NavBadge(count: badgeCount),
                                  ),
                              ],
                            ),
                            SizedBox(height: rl.iconLabelGap),
                            Text(
                              _labels[index],
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: rl.labelSize,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF5800B3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Small numeric badge — WhatsApp-style unread count pill shown on the
/// Chats/Requests nav icons in place of the old NotificationsPage.
class _NavBadge extends StatelessWidget {
  final int count;
  const _NavBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}