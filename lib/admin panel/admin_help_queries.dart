import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:credbro/help/help_query_model.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';


// ---------------------------------------------------------------------------
// Responsive helpers (same _clamp/_Resp/_Screen pattern used across the app)
// ---------------------------------------------------------------------------
double _clamp(double value, double min, double max) =>
    value < min ? min : (value > max ? max : value);

class _Screen {
  final double width;
  final double height;
  const _Screen(this.width, this.height);
  factory _Screen.of(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return _Screen(size.width, size.height);
  }
}

class _Resp {
  final _Screen screen;
  const _Resp(this.screen);
  double w(double value) => _clamp(screen.width * (value / 390), value * 0.75, value * 1.4);
  double h(double value) => _clamp(screen.height * (value / 844), value * 0.75, value * 1.4);
  double sp(double value) => _clamp(screen.width * (value / 390), value * 0.85, value * 1.25);
}

const Color _kLavenderBg = Color(0xFFFFFFFF);
const Color _kPurpleStart = Color(0xFF5800B3);
const Color _kPurpleEnd = Color(0xFF26004D);
const Color _kCardWhite = Colors.white;

class AdminHelpQueriesPage extends StatefulWidget {
  const AdminHelpQueriesPage({super.key});

  @override
  State<AdminHelpQueriesPage> createState() => _AdminHelpQueriesPageState();
}

class _AdminHelpQueriesPageState extends State<AdminHelpQueriesPage> {
  QueryStatus? _filter; // null = All
  String _search = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _Resp(_Screen.of(context));

    return Scaffold(
      backgroundColor: _kLavenderBg,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          "Support Queries",
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
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.black, size: 18),
            onPressed: () {
              Navigator.pop(context);
            }
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(r),
          _buildFilterChips(r),
          Expanded(child: _buildList(r)),
        ],
      ),
    );
  }

  Widget _buildSearchBar(_Resp r) {
    return Padding(
      padding: EdgeInsets.fromLTRB(r.w(16), r.h(10), r.w(16), r.h(4)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r.w(14)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
          style: TextStyle(fontSize: r.sp(14), color: Colors.black87),
          decoration: InputDecoration(
            hintText: 'Search by subject or user name',
            hintStyle: TextStyle(fontSize: r.sp(13), color: Colors.grey.shade500),
            prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade500, size: r.sp(22)),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
              icon: Icon(Icons.close_rounded, color: Colors.grey.shade500, size: r.sp(20)),
              onPressed: () {
                _searchController.clear();
                setState(() => _search = '');
              },
            )
                : null,
            filled: true,
            fillColor: _kCardWhite,
            contentPadding: EdgeInsets.symmetric(vertical: r.h(14), horizontal: r.w(12)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(r.w(14)),
              borderSide: const BorderSide(color: _kPurpleStart, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(r.w(14)),
              borderSide: const BorderSide(color: _kPurpleStart, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(r.w(14)),
              borderSide: const BorderSide(color: _kPurpleStart, width: 1), // replace with your actual brand color
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips(_Resp r) {
    final options = <_FilterOption>[
      _FilterOption('All', null, Icons.apps_rounded),
      _FilterOption('Pending', QueryStatus.pending, Icons.hourglass_top_rounded),
      _FilterOption('In Progress', QueryStatus.inProgress, Icons.autorenew_rounded),
      _FilterOption('Resolved', QueryStatus.resolved, Icons.check_circle_rounded),
    ];

    return SizedBox(
      height: r.h(46),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: r.w(16), vertical: r.h(4)),
        itemCount: options.length,
        separatorBuilder: (_, __) => SizedBox(width: r.w(10)),
        itemBuilder: (context, index) {
          final option = options[index];
          final selected = _filter == option.status;

          return GestureDetector(
            onTap: () => setState(() => _filter = option.status),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              padding: EdgeInsets.symmetric(horizontal: r.w(16), vertical: r.h(10)),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(r.w(24)),
                gradient: selected
                    ? LinearGradient(
                  colors: [_kPurpleStart, _kPurpleStart.withOpacity(0.75)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
                    : null,
                color: selected ? null : _kCardWhite,
                border: selected
                    ? null
                    : Border.all(color: Colors.grey.shade300, width: 1),
                boxShadow: selected
                    ? [
                  BoxShadow(
                    color: _kPurpleStart.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
                    : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    option.icon,
                    size: r.sp(15),
                    color: selected ? Colors.white : Colors.grey.shade600,
                  ),
                  SizedBox(width: r.w(6)),
                  Text(
                    option.label,
                    style: TextStyle(
                      fontSize: r.sp(12.5),
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  Widget _buildList(_Resp r) {
    Query<Map<String, dynamic>> query =
    FirebaseFirestore.instance.collection('help_queries').orderBy('createdAt', descending: true);
    if (_filter != null) {
      query = query.where('status', isEqualTo: _filter!.value);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Failed to load queries.', style: TextStyle(fontSize: r.sp(13), color: Colors.grey.shade600)),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _kPurpleStart));
        }

        var docs = snapshot.data?.docs ?? [];
        var items = docs.map(HelpQuery.fromDoc).toList();

        if (_search.isNotEmpty) {
          items = items
              .where((q) => q.subject.toLowerCase().contains(_search) || q.userName.toLowerCase().contains(_search))
              .toList();
        }

        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(r.w(24)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    _search.isNotEmpty
                        ? 'assets/images/no_search_results.png'
                        : 'assets/images/no_queries.png',
                    width: r.w(180),
                    height: r.w(180),
                    fit: BoxFit.contain,
                  ),
                  SizedBox(height: r.h(12)),
                  Text(
                    _search.isNotEmpty ? 'No matching queries' : 'No queries found',
                    style: TextStyle(fontSize: r.sp(16), fontWeight: FontWeight.w700, color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: r.h(6)),
                  Text(
                    _search.isNotEmpty
                        ? 'Try a different search term'
                        : 'New help queries will appear here',
                    style: TextStyle(fontSize: r.sp(13), color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(r.w(16), r.h(8), r.w(16), r.h(24)),
          itemCount: items.length,
          itemBuilder: (context, index) => _AdminQueryCard(query: items[index], r: r),
        );
      },
    );
  }
}

class _AdminQueryCard extends StatelessWidget {
  final HelpQuery query;
  final _Resp r;
  const _AdminQueryCard({required this.query, required this.r});

  Color get _statusColor {
    switch (query.status) {
      case QueryStatus.pending:
        return Colors.orange.shade700;
      case QueryStatus.inProgress:
        return Colors.blue.shade700;
      case QueryStatus.resolved:
        return Colors.green.shade700;
    }
  }

  IconData get _statusIcon {
    switch (query.status) {
      case QueryStatus.pending:
        return Icons.hourglass_top_rounded;
      case QueryStatus.inProgress:
        return Icons.autorenew_rounded;
      case QueryStatus.resolved:
        return Icons.check_circle_rounded;
    }
  }

  String get _initials {
    final parts = query.userName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first[0];
    final second = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = query.createdAt != null ? DateFormat('MMM d, h:mm a').format(query.createdAt!) : '';

    return InkWell(
      borderRadius: BorderRadius.circular(r.w(16)),
      onTap: () => _openDetail(context),
      child: Container(
        margin: EdgeInsets.only(bottom: r.h(12)),
        decoration: BoxDecoration(
          color: _kCardWhite,
          borderRadius: BorderRadius.circular(r.w(16)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4)),
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 2, offset: const Offset(0, 1)),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status accent bar
              Container(
                width: r.w(4),
                decoration: BoxDecoration(
                  color: _statusColor,
                  borderRadius: BorderRadius.horizontal(left: Radius.circular(r.w(16))),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(r.w(14), r.h(14), r.w(14), r.h(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(query.subject,
                                style: TextStyle(fontSize: r.sp(15), fontWeight: FontWeight.w700, color: Colors.black87),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          SizedBox(width: r.w(8)),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: r.w(10), vertical: r.h(5)),
                            decoration: BoxDecoration(
                              color: _statusColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(r.w(20)),
                              border: Border.all(color: _statusColor.withOpacity(0.25), width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_statusIcon, size: r.sp(11), color: _statusColor),
                                SizedBox(width: r.w(4)),
                                Text(query.status.label,
                                    style: TextStyle(color: _statusColor, fontSize: r.sp(10.5), fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: r.h(10)),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: r.w(11),
                            backgroundColor: _kPurpleStart.withOpacity(0.15),
                            child: Text(_initials,
                                style: TextStyle(fontSize: r.sp(9.5), fontWeight: FontWeight.w700, color: _kPurpleStart)),
                          ),
                          SizedBox(width: r.w(6)),
                          Expanded(
                            child: Text(query.userName,
                                style: TextStyle(fontSize: r.sp(12.5), color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: r.w(8), vertical: r.h(3)),
                            decoration: BoxDecoration(
                              color: _kPurpleStart.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(r.w(8)),
                            ),
                            child: Text(query.category,
                                style: TextStyle(fontSize: r.sp(10.5), color: _kPurpleStart, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      SizedBox(height: r.h(8)),
                      Text(query.message,
                          style: TextStyle(fontSize: r.sp(13), color: Colors.black87, height: 1.35),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      SizedBox(height: r.h(8)),
                      Divider(height: 1, color: Colors.grey.shade200),
                      SizedBox(height: r.h(6)),
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded, size: r.sp(12), color: Colors.grey.shade400),
                          SizedBox(width: r.w(4)),
                          Text(dateStr, style: TextStyle(fontSize: r.sp(11), color: Colors.grey.shade500)),
                          const Spacer(),
                          Icon(Icons.chevron_right_rounded, size: r.sp(16), color: Colors.grey.shade400),
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

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QueryDetailSheet(query: query),
    );
  }
}

class _QueryDetailSheet extends StatefulWidget {
  final HelpQuery query;
  const _QueryDetailSheet({required this.query});

  @override
  State<_QueryDetailSheet> createState() => _QueryDetailSheetState();
}

class _QueryDetailSheetState extends State<_QueryDetailSheet> {
  late QueryStatus _status;
  late final TextEditingController _noteController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _status = widget.query.status;
    _noteController = TextEditingController(text: widget.query.adminNote);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Color _statusColor(QueryStatus s) {
    switch (s) {
      case QueryStatus.pending:
        return Colors.orange.shade700;
      case QueryStatus.inProgress:
        return Colors.blue.shade700;
      case QueryStatus.resolved:
        return Colors.green.shade700;
    }
  }

  IconData _statusIcon(QueryStatus s) {
    switch (s) {
      case QueryStatus.pending:
        return Icons.hourglass_top_rounded;
      case QueryStatus.inProgress:
        return Icons.autorenew_rounded;
      case QueryStatus.resolved:
        return Icons.check_circle_rounded;
    }
  }

  Future<void> _launch(String scheme, String value, {String? subject}) async {
    if (value.trim().isEmpty) {
      _showSnack('No contact info available.', isError: true);
      return;
    }
    Uri uri;
    if (scheme == 'tel') {
      uri = Uri(scheme: 'tel', path: value.trim());
    } else {
      uri = Uri(scheme: 'mailto', path: value.trim(), queryParameters: subject != null ? {'subject': subject} : null);
    }
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        _showSnack('Could not open ${scheme == 'tel' ? 'dialer' : 'email app'}.', isError: true);
      }
    } catch (_) {
      if (mounted) _showSnack('Could not open ${scheme == 'tel' ? 'dialer' : 'email app'}.', isError: true);
    }
  }

  Future<void> _save({bool markContacted = false}) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final Map<String, dynamic> update = {
        'status': _status.value,
        'adminNote': _noteController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (markContacted) {
        update['contactedAt'] = FieldValue.serverTimestamp();
      }
      await FirebaseFirestore.instance.collection('help_queries').doc(widget.query.id).update(update);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showSnack('Failed to save changes. Try again.', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _Resp(_Screen.of(context));
    final q = widget.query;
    final dateStr = q.createdAt != null ? DateFormat('MMM d, y • h:mm a').format(q.createdAt!) : '';
    final contactedStr =
    q.contactedAt != null ? DateFormat('MMM d, h:mm a').format(q.contactedAt!) : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: _kLavenderBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(r.w(24))),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, -4)),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(r.w(20), r.h(12), r.w(20), r.h(20)),
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: r.w(42),
                  height: r.h(5),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              SizedBox(height: r.h(18)),

              // Header: subject + current status badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(q.subject,
                        style: TextStyle(fontSize: r.sp(19), fontWeight: FontWeight.w800, color: Colors.black87)),
                  ),
                  SizedBox(width: r.w(10)),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: r.w(10), vertical: r.h(5)),
                    decoration: BoxDecoration(
                      color: _statusColor(_status).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(r.w(20)),
                      border: Border.all(color: _statusColor(_status).withOpacity(0.3), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_statusIcon(_status), size: r.sp(12), color: _statusColor(_status)),
                        SizedBox(width: r.w(4)),
                        Text(_status.label,
                            style: TextStyle(
                                color: _statusColor(_status), fontSize: r.sp(10.5), fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: r.h(4)),
              Row(
                children: [
                  Icon(Icons.access_time_rounded, size: r.sp(12), color: Colors.grey.shade500),
                  SizedBox(width: r.w(4)),
                  Text(dateStr, style: TextStyle(fontSize: r.sp(12), color: Colors.grey.shade600)),
                ],
              ),
              SizedBox(height: r.h(18)),

              _sectionCard(
                r,
                title: 'User',
                icon: Icons.person_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow(r, Icons.person_outline, q.userName),
                    if (q.userEmail.isNotEmpty) _infoRow(r, Icons.email_outlined, q.userEmail),
                    if (q.userPhone.isNotEmpty) _infoRow(r, Icons.phone_outlined, q.userPhone),
                    SizedBox(height: r.h(12)),
                    Row(
                      children: [
                        Expanded(
                          child: _outlineActionButton(
                            r,
                            icon: Icons.call_rounded,
                            label: 'Call',
                            color: Colors.green.shade700,
                            onTap: () => _launch('tel', q.userPhone),
                          ),
                        ),
                        SizedBox(width: r.w(10)),
                        Expanded(
                          child: _outlineActionButton(
                            r,
                            icon: Icons.email_rounded,
                            label: 'Email',
                            color: _kPurpleStart,
                            onTap: () => _launch('mailto', q.userEmail, subject: 'Re: ${q.subject}'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: r.h(14)),

              _sectionCard(
                r,
                title: 'Category: ${q.category}',
                icon: Icons.label_rounded,
                child: Text(q.message, style: TextStyle(fontSize: r.sp(14), height: 1.45, color: Colors.black87)),
              ),
              SizedBox(height: r.h(14)),

              _sectionCard(
                r,
                title: 'Update Status',
                icon: Icons.flag_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: r.w(8),
                      runSpacing: r.h(8),
                      children: QueryStatus.values.map((s) {
                        final selected = _status == s;
                        final color = _statusColor(s);
                        return GestureDetector(
                          onTap: () => setState(() => _status = s),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: EdgeInsets.symmetric(horizontal: r.w(14), vertical: r.h(9)),
                            decoration: BoxDecoration(
                              color: selected ? color : color.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(r.w(20)),
                              border: Border.all(color: selected ? color : color.withOpacity(0.25), width: 1.2),
                              boxShadow: selected
                                  ? [BoxShadow(color: color.withOpacity(0.35), blurRadius: 2, offset: const Offset(0, 1))]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_statusIcon(s), size: r.sp(13), color: selected ? Colors.white : color),
                                SizedBox(width: r.w(5)),
                                Text(s.label,
                                    style: TextStyle(
                                        fontSize: r.sp(12),
                                        fontWeight: FontWeight.w600,
                                        color: selected ? Colors.white : color)),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (contactedStr != null) ...[
                      SizedBox(height: r.h(10)),
                      Row(
                        children: [
                          Icon(Icons.phone_callback_rounded, size: r.sp(13), color: Colors.grey.shade500),
                          SizedBox(width: r.w(5)),
                          Text('Last contacted: $contactedStr',
                              style: TextStyle(fontSize: r.sp(11), color: Colors.grey.shade600)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: r.h(14)),

              _sectionCard(
                r,
                title: 'Internal Note',
                subtitle: 'Visible to user once resolved',
                icon: Icons.edit_note_rounded,
                child: TextField(
                  controller: _noteController,
                  maxLines: 3,
                  maxLength: 300,
                  style: TextStyle(fontSize: r.sp(13.5)),
                  decoration: InputDecoration(
                    hintText: 'e.g. Refund processed, contacted via call...',
                    hintStyle: TextStyle(fontSize: r.sp(12), color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: EdgeInsets.symmetric(horizontal: r.w(12), vertical: r.h(10)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(r.w(10)),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(r.w(10)),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(r.w(10)),
                      borderSide: BorderSide(color: _kPurpleStart, width: 1.4),
                    ),
                  ),
                ),
              ),
              SizedBox(height: r.h(20)),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : () => _save(markContacted: true),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: r.h(13)),
                        side: BorderSide(color: Colors.grey.shade400),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.w(12))),
                      ),
                      icon: Icon(Icons.check_circle_outline, size: r.w(16), color: Colors.black87),
                      label: Text('Mark Contacted',
                          style: TextStyle(fontSize: r.sp(13), color: Colors.black87, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  SizedBox(width: r.w(10)),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [_kPurpleStart, _kPurpleEnd]),
                        borderRadius: BorderRadius.circular(r.w(12)),
                        boxShadow: [
                          BoxShadow(color: _kPurpleStart.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : () => _save(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: EdgeInsets.symmetric(vertical: r.h(13)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.w(12))),
                        ),
                        child: _isSaving
                            ? SizedBox(
                          height: r.h(18),
                          width: r.h(18),
                          child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                            : Text('Save Changes',
                            style: TextStyle(color: Colors.white, fontSize: r.sp(14), fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: r.h(20)),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionCard(_Resp r, {required String title, String? subtitle, required IconData icon, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(r.w(15)),
      decoration: BoxDecoration(
        color: _kCardWhite,
        borderRadius: BorderRadius.circular(r.w(16)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(r.w(5)),
                decoration: BoxDecoration(
                  color: _kPurpleStart.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(r.w(7)),
                ),
                child: Icon(icon, size: r.sp(13), color: _kPurpleStart),
              ),
              SizedBox(width: r.w(8)),
              Expanded(
                child: Text(title,
                    style: TextStyle(fontSize: r.sp(12.5), fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
              ),
            ],
          ),
          if (subtitle != null) ...[
            SizedBox(height: r.h(2)),
            Padding(
              padding: EdgeInsets.only(left: r.w(30)),
              child: Text(subtitle, style: TextStyle(fontSize: r.sp(10.5), color: Colors.grey.shade500)),
            ),
          ],
          SizedBox(height: r.h(10)),
          child,
        ],
      ),
    );
  }

  Widget _infoRow(_Resp r, IconData icon, String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: r.h(6)),
      child: Row(
        children: [
          Icon(icon, size: r.w(15), color: Colors.grey.shade500),
          SizedBox(width: r.w(8)),
          Expanded(child: Text(text, style: TextStyle(fontSize: r.sp(13), color: Colors.black87))),
        ],
      ),
    );
  }

  Widget _outlineActionButton(_Resp r,
      {required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(vertical: r.h(11)),
        side: BorderSide(color: color.withOpacity(0.4)),
        backgroundColor: color.withOpacity(0.06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.w(10))),
      ),
      icon: Icon(icon, size: r.w(16), color: color),
      label: Text(label, style: TextStyle(fontSize: r.sp(13), color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _FilterOption {
  final String label;
  final QueryStatus? status;
  final IconData icon;
  const _FilterOption(this.label, this.status, this.icon);
}