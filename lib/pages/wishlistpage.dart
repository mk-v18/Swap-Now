import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../user_product/model/user_product_listing.dart';
import '../user_product/product_lists.dart';

// ---------------------------------------------------------------------------
// WishlistPage – converted to StatefulWidget for safe context usage and
// proper stream lifecycle management.
// ---------------------------------------------------------------------------
class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  // ── Firestore & Auth ──────────────────────────────────────────────────────
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Cached reference so we never call currentUser! in build-time callbacks
  late final String _uid;

  // Track in-flight remove operations to prevent double-taps
  final Set<String> _removingIds = {};

  @override
  void initState() {
    super.initState();
    // FIX: obtain uid once; avoids repeated nullable-bang inside callbacks
    _uid = _auth.currentUser!.uid;
  }

  // ── Stream ────────────────────────────────────────────────────────────────
  /// Streams the user's wishlist.
  ///
  /// PERFORMANCE: Uses a single [asyncMap] instead of nested snapshots.
  /// Firestore reads are parallelised with [Future.wait] (N reads at once
  /// instead of N sequential awaits), reducing latency by up to N-1 RTTs.
  ///
  /// RELIABILITY: Skips documents whose [productId] field is absent/null,
  /// and silently drops products that no longer exist in [UserProductList].
  Stream<List<Map<String, dynamic>>> get _wishlistStream {
    return _db
        .collection('users')
        .doc(_uid)
        .collection('wishlist')
        .snapshots()
        .asyncMap((userSnap) async {
      if (userSnap.docs.isEmpty) return <Map<String, dynamic>>[];

      // PERFORMANCE: parallel fetch instead of sequential await
      final futures = userSnap.docs.map((doc) async {
        final productId = doc.data()['productId'] as String?;
        if (productId == null || productId.isEmpty) return null;

        final productSnap =
        await _db.collection('UserProductList').doc(productId).get();
        if (!productSnap.exists) return null;

        return <String, dynamic>{
          'type': 'user',
          'id': productId,
          'data': productSnap.data(),
        };
      });

      final results = await Future.wait(futures);

      // Remove nulls (deleted or malformed products)
      final tempList = results.whereType<Map<String, dynamic>>().toList();

      // Sort newest-first by product timestamp
      tempList.sort((a, b) {
        final aTime = a['data']?['timestamp'] as Timestamp?;
        final bTime = b['data']?['timestamp'] as Timestamp?;
        if (aTime == null || bTime == null) return 0;
        return bTime.compareTo(aTime);
      });

      return tempList;
    });
  }

  // ── Actions ───────────────────────────────────────────────────────────────
  /// Removes [item] from the wishlist, guarded against double-taps and
  /// stale-context crashes.
  Future<void> _removeFromWishlist(Map<String, dynamic> item) async {
    final id = item['id'] as String;

    // RELIABILITY: prevent concurrent removes for the same item
    if (_removingIds.contains(id)) return;
    if (!mounted) return;
    setState(() => _removingIds.add(id));

    try {
      await _db
          .collection('users')
          .doc(_uid)
          .collection('wishlist')
          .doc(id)
          .delete();

      // SECURITY / RELIABILITY: only show snackbar if still mounted
      if (!mounted) return;
      _showRemovedSnack();
    } catch (e) {
      if (!mounted) return;
      _showErrorSnack();
    } finally {
      if (mounted) setState(() => _removingIds.remove(id));
    }
  }

  void _showRemovedSnack() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.favorite_border, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Removed from wishlist',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFB00020),
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _showErrorSnack() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Could not remove item. Please try again.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  // ── UI Helpers ────────────────────────────────────────────────────────────
  /// Trust / assurance banner shown at the very bottom of the wishlist.
  Widget _buildTrustBanner() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: Image.asset(
        'assets/images/trust_banner.png',
        width: double.infinity,
        fit: BoxFit.fitWidth,
        // RELIABILITY: silent fallback — hides banner if asset is missing
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildEmptyState(bool isSmall) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.favorite_border,
            size: isSmall ? 52 : 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'Your wishlist is empty.',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: isSmall ? 14 : 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 52, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'Something went wrong.\nPlease check your connection.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width; // PERFORMANCE: sizeOf avoids full rebuild on padding/orientation changes
    final isSmall = width < 360;
    final isTablet = width >= 600;

    final crossAxisCount = isTablet ? 3 : 2;
    final gridAspectRatio = isTablet ? 0.78 : (isSmall ? 0.70 : 0.75);
    final gridPadding = isTablet ? 16.0 : 12.0;
    final gridSpacing = isTablet ? 14.0 : 12.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Wishlist',
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
          icon:
          const Icon(Icons.arrow_back_ios, color: Colors.black, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _wishlistStream,
        builder: (context, snapshot) {
          // RELIABILITY: explicit error state
          if (snapshot.hasError) return _buildErrorState();

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6A00FF)),
            );
          }

          final wishlist = snapshot.data ?? [];

          if (wishlist.isEmpty) return _buildEmptyState(isSmall);

          // SCALABILITY: Column + Expanded so the trust banner always sits
          // below the scrollable grid without overlapping content.
          return Column(
            children: [
              Expanded(
                child: GridView.builder(
                  padding: EdgeInsets.all(gridPadding),
                  itemCount: wishlist.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: gridSpacing,
                    crossAxisSpacing: gridSpacing,
                    childAspectRatio: gridAspectRatio,
                  ),
                  itemBuilder: (context, index) {
                    final item = wishlist[index];
                    final data =
                        item['data'] as Map<String, dynamic>? ?? {};

                    // FIX: safe cast — avoids runtime crash when field type
                    // unexpectedly differs from List
                    final images = data['images'] is List
                        ? data['images'] as List<dynamic>
                        : <dynamic>[];

                    final productId = item['id'] as String;
                    final isRemoving = _removingIds.contains(productId);

                    return UserProductListing(
                      imageUrl: images.isNotEmpty
                          ? images.first as String
                          : '', // RELIABILITY: empty string triggers errorBuilder instead of crash
                      title: (data['title'] as String?) ?? 'Unnamed Product',
                      price: data['price'],
                      condition: data['condition'],
                      location: data['location'],
                      // RELIABILITY: reflect in-progress removal in UI
                      isFavorite: !isRemoving,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              UserProductDetailsPage(productData: data),
                        ),
                      ),
                      // RELIABILITY: no-op when already removing (VoidCallback
                      // is non-nullable, so null is not assignable)
                      onFavoriteToggle: isRemoving
                          ? () {} // no-op while in-flight — prevents double-tap
                          : () => _removeFromWishlist(item),
                    );
                  },
                ),
              ),

              // ── Trust banner (always visible, below scroll area) ──────────
              _buildTrustBanner(),
            ],
          );
        },
      ),
    );
  }
}