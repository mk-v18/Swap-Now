import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  const VideoPlayerScreen({super.key, required this.videoUrl});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;
  bool _isReady = false;
  bool _hasError = false;
  bool _isLoading = false; // guards against concurrent _initPlayer() calls
  String _errorMessage = 'The video may be unavailable or your connection dropped.';

  StreamSubscription<String>? _errorSub;

  static const _purple = Color(0xFF7B1FA2);
  static const _loadTimeout = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _player = Player();
    _controller = VideoController(_player);

    // Catch playback errors that happen *after* a successful open — e.g. the
    // connection drops mid-stream — not just failures during initial load.
    _errorSub = _player.stream.error.listen((_) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isReady = false;
          _errorMessage = 'Playback stopped unexpectedly. Check your connection and retry.';
        });
      }
    });

    _initPlayer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _player.pause();
    } else if (state == AppLifecycleState.resumed) {
      // Don't auto-resume — user should decide to play again.
    }
  }

  bool get _isValidUrl {
    final uri = Uri.tryParse(widget.videoUrl);
    if (uri == null || widget.videoUrl.trim().isEmpty) return false;
    // Reject anything that isn't a plain http(s) URL — blocks file://,
    // content://, and other schemes that shouldn't reach the player.
    return uri.isScheme('HTTPS') || uri.isScheme('HTTP');
  }

  Future<void> _initPlayer() async {
    if (_isLoading) return; // ignore rapid repeated retry taps
    _isLoading = true;

    if (!_isValidUrl) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isReady = false;
          _errorMessage = 'This video link looks invalid.';
        });
      }
      _isLoading = false;
      return;
    }

    if (mounted) {
      setState(() {
        _hasError = false;
        _isReady = false;
        _errorMessage = 'The video may be unavailable or your connection dropped.';
      });
    }

    try {
      await _player.open(Media(widget.videoUrl)).timeout(
        _loadTimeout,
        onTimeout: () => throw TimeoutException('Video load timed out'),
      );
      if (mounted) setState(() => _isReady = true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'The video may be unavailable or your connection dropped.';
        });
      }
    } finally {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _errorSub?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isLandscape = mq.orientation == Orientation.landscape;
    final isTablet = mq.size.shortestSide >= 600;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: isLandscape
          ? null
          : AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: SafeArea(
        left: !isLandscape,
        right: !isLandscape,
        child: Semantics(
          label: 'Video player',
          child: _hasError
              ? _ErrorView(
            message: _errorMessage,
            onRetry: _isLoading ? null : _initPlayer,
            isTablet: isTablet,
          )
              : !_isReady
              ? _LoadingView(color: _purple)
              : _VideoView(
            controller: _controller,
            isLandscape: isLandscape,
            isTablet: isTablet,
          ),
        ),
      ),
    );
  }
}

// ── Video View ────────────────────────────────────────────────────────────────

class _VideoView extends StatelessWidget {
  final VideoController controller;
  final bool isLandscape;
  final bool isTablet;

  const _VideoView({
    required this.controller,
    required this.isLandscape,
    required this.isTablet,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    final Widget video = Video(
      controller: controller,
      controls: AdaptiveVideoControls,
    );

    if (isLandscape) {
      return SizedBox(
        width: mq.size.width,
        height: mq.size.height,
        child: video,
      );
    }

    final videoHeight = isTablet
        ? mq.size.height * 0.55
        : mq.size.width * (9 / 16);

    return Center(
      child: SizedBox(
        width: mq.size.width,
        height: videoHeight.clamp(200.0, mq.size.height * 0.75),
        child: video,
      ),
    );
  }
}

// ── Loading View ──────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  final Color color;
  const _LoadingView({required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: color),
          const SizedBox(height: 16),
          const Text(
            'Loading video…',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ── Error View ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool isTablet;

  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.isTablet,
  });

  static const _purple = Color(0xFF7B1FA2);

  @override
  Widget build(BuildContext context) {
    final iconSize = isTablet ? 80.0 : 64.0;
    final titleSize = isTablet ? 20.0 : 16.0;
    final subtitleSize = isTablet ? 15.0 : 13.0;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isTablet ? 48.0 : 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_rounded,
                color: Colors.white38, size: iconSize),
            const SizedBox(height: 16),
            Text(
              'Could not load video',
              style: TextStyle(
                color: Colors.white,
                fontSize: titleSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: subtitleSize),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: isTablet ? 200 : double.infinity,
              height: isTablet ? 52 : 48,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: onRetry == null
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white70),
                )
                    : const Icon(Icons.refresh_rounded),
                label: Text(
                  onRetry == null ? 'Retrying…' : 'Try Again',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _purple.withOpacity(0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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