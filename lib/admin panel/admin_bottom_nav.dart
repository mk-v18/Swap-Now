import 'package:amoeba/admin panel/admin_profile.dart';
import 'package:amoeba/admin panel/referal_page.dart';
import 'package:amoeba/admin%20panel/admin_categories_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/svg.dart';
import '../Advertisement/ad_uploader.dart';

// The three admin-only notification `type`s (see notification_service.dart)
// that route to the "Queries" hub (AdminCategoriesPage → Help Queries /
// Reports / Ad Responses) instead of anywhere in the regular user's nav.
// `ad_request_approved`/`ad_request_rejected` are NOT here — those go to
// the submitter, not the admin, and are handled by the regular
// BottomNavigation's Requests badge instead.
const Set<String> _kAdminQueryNotificationTypes = {
  'help_query',
  'ad_request_submitted',
  'new_suggestion',
};

class AdminBottomNavigation extends StatefulWidget {
  const AdminBottomNavigation({super.key});

  @override
  State<AdminBottomNavigation> createState() => _AdminBottomNavigationState();
}

class _AdminBottomNavigationState extends State<AdminBottomNavigation> {
  int _selectedIndex = 0;
  String? currentUserId;

  // ✅ Pages created once in initState, never recreated on rebuild
  late final List<Widget> _pages;

  final List<String> _iconPaths = [
    "assets/icons/shared.svg",
    "assets/icons/advertisement.svg",
    "assets/icons/add-1.svg",
    "assets/icons/user.svg",
  ];

  final List<String> _labels = [
    "Refer",
    "Ads",
    "Queries",
    "Profile",
  ];

  @override
  void initState() {
    super.initState();
    currentUserId = FirebaseAuth.instance.currentUser?.uid;

    // ✅ Built once — prevents pages from being recreated on every tab switch
    _pages = [
      const AdminReferralPage(),
      const AdvertisementPage(),
      AdminCategoriesPage(),
      const AdminProfilePage(),
    ];
  }

  // ── "Queries" tab badge — replaces the old in-app NotificationsPage for
  // admin-only notification types. Same `users/{uid}/notifications`
  // collection, filtered to help_query/ad_request_submitted/new_suggestion.
  CollectionReference<Map<String, dynamic>>? get _notificationsCollection {
    final uid = currentUserId;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications');
  }

  bool _isAdminQueryType(Map<String, dynamic> data) {
    final routeData = (data['data'] is Map)
        ? Map<String, dynamic>.from(data['data'] as Map)
        : <String, dynamic>{};
    final type = routeData['type'] as String? ?? 'text';
    return _kAdminQueryNotificationTypes.contains(type);
  }

  void _onTapNavItem(int index) {
    setState(() => _selectedIndex = index);
    // Opening "Queries" clears its badge — mirrors what the removed
    // NotificationsPage's mark-all-read used to do.
    if (index == 2) {
      _markQueriesRead();
    }
  }

  Future<void> _markQueriesRead() async {
    final collection = _notificationsCollection;
    if (collection == null) return;
    try {
      final snap =
      await collection.where('read', isEqualTo: false).get();
      final toMark = snap.docs.where((d) => _isAdminQueryType(d.data()));
      if (toMark.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in toMark) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } catch (_) {
      // Best-effort — badge just won't clear this time, no crash.
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double screenWidth = size.width;

    // Responsive breakpoints
    final bool isSmall = screenWidth < 360;
    final bool isTablet = screenWidth >= 600;

    // Responsive sizing
    final double navHeight = isTablet ? 80 : isSmall ? 60 : 70;
    final double iconSize = isTablet ? 26 : isSmall ? 18 : 22;
    final double fontSize = isTablet ? 12 : isSmall ? 9 : 10;
    final double verticalPadding = isTablet ? 8 : 6;
    final double horizontalMargin = isTablet ? 20 : 10;
    final double verticalMargin = isTablet ? 12 : 8;
    final double borderRadius = isTablet ? 28 : 24;
    final double itemBorderRadius = isTablet ? 20 : 16;
    final double horizontalItemMargin = isTablet ? 6 : 4;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: _pages[_selectedIndex],
      bottomNavigationBar: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _notificationsCollection
              ?.where('read', isEqualTo: false)
              .snapshots(),
          builder: (context, snap) {
            final queriesCount = (snap.data?.docs ?? const [])
                .where((d) => _isAdminQueryType(d.data()))
                .length;
            // index → badge count (only "Queries" [2] gets one).
            final badgeCounts = <int, int>{2: queriesCount};

            return Container(
              margin: EdgeInsets.symmetric(
                horizontal: horizontalMargin,
                vertical: verticalMargin,
              ),
              padding: EdgeInsets.symmetric(vertical: verticalPadding),
              height: navHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(borderRadius),
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
                        EdgeInsets.symmetric(horizontal: horizontalItemMargin),
                        padding: EdgeInsets.symmetric(vertical: verticalPadding),
                        decoration: isSelected
                            ? BoxDecoration(
                          color: const Color(0xFF5800B3),
                          borderRadius:
                          BorderRadius.circular(itemBorderRadius),
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
                                  height: iconSize,
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
                                    child: _AdminNavBadge(count: badgeCount),
                                  ),
                              ],
                            ),
                            SizedBox(height: isSmall ? 1 : 2),
                            if (screenWidth >= 320)
                              Text(
                                _labels[index],
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: fontSize,
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

/// Small numeric badge — same style as the regular BottomNavigation's
/// _NavBadge, shown on the admin "Queries" tab in place of the old
/// NotificationsPage.
class _AdminNavBadge extends StatelessWidget {
  final int count;
  const _AdminNavBadge({required this.count});

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