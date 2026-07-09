import 'package:credbro/admin%20panel/ad_response.dart';
import 'package:credbro/admin%20panel/admin_help_queries.dart';
import 'package:credbro/admin%20panel/admin_report_page.dart';
import 'package:flutter/material.dart';

// Local copies — private identifiers don't cross files in Dart
const Color _kPurpleStart = Color(0xFF6C63FF); // ⚠️ replace with your actual hex
const Color _kPurpleEnd = Color(0xFF8A7FFF);   // ⚠️ replace with your actual hex
const Color _kLavenderBg = Color(0xFFFFFFFF);  // ⚠️ replace with your actual hex
const Color _kCardWhite = Color(0xFFFFFFFF);

class _Screen {
  final double width;
  final double height;
  const _Screen(this.width, this.height);

  static _Screen of(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return _Screen(size.width, size.height);
  }
}

class _Resp {
  final _Screen screen;
  const _Resp(this.screen);

  double w(double value) => (value / 375) * screen.width; // adjust base width if needed
  double h(double value) => (value / 812) * screen.height; // adjust base height if needed
  double sp(double value) => w(value).clamp(value * 0.8, value * 1.3);
}

class AdminCategoriesPage extends StatelessWidget {
  const AdminCategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final r = _Resp(_Screen.of(context));

    final categories = <_AdminCategoryItem>[
      _AdminCategoryItem(
        title: 'Help Queries',
        subtitle: 'View and respond to user support tickets',
        icon: Icons.support_agent_rounded,
        color: _kPurpleStart,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminHelpQueriesPage()),
        ),
      ),
      _AdminCategoryItem(
        title: 'Reports',
        subtitle: 'Review flagged listings and user reports',
        icon: Icons.flag_rounded,
        color: Colors.orange.shade700,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminReportsPage()),
        ),
      ),
      _AdminCategoryItem(
        title: 'Ad Responses',
        subtitle: 'Manage ad inquiries and responses',
        icon: Icons.campaign_rounded,
        color: Colors.blue.shade700,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdResponsesPage(isAdmin: true)),
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: _kLavenderBg,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Queries',
          style: TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w600),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFF0ECFF)),
        ),
      ),
      body: SafeArea(
        top: false, // AppBar already handles top safe area
        child: _buildBody(r, categories),
      ),
    );
  }


  Widget _buildBody(_Resp r, List<_AdminCategoryItem> categories) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: r.h(12)),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: r.w(20), vertical: r.h(4)),
            itemCount: categories.length,
            separatorBuilder: (_, __) => SizedBox(height: r.h(14)),
            itemBuilder: (context, index) => _CategoryCard(item: categories[index], r: r),
          ),
        ),
      ],
    );
  }
}

class _AdminCategoryItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _AdminCategoryItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _CategoryCard extends StatelessWidget {
  final _AdminCategoryItem item;
  final _Resp r;
  const _CategoryCard({required this.item, required this.r});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(r.w(18)),
      onTap: item.onTap,
      child: Container(
        padding: EdgeInsets.all(r.w(16)),
        decoration: BoxDecoration(
          color: _kCardWhite,
          borderRadius: BorderRadius.circular(r.w(18)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 5)),
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 2, offset: const Offset(0, 1)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: r.w(52),
              height: r.w(52),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [item.color, item.color.withOpacity(0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(r.w(14)),
                boxShadow: [
                  BoxShadow(color: item.color.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Icon(item.icon, color: Colors.white, size: r.sp(24)),
            ),
            SizedBox(width: r.w(14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: TextStyle(fontSize: r.sp(15.5), fontWeight: FontWeight.w700, color: Colors.black87)),
                  SizedBox(height: r.h(3)),
                  Text(item.subtitle,
                      style: TextStyle(fontSize: r.sp(12), color: Colors.grey.shade600, height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            SizedBox(width: r.w(6)),
            Container(
              padding: EdgeInsets.all(r.w(6)),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chevron_right_rounded, size: r.sp(18), color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}