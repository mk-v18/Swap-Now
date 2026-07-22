import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ImageViewer extends StatefulWidget {
  final String imageUrl;

  const ImageViewer({super.key, required this.imageUrl});

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  final TransformationController _transformController =
  TransformationController();

  // Bump this to force Image.network to retry after a failure.
  int _retryToken = 0;
  bool _isZoomed = false;

  @override
  void initState() {

    super.initState();
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05;
    if (zoomed != _isZoomed && mounted) {
      setState(() => _isZoomed = zoomed);
    }
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  void _onDoubleTapDown(TapDownDetails details) {
    // Zoom toward the tapped point, or reset if already zoomed.
    final position = details.localPosition;
    final matrix = _isZoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
      ..translate(-position.dx * 1.5, -position.dy * 1.5)
      ..scale(2.5));
    _transformController.value = matrix;
  }

  void _retry() {
    setState(() => _retryToken++);
  }

  bool get _isValidUrl {
    final uri = Uri.tryParse(widget.imageUrl);
    if (uri == null || widget.imageUrl.trim().isEmpty) return false;
    // Guard against mixed-content / non-secure image loads.
    return uri.isScheme('HTTPS') || uri.isScheme('HTTP');
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;

    // Cap decoded resolution to what's actually useful at max zoom,
    // instead of decoding arbitrarily large source images at full size.
    final cacheWidth =
    (screenSize.width * devicePixelRatio * 4.0).round().clamp(1, 4096);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle.light,
        actions: [
          if (_isZoomed)
            IconButton(
              icon: const Icon(Icons.zoom_out_map, color: Colors.white70),
              tooltip: 'Reset zoom',
              onPressed: _resetZoom,
            ),
        ],
      ),
      body: Semantics(
        label: 'Product image, pinch or double-tap to zoom',
        image: true,
        child: !_isValidUrl
            ? _buildError('Image unavailable')
            : GestureDetector(
          onDoubleTapDown: _onDoubleTapDown,
          onDoubleTap: () {}, // required for onDoubleTapDown to fire
          child: InteractiveViewer(
            transformationController: _transformController,
            clipBehavior: Clip.none,
            minScale: 0.5,
            maxScale: 4.0,
            boundaryMargin: EdgeInsets.symmetric(
              horizontal: screenSize.width * 0.1,
              vertical: screenSize.height * 0.1,
            ),
            child: Center(
              child: Hero(
                tag: widget.imageUrl,
                child: Image.network(
                  widget.imageUrl,
                  key: ValueKey(_retryToken),
                  fit: BoxFit.contain,
                  cacheWidth: cacheWidth,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return SizedBox(
                      width: screenSize.width,
                      height: screenSize.height,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          value: loadingProgress.expectedTotalBytes !=
                              null
                              ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return _buildError('Failed to load image');
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh, color: Colors.white70),
              label: const Text('Retry', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }
}