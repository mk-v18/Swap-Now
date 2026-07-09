import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// A product card with:
/// • Full-card tap (no "View Details" button)
/// • CachedNetworkImage for memory + disk caching
/// • Gradient overlay for text legibility
/// • Condition badge + location row
/// • Isolated favorite toggle (doesn't fire card tap)
class UserProductListing extends StatelessWidget {
  final String imageUrl;
  final String title;
  final dynamic price;
  final String? condition;
  final String? location;
  final VoidCallback onPressed;
  final VoidCallback onFavoriteToggle;
  final bool isFavorite;

  const UserProductListing({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.price,
    this.condition,
    this.location,
    required this.onPressed,
    required this.onFavoriteToggle,
    this.isFavorite = false,
  });

  // ── Indian number formatting ─────────────────────────────────────────────
  String _formatPrice(dynamic price) {
    if (price == null) return '0';
    final num p = price is num ? price : num.tryParse(price.toString()) ?? 0;
    final String s = p.toStringAsFixed(0);
    if (s.length <= 3) return s;
    final String lastThree = s.substring(s.length - 3);
    final String rest = s.substring(0, s.length - 3);
    final String withCommas =
    rest.replaceAllMapped(RegExp(r'\B(?=(\d{2})+(?!\d))'), (m) => ',');
    return '$withCommas,$lastThree';
  }

  // ── Responsive scale: 0.85 (compact phone) → 1.3 (tablet) ───────────────
  double _scale(BuildContext context) =>
      (MediaQuery.of(context).size.width / 400).clamp(0.85, 1.3);

  @override
  Widget build(BuildContext context) {
    final s = _scale(context);

    final double cardRadius    = 18 * s;
    final double imageRadius   = 13 * s;
    final double outerPad      = 6  * s;
    final double innerHPad     = 9  * s;
    final double innerVPad     = 7  * s;
    final double favPad        = 5  * s;
    final double favIconSize   = 14 * s;
    final double titleFontSize = (16 * s).clamp(14.0, 20.0);
    final double priceFontSize = (13   * s).clamp(11.0, 17.0);
    final double metaFontSize  = (10   * s).clamp(11.0, 14.0);
    final double metaIconSize  = (12   * s).clamp(11.0, 15.0);
    final double spacingSmall  = 4 * s;
    final double spacingMid    = 6 * s;
    final double badgeFontSize = (9.5 * s).clamp(8.0, 12.0);
    final double badgePadH     = 6 * s;
    final double badgePadV     = 2.5 * s;

    const Color primary        = Color(0xFF6A1B9A);
    const Color primaryDark    = Color(0xFF4A148C);
    const Color accentLight    = Color(0xFFF3E5F5);

    return Semantics(
      label: '$title, ₹${_formatPrice(price)}${condition != null ? ", $condition" : ""}',
      button: true,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(cardRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.13),
              blurRadius: 18,
              spreadRadius: 1,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(cardRadius),
          elevation: 0,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(cardRadius),
            splashColor: primary.withOpacity(0.08),
            highlightColor: primary.withOpacity(0.04),
            child: Ink(
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(cardRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── IMAGE ──────────────────────────────────────────────────
                  Expanded(
                    child: Padding(
                      padding:
                      EdgeInsets.fromLTRB(outerPad, outerPad, outerPad, 0),
                      child: Stack(
                        children: [
                          // Cached image
                          ClipRRect(
                            borderRadius: BorderRadius.circular(imageRadius),
                            child: SizedBox.expand(
                              child: CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                // Fade in smoothly once loaded
                                fadeInDuration:
                                const Duration(milliseconds: 250),
                                // Shimmer-style placeholder
                                placeholder: (_, __) => Container(
                                  color: const Color(0xFFEEEEEE),
                                  child: Center(
                                    child: SizedBox(
                                      width: 22 * s,
                                      height: 22 * s,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: primary.withOpacity(0.4),
                                      ),
                                    ),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color: const Color(0xFFEEEEEE),
                                  child: Center(
                                    child: Icon(Icons.image_not_supported,
                                        color: Colors.grey[400], size: 28 * s),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Subtle bottom gradient for text legibility
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            height: 40 * s,
                            child: ClipRRect(
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(imageRadius),
                                bottomRight: Radius.circular(imageRadius),
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.28),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Condition badge — bottom-left of image
                          if (condition != null && condition!.isNotEmpty)
                            Positioned(
                              bottom: 6 * s,
                              left: 6 * s,
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: badgePadH, vertical: badgePadV),
                                decoration: BoxDecoration(
                                  color: primaryDark.withOpacity(0.82),
                                  borderRadius:
                                  BorderRadius.circular(20 * s),
                                ),
                                child: Text(
                                  condition!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: badgeFontSize,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),

                          // Favorite button — top-right, absorbs its own tap
                          Positioned(
                            top: 6 * s,
                            right: 6 * s,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onFavoriteToggle,
                              child: Container(
                                padding: EdgeInsets.all(favPad),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.14),
                                      blurRadius: 5,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  isFavorite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: isFavorite ? primary : Colors.black38,
                                  size: favIconSize,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── BOTTOM INFO ────────────────────────────────────────────
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        innerHPad, innerVPad, innerHPad, innerVPad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                            height: 1.25,
                          ),
                        ),

                        SizedBox(height: spacingSmall),

                        // Price row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Price pill
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 7 * s, vertical: 2.5 * s),
                              decoration: BoxDecoration(
                                color: accentLight,
                                borderRadius: BorderRadius.circular(8 * s),
                              ),
                              child: Text(
                                '₹ ${_formatPrice(price)}',
                                style: TextStyle(
                                  fontSize: priceFontSize,
                                  fontWeight: FontWeight.w800,
                                  color: primaryDark,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Location
                        if (location != null && location!.isNotEmpty) ...[
                          SizedBox(height: spacingMid),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: metaIconSize,
                                color: primary.withOpacity(0.7),
                              ),
                              SizedBox(width: 3.5 * s), // was 2*s — was causing the cramped look
                              Expanded(
                                child: Text(
                                  location!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: metaFontSize,
                                    fontWeight: FontWeight.w500, // was w600 — softer, less competing with price
                                    color: Colors.black54,
                                    height: 1.3,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}