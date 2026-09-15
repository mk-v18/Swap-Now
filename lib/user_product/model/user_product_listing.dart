import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Shared distance formatting so every screen reads the same way:
/// - under 1 km: whole meters, e.g. "350 m" (always precise — no vague
///   "Nearby" label, even for very short distances)
/// - 1 km and up: one decimal, e.g. "5.7 km"
String formatDistanceLabel(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(1)} km';
}

/// A product card with:
/// • Full-card tap (no "View Details" button)
/// • CachedNetworkImage for memory + disk caching
/// • Gradient overlay for text legibility
/// • Condition badge inside the image (bottom-left)
/// • Location row below title
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

  /// Distance (in km) between the current user and this listing's owner.
  /// Only ever rendered when non-null AND <= 15 km — callers should still
  /// pass values above that threshold (or null); this widget enforces the
  /// cutoff itself so every screen behaves consistently.
  final double? distanceKm;

  /// false (home/default): the distance badge shows just "x.x km".
  /// true (other pages, e.g. wishlist): the badge shows "x.x km • location"
  /// so the owner's location comes along with the distance value.
  final bool showDistanceWithLocation;

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
    this.distanceKm,
    this.showDistanceWithLocation = false,
  });

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
    final double metaFontSize  = (10   * s).clamp(11.0, 14.0);
    final double metaIconSize  = (12   * s).clamp(11.0, 15.0);
    final double spacingSmall  = 4 * s;
    final double spacingMid    = 6 * s;
    final double badgeFontSize = (10 * s).clamp(9.0, 12.5);
    final double badgePadH     = 7 * s;
    final double badgePadV     = 3 * s;

    const Color primary        = Color(0xFF6A1B9A);
    const Color primaryDark    = Color(0xFF4A148C);
    const Color accentLight    = Color(0xFFF3E5F5);
    const Color borderColor    = Color(0xFFECEAFF);

    // Only ever shown within the 15 km cutoff — anything farther (or
    // unknown) falls back to plain location text below.
    final bool showDistance = distanceKm != null && distanceKm! <= 15;
    final String? distanceValueLabel =
    showDistance ? formatDistanceLabel(distanceKm!) : null;
    final bool hasLocation = location != null && location!.isNotEmpty;

    // What renders below the title, and which icon it uses:
    // - within 15 km, home (showDistanceWithLocation=false): distance ONLY
    // - within 15 km, other pages (showDistanceWithLocation=true):
    //   distance + location together
    // - otherwise: plain location (unchanged fallback)
    final String? metaLine = distanceValueLabel != null
        ? (showDistanceWithLocation && hasLocation
        ? '$distanceValueLabel • ${location!}'
        : distanceValueLabel)
        : (hasLocation ? location : null);
    final IconData metaIcon =
    distanceValueLabel != null ? Icons.near_me_rounded : Icons.location_on_rounded;

    return Semantics(
      label: '$title${condition != null ? ", $condition" : ""}${location != null ? ", $location" : ""}',
      button: true,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(cardRadius),
          border: Border.all(
            color: borderColor,
            width: 1.2,
          ),
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

                          // Subtle bottom gradient for badge legibility
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
                                  color: accentLight,
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
                                    color: primaryDark,
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
                                  border: Border.all(
                                    color: borderColor,
                                    width: 1.2,
                                  ),
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

                        // Distance (within 15 km) or plain location,
                        // below the name — a plain text row, not a badge,
                        // so it doesn't compete visually with the title.
                        if (metaLine != null) ...[
                          SizedBox(height: spacingMid),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                metaIcon,
                                size: metaIconSize,
                                color: primary.withOpacity(0.7),
                              ),
                              SizedBox(width: 3.5 * s),
                              Expanded(
                                child: Text(
                                  metaLine,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: metaFontSize,
                                    fontWeight: FontWeight.w500,
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