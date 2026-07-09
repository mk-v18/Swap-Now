import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PaymentsDetails extends StatefulWidget {
  const PaymentsDetails({super.key});

  @override
  State<PaymentsDetails> createState() => _PaymentsDetailsState();
}

class _PaymentsDetailsState extends State<PaymentsDetails> {
  static const Color _brand = Color(0xFF5800B3);
  static const Color _title = Color(0xFF0D1B4B);

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
        message: 'Please log in to view your payment history.',
      )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('payments')
            .where('userId', isEqualTo: user.uid)
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _EmptyState(
              icon: Icons.error_outline,
              message:
              'Could not load payments right now.\nPlease try again shortly.',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _brand),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const _EmptyState(
              icon: Icons.receipt_long_outlined,
              message: 'No payments yet.\nYour transaction history will show up here.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              return _PaymentCard(data: data);
            },
          );
        },
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.data});

  final Map<String, dynamic> data;

  static const Color _brand = Color(0xFF5800B3);

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] as String?) ?? 'unknown';
    final isSuccess =
        status == 'pending_verification' || status == 'verified' || status == 'success';
    final isFailed = status == 'failed';

    final amountPaise = data['amount'] as int?;
    final amountText = amountPaise != null
        ? '₹${(amountPaise / 100).toStringAsFixed(2)}'
        : '—';

    final paymentId = data['paymentId'] as String?;
    final orderId = data['orderId'] as String?;
    final message = data['message'] as String?;
    final code = data['code'];

    final ts = data['timestamp'];
    String dateText = '—';
    if (ts is Timestamp) {
      dateText = DateFormat('d MMM yyyy, h:mm a').format(ts.toDate());
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
              Text(
                isFailed ? 'Payment Failed' : 'Registration Fee',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0D1B4B),
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
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}