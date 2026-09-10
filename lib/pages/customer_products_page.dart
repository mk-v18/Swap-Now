import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'product_detail_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CustomerProductsPage
//
// Opened from the chat screen's new "Customer Products" icon. Shows the
// OTHER person's still-available listings (i.e. everything in their
// `UserProductList` that hasn't been marked `status: 'exchanged'` yet) so
// either side of a chat can browse what the other person still has to swap.
//
// Because this is driven entirely by `userId` (the other participant's uid,
// passed in as `widget.receiverId` from ChatScreen), the exact same page
// works symmetrically in both directions: when user1 opens it from the chat
// they see user2's unexchanged items, and when user2 opens the identical
// chat screen (where `receiverId` now resolves to user1) they see user1's.
//
// This intentionally reuses `ProductDetailPage` (already view-only unless
// *you* happen to have an accepted swap on that exact listing) instead of
// duplicating the detail screen, and mirrors the card styling from
// `MyProductsPage` minus the Edit/Delete actions, which don't make sense on
// someone else's listings.
// ─────────────────────────────────────────────────────────────────────────────
class CustomerProductsPage extends StatelessWidget {
  final String userId;
  final String userName;

  const CustomerProductsPage({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;
    final isSmall = screenWidth < 360;

    final crossAxisCount = isTablet ? 3 : (isSmall ? 1 : 2);
    final hPadding = isTablet ? 20.0 : 16.0;
    final spacing = isTablet ? 16.0 : 12.0;
    final aspectRatio = isSmall ? 0.75 : (isTablet ? 0.72 : 0.70);

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          "$userName's Products",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.black, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFF0ECFF)),
        ),
      ),
      // NOTE: filtered client-side (status != 'exchanged') rather than in the
      // Firestore query itself — Firestore's `!=` operator has awkward
      // interactions with `orderBy` on a different field (it implicitly
      // requires the orderBy to be on the same field as the inequality), and
      // a single user's listing count is small enough that this is cheap.
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('UserProductList')
            .where('userId', isEqualTo: userId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Something went wrong'));
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6A00FF)),
            );
          }

          final products = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return (data['status'] ?? '') != 'exchanged';
          }).toList();

          if (products.isEmpty) {
            return _buildEmptyState(isSmall);
          }

          return GridView.builder(
            padding: EdgeInsets.fromLTRB(
                hPadding, hPadding, hPadding, hPadding + 8),
            itemCount: products.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: aspectRatio,
            ),
            itemBuilder: (context, index) {
              final doc = products[index];
              final data = doc.data() as Map<String, dynamic>;
              final images = List<String>.from(data['images'] ?? []);

              return _CustomerProductCard(
                data: data,
                images: images,
                onView: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductDetailPage(
                      productId: doc.id,
                      data: data,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isSmall) {
    final iconSize = isSmall ? 52.0 : 64.0;
    const accent = Color(0xFF4A148C);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: iconSize + 56,
                  height: iconSize + 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withOpacity(0.06),
                  ),
                ),
                Container(
                  width: iconSize + 36,
                  height: iconSize + 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withOpacity(0.10),
                  ),
                ),
                Container(
                  width: iconSize + 20,
                  height: iconSize + 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withOpacity(0.14),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: iconSize * 0.5,
                    color: accent,
                  ),
                ),
              ],
            ),
            SizedBox(height: isSmall ? 16 : 20),
            Text(
              'No products available',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: isSmall ? 15 : 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "$userName hasn't listed anything that's still available.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: isSmall ? 12 : 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// View-only product card — same visual language as MyProductsPage's
// _ProductCard, but with the Edit/Delete footer actions stripped out
// since these listings don't belong to the person browsing them.
// ─────────────────────────────────────────────────────────────
class _CustomerProductCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final List<String> images;
  final VoidCallback onView;

  const _CustomerProductCard({
    required this.data,
    required this.images,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 360;
    final isTablet = screenWidth >= 600;

    final titleFontSize = isSmall ? 13.0 : (isTablet ? 15.0 : 14.0);

    const Color borderColor = Color(0xFFECEAFF);
    const Color purple = Color(0xFF6A00FF);

    return GestureDetector(
      onTap: onView,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            // ── Image ─────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: const Color(0xFFEEEEEE),
                        child: images.isNotEmpty
                            ? Image.network(
                          images[0],
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (_, __, ___) => Center(
                            child: Icon(
                              Icons.image_not_supported,
                              color: Colors.grey.shade400,
                              size: isSmall ? 24 : 30,
                            ),
                          ),
                        )
                            : Center(
                          child: Icon(
                            Icons.image_not_supported,
                            color: Colors.grey.shade400,
                            size: isSmall ? 24 : 30,
                          ),
                        ),
                      ),
                    ),
                    if ((data['condition'] ?? '').toString().isNotEmpty)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            data['condition'],
                            style: TextStyle(
                              fontSize: isSmall ? 8 : 10,
                              fontWeight: FontWeight.w600,
                              color: purple,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Title ─────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                  isSmall ? 10 : 12, 8, isSmall ? 10 : 12, 0),
              child: Text(
                data['title'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: titleFontSize,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
            ),

            // ── View button — full width, no Edit/Delete ──────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                isSmall ? 10 : 12,
                8,
                isSmall ? 10 : 12,
                isSmall ? 8 : 10,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 1),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onView,
                    borderRadius: BorderRadius.circular(12),
                    splashColor: purple.withOpacity(0.10),
                    highlightColor: purple.withOpacity(0.05),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          vertical: isSmall ? 8 : 9, horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.visibility_outlined,
                              size: isSmall ? 14 : 15, color: purple),
                          const SizedBox(width: 5),
                          Text(
                            'View',
                            style: TextStyle(
                              fontSize: isSmall ? 11 : 12,
                              fontWeight: FontWeight.w600,
                              color: purple,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}