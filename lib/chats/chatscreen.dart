import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:credbro/chats/chatservice.dart';
import 'package:credbro/chats/image_viewer.dart';
import 'package:credbro/chats/video_player.dart';
import 'package:credbro/chats/encryption_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:credbro/chats/location_picker.dart';
import 'package:credbro/chats/notification_service.dart';
import 'package:geocoding/geocoding.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gal/gal.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String receiverId;
  final String receiverName;
  final String receiverImage;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.receiverId,
    required this.receiverName,
    required this.receiverImage,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final ChatService _chatService = ChatService();
  final EncryptionService _enc = EncryptionService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final picker = ImagePicker();
  final Set<String> _selectedMessageIds = {};
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  double _uploadProgress = 0.0;
  final Map<String, String> _geocodeCache = {};
  final Map<String, double?> _downloadProgress = {};
  final Set<String> _downloadLock = {}; // prevents duplicate downloads of same file
  final List<Future<void> Function()> _pendingDownloads = []; // queued when at capacity
  int _activeDownloads = 0;
  static const int _maxConcurrentDownloads = 3;

  bool _isRecording = false;
  bool _isTyping = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;
  String? _currentlyPlayingUrl;
  bool _isPlaying = false;

  Map<String, dynamic>? _intent;
  bool _bannerCollapsed = false;

  final Set<String> _alreadySaved = {};

  // Tracks the last snapshot length for which we called markMessagesAsSeen.
  // Prevents calling it on every single stream rebuild (would be hundreds of
  // Firestore writes per second while the chat is open).
  int _lastSeenSnapshotLength = -1;

  // ── Design tokens ─────────────────────────────────────────────────────────
  static const Color _purple = Color(0xFF7B1FA2);
  static const Color _lightPurple = Color(0xFFEDE7F6);
  static const Color _teal = Color(0xFF00796B);

  // ── Responsive helpers ────────────────────────────────────────────────────
  double get _sw => MediaQuery.of(context).size.width;
  bool get _isSmall => _sw < 360;
  bool get _isTablet => _sw >= 600;

  double get _bubbleMax => _isTablet ? _sw * 0.55 : _isSmall ? _sw * 0.82 : _sw * 0.72;
  double get _mediaW => _isTablet ? 280.0 : _isSmall ? _sw * 0.62 : _sw * 0.58;
  double get _mediaH => _isTablet ? 260.0 : _sw * 0.52;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chatService.setUserPresence(FirebaseAuth.instance.currentUser!.uid, online: true);
    _chatService.markMessagesAsSeen(widget.chatId);
    NotificationService().setActiveChatId(widget.chatId);
    NotificationService().cancelChatNotifications(widget.chatId);
    _messageController.addListener(_onTypingChanged);
    _loadIntent();
    _loadSavedUrls();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() { _isPlaying = false; _currentlyPlayingUrl = null; });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _chatService.setUserPresence(uid, online: false);
    } else if (state == AppLifecycleState.resumed) {
      _chatService.setUserPresence(uid, online: true);
      _chatService.markMessagesAsSeen(widget.chatId);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.removeListener(_onTypingChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _chatService.setTyping(widget.chatId, FirebaseAuth.instance.currentUser!.uid, false);
    _chatService.setUserPresence(FirebaseAuth.instance.currentUser!.uid, online: false);
    NotificationService().setActiveChatId(null);
    super.dispose();
  }

  // ── Snack helpers ─────────────────────────────────────────────────────────
  void _snack(String msg, {bool error = false, bool success = false}) {
    if (!mounted) return;
    final color = error
        ? const Color(0xFFB00020)
        : success
        ? const Color(0xFF1B8A4C)
        : Colors.black87;
    final icon = error
        ? Icons.error_outline
        : success
        ? Icons.check_circle_outline
        : Icons.info_outline;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13))),
        ]),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: EdgeInsets.symmetric(
            horizontal: _isTablet ? _sw * 0.15 : 16, vertical: 12),
        duration: Duration(seconds: error ? 3 : 2),
      ));
  }

  // ── Typing ────────────────────────────────────────────────────────────────
  void _onTypingChanged() {
    final nowTyping = _messageController.text.isNotEmpty;
    if (nowTyping != _isTyping) {
      _isTyping = nowTyping;
      _chatService.setTyping(
          widget.chatId, FirebaseAuth.instance.currentUser!.uid, _isTyping);
    }
  }

  // ── Data loaders ──────────────────────────────────────────────────────────
  Future<void> _loadSavedUrls() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('saved_media_${widget.chatId}') ?? [];
    if (mounted) {
      setState(() {
        for (final url in saved) {
          _alreadySaved.add(url);
          _downloadProgress[url] = -1;
        }
      });
    }
  }

  Future<void> _markUrlAsSaved(String url) async {
    _alreadySaved.add(url);
    final prefs = await SharedPreferences.getInstance();
    final key = 'saved_media_${widget.chatId}';
    final existing = prefs.getStringList(key) ?? [];
    if (!existing.contains(url)) {
      existing.add(url);
      await prefs.setStringList(key, existing);
    }
  }

  Future<void> _loadIntent() async {
    final doc = await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .get();
    if (!mounted) return;
    if (doc.exists) {
      final intent = (doc.data() as Map<String, dynamic>)['intent'] as Map<String, dynamic>?;
      if (intent != null) setState(() => _intent = intent);
    }
  }

  // ── Send actions ──────────────────────────────────────────────────────────
  Future<void> _sendText() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final encrypted = _enc.encrypt(text);
    _messageController.clear();
    await _chatService.sendMessage(
      chatId: widget.chatId,
      receiverId: widget.receiverId,
      type: 'text',
      text: encrypted,
      encrypted: true,
      plainTextPreview: text,
    );
  }

  Future<void> _pickMedia({required bool fromCamera}) async {
    try {
      final picked = await picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 80,
      );
      if (picked == null) return;
      final file = File(picked.path);
      final ext = picked.path.split('.').last;
      final path = 'chat_media/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}.$ext';
      setState(() => _uploadProgress = 0.01);
      final url = await _chatService.uploadFile(
          file: file, path: path, onProgress: (p) => setState(() => _uploadProgress = p));
      await _chatService.sendMessage(
          chatId: widget.chatId, receiverId: widget.receiverId, type: 'image', fileUrl: url);
      setState(() => _uploadProgress = 0.0);
    } catch (_) {
      _snack('Error picking image', error: true);
    }
  }

  Future<void> _pickVideo({bool fromCamera = false}) async {
    try {
      final picked = await picker.pickVideo(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (picked == null) return;
      final file = File(picked.path);
      final ext = picked.path.split('.').last;
      final path = 'chat_videos/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}.$ext';
      setState(() => _uploadProgress = 0.01);
      final url = await _chatService.uploadFile(
          file: file, path: path, onProgress: (p) => setState(() => _uploadProgress = p));
      await _chatService.sendMessage(
          chatId: widget.chatId, receiverId: widget.receiverId, type: 'video', fileUrl: url);
      setState(() => _uploadProgress = 0.0);
    } catch (_) {
      _snack('Error picking video', error: true);
    }
  }

  Future<void> _sendLocation() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
    );
    if (result == null) return;
    await _chatService.sendMessage(
      chatId: widget.chatId,
      receiverId: widget.receiverId,
      type: 'location',
      text: 'Shared a location',
      extra: {'lat': result['lat'], 'lng': result['lng'], 'address': result['address'] ?? ''},
    );
  }

  // ── Recording ─────────────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    if (!await _audioRecorder.hasPermission()) {
      _snack('Microphone permission denied', error: true);
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(
        RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000), path: path);
    setState(() { _isRecording = true; _recordDuration = Duration.zero; });
    _recordTimer = Timer.periodic(
        const Duration(seconds: 1), (_) => setState(() => _recordDuration += const Duration(seconds: 1)));
  }

  Future<void> _stopAndSendRecording() async {
    _recordTimer?.cancel();
    final path = await _audioRecorder.stop();
    setState(() { _isRecording = false; _recordDuration = Duration.zero; });
    if (path == null) return;
    final storagePath = 'chat_audio/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}.m4a';
    setState(() => _uploadProgress = 0.01);
    final url = await _chatService.uploadFile(
        file: File(path),
        path: storagePath,
        onProgress: (p) => setState(() => _uploadProgress = p));
    await _chatService.sendMessage(
        chatId: widget.chatId, receiverId: widget.receiverId, type: 'audio', fileUrl: url);
    setState(() => _uploadProgress = 0.0);
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await _audioRecorder.stop();
    setState(() { _isRecording = false; _recordDuration = Duration.zero; });
  }

  Future<void> _toggleAudio(String url) async {
    if (_currentlyPlayingUrl == url && _isPlaying) {
      await _audioPlayer.pause();
    } else {
      _currentlyPlayingUrl = url;
      await _audioPlayer.play(UrlSource(url));
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────
  Future<void> _deleteSelected() async {
    if (_selectedMessageIds.isEmpty) return;
    await _chatService.deleteMessages(widget.chatId, _selectedMessageIds.toList());
    setState(() => _selectedMessageIds.clear());
  }

  Future<void> _deleteChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete chat'),
        content: const Text('Delete this entire chat and all messages?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await _chatService.deleteChat(widget.chatId);
      if (mounted) Navigator.pop(context);
    }
  }

  // ── Report ────────────────────────────────────────────────────────────────
  Future<void> _showReportDialog() async {
    final reasonCtrl = TextEditingController();
    final selectedReason = ValueNotifier<String?>(null);

    const primaryPurple = Color(0xFF26004D);
    const dangerRed = Color(0xFFE53935);
    final quickReasons = ['Spam', 'Harassment', 'Scam', 'Fake profile', 'Inappropriate'];

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: dangerRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.flag_rounded, color: dangerRed, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'Report User',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: primaryPurple),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    children: [
                      const TextSpan(text: 'Reporting '),
                      TextSpan(
                        text: widget.receiverName,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: primaryPurple),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Quick select', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                const SizedBox(height: 8),
                ValueListenableBuilder<String?>(
                  valueListenable: selectedReason,
                  builder: (_, selected, __) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: quickReasons.map((r) {
                      final isSelected = selected == r;
                      return GestureDetector(
                        onTap: () {
                          selectedReason.value = r;
                          if (reasonCtrl.text.trim().isEmpty) {
                            reasonCtrl.text = r;
                            reasonCtrl.selection = TextSelection.collapsed(offset: reasonCtrl.text.length);
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: isSelected ? primaryPurple : primaryPurple.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? primaryPurple : primaryPurple.withOpacity(0.15),
                            ),
                          ),
                          child: Text(
                            r,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : primaryPurple,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 4,
                  maxLength: 500,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Describe the issue in more detail…',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                    filled: true,
                    fillColor: const Color(0xFFF3F0FB),
                    counterStyle: const TextStyle(fontSize: 11, color: Colors.black38),
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: primaryPurple, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: TextButton.styleFrom(foregroundColor: Colors.black54),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: dangerRed,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Submit Report', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      if (reasonCtrl.text.trim().isEmpty) {
        _snack('Please enter a reason before submitting.', error: true);
        return;
      }

      final finalConfirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: dangerRed.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline_rounded, color: dangerRed, size: 26),
          ),
          title: const Text(
            'Confirm Report',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: primaryPurple),
          ),
          content: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(fontSize: 13.5, color: Colors.black87, height: 1.4),
              children: [
                const TextSpan(text: 'You are about to report '),
                TextSpan(
                  text: widget.receiverName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: '. This will be reviewed by our team. Continue?'),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: TextButton.styleFrom(foregroundColor: Colors.black54),
              child: const Text('Go Back', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: dangerRed,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Yes, Report', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ],
        ),
      );

      if (finalConfirm != true || !mounted) return;

      try {
        await _chatService.reportUser(
          reportedUserId: widget.receiverId,
          reportedUserName: widget.receiverName,
          chatId: widget.chatId,
          reason: reasonCtrl.text.trim(),
        );
        if (mounted) _snack('Report submitted. Our team will review it.', success: true);
      } catch (_) {
        if (mounted) _snack('Failed to submit report. Please try again.', error: true);
      }
    } finally {
      reasonCtrl.dispose();
      selectedReason.dispose();
    }
  }

  // ── Download (with lock to prevent double-tap race) ───────────────────────
  Future<void> _downloadFile(String url, String type) async {
    if (_alreadySaved.contains(url)) return;
    if (_downloadLock.contains(url)) return; // already in flight or queued
    _downloadLock.add(url);

    if (_activeDownloads >= _maxConcurrentDownloads) {
      // At capacity — queue it and show a pending indicator rather than
      // stacking up unlimited simultaneous Dio downloads.
      if (mounted) setState(() => _downloadProgress[url] = 0.0);
      _pendingDownloads.add(() => _runDownload(url, type));
      return;
    }

    await _runDownload(url, type);
  }

  Future<void> _runDownload(String url, String type) async {
    _activeDownloads++;

    final hasAccess = await Gal.hasAccess(toAlbum: true);
    if (!hasAccess) {
      final granted = await Gal.requestAccess(toAlbum: true);
      if (!granted) {
        _downloadLock.remove(url);
        _activeDownloads--;
        _snack('Gallery permission denied', error: true);
        _processQueue();
        return;
      }
    }

    if (mounted) setState(() => _downloadProgress[url] = 0.0);

    try {
      final dir = await getTemporaryDirectory();
      final rawExt = url.split('?').first.split('.').last.toLowerCase();
      final ext = rawExt.length <= 4 ? rawExt : (type == 'image' ? 'jpg' : 'mp4');
      final savePath = '${dir.path}/SwapNow_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await Dio().download(url, savePath, onReceiveProgress: (recv, total) {
        if (total > 0 && mounted) setState(() => _downloadProgress[url] = recv / total);
      });

      if (!mounted) return;

      bool saved = false;
      try {
        if (type == 'image') {
          await Gal.putImage(savePath, album: 'SwapNow');
          saved = true;
        } else if (type == 'video') {
          await Gal.putVideo(savePath, album: 'SwapNow');
          saved = true;
        }
      } catch (_) {}

      final tmp = File(savePath);
      if (await tmp.exists()) await tmp.delete();

      if (!mounted) return;
      if (saved) {
        await _markUrlAsSaved(url);
        setState(() => _downloadProgress[url] = -1);
        _snack('${type == 'image' ? 'Photo' : 'Video'} saved to gallery ✓', success: true);
      } else {
        setState(() => _downloadProgress[url] = null);
        _snack('Could not save to gallery', error: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _downloadProgress[url] = null);
        _snack('Download failed — tap to retry', error: true);
      }
    } finally {
      _downloadLock.remove(url);
      _activeDownloads--;
      _processQueue();
    }
  }

  void _processQueue() {
    while (_activeDownloads < _maxConcurrentDownloads && _pendingDownloads.isNotEmpty) {
      final next = _pendingDownloads.removeAt(0);
      next();
    }
  }


  Future<String> _reverseGeocode(double lat, double lng) async {
    final key = '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
    final cached = _geocodeCache[key];
    if (cached != null) return cached;

    try {
      final ps = await placemarkFromCoordinates(lat, lng);
      if (ps.isEmpty) return 'Tap to open map';
      final p = ps.first;
      final parts = [
        if ((p.name ?? '').isNotEmpty && p.name != p.street) p.name,
        if ((p.subLocality ?? '').isNotEmpty) p.subLocality,
        if ((p.locality ?? '').isNotEmpty) p.locality,
      ].whereType<String>().toList();
      final result = parts.isNotEmpty ? parts.join(', ') : 'Tap to open map';
      _geocodeCache[key] = result; // only cache successful lookups, so failures can retry
      return result;
    } catch (_) {
      return 'Tap to open map';
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final selectedMode = _selectedMessageIds.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: false,
      appBar: _buildAppBar(selectedMode),
      body: Container(
        decoration: const BoxDecoration(
          // Beautiful purple-to-lavender gradient background
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF3E5F5), Color(0xFFE8EAF6), Color(0xFFFCE4EC)],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Subtle decorative pattern overlay
            Positioned.fill(child: _buildBgPattern()),
            SafeArea(
              top: false,
              child: Column(
                children: [
                  if (_intent != null) _buildIntentBanner(),
                  Expanded(child: _buildMessageList()),
                  if (_uploadProgress > 0 && _uploadProgress < 1)
                    LinearProgressIndicator(
                      value: _uploadProgress,
                      backgroundColor: _lightPurple,
                      color: _purple,
                      minHeight: 3,
                    ),
                  _isRecording ? _buildRecordingBar() : _buildInputBar(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Background decorative pattern ─────────────────────────────────────────
  Widget _buildBgPattern() {
    return CustomPaint(painter: _BubblePatternPainter());
  }

  // ── Intent banner ─────────────────────────────────────────────────────────
  Widget _buildIntentBanner() {
    final intentType = _intent!['type'] as String? ?? 'swap';
    final isSell = intentType == 'sell';
    final isBuy = intentType == 'buy';
    final color = isSell ? const Color(0xFFD84315) : isBuy ? _purple : _teal;
    final icon = isSell
        ? Icons.storefront_outlined
        : isBuy
        ? Icons.shopping_bag_outlined
        : Icons.swap_horiz_rounded;
    final label = isSell
        ? 'Wants to Sell to Company'
        : isBuy
        ? 'Wants to Buy'
        : 'Wants to Swap';

    final listedProduct = _intent!['listedProduct'] as Map<String, dynamic>?;
    final swapProductsRaw = _intent!['swapProducts'] as List?;
    final swapProducts =
        swapProductsRaw?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];

    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      child: Container(
        color: color.withOpacity(0.06),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: _isSmall ? 10 : 14, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.12), shape: BoxShape.circle),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: _isSmall ? 12 : 13,
                            fontWeight: FontWeight.w700,
                            color: color)),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _bannerCollapsed = !_bannerCollapsed),
                    child: AnimatedRotation(
                      turns: _bannerCollapsed ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      child: Icon(Icons.keyboard_arrow_up, size: 20, color: Colors.grey[500]),
                    ),
                  ),
                ],
              ),
            ),
            if (!_bannerCollapsed) ...[
              if (listedProduct != null)
                _buildProductChip(listedProduct, color,
                    prefix: isBuy ? 'Interested in' : 'Wants in exchange for'),
              if (!isBuy && !isSell && swapProducts.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.only(
                      left: _isSmall ? 10 : 14,
                      right: _isSmall ? 10 : 14,
                      top: 2,
                      bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.arrow_forward, size: 13, color: Colors.grey[500]),
                      const SizedBox(width: 6),
                      Text('Offering:',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600])),
                    ],
                  ),
                ),
                SizedBox(
                  height: _isSmall ? 68 : 76,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.fromLTRB(
                        _isSmall ? 10 : 14, 0, _isSmall ? 10 : 14, 10),
                    itemCount: swapProducts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => _buildSwapProductTile(swapProducts[i], _teal),
                  ),
                ),
              ],
            ],
            Divider(height: 1, color: color.withOpacity(0.15)),
          ],
        ),
      ),
    );
  }

  Widget _buildProductChip(Map<String, dynamic> product, Color color, {String prefix = ''}) {
    final images = (product['images'] as List?) ?? [];
    final imageUrl = images.isNotEmpty ? images[0] as String : null;
    final hPad = _isSmall ? 10.0 : 14.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
      child: Row(
        children: [
          if (prefix.isNotEmpty)
            Flexible(
              child: Text('$prefix  ',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  overflow: TextOverflow.ellipsis),
            ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 26,
                        height: 26,
                        fit: BoxFit.cover,
                        errorWidget: (ctx, url, error) => Container(
                          width: 26,
                          height: 26,
                          color: Colors.grey[300],
                          child: const Icon(Icons.image_not_supported_outlined, size: 14, color: Colors.grey),
                        ),
                      ),
                    ),
                  if (imageUrl != null) const SizedBox(width: 6),
                  Flexible(
                    child: Text(product['title'] ?? 'Product',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwapProductTile(Map<String, dynamic> p, Color color) {
    final images = (p['images'] as List?) ?? [];
    final imageUrl = images.isNotEmpty ? images[0] as String : null;
    return GestureDetector(
      onTap: () => _showSwapProductDetail(p),
      child: Container(
        width: _isSmall ? 110.0 : 130.0,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 34,
                height: 34,
                color: Colors.grey[200],
                child: imageUrl != null
                    ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  errorWidget: (ctx, url, error) =>
                  const Icon(Icons.image_not_supported_outlined, size: 16, color: Colors.grey),
                )
                    : const Icon(Icons.image_not_supported, size: 16, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(p['title'] ?? 'Product',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('₹ ${p['price'] ?? '—'}',
                      style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Swap product detail sheet ─────────────────────────────────────────────
  /*void _showSwapProductDetail(Map<String, dynamic> p) {
    final images = (p['images'] as List?)?.map((e) => e as String).toList() ?? [];
    final pageCtrl = PageController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,

    );
  }*/

  void _showSwapProductDetail(Map<String, dynamic> p) {
    final images = (p['images'] as List?)?.map((e) => e as String).toList() ?? [];
    final pageCtrl = PageController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: _isSmall ? 0.92 : 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) {
          int currentImg = 0;
          return StatefulBuilder(builder: (ctx2, setSheet) {
            return Container(
              decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: _isSmall ? 180 : (_isTablet ? 300 : 220),
                    child: images.isEmpty
                        ? Container(color: Colors.grey[200], child: const Center(child: Icon(Icons.image_not_supported, size: 48, color: Colors.grey)))
                        : Stack(
                      children: [
                        PageView.builder(
                          controller: pageCtrl,
                          itemCount: images.length,
                          onPageChanged: (i) => setSheet(() => currentImg = i),
                          itemBuilder: (_, i) => CachedNetworkImage(
                            imageUrl: images[i],
                            fit: BoxFit.cover,
                            width: double.infinity,
                            placeholder: (ctx, url) => Container(
                              color: Colors.grey[100],
                              child: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00796B)),
                              ),
                            ),
                            errorWidget: (ctx, url, error) => Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: Icon(Icons.image_not_supported_outlined, size: 40, color: Colors.grey),
                              ),
                            ),
                          ),
                        ),
                        if (images.length > 1)
                          Positioned(
                            bottom: 10, left: 0, right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(images.length, (i) {
                                final active = i == currentImg;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  width: active ? 18 : 6, height: 5,
                                  decoration: BoxDecoration(
                                      color: active ? Colors.white : Colors.white54,
                                      borderRadius: BorderRadius.circular(3)),
                                );
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollCtrl,
                      padding: EdgeInsets.all(_isSmall ? 14 : 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: const Color(0xFF00796B).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.swap_horiz_rounded, size: 14, color: Color(0xFF00796B)),
                              SizedBox(width: 4),
                              Text('Offered for Swap',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF00796B), fontWeight: FontWeight.w600)),
                            ]),
                          ),
                          const SizedBox(height: 12),
                          Text(p['title'] ?? 'Product',
                              style: TextStyle(fontSize: _isSmall ? 17 : 20, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text('₹ ${p['price'] ?? '—'}',
                              style: TextStyle(
                                  fontSize: _isSmall ? 16 : 18,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF6A1B9A))),
                          const SizedBox(height: 14),
                          if ((p['condition'] ?? '').toString().isNotEmpty)
                            _detailRow('Condition', p['condition'].toString()),
                          if ((p['category'] ?? '').toString().isNotEmpty)
                            _detailRow('Category', p['category'].toString()),
                          if ((p['location'] ?? '').toString().isNotEmpty)
                            _detailRow('Location', p['location'].toString()),
                          if ((p['description'] ?? '').toString().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text('Description',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text(p['description'].toString(),
                                style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.6)),
                          ],
                          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          });
        },
      ),
    ).whenComplete(() => pageCtrl.dispose());
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _isSmall ? 80 : 90,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────
  AppBar _buildAppBar(bool selectedMode) {
    return AppBar(
      backgroundColor: _purple,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      elevation: 2,
      title: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            CircleAvatar(
              radius: _isSmall ? 17 : 20,
              backgroundImage: NetworkImage(widget.receiverImage),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.receiverName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: _isSmall ? 14 : 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  _buildPresenceText(),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: selectedMode
          ? [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text('${_selectedMessageIds.length}',
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
        IconButton(icon: const Icon(Icons.delete, color: Colors.white), onPressed: _deleteSelected),
        IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => setState(() => _selectedMessageIds.clear())),
      ]
          : [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onSelected: (v) {
            if (v == 'delete_chat') _deleteChat();
            if (v == 'report') _showReportDialog();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'report',
              child: Row(children: [
                Icon(Icons.flag_outlined, color: Colors.red, size: 18),
                SizedBox(width: 10),
                Text('Report User', style: TextStyle(color: Colors.red)),
              ]),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'delete_chat', child: Text('Delete Chat')),
          ],
        ),
      ],
    );
  }

  Widget _buildPresenceText() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(widget.receiverId).snapshots(),
      builder: (context, userSnap) {
        final online = userSnap.hasData && userSnap.data!.exists
            ? ((userSnap.data!.data() as Map<String, dynamic>)['online'] ?? false) as bool
            : false;
        final Timestamp? lastSeenTs = userSnap.hasData && userSnap.data!.exists
            ? (userSnap.data!.data() as Map<String, dynamic>)['lastSeen'] as Timestamp?
            : null;

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).snapshots(),
          builder: (ctx, chatSnap) {
            bool isTyping = false;
            if (chatSnap.hasData && chatSnap.data!.exists) {
              final typing =
                  ((chatSnap.data!.data() as Map<String, dynamic>)['typing'] as Map<String, dynamic>?) ?? {};
              isTyping = typing[widget.receiverId] == true;
            }

            String label;
            bool highlight = false;

            if (isTyping) {
              label = 'typing...';
              highlight = true;
            } else if (online) {
              label = 'online';
              highlight = true;
            } else if (lastSeenTs != null) {
              final ls = lastSeenTs.toDate();
              final now = DateTime.now();
              final diff = now.difference(ls);
              final today = DateTime(now.year, now.month, now.day);
              final lsDay = DateTime(ls.year, ls.month, ls.day);

              if (diff.inSeconds < 60) {
                label = 'last seen just now';
              } else if (diff.inMinutes < 60) {
                label = 'last seen ${diff.inMinutes}m ago';
              } else if (lsDay == today) {
                label = 'last seen today at ${DateFormat('h:mm a').format(ls)}';
              } else if (lsDay == today.subtract(const Duration(days: 1))) {
                label = 'last seen yesterday at ${DateFormat('h:mm a').format(ls)}';
              } else {
                label = 'last seen ${DateFormat('d/M/yy').format(ls)}';
              }
            } else {
              label = 'last seen recently';
            }

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(label,
                  key: ValueKey(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      color: highlight ? Colors.white : Colors.white70,
                      fontStyle: isTyping ? FontStyle.italic : FontStyle.normal)),
            );
          },
        );
      },
    );
  }

  // ── Message list ──────────────────────────────────────────────────────────
  Widget _buildMessageList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _chatService.getMessages(widget.chatId),
      builder: (context, snapshot) {
        // Mark seen only when the message count actually changes (new message
        // arrived), not on every rebuild — avoids hundreds of Firestore writes.
        if (snapshot.hasData) {
          final len = snapshot.data!.docs.length;
          if (len != _lastSeenSnapshotLength) {
            _lastSeenSnapshotLength = len;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _chatService.markMessagesAsSeen(widget.chatId);
            });
          }
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline, size: 44, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text('Messages are end-to-end encrypted',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            ]),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          reverse: true,
          padding: EdgeInsets.symmetric(
              horizontal: _isTablet ? _sw * 0.08 : 10, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final ts = (data['timestamp'] as Timestamp?)?.toDate();

            bool showDateChip = false;
            if (ts != null) {
              if (i == docs.length - 1) {
                showDateChip = true;
              } else {
                final prevTs = ((docs[i + 1].data() as Map<String, dynamic>)['timestamp'] as Timestamp?)?.toDate();
                if (prevTs != null && _dateLabel(ts) != _dateLabel(prevTs)) {
                  showDateChip = true;
                }
              }
            }

            return Column(
              children: [
                if (showDateChip && ts != null) _buildDateChip(_dateLabel(ts)),
                _buildMessage(doc),
              ],
            );
          },
        );
      },
    );
  }

  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('MMM d, yyyy').format(dt);
  }

  Widget _buildDateChip(String label) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildMessage(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final isMe = data['senderId'] == FirebaseAuth.instance.currentUser!.uid;
    final type = (data['type'] ?? 'text') as String;
    String text = (data['text'] ?? '') as String;
    final fileUrl = (data['fileUrl'] ?? '') as String;
    final extra = (data['extra'] is Map)
        ? Map<String, dynamic>.from(data['extra'] as Map)
        : <String, dynamic>{};
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final status = (data['status'] ?? 'sent') as String;
    final encrypted = data['encrypted'] == true;
    final time = timestamp != null ? DateFormat('h:mm a').format(timestamp) : '';
    final selected = _selectedMessageIds.contains(doc.id);

    if (type == 'text' && encrypted) {
      text = _enc.decrypt(text);
    }

    return GestureDetector(
      onLongPress: () => setState(() {
        _selectedMessageIds.contains(doc.id)
            ? _selectedMessageIds.remove(doc.id)
            : _selectedMessageIds.add(doc.id);
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: selected ? _purple.withOpacity(0.12) : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Column(
            crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                constraints: BoxConstraints(maxWidth: _bubbleMax),
                decoration: BoxDecoration(
                  color: isMe ? _purple : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4, offset: const Offset(0, 2))
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  ),
                  child: _messageWidget(type, text, fileUrl, extra, isMe),
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (encrypted && type == 'text')
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Icon(Icons.lock, size: 10, color: Colors.grey[400]),
                    ),
                  Text(time, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  if (isMe) ...[const SizedBox(width: 4), _buildTick(status)],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTick(String status) {
    switch (status) {
      case 'seen':
        return const Icon(Icons.done_all, size: 16, color: Color(0xFF53BDEB));
      case 'delivered':
        return Icon(Icons.done_all, size: 16, color: Colors.grey[400]);
      default:
        return Icon(Icons.done, size: 16, color: Colors.grey[400]);
    }
  }

  Widget _messageWidget(
      String type, String text, String fileUrl, Map<String, dynamic> extra, bool isMe) {
    final textColor = isMe ? Colors.white : Colors.black87;

    switch (type) {
      case 'image':
        return GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => ImageViewer(imageUrl: fileUrl))),
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              Hero(
                tag: fileUrl,
                child: CachedNetworkImage(
                  imageUrl: fileUrl,
                  width: _mediaW,
                  height: _mediaH,
                  fit: BoxFit.cover,
                  placeholder: (ctx, url) => SizedBox(
                    width: _mediaW,
                    height: _mediaH,
                    child: Center(
                      child: CircularProgressIndicator(color: _purple, strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (ctx, url, error) => Container(
                    width: _mediaW,
                    height: _mediaH,
                    color: Colors.grey[200],
                    child: const Center(
                      child: Icon(Icons.broken_image_outlined, size: 40, color: Colors.grey),
                    ),
                  ),
                ),
              ),
              _buildDownloadBadge(fileUrl, 'image'),
            ],
          ),
        );

      case 'video':
        return GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => VideoPlayerScreen(videoUrl: fileUrl))),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: _mediaW,
                height: _mediaH * 0.72,
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                child: const Icon(Icons.movie, size: 60, color: Colors.white24),
              ),
              Container(
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                padding: const EdgeInsets.all(12),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
              ),
              Positioned(
                  bottom: 8,
                  right: 8,
                  child: _buildDownloadBadge(fileUrl, 'video')),
            ],
          ),
        );

      case 'audio':
        final isThisPlaying = _currentlyPlayingUrl == fileUrl && _isPlaying;
        final waveWidth = _isSmall ? 90.0 : 120.0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _toggleAudio(fileUrl),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                      color: isMe ? Colors.white24 : _lightPurple, shape: BoxShape.circle),
                  child: Icon(isThisPlaying ? Icons.pause : Icons.play_arrow,
                      color: isMe ? Colors.white : _purple, size: 24),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: waveWidth, height: 2,
                    decoration: BoxDecoration(
                        color: isMe ? Colors.white54 : Colors.grey[300],
                        borderRadius: BorderRadius.circular(1)),
                    child: isThisPlaying
                        ? LinearProgressIndicator(
                        color: isMe ? Colors.white : _purple,
                        backgroundColor: Colors.transparent)
                        : null,
                  ),
                  const SizedBox(height: 4),
                  Icon(Icons.mic, size: 14, color: isMe ? Colors.white70 : Colors.grey[500]),
                ],
              ),
            ],
          ),
        );

      case 'location':
        final lat = extra['lat'];
        final lng = extra['lng'];
        final savedAddress = (extra['address'] ?? '') as String;
        return GestureDetector(
          onTap: () async {
            final url = Uri.parse(
                'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
            if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                      color: isMe ? Colors.white24 : _lightPurple, shape: BoxShape.circle),
                  child: Icon(Icons.location_on, color: isMe ? Colors.white : _purple, size: 20),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Shared Location',
                          style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                              fontSize: _isSmall ? 13 : 14)),
                      const SizedBox(height: 2),
                      if (savedAddress.isNotEmpty)
                        Text(savedAddress,
                            style: TextStyle(
                                color: isMe ? Colors.white70 : Colors.grey[500], fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis)
                      else
                        FutureBuilder<String>(
                          future: _reverseGeocode(
                              lat?.toDouble() ?? 0, lng?.toDouble() ?? 0),
                          builder: (ctx, snap) => Text(snap.data ?? 'Tap to open map',
                              style: TextStyle(
                                  color: isMe ? Colors.white70 : Colors.grey[500], fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.open_in_new,
                    color: isMe ? Colors.white60 : Colors.grey[400], size: 14),
              ],
            ),
          ),
        );

      default:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(text,
              style: TextStyle(color: textColor, fontSize: _isSmall ? 14 : 15)),
        );
    }
  }

  Widget _buildDownloadBadge(String url, String type) {
    final progress = _downloadProgress[url];
    if (progress == null) {
      return GestureDetector(
        onTap: () => _downloadFile(url, type),
        child: Container(
          margin: const EdgeInsets.all(6),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.download_rounded, color: Colors.white, size: 18),
        ),
      );
    } else if (progress >= 0 && progress < 1) {
      return Container(
        margin: const EdgeInsets.all(6),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(value: progress, strokeWidth: 2, color: Colors.white),
        ),
      );
    } else {
      return Container(
        margin: const EdgeInsets.all(6),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.8), borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.check, color: Colors.white, size: 18),
      );
    }
  }

  // ── Input bar ─────────────────────────────────────────────────────────────
  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 8, right: 8, top: 6,
        bottom: MediaQuery.of(context).padding.bottom > 0
            ? MediaQuery.of(context).padding.bottom
            : 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: _purple),
            onPressed: _showAttachOptions,
            padding: const EdgeInsets.all(8),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(26),
              ),
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  hintText: 'Message',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
          ),
          const SizedBox(width: 6),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _messageController,
            builder: (_, value, __) {
              final hasText = value.text.trim().isNotEmpty;
              return GestureDetector(
                onTap: hasText ? _sendText : null,
                onLongPress: hasText ? null : _startRecording,
                child: Container(
                  width: 44, height: 44,
                  decoration: const BoxDecoration(color: _purple, shape: BoxShape.circle),
                  child: Icon(hasText ? Icons.send_rounded : Icons.mic,
                      color: Colors.white, size: 22),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingBar() {
    final minutes = _recordDuration.inMinutes.remainder(60);
    final seconds = _recordDuration.inSeconds.remainder(60);
    return Container(
      padding: EdgeInsets.only(
        left: 12, right: 12, top: 10,
        bottom: MediaQuery.of(context).padding.bottom > 0
            ? MediaQuery.of(context).padding.bottom
            : 10,
      ),
      color: Colors.white,
      child: Row(
        children: [
          GestureDetector(
            onTap: _cancelRecording,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
              child: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                _AnimatedWaveform(color: _purple),
                const SizedBox(width: 10),
                Text(
                    '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: _purple, fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
          ),
          GestureDetector(
            onTap: _stopAndSendRecording,
            child: Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(color: _purple, shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  // ── Attach options ────────────────────────────────────────────────────────
  void _showAttachOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        final bottomPad = MediaQuery.of(context).padding.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomPad > 0 ? bottomPad : 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                    color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(_isTablet ? 48 : 16, 8, _isTablet ? 48 : 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _attachOption(Icons.camera_alt, 'Camera', Colors.pink, () {
                      Navigator.pop(context);
                      _pickMedia(fromCamera: true);
                    }),
                    _attachOption(Icons.photo, 'Gallery', Colors.purple, () {
                      Navigator.pop(context);
                      _pickMedia(fromCamera: false);
                    }),
                    _attachOption(Icons.videocam, 'Video', Colors.deepOrange, () {
                      Navigator.pop(context);
                      _pickVideo(fromCamera: false);
                    }),
                    _attachOption(Icons.video_camera_back_outlined, 'Rec Video', Colors.red, () {
                      Navigator.pop(context);
                      _pickVideo(fromCamera: true);
                    }),
                    _attachOption(Icons.location_on, 'Location', Colors.green, () {
                      Navigator.pop(context);
                      _sendLocation();
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _attachOption(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _isSmall ? 48 : 54,
            height: _isSmall ? 48 : 54,
            decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: _isSmall ? 22 : 26),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: _isSmall ? 11 : 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── Background pattern painter ────────────────────────────────────────────────
class _BubblePatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final bubbles = [
      // [x_fraction, y_fraction, radius, opacity]
      [0.05, 0.08, 60.0, 0.04],
      [0.9, 0.05, 80.0, 0.03],
      [0.15, 0.35, 40.0, 0.035],
      [0.85, 0.28, 55.0, 0.04],
      [0.5, 0.15, 70.0, 0.025],
      [0.03, 0.6, 90.0, 0.03],
      [0.92, 0.55, 65.0, 0.035],
      [0.4, 0.72, 50.0, 0.04],
      [0.75, 0.78, 75.0, 0.03],
      [0.2, 0.88, 45.0, 0.035],
      [0.6, 0.92, 55.0, 0.03],
    ];

    for (final b in bubbles) {
      paint.color = const Color(0xFF7B1FA2).withOpacity(b[3] as double);
      canvas.drawCircle(
        Offset(size.width * (b[0] as double), size.height * (b[1] as double)),
        b[2] as double,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Animated waveform ─────────────────────────────────────────────────────────
class _AnimatedWaveform extends StatefulWidget {
  final Color color;
  const _AnimatedWaveform({required this.color});

  @override
  State<_AnimatedWaveform> createState() => _AnimatedWaveformState();
}

class _AnimatedWaveformState extends State<_AnimatedWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waveWidth = MediaQuery.of(context).size.width < 360 ? 60.0 : 80.0;
    return SizedBox(
      height: 28,
      width: waveWidth,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(10, (i) {
            final wave = ((_ctrl.value + i * 0.1) % 1.0);
            final height = 4 + (wave * 18).abs();
            return Container(
              width: 3, height: height,
              decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)),
            );
          }),
        ),
      ),
    );
  }
}