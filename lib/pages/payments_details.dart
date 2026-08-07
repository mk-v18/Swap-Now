import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// FIX(gap): This page used to read only the `payments` collection, which
// is written exclusively by the one-time registration fee flow
// (start/payment.dart). The newer per-listing publish fee
// (user_product/product_page.dart) logs its verified payments to a
// SEPARATE `listingPayments` collection — so any ₹49 lifetime unlock or
// per-listing fee a user paid was silently invisible here, even though it
// went through fine. This page now merges both collections into one
// timeline, tagging each entry so the card can show the right title.
class PaymentsDetails extends StatefulWidget {
  const PaymentsDetails({super.key});

  @override
  State<PaymentsDetails> createState() => _PaymentsDetailsState();
}

/// Which collection a merged entry came from — drives title/labels only;
/// both render through the same `_PaymentCard`.
enum _PaymentSource { registration, listing }

class _PaymentEntry {
  final _PaymentSource source;
  final Map<String, dynamic> data;
  final DateTime? timestamp; // null while a serverTimestamp is still pending
  const _PaymentEntry({required this.source, required this.data, required this.timestamp});
}

class _PaymentsDetailsState extends State<PaymentsDetails> {
  static const Color _brand = Color(0xFF5800B3);
  static const Color _title = Color(0xFF0D1B4B);

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _registrationSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _listingSub;

  List<_PaymentEntry>? _registrationEntries; // null = still loading
  List<_PaymentEntry>? _listingEntries;
  String? _registrationError;
  String? _listingError;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _registrationSub = FirebaseFirestore.instance
        .collection('payments')
        .where('userId', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen(
          (snap) {
        if (!mounted) return;
        setState(() {
          _registrationError = null;
          _registrationEntries = snap.docs
              .map((d) => _PaymentEntry(
            source: _PaymentSource.registration,
            data: d.data(),
            timestamp: _tsOf(d.data()['timestamp']),
          ))
              .toList();
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _registrationError = e.toString());
      },
    );

    _listingSub = FirebaseFirestore.instance
        .collection('listingPayments')
        .where('userId', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen(
          (snap) {
        if (!mounted) return;
        setState(() {
          _listingError = null;
          _listingEntries = snap.docs
              .map((d) => _PaymentEntry(
            source: _PaymentSource.listing,
            data: d.data(),
            timestamp: _tsOf(d.data()['timestamp']),
          ))
              .toList();
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _listingError = e.toString());
      },
    );
  }

  static DateTime? _tsOf(dynamic ts) => ts is Timestamp ? ts.toDate() : null;

  @override
  void dispose() {
    _registrationSub?.cancel();
    _listingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        title: const Text(
          'Payments Details',
          style: TextStyle(
            color: _title,
            fontWeight: FontWeight.w600,
            fontSize: 18,
            letterSpacing: -0.3,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.black, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFF0ECFF)),
        ),
      ),
      body: user == null
          ? const _EmptyState(
        icon: Icons.lock_outline,
        title: 'Please log in',
        subtitle: 'Log in to view your payment history',
      )
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_registrationError != null || _listingError != null) {
      return const _EmptyState(
        icon: Icons.error_outline,
        title: 'Could not load payments',
        subtitle: 'Please try again shortly',
        accent: Color(0xFFD32F2F),
      );
    }

    // Either stream can still be on its first snapshot.
    if (_registrationEntries == null || _listingEntries == null) {
      return const Center(child: CircularProgressIndicator(color: _brand));
    }

    final merged = [..._registrationEntries!, ..._listingEntries!]
      ..sort((a, b) {
        // Entries with no timestamp yet (just-written, server round trip
        // still pending) sort first so they're visible immediately.
        if (a.timestamp == null && b.timestamp == null) return 0;
        if (a.timestamp == null) return -1;
        if (b.timestamp == null) return 1;
        return b.timestamp!.compareTo(a.timestamp!);
      });

    if (merged.isEmpty) {
      return const _EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No payments yet',
        subtitle: 'Your transaction history will show up here',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: merged.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _PaymentCard(entry: merged[index]),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.entry});

  final _PaymentEntry entry;

  @override
  Widget build(BuildContext context) {
    final data = entry.data;
    final status = (data['status'] as String?) ?? 'unknown';
    final isFailed = status == 'failed';
    final isSuccess = !isFailed;

    final amountPaise = data['amount'] as int?;
    final amountText = amountPaise != null
        ? '₹${(amountPaise / 100).toStringAsFixed(2)}'
        : '—';

    final paymentId = data['paymentId'] as String?;
    final orderId = data['orderId'] as String?;
    final message = data['message'] as String?;
    final code = data['code'];

    String dateText = '—';
    if (entry.timestamp != null) {
      dateText = DateFormat('d MMM yyyy, h:mm a').format(entry.timestamp!);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _titleFor(entry, isFailed),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0D1B4B),
                  ),
                ),
              ),
              _StatusBadge(status: status, isSuccess: isSuccess, isFailed: isFailed),
            ],
          ),
          const SizedBox(height: 10),
          if (!isFailed) ...[
            _DetailRow(label: 'Amount', value: amountText, emphasize: true),
            if (paymentId != null && paymentId != 'unknown')
              _DetailRow(label: 'Payment ID', value: paymentId),
            if (orderId != null && orderId.isNotEmpty)
              _DetailRow(label: 'Order ID', value: orderId),
          ] else ...[
            if (message != null && message.isNotEmpty)
              _DetailRow(label: 'Reason', value: message),
            if (code != null) _DetailRow(label: 'Error Code', value: code.toString()),
          ],
          _DetailRow(label: 'Date', value: dateText),
        ],
      ),
    );
  }

  String _titleFor(_PaymentEntry entry, bool isFailed) {
    if (isFailed) return 'Payment Failed';
    if (entry.source == _PaymentSource.registration) return 'Registration Fee';
    final feeType = entry.data['feeType'] as String?;
    return feeType == 'lifetime' ? 'Lifetime Listing Access' : 'Listing Fee';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.status,
    required this.isSuccess,
    required this.isFailed,
  });

  final String status;
  final bool isSuccess;
  final bool isFailed;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;

    if (isFailed) {
      bg = const Color(0xFFFDECEC);
      fg = const Color(0xFFB00020);
      label = 'Failed';
    } else if (status == 'verified' || status == 'success') {
      bg = const Color(0xFFE7F6EC);
      fg = const Color(0xFF1B8A4C);
      label = 'Verified';
    } else {
      bg = const Color(0xFFF3E9FF);
      fg = const Color(0xFF5800B3);
      label = 'Processing';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: emphasize ? 14 : 12.5,
                fontWeight: emphasize ? FontWeight.w600 : FontWeight.w500,
                color: emphasize ? const Color(0xFF5800B3) : Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
    this.accent = const Color(0xFF4A148C),
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: accent.withOpacity(0.65)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}