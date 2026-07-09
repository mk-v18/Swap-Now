import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'help_query_model.dart';

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

// ---------------------------------------------------------------------------
// Theme constants (matches AdminChatPage / ChatsPage design language)
// ---------------------------------------------------------------------------
const Color _kLavenderBg = Color(0xFFFFFFFF);
const Color _kPurpleStart = Color(0xFF5800B3);
const Color _kPurpleEnd = Color(0xFF26004D);
const Color _kCardWhite = Colors.white;
const LinearGradient _kBrandGradient =
LinearGradient(colors: [_kPurpleStart, _kPurpleEnd]);

class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key});

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  final _phoneController = TextEditingController();

  String _category = kHelpQueryCategories.first;
  bool _isSubmitting = false;

  // Non-null while the form sheet is editing an existing query instead of
  // creating a new one.
  String? _editingDocId;

  String _userName = '';
  String _userEmail = '';
  DateTime? _lastSubmitAt;

  @override
  void initState() {
    super.initState();
    _prefillUserInfo();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _prefillUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _userEmail = user.email ?? '';
    _userName = user.displayName ?? '';
    _phoneController.text = user.phoneNumber ?? '';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!mounted) return;
      final data = doc.data();
      if (data != null) {
        setState(() {
          _userName = (data['name'] as String?)?.trim().isNotEmpty == true
              ? data['name'] as String
              : _userName;
          _userEmail = (data['email'] as String?)?.trim().isNotEmpty == true
              ? data['email'] as String
              : _userEmail;
          if (_phoneController.text.isEmpty) {
            _phoneController.text = (data['phone'] as String?) ?? '';
          }
        });
      }
    } catch (_) {
      // Silent fallback — form still works with FirebaseAuth values only.
    }
  }

  Future<void> _submitQuery(StateSetter setModalState) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('Please sign in to submit a query.', isError: true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    // Guard against accidental double submission / spam taps.
    final now = DateTime.now();
    if (_lastSubmitAt != null && now.difference(_lastSubmitAt!) < const Duration(seconds: 20)) {
      _showSnack('Please wait a few seconds before submitting again.', isError: true);
      return;
    }
    if (_isSubmitting) return;

    setModalState(() => _isSubmitting = true);

    final isEditing = _editingDocId != null;

    try {
      if (isEditing) {
        await FirebaseFirestore.instance
            .collection('help_queries')
            .doc(_editingDocId)
            .update({
          'category': _category,
          'subject': _subjectController.text.trim(),
          'message': _messageController.text.trim(),
          'userPhone': _phoneController.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseFirestore.instance.collection('help_queries').add({
          'userId': user.uid,
          'userName': _userName.trim().isEmpty ? 'Unknown' : _userName.trim(),
          'userEmail': _userEmail.trim(),
          'userPhone': _phoneController.text.trim(),
          'category': _category,
          'subject': _subjectController.text.trim(),
          'message': _messageController.text.trim(),
          'status': QueryStatus.pending.value,
          'adminNote': '',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'contactedAt': null,
        });
      }

      if (!mounted) return;
      _lastSubmitAt = now;
      _subjectController.clear();
      _messageController.clear();
      _isSubmitting = false;
      _editingDocId = null;
      Navigator.of(context).pop();
      _showSnack(isEditing
          ? 'Your query has been updated.'
          : 'Your query has been submitted. We\'ll get back to you soon.');
    } catch (e) {
      if (!mounted) return;
      setModalState(() => _isSubmitting = false);
      _showSnack('Failed to submit. Please check your connection and try again.', isError: true);
    }
  }

  Future<void> _confirmDeleteQuery(HelpQuery query) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete query?'),
        content: Text('This will permanently remove "${query.subject}". This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('help_queries')
          .doc(query.id)
          .delete();
      if (!mounted) return;
      _showSnack('Query deleted.');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to delete. Please try again.', isError: true);
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
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: _kLavenderBg,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Help Center',
          style: TextStyle(
              color: Color(0xFF1A1A2E),
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3),
        ),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.black, size: 18),
            onPressed: () {
              Navigator.pop(context);
            }
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFF0ECFF)),
        ),
      ),
      body: user == null
          ? _SignInPrompt(r: r)
          : Column(
        children: [
          _buildHeaderCard(r),
          Expanded(child: _buildQueryList(r, user.uid)),
        ],
      ),
      floatingActionButton: user == null
          ? null
          : Container(
        decoration: BoxDecoration(
          gradient: _kBrandGradient,
          borderRadius: BorderRadius.circular(r.w(28)),
          boxShadow: [
            BoxShadow(
              color: _kPurpleStart.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () => _openFormSheet(r),
          backgroundColor: Colors.transparent,
          elevation: 0,
          highlightElevation: 0,
          icon: const Icon(Icons.add_comment_outlined, color: Colors.white),
          label: const Text(
            'New Query',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  // [existing] omitted for the new query case; pass a HelpQuery to edit it.
  void _openFormSheet(_Resp r, {HelpQuery? existing}) {
    _isSubmitting = false;

    if (existing != null) {
      _editingDocId = existing.id;
      _category = existing.category;
      _subjectController.text = existing.subject;
      _messageController.text = existing.message;
      // Phone is left as-is (prefilled from profile) unless the query stored
      // its own contact number.
    } else {
      _editingDocId = null;
      _category = kHelpQueryCategories.first;
      _subjectController.clear();
      _messageController.clear();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Bottom sheet resizes with the keyboard and scrolls internally
            // instead of the page's own Column overflowing.
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: DraggableScrollableSheet(
                initialChildSize: 0.85,
                minChildSize: 0.5,
                maxChildSize: 0.95,
                expand: false,
                builder: (context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: _kCardWhite,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(r.w(20))),
                    ),
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(r.w(16), r.h(10), r.w(16), r.h(24)),
                      child: _buildFormCard(r, setModalState),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      // Reset edit state if the sheet is dismissed without submitting.
      _editingDocId = null;
    });
  }

  Widget _buildHeaderCard(_Resp r) {
    return Container(
      margin: EdgeInsets.fromLTRB(r.w(16), r.h(12), r.w(16), r.h(4)),
      padding: EdgeInsets.all(r.w(16)),
      decoration: BoxDecoration(
        gradient: _kBrandGradient,
        borderRadius: BorderRadius.circular(r.w(16)),
      ),
      child: Row(
        children: [
          Icon(Icons.support_agent_rounded, color: Colors.white, size: r.w(32)),
          SizedBox(width: r.w(12)),
          Expanded(
            child: Text(
              'Have an issue or question? Submit a query and our support team will contact you directly.',
              style: TextStyle(color: Colors.white, fontSize: r.sp(13), height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(_Resp r, StateSetter setModalState) {
    final isEditing = _editingDocId != null;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: r.w(40),
              height: r.h(4),
              margin: EdgeInsets.only(bottom: r.h(18)),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(r.w(4)),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: r.w(44),
                height: r.w(44),
                decoration: BoxDecoration(
                  gradient: _kBrandGradient,
                  borderRadius: BorderRadius.circular(r.w(13)),
                  boxShadow: [
                    BoxShadow(
                      color: _kPurpleStart.withOpacity(0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  isEditing ? Icons.edit_note_rounded : Icons.support_agent_rounded,
                  color: Colors.white,
                  size: r.w(24),
                ),
              ),
              SizedBox(width: r.w(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isEditing ? 'Edit your query' : 'Submit a new query',
                        style: TextStyle(
                            fontSize: r.sp(17),
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1A1A2E),
                            letterSpacing: -0.3)),
                    SizedBox(height: r.h(2)),
                    Text(
                      isEditing
                          ? 'Update the details below and save your changes.'
                          : 'Our support team usually replies within 24 hours.',
                      style: TextStyle(fontSize: r.sp(12), color: Colors.grey.shade600, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: r.h(22)),
          _sectionLabel('Category', Icons.category_outlined, r),
          SizedBox(height: r.h(8)),
          _buildCategoryChips(r, setModalState),
          SizedBox(height: r.h(18)),
          _sectionLabel('Subject', Icons.short_text_rounded, r),
          SizedBox(height: r.h(8)),
          TextFormField(
            controller: _subjectController,
            maxLength: 80,
            style: TextStyle(fontSize: r.sp(14)),
            decoration: _fieldDecoration('e.g. Payment not reflecting', r, icon: Icons.short_text_rounded),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Subject is required' : null,
          ),
          SizedBox(height: r.h(6)),
          _sectionLabel('Describe your issue', Icons.notes_rounded, r),
          SizedBox(height: r.h(8)),
          TextFormField(
            controller: _messageController,
            maxLength: 800,
            maxLines: 5,
            style: TextStyle(fontSize: r.sp(14)),
            decoration: _fieldDecoration('Tell us what happened, with as much detail as you can...', r),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Please describe your issue';
              if (v.trim().length < 10) return 'Please provide a bit more detail';
              return null;
            },
          ),
          SizedBox(height: r.h(6)),
          _sectionLabel('Contact phone', Icons.call_outlined, r),
          SizedBox(height: r.h(8)),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            style: TextStyle(fontSize: r.sp(14)),
            decoration: _fieldDecoration('Where can we reach you?', r, icon: Icons.call_outlined),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Contact phone is required';
              final digitsOnly = v.trim().replaceAll(RegExp(r'\D'), '');
              if (digitsOnly.length < 10) return 'Enter a valid phone number';
              return null;
            },
          ),
          SizedBox(height: r.h(20)),
          SizedBox(
            width: double.infinity,
            height: r.h(52),
            child: Container(
              decoration: BoxDecoration(
                gradient: _isSubmitting ? null : _kBrandGradient,
                color: _isSubmitting ? Colors.grey.shade300 : null,
                borderRadius: BorderRadius.circular(r.w(14)),
                boxShadow: _isSubmitting
                    ? null
                    : [
                  BoxShadow(
                    color: _kPurpleStart.withOpacity(0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : () => _submitQuery(setModalState),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  padding: EdgeInsets.symmetric(vertical: r.h(14)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.w(14))),
                ),
                child: _isSubmitting
                    ? SizedBox(
                  height: r.h(20),
                  width: r.h(20),
                  child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                )
                    : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(isEditing ? Icons.save_outlined : Icons.send_rounded,
                        color: Colors.white, size: r.w(18)),
                    SizedBox(width: r.w(8)),
                    Text(isEditing ? 'Update Query' : 'Submit Query',
                        style: TextStyle(
                            color: Colors.white, fontSize: r.sp(15), fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, IconData icon, _Resp r) {
    return Row(
      children: [
        Icon(icon, size: r.w(15), color: _kPurpleStart),
        SizedBox(width: r.w(6)),
        Text(label,
            style: TextStyle(
                fontSize: r.sp(14),
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1A2E))),
      ],
    );
  }

  Widget _buildCategoryChips(_Resp r, StateSetter setModalState) {
    return Wrap(
      spacing: r.w(8),
      runSpacing: r.h(8),
      children: kHelpQueryCategories.map((c) {
        final selected = c == _category;
        return GestureDetector(
          onTap: () => setModalState(() => _category = c),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(horizontal: r.w(14), vertical: r.h(9)),
            decoration: BoxDecoration(
              gradient: selected ? _kBrandGradient : null,
              color: selected ? null : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(r.w(20)),
              border: Border.all(
                color: selected ? Colors.transparent : Colors.grey.shade300,
                width: 1,
              ),
            ),
            child: Text(
              c,
              style: TextStyle(
                fontSize: r.sp(12.5),
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  InputDecoration _fieldDecoration(String hint, _Resp r, {IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: r.sp(13), color: Colors.grey.shade400),
      prefixIcon: icon == null
          ? null
          : Padding(
        padding: EdgeInsets.only(left: r.w(2)),
        child: Icon(icon, size: r.w(18), color: Colors.grey.shade500),
      ),
      filled: true,
      fillColor: Colors.grey.shade50,
      counterStyle: TextStyle(fontSize: r.sp(10.5), color: Colors.grey.shade400),
      errorStyle: TextStyle(fontSize: r.sp(11), color: Colors.red.shade600),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r.w(12)),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r.w(12)),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r.w(12)),
        borderSide: const BorderSide(color: _kPurpleStart, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r.w(12)),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: r.w(14), vertical: r.h(13)),
    );
  }

  Widget _buildQueryList(_Resp r, String uid) {
    final stream = FirebaseFirestore.instance
        .collection('help_queries')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _CenteredMessage(
            icon: Icons.error_outline,
            text: 'Something went wrong loading your queries.',
            r: r,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _kPurpleStart));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _CenteredMessage(
            icon: Icons.inbox_outlined,
            text: 'No queries yet. Tap "New Query" to reach our support team.',
            r: r,
          );
        }

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(r.w(16), r.h(8), r.w(16), r.h(80)),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final q = HelpQuery.fromDoc(docs[index]);
            return _QueryCard(
              query: q,
              r: r,
              onEdit: () => _openFormSheet(r, existing: q),
              onDelete: () => _confirmDeleteQuery(q),
            );
          },
        );
      },
    );
  }
}

class _QueryCard extends StatelessWidget {
  final HelpQuery query;
  final _Resp r;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _QueryCard({
    required this.query,
    required this.r,
    required this.onEdit,
    required this.onDelete,
  });

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

  // Only allow the user to edit/delete a query support hasn't started
  // working on yet, to avoid clobbering something already in progress.
  bool get _canModify => query.status == QueryStatus.pending;

  @override
  Widget build(BuildContext context) {
    final dateStr = query.createdAt != null ? DateFormat('MMM d, h:mm a').format(query.createdAt!) : '';

    return Container(
      margin: EdgeInsets.only(bottom: r.h(12)),
      padding: EdgeInsets.all(r.w(14)),
      decoration: BoxDecoration(
        color: _kCardWhite,
        borderRadius: BorderRadius.circular(r.w(14)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(query.subject,
                    style: TextStyle(fontSize: r.sp(15), fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: r.w(10), vertical: r.h(4)),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(r.w(20)),
                ),
                child: Text(query.status.label,
                    style: TextStyle(color: _statusColor, fontSize: r.sp(11), fontWeight: FontWeight.w600)),
              ),
              if (_canModify) ...[
                SizedBox(width: r.w(4)),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: r.w(20), color: Colors.grey.shade600),
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: r.w(18), color: _kPurpleStart),
                          SizedBox(width: r.w(8)),
                          const Text('Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: r.w(18), color: Colors.red.shade600),
                          SizedBox(width: r.w(8)),
                          Text('Delete', style: TextStyle(color: Colors.red.shade600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          SizedBox(height: r.h(6)),
          Text(query.category, style: TextStyle(fontSize: r.sp(12), color: _kPurpleStart, fontWeight: FontWeight.w500)),
          SizedBox(height: r.h(6)),
          Text(query.message,
              style: TextStyle(fontSize: r.sp(13), color: Colors.black87, height: 1.3),
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
          if (query.status == QueryStatus.resolved && query.adminNote.trim().isNotEmpty) ...[
            SizedBox(height: r.h(8)),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(r.w(10)),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.06),
                borderRadius: BorderRadius.circular(r.w(10)),
                border: Border.all(color: Colors.green.withOpacity(0.2)),
              ),
              child: Text('Support note: ${query.adminNote}',
                  style: TextStyle(fontSize: r.sp(12), color: Colors.green.shade800)),
            ),
          ],
          SizedBox(height: r.h(8)),
          Text(dateStr, style: TextStyle(fontSize: r.sp(11), color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final _Resp r;
  const _CenteredMessage({required this.icon, required this.text, required this.r});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(r.w(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: r.w(48), color: Colors.grey.shade400),
            SizedBox(height: r.h(12)),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: r.sp(13))),
          ],
        ),
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  final _Resp r;
  const _SignInPrompt({required this.r});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(r.w(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: r.w(48), color: Colors.grey.shade400),
            SizedBox(height: r.h(12)),
            Text('Please sign in to contact support.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: r.sp(14), color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}