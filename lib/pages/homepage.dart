import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:credbro/pages/wishlistpage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/svg.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../user_product/product_lists.dart';
import '../user_product/model/user_product_listing.dart';

/// Centralised breakpoints — tweak once, affects everything.
class _BP {
  static bool isTablet(BuildContext ctx) =>
      MediaQuery.of(ctx).size.width >= 600;
  static bool isDesktop(BuildContext ctx) =>
      MediaQuery.of(ctx).size.width >= 900;

  static double hPad(BuildContext ctx) => isTablet(ctx) ? 28.0 : 18.0;
  static double headerHeight(BuildContext ctx) => isTablet(ctx) ? 280.0 : 230.0;

  static double fontSize(BuildContext ctx, double base) {
    if (isDesktop(ctx)) return base * 1.2;
    if (isTablet(ctx)) return base * 1.1;
    return base;
  }

  static int gridCols(BuildContext ctx) {
    if (isDesktop(ctx)) return 4;
    if (isTablet(ctx)) return 3;
    return 2;
  }

  static double cardAspectRatio(BuildContext ctx) =>
      isTablet(ctx) ? 0.72 : 0.75;

  static double avatarRadius(BuildContext ctx) => isTablet(ctx) ? 38.0 : 30.0;
  static double iconBtnSize(BuildContext ctx) => isTablet(ctx) ? 24.0 : 20.0;
  static double searchFontSize(BuildContext ctx) =>
      isTablet(ctx) ? 15.0 : 14.0;
}

/// Updated category list.
const List<String> _kCategories = [
  'Books',
  'Courses',
  'Laptops',
  'Mobile Phones',
  'Electronics',
  'Vehicles',
  'Cycles',
  'Kitchen',
  'Home Decor',
  'Toys',
  'Sports & Fitness',
  'Plants & Gardening',
  'Pets & Pet Items',
  'Furniture',
  'Agriculture Equipment',
  'Tools & Hardware',
  'Automotive',
  'Clothes',
  'Personal Care & Beauty',
  'Musical Instruments',
  'Paints',
  'Other',
];

// ─── Brand colours ────────────────────────────────────────────────────────────
const Color _kPrimary = Color(0xFF5800B3);
const Color _kPrimaryDark = Color(0xFF26004D);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Map<String, double> _distanceCache = {};
  // Hard cap so a long session with many distinct locations can't let this
  // map grow unbounded — cheap perf/memory guardrail.
  static const int _distanceCacheCap = 500;

  String userLocation = "";
  double? userLat;
  double? userLng;
  List<String> _selectedFilters = [];

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String name = "";
  String profileImageUrl = "";

  Timer? _debounce;
  List<Map<String, dynamic>> _processedItems = [];

  bool _isProcessingItems = false;
  List<QueryDocumentSnapshot>? _lastDocs;
  String _lastDocsFingerprint = '';

  static const int _pageSize = 10;
  int _visibleCount = _pageSize;

  final ScrollController _scrollController = ScrollController();
  bool _showPinnedSearch = false;

  // Single wishlist listener shared by every card — replaces N per-card
  // StreamBuilders, which were opening one Firestore listener per visible
  // product (huge overhead at scale, and the main mobile jank source).
  //
  // Favourites are held in a ValueNotifier rather than plain state so that
  // toggling a heart icon repaints only the cards that read it (via
  // ValueListenableBuilder) instead of rebuilding the entire HomePage tree
  // on every wishlist change.
  StreamSubscription<QuerySnapshot>? _wishlistSub;
  final ValueNotifier<Set<String>> _favoriteIds = ValueNotifier({});

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Product list renders immediately via its own StreamBuilder below —
    // location/profile data loads quietly in the background and patches
    // in (header text, distance sorting, avatar) whenever it's ready,
    // without blocking the first frame or the product grid.
    _fetchUserData();
    _listenWishlist();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _distanceCache.clear();
    _wishlistSub?.cancel();
    _favoriteIds.dispose();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _listenWishlist() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _wishlistSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('wishlist')
        .snapshots()
        .listen((snap) {
      // Notifier update — no setState, so this no longer rebuilds the
      // whole HomePage (header, search bar, filter row, grid) every time
      // a single item is (un)favourited.
      _favoriteIds.value = snap.docs.map((d) => d.id).toSet();
    });
  }

  void _onScroll() {
    if (!mounted) return;
    final threshold = _BP.headerHeight(context) - kToolbarHeight - 10;
    final shouldShow = _scrollController.offset > threshold;
    if (shouldShow != _showPinnedSearch) {
      setState(() => _showPinnedSearch = shouldShow);
    }

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      if (_visibleCount < _processedItems.length) {
        setState(() {
          _visibleCount = (_visibleCount + _pageSize)
              .clamp(_pageSize, _processedItems.length);
        });
      }
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final newQuery = _searchController.text.trim().toLowerCase();
      if (newQuery == _searchQuery) return;
      setState(() {
        _searchQuery = newQuery;
        _visibleCount = _pageSize;
      });
      if (_lastDocs != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _processItems(_lastDocs!);
        });
      }
    });
  }

  // ─── Refresh ──────────────────────────────────────────────────────────────

  /// Pull-to-refresh handler. The product grid is already live via a
  /// Firestore stream, so refreshing mainly means: re-check the user's
  /// location (in case it changed), clear stale distance/geocode caching,
  /// and recompute + re-sort the currently loaded docs against it.
  Future<void> _handleRefresh() async {
    _distanceCache.clear();
    _lastDocsFingerprint = ''; // force _fingerprint to look "stale" too
    await _fetchUserData();
    if (_lastDocs != null) {
      await _processItems(_lastDocs!);
    }
    if (mounted) {
      setState(() => _visibleCount = _pageSize);
    }
  }

  // ─── Location ─────────────────────────────────────────────────────────────

  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!doc.exists) return;

      final data = doc.data();
      if (data == null) return;

      final fetchedName = (data['name'] as String?) ?? '';
      final fetchedImage = (data['profileImage'] as String?) ?? '';

      // Push name/avatar to UI immediately — don't wait on geocoding.
      if (mounted) {
        setState(() {
          name = fetchedName;
          profileImageUrl = fetchedImage;
        });
      }

      final loc = data['location'];
      if (loc is String && loc.isNotEmpty) {
        if (mounted) setState(() => userLocation = loc);
        try {
          final geo = await locationFromAddress(loc);
          if (geo.isNotEmpty && mounted) {
            setState(() {
              userLat = geo.first.latitude;
              userLng = geo.first.longitude;
            });
            if (_lastDocs != null) _processItems(_lastDocs!);
          }
        } catch (_) {}
      } else if (loc is Map) {
        final lat = loc['lat'];
        final lng = loc['lng'];
        if (lat != null && lng != null) {
          final latVal = (lat as num).toDouble();
          final lngVal = (lng as num).toDouble();
          if (mounted) {
            setState(() {
              userLat = latVal;
              userLng = lngVal;
            });
            if (_lastDocs != null) _processItems(_lastDocs!);
          }
          try {
            final p = await placemarkFromCoordinates(latVal, lngVal);
            if (mounted) {
              setState(() {
                userLocation =
                p.isNotEmpty ? (p.first.locality ?? 'Unknown') : 'Unknown';
              });
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('fetchUserData error: $e');
    }
  }

  double _calcDistance(double lat1, double lon1, double lat2, double lon2) =>
      Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000;

  void _cacheDistance(String key, double value) {
    if (_distanceCache.length >= _distanceCacheCap) {
      // Cheap eviction: drop the oldest entry (first key) rather than
      // paying for an LRU structure for what's just a soft memory guard.
      _distanceCache.remove(_distanceCache.keys.first);
    }
    _distanceCache[key] = value;
  }

  // ─── Item processing ──────────────────────────────────────────────────────

  Future<void> _processItems(List<QueryDocumentSnapshot> docs) async {
    if (_isProcessingItems) return;
    _isProcessingItems = true;

    final currentUser = FirebaseAuth.instance.currentUser;
    final query = _searchQuery;
    // Set instead of List: filter membership checks below go from O(n) to
    // O(1) per candidate, which matters once categories list grows.
    final filters = Set<String>.from(_selectedFilters);

    final List<Map<String, dynamic>> candidates = [];
    // address string -> every candidate entry waiting on that address.
    // Multiple items sharing a location string only pay for one geocode.
    final Map<String, List<Map<String, dynamic>>> pendingGeocode = {};

    try {
      for (final doc in docs) {
        final raw = doc.data();
        if (raw == null || raw is! Map<String, dynamic>) continue;
        final data = raw;

        if (currentUser != null && data['userId'] == currentUser.uid) continue;

        // NEW: once a swap for this listing is marked successful, the
        // onSwapCompleted Cloud Function sets status: 'exchanged' on the
        // UserProductList doc — hide it from the homepage from that point on.
        if (data['status'] == 'exchanged') continue;

        if (filters.isNotEmpty) {
          final cat = (data['category'] as String?) ?? '';
          if (!filters.contains(cat)) continue;
        }

        if (query.isNotEmpty) {
          final title = (data['title'] as String? ?? '').toLowerCase();
          final desc = (data['description'] as String? ?? '').toLowerCase();
          if (!title.contains(query) && !desc.contains(query)) continue;
        }

        final entry = <String, dynamic>{'distance': 9999.0, 'doc': doc};
        candidates.add(entry);

        if (userLat == null || userLng == null) continue;

        final lat = data['lat'];
        final lng = data['lng'];
        if (lat != null && lng != null) {
          final key =
              '${(lat as num).toStringAsFixed(5)}_${(lng as num).toStringAsFixed(5)}';
          final cached = _distanceCache[key];
          if (cached != null) {
            entry['distance'] = cached;
          } else {
            final d = _calcDistance(
              userLat!,
              userLng!,
              lat.toDouble(),
              (lng as num).toDouble(),
            );
            _cacheDistance(key, d);
            entry['distance'] = d;
          }
        } else {
          final locStr = (data['location'] as String?) ?? '';
          if (locStr.isEmpty) continue;
          if (_distanceCache.containsKey(locStr)) {
            entry['distance'] = _distanceCache[locStr]!;
          } else {
            pendingGeocode.putIfAbsent(locStr, () => []).add(entry);
          }
        }
      }

      // Resolve every uncached address concurrently instead of one at a
      // time — this was the biggest latency sink: N products with no
      // stored lat/lng meant N sequential network round-trips.
      if (pendingGeocode.isNotEmpty) {
        await Future.wait(pendingGeocode.entries.map((e) async {
          try {
            final geo = await locationFromAddress(e.key);
            if (geo.isNotEmpty) {
              final d = _calcDistance(
                userLat!,
                userLng!,
                geo.first.latitude,
                geo.first.longitude,
              );
              _cacheDistance(e.key, d);
              for (final entry in e.value) {
                entry['distance'] = d;
              }
            }
          } catch (_) {}
        }));
      }

      candidates.sort(
            (a, b) =>
            (a['distance'] as double).compareTo(b['distance'] as double),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('_processItems error: $e');
    } finally {
      _isProcessingItems = false;
    }

    if (mounted) {
      setState(() {
        _processedItems = candidates;
        if (_visibleCount < _pageSize) _visibleCount = _pageSize;
      });
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _handleRefresh,
              color: _kPrimaryDark,
              child: CustomScrollView(
                controller: _scrollController,
                // Ensures the refresh gesture still works even when
                // content is shorter than the viewport (e.g. empty state).
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                // Builds a little ahead of/behind the viewport so cards
                // are ready before they're visible instead of popping in.
                cacheExtent: 600,
                slivers: [
                  SliverAppBar(
                    automaticallyImplyLeading: false,
                    pinned: true,
                    floating: false,
                    snap: false,
                    elevation: 0,
                    expandedHeight: _BP.headerHeight(context),
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    // When collapsed: show "SwapNow" + icons in the title row.
                    // When expanded: title is hidden — _buildHeader owns everything.
                    title: _showPinnedSearch
                        ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Amoeba',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 24,
                          ),
                        ),
                        Row(
                          children: [
                            _iconBtn(context, 'assets/icons/favourite.svg',
                                const WishlistPage()),
                            SizedBox(
                                width: _BP.isTablet(context) ? 10 : 8),
                            _profileAvatar(context),
                            SizedBox(
                                width: _BP.isTablet(context) ? 10 : 8),
                          ],
                        ),
                      ],
                    )
                        : null,
                    actions: const [],
                    flexibleSpace: FlexibleSpaceBar(
                      collapseMode: CollapseMode.pin,
                      background: _buildHeader(context),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 15),
                      child: _buildFilterRow(context),
                    ),
                  ),
                  // Real sliver-based product list — cards are built lazily
                  // as they scroll into view, instead of the old
                  // shrinkWrap GridView which built all ~200 cards eagerly
                  // on every rebuild regardless of what was on screen.
                  _buildProductStream(context),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),
                  SliverToBoxAdapter(
                    child: _buildTrustBanner(context),
                  ),
                ],
              ),
            ),

            // Pinned search bar — only the search bar slides in/out.
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              top: _showPinnedSearch
                  ? kToolbarHeight + MediaQuery.of(context).padding.top
                  : -80,
              left: 0,
              right: 0,
              child: Container(
                color: _kPrimary,
                padding: EdgeInsets.symmetric(
                  horizontal: _BP.hPad(context),
                  vertical: 8,
                ),
                child: _buildSearchBar(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrustBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: Image.asset(
        'assets/images/trust_banner.png',
        width: double.infinity,
        fit: BoxFit.fitWidth,
        errorBuilder: (context, error, stackTrace) =>
        const SizedBox.shrink(),
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final hPad = _BP.hPad(context);
    final isTablet = _BP.isTablet(context);
    final screenW = MediaQuery.of(context).size.width;
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kPrimary, Colors.white],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: EdgeInsets.fromLTRB(hPad, topPadding + 12, hPad, 0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Amoeba",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: _BP.fontSize(context, 24),
                    ),
                  ),
                  if (!_showPinnedSearch)
                    Row(
                      children: [
                        _iconBtn(context, 'assets/icons/favourite.svg',
                            const WishlistPage()),
                        SizedBox(width: isTablet ? 14 : 12),
                        _profileAvatar(context),
                      ],
                    ),
                ],
              ),

              SizedBox(height: isTablet ? 4 : 2),

              // ── Location ──
              Row(
                children: [
                  Icon(Icons.add_location_alt_outlined,
                      color: Colors.white, size: isTablet ? 20 : 18),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      userLocation.isNotEmpty
                          ? userLocation
                          : "Location not set",
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isTablet ? 13 : 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: isTablet ? 18 : 20),

              // ── Tagline ──
              Text(
                "Let's exchange\nmaterials",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _BP.fontSize(context, 20),
                  fontWeight: FontWeight.w600,
                ),
              ),

              SizedBox(height: isTablet ? 70 : 60),
            ],
          ),

          // ── Decorative image ──
          if (screenW >= 360)
            Positioned(
              right: isTablet ? 0 : 12,
              top: isTablet ? 48 : 54,
              child: Image.asset(
                'assets/images/items.png',
                width: isTablet ? 160 : 120,
                height: isTablet ? 160 : 120,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
              ),
            ),

          // ── Inline search bar (visible while header is expanded) ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 5,
            child: _buildSearchBar(context),
          ),
        ],
      ),
    );
  }

  /// Profile avatar — display only, no tap navigation.
  Widget _profileAvatar(BuildContext context) {
    final size = _BP.iconBtnSize(context) + 16;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: profileImageUrl.isNotEmpty
          ? Image.network(
        profileImageUrl,
        fit: BoxFit.cover,
        cacheWidth: (size * 2).toInt(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.person,
          size: size * 0.6,
          color: _kPrimaryDark,
        ),
      )
          : Icon(
        Icons.person,
        size: size * 0.6,
        color: _kPrimaryDark,
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final isTablet = _BP.isTablet(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isTablet ? 20 : 16),
        border: Border.all(
          color: _kPrimaryDark.withOpacity(0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _kPrimaryDark.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(
          fontSize: _BP.searchFontSize(context),
          fontWeight: FontWeight.w500,
        ),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: "Search products...",
          hintStyle: TextStyle(
            color: Colors.grey.shade400,
            fontSize: _BP.searchFontSize(context),
            fontWeight: FontWeight.w400,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: isTablet ? 16 : 14),
          prefixIcon: Container(
            margin: const EdgeInsets.only(left: 4, right: 2),
            child: Icon(
              Icons.search_rounded,
              color: _kPrimaryDark.withOpacity(0.6),
              size: isTablet ? 22 : 20,
            ),
          ),
          suffixIcon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: _searchQuery.isNotEmpty
                ? IconButton(
              key: const ValueKey('clear'),
              icon: Icon(Icons.close_rounded,
                  color: Colors.grey.shade500, size: isTablet ? 20 : 18),
              onPressed: () {
                _searchController.clear();
                FocusScope.of(context).unfocus();
              },
            )
                : const SizedBox.shrink(key: ValueKey('empty')),
          ),
        ),
      ),
    );
  }

  Widget _circleIcon(Widget child) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: _kPrimaryDark.withOpacity(0.06), width: 1),
        boxShadow: [
          BoxShadow(
            color: _kPrimaryDark.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _iconBtn(BuildContext context, String svgPath, Widget page) {
    final size = _BP.iconBtnSize(context);
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        splashColor: _kPrimaryDark.withOpacity(0.1),
        highlightColor: _kPrimaryDark.withOpacity(0.05),
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
        child: _circleIcon(
          SvgPicture.asset(
            svgPath,
            width: size,
            height: size,
            colorFilter: const ColorFilter.mode(
              _kPrimaryDark,
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Filter row ───────────────────────────────────────────────────────────

  Widget _buildFilterRow(BuildContext context) {
    final hPad = _BP.hPad(context);
    final hasFilters = _selectedFilters.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(left: hPad, right: hPad - 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                "New Items",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: _BP.fontSize(context, 16),
                ),
              ),
              if (hasFilters) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _kPrimaryDark,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_selectedFilters.length}',
                    style:
                    const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
          // Now shows a "Filter" label alongside the icon, so the control
          // reads clearly instead of relying on the icon alone.
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _showFilterSheet,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.filter_list,
                      color: hasFilters ? _kPrimaryDark : Colors.grey,
                      size: _BP.isTablet(context) ? 22 : 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "Filter",
                      style: TextStyle(
                        color: hasFilters ? _kPrimaryDark : Colors.grey[700],
                        fontWeight: FontWeight.w600,
                        fontSize: _BP.fontSize(context, 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Filter sheet ─────────────────────────────────────────────────────────

  void _showFilterSheet() async {
    List<String> selected = List.from(_selectedFilters);
    final isTablet = _BP.isTablet(context);

    final filters = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (context, scrollController) {
              return Container(
                constraints: BoxConstraints(
                  maxWidth: isTablet ? 520 : double.infinity,
                ),
                padding: EdgeInsets.all(isTablet ? 24 : 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Filter by Category",
                          style: TextStyle(
                            fontSize: isTablet ? 18 : 16,
                            fontWeight: FontWeight.w600,
                            color: _kPrimaryDark,
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setModalState(() => selected.clear()),
                          child: const Text(
                            "Clear All",
                            style: TextStyle(
                              color: _kPrimaryDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: _kCategories.length,
                        itemBuilder: (context, index) {
                          final cat = _kCategories[index];
                          return CheckboxListTile(
                            dense: true,
                            visualDensity: const VisualDensity(vertical: -2),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4),
                            title: Text(
                              cat,
                              style: TextStyle(
                                fontSize: isTablet ? 15 : 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            value: selected.contains(cat),
                            activeColor: _kPrimaryDark,
                            onChanged: (value) => setModalState(() {
                              value == true
                                  ? selected.add(cat)
                                  : selected.remove(cat);
                            }),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: _kPrimaryDark),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: EdgeInsets.symmetric(
                                  vertical: isTablet ? 14 : 12),
                            ),
                            onPressed: () =>
                                Navigator.pop(context, <String>[]),
                            child: Text(
                              "Clear Filters",
                              style: TextStyle(
                                color: _kPrimaryDark,
                                fontSize: isTablet ? 15 : 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kPrimaryDark,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: EdgeInsets.symmetric(
                                  vertical: isTablet ? 14 : 12),
                            ),
                            onPressed: () =>
                                Navigator.pop(context, selected),
                            child: Text(
                              "Apply Filters",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isTablet ? 15 : 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );

    if (filters != null && mounted) {
      setState(() {
        _selectedFilters = filters;
        _visibleCount = _pageSize;
      });
      if (_lastDocs != null) _processItems(_lastDocs!);
    }
  }

  // ─── Product list (sliver-based) ───────────────────────────────────────────

  /// Includes each doc's status alongside its id, not just list shape —
  /// a plain count+first+last-id fingerprint doesn't change when a
  /// listing's status flips to 'exchanged' in the middle of the list
  /// (e.g. via the onSwapCompleted Cloud Function), so that update was
  /// silently never triggering a re-run of _processItems and the sold
  /// item kept showing on the homepage.
  static String _fingerprint(List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) return '';
    final buffer = StringBuffer('${docs.length}');
    for (final doc in docs) {
      final raw = doc.data();
      final status =
      (raw is Map<String, dynamic>) ? (raw['status'] ?? '') : '';
      buffer.write('_${doc.id}:$status');
    }
    return buffer.toString();
  }

  /// Returns a single sliver (via [SliverMainAxisGroup]) that plugs
  /// directly into the outer CustomScrollView. Cards are only built when
  /// they scroll into view.
  Widget _buildProductStream(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('UserProductList')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (kDebugMode) debugPrint('Firestore error: ${snapshot.error}');
          return SliverToBoxAdapter(
            child: _buildStatePlaceholder(
              context,
              asset: 'assets/images/error_state.png',
              fallbackIcon: Icons.error_outline,
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            _processedItems.isEmpty) {
          return const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: _kPrimaryDark),
              ),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final docs = snapshot.data!.docs;
          final fp = _fingerprint(docs);
          if (fp != _lastDocsFingerprint) {
            _lastDocsFingerprint = fp;
            _lastDocs = docs;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _processItems(docs);
            });
          }
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return SliverToBoxAdapter(
            child: _buildStatePlaceholder(
              context,
              asset: 'assets/images/no_items.png',
              fallbackIcon: Icons.inventory_2_outlined,
            ),
          );
        }

        if (_isProcessingItems && _processedItems.isEmpty) {
          return const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: _kPrimaryDark),
              ),
            ),
          );
        }

        if (_processedItems.isEmpty) {
          return SliverToBoxAdapter(
            child: _buildStatePlaceholder(
              context,
              asset: _searchQuery.isNotEmpty
                  ? 'assets/images/no_search_results.png'
                  : 'assets/images/no_nearby_items.png',
              fallbackIcon: _searchQuery.isNotEmpty
                  ? Icons.search_off
                  : Icons.location_off_outlined,
            ),
          );
        }

        final visibleItems = _processedItems.take(_visibleCount).toList();

        final nearby = visibleItems
            .where((e) => (e['distance'] as double) <= 15)
            .toList();
        final midRange = visibleItems
            .where((e) =>
        (e['distance'] as double) > 15 &&
            (e['distance'] as double) <= 80)
            .toList();

        final hasMore = _visibleCount < _processedItems.length;

        return SliverMainAxisGroup(
          slivers: [
            if (nearby.isNotEmpty) _buildGridSliver(context, nearby),
            if (midRange.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: _BP.hPad(context),
                    top: 12,
                    bottom: 5,
                  ),
                  child: Text(
                    "Nearby Products",
                    style: TextStyle(
                      fontSize: _BP.fontSize(context, 16),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              _buildGridSliver(context, midRange),
            ],
            if (hasMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _kPrimaryDark,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildStatePlaceholder(
      BuildContext context, {
        required String asset,
        required IconData fallbackIcon,
      }) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Image.asset(
          asset,
          width: 200,
          height: 200,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Icon(
            fallbackIcon,
            size: 80,
            color: Colors.grey[400],
          ),
        ),
      ),
    );
  }

  // ─── Grid (real sliver, lazily built) ──────────────────────────────────────

  Widget _buildGridSliver(
      BuildContext context, List<Map<String, dynamic>> items) {
    final cols = _BP.gridCols(context);
    final hPad = _BP.isTablet(context) ? 16.0 : 12.0;
    final spacing = _BP.isTablet(context) ? 14.0 : 12.0;

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          childAspectRatio: _BP.cardAspectRatio(context),
        ),
        delegate: SliverChildBuilderDelegate(
              (context, index) {
            final doc = items[index]['doc'] as QueryDocumentSnapshot;
            // Cards are stateless and cheap to rebuild, so we don't need
            // Flutter to keep them alive off-screen — disabling that
            // bookkeeping saves work on large grids. RepaintBoundary is
            // still on (the default) so scrolling doesn't repaint the
            // whole grid every frame, just the cards that changed.
            return _ProductCard(
              key: ValueKey(doc.id),
              doc: doc,
              favoriteIdsListenable: _favoriteIds,
            );
          },
          childCount: items.length,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          addSemanticIndexes: false,
        ),
      ),
    );
  }
}

// ─── Product card ──────────────────────────────────────────────────────────
// Listens to the shared favourites ValueNotifier directly, so toggling a
// heart only rebuilds this one card instead of the whole HomePage tree.

class _ProductCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final ValueListenable<Set<String>> favoriteIdsListenable;

  const _ProductCard({
    super.key,
    required this.doc,
    required this.favoriteIdsListenable,
  });

  @override
  Widget build(BuildContext context) {
    final raw = doc.data();
    final data =
    (raw is Map<String, dynamic>) ? raw : const <String, dynamic>{};

    final images =
    (data['images'] is List) ? data['images'] as List : const [];
    final imageUrl = images.isNotEmpty
        ? images[0].toString()
        : 'https://via.placeholder.com/150';

    return ValueListenableBuilder<Set<String>>(
      valueListenable: favoriteIdsListenable,
      builder: (context, favoriteIds, _) {
        final isFavorite = favoriteIds.contains(doc.id);
        return UserProductListing(
          imageUrl: imageUrl,
          title: (data['title'] as String? ?? 'Unnamed Product'),
          price: data['price'],
          condition: data['condition'],
          location: data['location'],
          isFavorite: isFavorite,
          onPressed: () => _openDetail(context, data),
          onFavoriteToggle: () => _toggleWishlist(context, isFavorite),
        );
      },
    );
  }

  void _openDetail(BuildContext context, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProductDetailsPage(
          productId: doc.id,
          productData: data,
        ),
      ),
    );
  }

  Future<void> _toggleWishlist(BuildContext context, bool isFavorite) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('wishlist')
        .doc(doc.id);

    try {
      if (isFavorite) {
        await ref.delete();
      } else {
        await ref.set({
          'productId': doc.id,
          'addedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Wishlist toggle failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update favorites. Try again.'),
          ),
        );
      }
    }
  }
}