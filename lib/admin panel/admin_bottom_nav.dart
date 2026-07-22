import 'package:credbro/admin panel/admin_profile.dart';
import 'package:credbro/admin panel/referal_page.dart';
import 'package:credbro/admin%20panel/ad_response.dart';
import 'package:credbro/admin%20panel/admin_categories_page.dart';
import 'package:credbro/admin%20panel/admin_chat.dart';
import 'package:credbro/admin%20panel/admin_help_queries.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/svg.dart';
import '../Advertisement/ad_uploader.dart';

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
        child: Container(
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

              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedIndex = index),
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
                        SvgPicture.asset(
                          _iconPaths[index],
                          height: iconSize,
                          colorFilter: ColorFilter.mode(
                            isSelected ? Colors.white : const Color(0xFF5800B3),
                            BlendMode.srcIn,
                          ),
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
        ),
      ),
    );
  }
}