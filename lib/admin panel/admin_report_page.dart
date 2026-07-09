import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:credbro/chats/chatservice.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Admin-only screen that lists all user reports and lets the admin
/// review them, add notes, and take actions (ban / dismiss).
///
/// Route: add to your admin navigation or push via:
///   Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminReportsPage()));
///
///



// ...keep _updateWithNote, _confirmBan, _snack exactly as you already have them



class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage>
    with SingleTickerProviderStateMixin {
  final ChatService _chatService = ChatService();
  late TabController _tabs;

  static const _purple = Color(0xFF7B1FA2);
  static const _statusColors = {
    'pending': Color(0xFFE65100),
    'reviewed': Color(0xFF1565C0),
    'actioned': Color(0xFF2E7D32),
    'dismissed': Color(0xFF757575),
  };

  static const _statusIcons = {
    'pending': Icons.hourglass_empty_rounded,
    'reviewed': Icons.visibility_rounded,
    'actioned': Icons.check_circle_outline_rounded,
    'dismissed': Icons.block_rounded,
  };

  final _statuses = ['pending', 'reviewed', 'actioned', 'dismissed'];

  double _cl(double v, double mn, double mx) => v.clamp(mn, mx);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'reviewed':
        return 'Reviewed';
      case 'actioned':
        return 'Actioned';
      case 'dismissed':
        return 'Dismissed';
      default:
        return 'Pending';
    }
  }

  // ── Build — matches AdResponsesPage AppBar + TabBar exactly ─────────────
  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildTabBar(sw),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _ReportList(chatService: _chatService, statusFilter: 'pending', onAction: _handleAction),
                _ReportList(chatService: _chatService, statusFilter: 'reviewed', onAction: _handleAction),
                _ReportList(chatService: _chatService, statusFilter: 'actioned', onAction: _handleAction),
                _ReportList(chatService: _chatService, statusFilter: 'dismissed', onAction: _handleAction),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
    scrolledUnderElevation: 0,
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.white,
    elevation: 0,
    centerTitle: true,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 18),
      onPressed: () => Navigator.pop(context),
    ),
    title: const Text(
      'User Reports',
      style: TextStyle(
        color: Color(0xFF1A1A2E),
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
    ),
    bottom: const PreferredSize(
      preferredSize: Size.fromHeight(1),
      child: Divider(height: 1, thickness: 1, color: Color(0xFFF0ECFF)),
    ),
  );

  Widget _buildTabBar(double sw) => Container(
    color: Colors.white,
    child: TabBar(
      controller: _tabs,
      isScrollable: false,
      padding: EdgeInsets.zero,
      tabAlignment: TabAlignment.fill,
      labelColor: _purple,
      unselectedLabelColor: Colors.grey.shade500,
      labelStyle: TextStyle(fontSize: _cl(sw * 0.030, 11.0, 13.0), fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontSize: _cl(sw * 0.030, 11.0, 13.0), fontWeight: FontWeight.w500),
      indicatorColor: _purple,
      indicatorWeight: 2.5,
      indicatorSize: TabBarIndicatorSize.tab,
      tabs: _statuses.map((s) {
        final isSelected = _tabs.index == _statuses.indexOf(s);
        return Tab(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _statusIcons[s] ?? Icons.circle,
                  size: 13,
                  color: isSelected ? (_statusColors[s] ?? _purple) : Colors.grey.shade400,
                ),
                const SizedBox(width: 3),
                Text(
                  _statusLabel(s),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    ),
  );

  // ── Action dispatcher (unchanged from your existing code) ────────────────
  Future<void> _handleAction(
      BuildContext _ignored,
      String reportId,
      Map<String, dynamic> reportData,
      ) async {
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ActionSheet(reportData: reportData),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'mark_reviewed':
        await _updateWithNote(reportId, 'reviewed');
        break;
      case 'ban_user':
        await _confirmBan(reportId, reportData);
        break;
      case 'dismiss':
        await _updateWithNote(reportId, 'dismissed');
        break;
      case 'unban':
        await _chatService.unbanUser(reportData['reportedUserId'] as String);
        if (mounted) _snack('User unbanned.', success: true);
        break;
    }
  }


  Future<void> _updateWithNote(String reportId, String status) async {
    // Dispose controller properly to avoid memory leak.
    final noteCtrl = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
            status == 'reviewed' ? 'Mark as Reviewed' : 'Dismiss Report',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status == 'reviewed'
                    ? 'Add an optional note about what was found.'
                    : 'Dismiss this report. Add an optional note.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Admin note (optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Confirm',
                  style: TextStyle(color: _statusColors[status] ?? _purple)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await _chatService.updateReport(reportId,
          status: status, adminNote: noteCtrl.text.trim());
      if (mounted) _snack('Report marked as $status.', success: true);
    } finally {
      noteCtrl.dispose();
    }
  }

  Future<void> _confirmBan(
      String reportId,
      Map<String, dynamic> reportData,
      ) async {
    final noteCtrl = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(children: [
            Icon(Icons.block, color: Colors.red, size: 20),
            SizedBox(width: 8),
            Text('Ban User',
                style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This will ban "${reportData['reportedUserName']}". They will no longer be able to access the app.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Reason for ban (visible to audit log)',
                  border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ban User',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await _chatService.banUser(reportData['reportedUserId'] as String);
      await _chatService.updateReport(reportId,
          status: 'actioned',
          adminNote: noteCtrl.text.trim().isNotEmpty
              ? noteCtrl.text.trim()
              : 'User banned.');
      if (mounted) _snack('User has been banned.', success: true);
    } finally {
      noteCtrl.dispose();
    }
  }

  void _snack(String msg, {bool success = false, bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error
          ? const Color(0xFFB00020)
          : success
          ? const Color(0xFF2E7D32)
          : Colors.black87,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}

// ── Report list tab ───────────────────────────────────────────────────────────
class _ReportList extends StatelessWidget {
  final ChatService chatService;
  final String statusFilter;
  // BuildContext param kept only for signature compat; handler uses its own mounted context.
  final Future<void> Function(BuildContext, String, Map<String, dynamic>) onAction;

  const _ReportList({
    required this.chatService,
    required this.statusFilter,
    required this.onAction,
  });

  static const Color _kPurpleStart = Color(0xFF7B1FA2); // ⚠️ match your actual brand purple

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: chatService.getAllReports(statusFilter: statusFilter),
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade300),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to load reports.',
                    style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _kPurpleStart),
          );
        }

        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/no_reports.png',
                    width: 180,
                    height: 180,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No $statusFilter reports',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Reports will show up here once submitted',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            return _ReportCard(
              reportId: doc.id,
              data: data,
              // Pass `context` (the StatelessWidget's stable context),
              // NOT the itemBuilder's `_` which is a ListView child context.
              onAction: (rid, rdata) => onAction(context, rid, rdata),
            );
          },
        );
      },
    );
  }
}

// ── Report card ───────────────────────────────────────────────────────────────
class _ReportCard extends StatelessWidget {
  final String reportId;
  final Map<String, dynamic> data;
  final Future<void> Function(String, Map<String, dynamic>) onAction;

  const _ReportCard({
    required this.reportId,
    required this.data,
    required this.onAction,
  });

  static const _statusColors = {
    'pending': Color(0xFFE65100),
    'reviewed': Color(0xFF1565C0),
    'actioned': Color(0xFF2E7D32),
    'dismissed': Color(0xFF757575),
  };

  static const _statusIcons = {
    'pending': Icons.hourglass_top_rounded,
    'reviewed': Icons.visibility_rounded,
    'actioned': Icons.check_circle_rounded,
    'dismissed': Icons.block_rounded,
  };

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty || parts.first == '—') return '?';
    return parts.first[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] ?? 'pending') as String;
    final color = _statusColors[status] ?? Colors.grey;
    final icon = _statusIcons[status] ?? Icons.flag_rounded;
    final ts = (data['timestamp'] as Timestamp?)?.toDate();
    final timeStr = ts != null ? DateFormat('MMM d, h:mm a').format(ts) : '—';
    final adminNote = (data['adminNote'] ?? '') as String;
    final reportedName = (data['reportedUserName'] ?? '—') as String;
    final rawReporterName = (data['reporterName'] ?? '') as String;
    final reporterName = rawReporterName.trim().isEmpty ? 'Unknown' : rawReporterName;
    final rawReporterEmail = (data['reporterEmail'] ?? '') as String;
    final reporterEmail = rawReporterEmail.trim().isEmpty ? 'No email' : rawReporterEmail;
    final reason = (data['reason'] ?? '—') as String;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => onAction(reportId, data),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 5)),
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 2, offset: const Offset(0, 1)),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left status accent bar
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title (reported user) + status pill
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              reportedName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, size: 12, color: color),
                                const SizedBox(width: 4),
                                Text(
                                  status[0].toUpperCase() + status.substring(1),
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Avatar + reporter email + (banned badge if any)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 11,
                            backgroundColor: const Color(0xFF7B1FA2).withOpacity(0.12),
                            child: Text(
                              _initials(reporterName),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF7B1FA2),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  reporterName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  reporterEmail,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.grey.shade500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          _BannedBadge(userId: data['reportedUserId'] as String? ?? ''),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Reason
                      Text(
                        reason,
                        style: const TextStyle(fontSize: 13.5, color: Colors.black87, height: 1.35),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      if (adminNote.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7B1FA2).withOpacity(0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF7B1FA2).withOpacity(0.15)),
                          ),
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
                              children: [
                                const TextSpan(
                                  text: 'Admin note: ',
                                  style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF7B1FA2)),
                                ),
                                TextSpan(text: adminNote),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),

                      // Footer: time + chevron
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded, size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(timeStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          const Spacer(),
                          Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey.shade400),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reads live user doc to show whether the user is currently banned.
class _BannedBadge extends StatelessWidget {
  final String userId;
  const _BannedBadge({required this.userId});

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
      builder: (_, snap) {
        if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();
        final banned = (snap.data!.data() as Map<String, dynamic>)['banned'] == true;
        if (!banned) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.red.shade200, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block_rounded, size: 12, color: Colors.red.shade700),
              const SizedBox(width: 4),
              Text(
                'Banned',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Action bottom sheet ───────────────────────────────────────────────────────
class _ActionSheet extends StatelessWidget {
  final Map<String, dynamic> reportData;
  const _ActionSheet({required this.reportData});

  @override
  Widget build(BuildContext context) {
    final status = (reportData['status'] ?? 'pending') as String;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        child: SingleChildScrollView(          // ⬅️ added
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 42,
                height: 5,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              // Header with icon
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B1FA2).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.gavel_rounded, size: 18, color: Color(0xFF7B1FA2)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Actions for Report',
                            style: TextStyle(
                                fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.grey.shade900)),
                        Text(
                          reportData['reportedUserName'] != null
                              ? 'Regarding ${reportData['reportedUserName']}'
                              : 'Choose an action below',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: Colors.grey.shade200),
              const SizedBox(height: 6),

              if (status == 'pending')
                _ActionTile(
                  icon: Icons.visibility_rounded,
                  label: 'Mark as Reviewed',
                  subtitle: 'Flag it for further review',
                  color: const Color(0xFF1565C0),
                  onTap: () => Navigator.pop(context, 'mark_reviewed'),
                ),

              _ActionTile(
                icon: Icons.block_rounded,
                label: 'Ban User',
                subtitle: 'Prevent "${reportData['reportedUserName']}" from accessing the app',
                color: Colors.red.shade700,
                onTap: () => Navigator.pop(context, 'ban_user'),
              ),

              _ActionTile(
                icon: Icons.undo_rounded,
                label: 'Unban User',
                subtitle: 'Restore access if previously banned',
                color: const Color(0xFF2E7D32),
                onTap: () => Navigator.pop(context, 'unban'),
              ),

              if (status != 'dismissed')
                _ActionTile(
                  icon: Icons.close_rounded,
                  label: 'Dismiss Report',
                  subtitle: 'Mark as not actionable',
                  color: Colors.grey.shade600,
                  onTap: () => Navigator.pop(context, 'dismiss'),
                ),

              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.15)),
              color: color.withOpacity(0.03),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withOpacity(0.75)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: color.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: color)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500, height: 1.3),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}