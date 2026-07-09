import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AdResponsesPage
//  Shows a real-time list of ad requests submitted by the current user.
//  Each card shows status, title, budget, duration and a "View Details" sheet.
//  Admins (isAdmin: true in users/{uid}) additionally see Approve / Reject
//  actions that update the status field in Firestore.
//
//  Firestore path read:
//    • User view  → "AdRequests/{uid}/ads"  (own submissions)
//    • Admin view → collectionGroup("ads")  (all submissions)
//
//  Required Firestore index (collectionGroup):
//    Collection: ads  |  Fields: status ASC, createdAt DESC
// ─────────────────────────────────────────────────────────────────────────────

class AdResponsesPage extends StatefulWidget {
  /// Pass [isAdmin] = true from the admin dashboard to show all ads +
  /// Approve / Reject controls. Defaults to false (user's own ads only).
  final bool isAdmin;
  const AdResponsesPage({Key? key, this.isAdmin = false}) : super(key: key);

  @override
  State<AdResponsesPage> createState() => _AdResponsesPageState();
}

class _AdResponsesPageState extends State<AdResponsesPage>
    with SingleTickerProviderStateMixin {

  // ── Design tokens ─────────────────────────────────────────────────────────
  static const _purple      = Color(0xFF5800B3);
  static const _deepPurple  = Color(0xFF26004D);
  static const _lightPurple = Color(0xFFF3EEFF);
  static const _green       = Color(0xFF1B8A4C);
  static const _red         = Color(0xFFB00020);
  static const _amber       = Color(0xFFF59E0B);

  // ── Tabs: All / Pending / Approved / Rejected ────────────────────────────
  late final TabController _tabs;
  final _statuses = ['All', 'pending', 'approved', 'rejected'];

  String _selectedStatus = 'All';
  bool   _actionLoading  = false;

  double _cl(double v, double mn, double mx) => v.clamp(mn, mx);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _statuses.length, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) return;
      setState(() => _selectedStatus = _statuses[_tabs.index]);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Firestore query ───────────────────────────────────────────────────────
  // We ALWAYS filter by status (whereIn for "All", isEqualTo for specific tab).
  // This ensures the composite index (status + createdAt) is always used,
  // avoiding the COLLECTION_GROUP_DESC single-field index requirement.
  Query<Map<String, dynamic>> get _query {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    Query<Map<String, dynamic>> q = widget.isAdmin
        ? FirebaseFirestore.instance.collectionGroup('ads')
        : FirebaseFirestore.instance
        .collection('AdRequests')
        .doc(uid)
        .collection('ads');

    // Always apply a status filter so the composite index is always used.
    // "All" tab → whereIn across every status value.
    if (_selectedStatus == 'All') {
      q = q.where('status', whereIn: ['pending', 'approved', 'rejected']);
    } else {
      q = q.where('status', isEqualTo: _selectedStatus);
    }

    return q.orderBy('createdAt', descending: true);
  }

  // ── Status helpers ────────────────────────────────────────────────────────
  Color _statusColor(String status) {
    switch (status) {
      case 'approved': return _green;
      case 'rejected': return _red;
      default:         return _amber;
    }
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'approved': return const Color(0xFFE8F5EE);
      case 'rejected': return const Color(0xFFFFEBEE);
      default:         return const Color(0xFFFFF8E1);
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'approved': return Icons.check_circle_outline_rounded;
      case 'rejected': return Icons.cancel_outlined;
      default:         return Icons.hourglass_empty_rounded;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved': return 'Approved';
      case 'rejected': return 'Rejected';
      default:         return 'Pending';
    }
  }

  // ── Admin actions ─────────────────────────────────────────────────────────
  Future<void> _updateStatus(
      DocumentReference ref, String newStatus) async {
    setState(() => _actionLoading = true);
    try {
      await ref.update({
        'status':     newStatus,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': FirebaseAuth.instance.currentUser?.uid,
      }).timeout(const Duration(seconds: 10));
      if (mounted) _snack('Status updated to $newStatus.', isError: false);
    } on Exception catch (e) {
      if (mounted) _snack('Update failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  // ── Snack ─────────────────────────────────────────────────────────────────
  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg,
              style: const TextStyle(fontSize: 13, color: Colors.white,
                  fontWeight: FontWeight.w500))),
        ]),
        backgroundColor: isError ? _red : _green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 2),
      ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mq  = MediaQuery.of(context);
    final sw  = mq.size.width;
    final hPad      = _cl(sw * 0.05, 16.0, 32.0);
    final cardRadius = _cl(sw * 0.04, 12.0, 18.0);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: _buildAppBar(),
      body: Column(children: [
        // ── Tab bar ──────────────────────────────────────────────────────
        _buildTabBar(sw),
        // ── Content ──────────────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _query.snapshots(),
            builder: (ctx, snap) {
              if (snap.hasError) return _errorView(snap.error.toString());
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: _purple));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) return _emptyView(sw);
              return ListView.separated(
                padding: EdgeInsets.symmetric(
                    horizontal: hPad, vertical: 16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _adCard(docs[i], cardRadius, sw),
              );
            },
          ),
        ),
      ]),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() => AppBar(
    scrolledUnderElevation: 0,
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.white,
    elevation: 0,
    centerTitle: true,
    leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: Colors.black, size: 18),
        onPressed: () {
          Navigator.pop(context);
        }
    ),
    title: Text(
      widget.isAdmin ? 'All Ad Requests' : 'My Ad Requests',
      style: const TextStyle(
          color: Color(0xFF1A1A2E),
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3),
    ),
    bottom: const PreferredSize(
      preferredSize: Size.fromHeight(1),
      child: Divider(height: 1, thickness: 1, color: Color(0xFFF0ECFF)),
    ),
  );

  // ── Tab bar ───────────────────────────────────────────────────────────────
  Widget _buildTabBar(double sw) => Container(
    color: Colors.white,
    child: TabBar(
      controller: _tabs,
      isScrollable: false,          // always fill full width
      padding: EdgeInsets.zero,     // ← removes the left gap
      tabAlignment: TabAlignment.fill, // ← stretches tabs evenly
      labelColor: _purple,
      unselectedLabelColor: Colors.grey.shade500,
      labelStyle: TextStyle(
          fontSize: _cl(sw * 0.030, 11.0, 13.0),    // was 0.034
          fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(
          fontSize: _cl(sw * 0.030, 11.0, 13.0),    // was 0.034
          fontWeight: FontWeight.w500),
      indicatorColor: _purple,
      indicatorWeight: 2.5,
      indicatorSize: TabBarIndicatorSize.tab, // ← indicator fills tab width
      tabs: _statuses.map((s) {
        final isSelected = _tabs.index == _statuses.indexOf(s);
        return Tab(
          child: FittedBox(                          // ← shrinks content to fit
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (s != 'All') ...[
                Icon(
                  _statusIcon(s.isEmpty ? 'pending' : s),
                  size: 13,
                  color: isSelected ? _statusColor(s) : Colors.grey.shade400,
                ),
                const SizedBox(width: 3),
              ],
              Text(
                s == 'All' ? 'All' : _statusLabel(s),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ]),
          ),
        );
      }).toList(),
    ),
  );

  // ── Ad card ───────────────────────────────────────────────────────────────
  Widget _adCard(
      DocumentSnapshot<Map<String, dynamic>> doc,
      double radius,
      double sw) {
    final data     = doc.data() ?? {};
    final status   = data['status'] as String? ?? 'pending';
    final title    = data['title']    as String? ?? 'Untitled Ad';
    final category = data['category'] as String? ?? '—';
    final budget   = data['budget']   as num?    ?? 0;
    final duration = data['duration'] as String? ?? '—';
    final ts       = data['createdAt'] as Timestamp?;
    final created  = ts != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate())
        : 'Just now';
    final bannerUrl = data['bannerUrl'] as String?;

    return GestureDetector(
      onTap: () => _showDetails(doc, sw),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Banner thumbnail (if any)
          if (bannerUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
              child: Image.network(
                bannerUrl,
                height: _cl(sw * 0.35, 100.0, 160.0),
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                loadingBuilder: (_, child, prog) => prog == null
                    ? child
                    : SizedBox(
                    height: 120,
                    child: Center(
                        child: CircularProgressIndicator(
                            color: _purple, strokeWidth: 1.5))),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + status
                Row(children: [
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: _cl(sw * 0.04, 14.0, 16.0),
                            color: const Color(0xFF1A1A2E))),
                  ),
                  const SizedBox(width: 8),
                  _statusChip(status, sw),
                ]),
                const SizedBox(height: 8),

                // Meta row
                Wrap(spacing: 10, runSpacing: 6, children: [
                  _metaChip(Icons.category_outlined, category, sw),
                  _metaChip(Icons.currency_rupee_rounded,
                      '₹${budget.toStringAsFixed(0)}', sw),
                  _metaChip(Icons.timer_outlined, duration, sw),
                ]),
                const SizedBox(height: 10),

                // Footer
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Icon(Icons.access_time_rounded,
                          size: 12, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text(created,
                          style: TextStyle(
                              fontSize: _cl(sw * 0.028, 9.5, 11.5),
                              color: Colors.grey.shade500)),
                    ]),
                    Row(children: [
                      Text('View details',
                          style: TextStyle(
                              color: _purple,
                              fontSize: _cl(sw * 0.03, 10.5, 12.5),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_forward_ios_rounded,
                          size: 10, color: _purple),
                    ]),
                  ],
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── Status chip ───────────────────────────────────────────────────────────
  Widget _statusChip(String status, double sw) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: _statusBg(status),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(_statusIcon(status),
          size: 12, color: _statusColor(status)),
      const SizedBox(width: 4),
      Text(_statusLabel(status),
          style: TextStyle(
              color: _statusColor(status),
              fontSize: _cl(sw * 0.028, 9.5, 11.5),
              fontWeight: FontWeight.w700)),
    ]),
  );

  // ── Meta chip ─────────────────────────────────────────────────────────────
  Widget _metaChip(IconData icon, String label, double sw) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: _lightPurple,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: _purple.withOpacity(0.7)),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(
              color: _purple,
              fontSize: _cl(sw * 0.028, 9.5, 11.5),
              fontWeight: FontWeight.w600)),
    ]),
  );

  // ── Detail bottom sheet ───────────────────────────────────────────────────
  void _showDetails(
      DocumentSnapshot<Map<String, dynamic>> doc, double sw) {
    final data     = doc.data() ?? {};
    final status   = data['status']        as String? ?? 'pending';
    final title    = data['title']         as String? ?? 'Untitled';
    final desc     = data['description']   as String? ?? '—';
    final budget   = data['budget']        as num?    ?? 0;
    final duration = data['duration']      as String? ?? '—';
    final category = data['category']      as String? ?? '—';
    final cName    = data['contactName']   as String? ?? '—';
    final cEmail   = data['contactEmail']  as String? ?? '—';
    final cPhone   = data['contactPhone']  as String? ?? '';
    final bannerUrl= data['bannerUrl']     as String?;
    final ts       = data['createdAt']     as Timestamp?;
    final created  = ts != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate())
        : 'Just now';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(children: [
            // Handle
            const SizedBox(height: 10),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 6),

            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: EdgeInsets.symmetric(
                    horizontal: _cl(sw * 0.05, 16.0, 28.0),
                    vertical: 8),
                children: [
                  // Sheet header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Ad Details',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: _cl(sw * 0.045, 16.0, 20.0),
                              color: const Color(0xFF1A1A2E))),
                      _statusChip(status, sw),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Banner
                  if (bannerUrl != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        bannerUrl,
                        height: _cl(sw * 0.45, 140.0, 200.0),
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Title
                  _sheetSection('Ad Title', title, sw),
                  _sheetSection('Description', desc, sw),

                  // Info grid
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(child: _infoBox('Budget', '₹${budget.toStringAsFixed(0)}', sw)),
                    const SizedBox(width: 10),
                    Expanded(child: _infoBox('Duration', duration, sw)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _infoBox('Category', category, sw)),
                    const SizedBox(width: 10),
                    Expanded(child: _infoBox('Submitted', created, sw,
                        small: true)),
                  ]),
                  const SizedBox(height: 16),

                  // Contact
                  _sheetLabel('Contact Details', sw),
                  const SizedBox(height: 8),
                  _contactRow(Icons.person_outline_rounded, cName, sw),
                  const SizedBox(height: 6),
                  _contactRow(Icons.mail_outline_rounded, cEmail, sw),
                  if (cPhone.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _contactRow(Icons.phone_outlined, cPhone, sw),
                  ],
                  const SizedBox(height: 20),

                  // Admin actions
                  if (widget.isAdmin && status == 'pending')
                    _adminActions(doc.reference, sw),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Admin action buttons ──────────────────────────────────────────────────
  Widget _adminActions(DocumentReference ref, double sw) {
    return Row(children: [
      Expanded(
        child: _actionBtn(
          label: 'Approve',
          icon: Icons.check_circle_outline_rounded,
          color: _green,
          bgColor: const Color(0xFFE8F5EE),
          onTap: _actionLoading
              ? null
              : () async {
            Navigator.pop(context);
            await _updateStatus(ref, 'approved');
          },
          sw: sw,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _actionBtn(
          label: 'Reject',
          icon: Icons.cancel_outlined,
          color: _red,
          bgColor: const Color(0xFFFFEBEE),
          onTap: _actionLoading
              ? null
              : () async {
            Navigator.pop(context);
            await _updateStatus(ref, 'rejected');
          },
          sw: sw,
        ),
      ),
    ]);
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required VoidCallback? onTap,
    required double sw,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: _cl(sw * 0.038, 13.0, 15.0),
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  // ── Sheet helpers ─────────────────────────────────────────────────────────
  Widget _sheetSection(String label, String value, double sw) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sheetLabel(label, sw),
      const SizedBox(height: 4),
      Text(value,
          style: TextStyle(
              fontSize: _cl(sw * 0.038, 13.0, 15.0),
              color: Colors.black87,
              height: 1.5)),
    ]),
  );

  Widget _sheetLabel(String text, double sw) => Text(text,
      style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: _cl(sw * 0.032, 11.0, 13.0),
          color: _purple,
          letterSpacing: 0.5));

  Widget _infoBox(String label, String value, double sw,
      {bool small = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _lightPurple,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: _cl(sw * 0.028, 9.0, 11.0),
                color: _purple.withOpacity(0.7),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3)),
        const SizedBox(height: 4),
        Text(value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: small
                    ? _cl(sw * 0.03, 10.0, 12.0)
                    : _cl(sw * 0.038, 13.0, 15.0),
                color: _deepPurple,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _contactRow(IconData icon, String text, double sw) => Row(children: [
    Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _lightPurple,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 14, color: _purple),
    ),
    const SizedBox(width: 10),
    Expanded(
      child: Text(text,
          style: TextStyle(
              fontSize: _cl(sw * 0.036, 12.5, 14.5),
              color: Colors.black87,
              fontWeight: FontWeight.w500)),
    ),
  ]);

// ── Empty state ───────────────────────────────────────────────────────────
  Widget _emptyView(double sw) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Image.asset(
        _emptyImageAsset(),
        width: _cl(sw * 0.7, 200.0, 320.0),
        fit: BoxFit.contain,
      ),
    ),
  );

// ── Picks the right empty-state illustration ────────────────────────────
  String _emptyImageAsset() {
    switch (_selectedStatus) {
      case 'approved':
        return 'assets/images/empty_approved.png';
      case 'rejected':
        return 'assets/images/empty_rejected.png';
      case 'pending':
        return 'assets/images/empty_pending.png';
      default:
        return widget.isAdmin
            ? 'assets/images/empty_no_ads.png'
            : 'assets/images/empty_no_ads.png';
    }
  }

  // ── Error state ───────────────────────────────────────────────────────────
  Widget _errorView(String error) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.error_outline_rounded,
            size: 48, color: _red.withOpacity(0.6)),
        const SizedBox(height: 12),
        const Text('Something went wrong',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Color(0xFF1A1A2E))),
        const SizedBox(height: 6),
        Text(error,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500)),
      ]),
    ),
  );
}