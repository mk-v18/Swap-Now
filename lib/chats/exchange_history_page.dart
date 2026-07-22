import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'swap_request_service.dart';

class _T {
  static const purple = Color(0xFF6A1B9A);
  static const teal = Color(0xFF00796B);
  static const textDark = Color(0xFF1A1A2E);
  static const textLight = Color(0xFF9999AA);
}

class ExchangeHistoryPage extends StatelessWidget {
  const ExchangeHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = SwapRequestService();
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          "Exchange History",
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
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
      body: StreamBuilder<QuerySnapshot>(
        stream: service.myExchangeHistory(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_rounded, size: 46, color: Colors.grey[350]),
                  const SizedBox(height: 10),
                  Text('No completed exchanges yet',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13.5)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final participants = List<String>.from(data['participants'] ?? []);
              final names = Map<String, dynamic>.from(data['participantNames'] ?? {});
              final otherUid = participants.firstWhere((u) => u != myUid, orElse: () => '');
              final otherName = names[otherUid] ?? 'Someone';
              final listedProduct = Map<String, dynamic>.from(data['listedProduct'] ?? {});
              final offered = ((data['offeredProducts'] as List?) ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
              final ts = (data['completedAt'] as Timestamp?)?.toDate();
              final dateLabel = ts != null ? DateFormat('MMM d, yyyy').format(ts) : '—';

              // NEW: distinguish completed vs cancelled entries. Defaults to
              // 'completed' for backward compatibility with history docs
              // written before the cancel flow existed (they have no
              // `status` field at all).
              final status = (data['status'] ?? 'completed') as String;
              final isCancelled = status == 'cancelled';
              final statusColor = isCancelled ? Colors.redAccent : _T.teal;
              final statusIcon = isCancelled ? Icons.cancel_rounded : Icons.check_circle_rounded;
              final statusVerb = isCancelled ? 'Cancelled with ' : 'Exchanged with ';

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1), shape: BoxShape.circle),
                          child: Icon(statusIcon, color: statusColor, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 13, color: _T.textDark),
                              children: [
                                TextSpan(text: statusVerb),
                                TextSpan(text: otherName, style: const TextStyle(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                        Text(dateLabel, style: const TextStyle(fontSize: 11.5, color: _T.textLight)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _productChip('Received', listedProduct['title'] ?? 'Product', isCancelled ? Colors.grey : _T.purple),
                    if (offered.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ...offered.map((p) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: _productChip('Given', p['title'] ?? 'Product', isCancelled ? Colors.grey : _T.teal),
                      )),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _productChip(String label, String title, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Text(label, style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _T.textDark)),
        ),
      ],
    );
  }
}