import 'package:credbro/chats/exchange_history_page.dart';
import 'package:credbro/chats/swap_requests_page.dart';
import 'package:credbro/pages/chatspage.dart';
import 'package:credbro/pages/homepage.dart';
import 'package:credbro/pages/profilepage_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/svg.dart';

import '../user_product/product_page.dart';

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
        child: Container(
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

              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedIndex = index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: EdgeInsets.symmetric(horizontal: rl.itemMarginH),
                    padding: EdgeInsets.symmetric(vertical: rl.itemPaddingV),
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
                        SvgPicture.asset(
                          _iconPaths[index],
                          height: rl.iconSize,
                          colorFilter: ColorFilter.mode(
                            isSelected ? Colors.white : const Color(0xFF5800B3),
                            BlendMode.srcIn,
                          ),
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
        ),
      ),
    );
  }
}
