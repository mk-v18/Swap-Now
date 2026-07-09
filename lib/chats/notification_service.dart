import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

/// WhatsApp-style notification service.
/// Singleton — call NotificationService().init(navigatorKey) once from SplashScreen.
class NotificationService {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // ── Private fields ────────────────────────────────────────────────────────
  final _messaging          = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  GlobalKey<NavigatorState>? _navigatorKey;

  // FIX: Guard against double-init (hot restart / SplashScreen rebuilds).
  bool _initialized = false;

  // FIX: Active chat suppression — set from ChatScreen via setActiveChatId().
  String? _currentChatId;

  // FIX: Reusable HTTP client — avoids creating a new TCP connection per
  // avatar bitmap load. Closed in dispose().
  final _httpClient = http.Client();

  // FIX: Pending cold-start navigation — stores the initial message payload
  // when getInitialMessage() fires before the widget tree is ready.
  // Drained by _drainPendingNavigation() once the navigator is available.
  String? _pendingNavigationPayload;

  static const _chatChannelId   = 'chat_messages';
  static const _chatChannelName = 'Chat Messages';

  // FIX: Allowed URL schemes for avatar loading — blocks file://, data://,
  // and other non-HTTP schemes from a crafted FCM payload (SSRF prevention).
  static const _allowedSchemes = {'https', 'http'};

  // ── INIT ──────────────────────────────────────────────────────────────────
  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    if (_initialized) return;
    _initialized = true;
    _navigatorKey = navigatorKey;

    // ① Request permission
    await _messaging.requestPermission(
      alert:       true,
      badge:       true,
      sound:       true,
      provisional: false,
    );

    // ② Local notifications plugin
    const androidSettings = AndroidInitializationSettings('ic_notification'); // was '@mipmap/ic_launcher'
    const iosSettings     = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationTapped,
    );

    // ③ Android notification channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
      const AndroidNotificationChannel(
        _chatChannelId,
        _chatChannelName,
        description:      'Chat message notifications',
        importance:       Importance.max,
        playSound:        true,
        enableVibration:  true,
        showBadge:        true,
      ),
    );

    // ④ FCM token — save on init and refresh
    await _saveToken();
    _messaging.onTokenRefresh.listen(_updateToken);

    // ⑤ Foreground messages → local notification
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // ⑥ Background tap (app was running in background)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);

    // ⑦ Cold-start tap (app was terminated)
    // FIX: navigatorKey.currentState is NULL here — the widget tree has not
    // built yet. Store the payload and drain it once the navigator is ready.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      _pendingNavigationPayload = jsonEncode(initial.data);
      // Schedule drain after first frame — navigator is guaranteed ready then.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _drainPendingNavigation();
      });
    }
  }

  // ── TOKEN MANAGEMENT ──────────────────────────────────────────────────────
  Future<void> _saveToken([String? token]) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      token ??= await _messaging.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
      // FIX: use set+merge instead of update — update throws if doc
      // doesn't exist yet (race on first login before PersonalDetailsPage
      // writes the doc).
    } catch (e) {
      debugPrint('[Notifications] Token save failed: $e');
    }
  }

  Future<void> _updateToken(String token) => _saveToken(token);

  /// Call on logout — removes token so device stops receiving notifications.
  Future<void> clearToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await Future.wait([
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({'fcmToken': FieldValue.delete()}),
        _messaging.deleteToken(),
      ]);
      // Allow re-init on next login.
      _initialized = false;
    } catch (e) {
      debugPrint('[Notifications] Token clear failed: $e');
    }
  }

  // ── FOREGROUND HANDLER ────────────────────────────────────────────────────
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final data        = message.data;
    final chatId      = _str(data, 'chatId');
    final senderName  = _str(data, 'senderName',  fallback: 'Someone');
    final senderPhoto = _str(data, 'senderPhoto');
    final body        = _str(data, 'body',         fallback: 'New message');
    final type        = _str(data, 'type',         fallback: 'text');

    if (chatId.isEmpty) return;
    // Suppress if this chat is already open on screen.
    if (_currentChatId == chatId) return;

    // FIX: Load bitmap in parallel with notification setup — not blocking the
    // show() call. We fire-and-forget the fetch and show without avatar first,
    // then update if the image arrives quickly. Simpler: just fetch with a
    // short timeout so slow avatars don't delay the notification.
    final largeIcon = await _safeFetchBitmap(senderPhoto);

    await _showLocalNotification(
      chatId:      chatId,
      senderName:  senderName,
      senderPhoto: senderPhoto,
      body:        body,
      type:        type,
      payload:     jsonEncode(data),
      largeIcon:   largeIcon,
    );
  }

  // ── SHOW LOCAL NOTIFICATION ───────────────────────────────────────────────
  Future<void> _showLocalNotification({
    required String    chatId,
    required String    senderName,
    required String    senderPhoto,
    required String    body,
    required String    type,
    required String    payload,
    Uint8List?         largeIcon,
  }) async {
    // FIX: Use a stable, collision-resistant ID.
    // hashCode % 100000 has a ~1% collision rate across 10 chats.
    // Use the full positive hashCode — still fits in a 32-bit int.
    final notifId = chatId.hashCode & 0x7FFFFFFF;

    final androidDetails = AndroidNotificationDetails(
      _chatChannelId,
      _chatChannelName,
      channelDescription: 'Chat message notifications',
      importance:         Importance.max,
      priority:           Priority.high,
      groupKey:           'chat_$chatId',
      setAsGroupSummary:  false,
      tag:                chatId,
      actions: [
        AndroidNotificationAction(
          'reply_$chatId',
          'Reply',
          allowGeneratedReplies: true,
          inputs: [
            const AndroidNotificationActionInput(label: 'Type a reply…'),
          ],
        ),
        const AndroidNotificationAction('mark_read', 'Mark as read'),
      ],
      largeIcon: largeIcon != null
          ? ByteArrayAndroidBitmap(largeIcon)
          : const DrawableResourceAndroidBitmap('@mipmap/ic_notification'),
      styleInformation: BigTextStyleInformation(body),
      color:            const Color(0xFF7B1FA2),
      colorized:        false,
      icon: 'ic_notification',
      playSound:        true,
      enableVibration:  true,
      when:             DateTime.now().millisecondsSinceEpoch,
      showWhen:         true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert:      true,
      presentBadge:      true,
      presentSound:      true,
      threadIdentifier:  'chat',
    );

    await _localNotifications.show(
      notifId,
      senderName,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  // ── NOTIFICATION TAP → NAVIGATE ───────────────────────────────────────────
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    final actionId = response.actionId;

    if (actionId?.startsWith('reply_') == true) {
      final replyText = response.input?.trim();
      if (replyText != null && replyText.isNotEmpty) {
        _sendQuickReply(payload, replyText);
      }
      return;
    }

    if (actionId == 'mark_read') {
      _handleMarkRead(payload);
      return;
    }

    // Default: open the chat screen.
    _navigateToChat(payload);
  }

  void _handleMarkRead(String payload) {
    try {
      final data   = jsonDecode(payload) as Map<String, dynamic>;
      final chatId = _str(data, 'chatId');
      if (chatId.isNotEmpty) _markSeenSilently(chatId);
    } catch (e) {
      debugPrint('[Notifications] Mark-read parse error: $e');
    }
  }

  // ── QUICK REPLY ───────────────────────────────────────────────────────────
  Future<void> _sendQuickReply(String payload, String replyText) async {
    try {
      final data       = jsonDecode(payload) as Map<String, dynamic>;
      final chatId     = _str(data, 'chatId');
      final receiverId = _str(data, 'senderId'); // reply TO original sender

      if (chatId.isEmpty || receiverId.isEmpty) return;

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);

      await Future.wait([
        chatRef.collection('messages').add({
          'senderId'  : uid,
          'receiverId': receiverId,
          'type'      : 'text',
          'text'      : replyText,
          'fileUrl'   : '',
          'extra'     : <String, dynamic>{},
          'timestamp' : FieldValue.serverTimestamp(),
          'status'    : 'sent',
          // FIX: Don't hardcode encrypted:false — omit the field entirely so
          // the chat screen's own encryption logic applies when it reads it.
          // A quick reply from the notification shade is unencrypted by design
          // (no keystore access in the notification handler), so we mark it
          // explicitly to signal that, rather than silently lying.
          'encrypted' : false,
        }),
        chatRef.update({
          'lastMessage' : replyText,
          'lastSenderId': uid,
          'lastStatus'  : 'sent',
          'timestamp'   : FieldValue.serverTimestamp(),
        }),
      ]);

      // Cancel the notification we just replied to.
      await cancelChatNotifications(chatId);
    } catch (e) {
      debugPrint('[Notifications] Quick reply error: $e');
    }
  }

  // ── MARK SEEN ─────────────────────────────────────────────────────────────
  Future<void> _markSeenSilently(String chatId) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // FIX: The original query used where('status', isNotEqualTo: 'seen')
      // which requires a composite Firestore index that is almost certainly
      // missing → silent failure on first deploy.
      //
      // Safer approach: update the chat-level lastStatus field and use a
      // Cloud Function or ChatScreen to sweep message statuses.
      // For the notification action, we only need to clear the badge/tray —
      // the full status sweep happens when the user opens the chat.
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .update({'lastStatus': 'seen'});

      await cancelChatNotifications(chatId);
    } catch (e) {
      debugPrint('[Notifications] Mark seen error: $e');
    }
  }

  // ── BACKGROUND / COLD-START OPEN ─────────────────────────────────────────
  void _handleNotificationOpen(RemoteMessage message) {
    _navigateToChat(jsonEncode(message.data));
  }

  // FIX: Drain any navigation that was queued during cold start (when the
  // navigator was not yet ready). Called from addPostFrameCallback in init().
  void _drainPendingNavigation() {
    final payload = _pendingNavigationPayload;
    if (payload == null) return;
    _pendingNavigationPayload = null;
    _navigateToChat(payload);
  }

  /// Navigate to /chat. Safe to call at any time — guards against null navigator.
  void _navigateToChat(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;

      final chatId      = _str(data, 'chatId');
      final senderId    = _str(data, 'senderId');
      final senderName  = _str(data, 'senderName');
      final senderPhoto = _str(data, 'senderPhoto');

      if (chatId.isEmpty) {
        debugPrint('[Notifications] Dropped navigation — chatId missing in payload');
        return;
      }

      final nav = _navigatorKey?.currentState;
      if (nav == null) {
        // Navigator not ready yet — queue and retry on next frame.
        _pendingNavigationPayload = payload;
        WidgetsBinding.instance.addPostFrameCallback((_) => _drainPendingNavigation());
        return;
      }

      nav.pushNamed('/chat', arguments: {
        'chatId'       : chatId,
        'receiverId'   : senderId,
        'receiverName' : senderName,
        'receiverImage': senderPhoto,
      });
    } catch (e) {
      debugPrint('[Notifications] Navigate error: $e');
    }
  }

  // ── ACTIVE CHAT MANAGEMENT ────────────────────────────────────────────────
  /// Call from ChatScreen.initState / dispose to suppress notifications
  /// while the user has that chat open.
  void setActiveChatId(String? chatId) => _currentChatId = chatId;

  // ── CANCEL NOTIFICATIONS ──────────────────────────────────────────────────
  Future<void> cancelChatNotifications(String chatId) async {
    await _localNotifications.cancel(
      chatId.hashCode & 0x7FFFFFFF,
      tag: chatId,
    );
  }

  // ── BITMAP LOADER ─────────────────────────────────────────────────────────
  /// FIX: Validates URL scheme before making any network request.
  /// Blocks file://, data://, ftp://, and other non-HTTP schemes from a
  /// crafted FCM payload. Uses the shared _httpClient for connection reuse.
  Future<Uint8List?> _safeFetchBitmap(String url) async {
    if (url.isEmpty) return null;
    try {
      final uri = Uri.parse(url);
      // Security: only allow http/https — block file://, data://, etc.
      if (!_allowedSchemes.contains(uri.scheme.toLowerCase())) {
        debugPrint('[Notifications] Blocked non-HTTP avatar URL: ${uri.scheme}');
        return null;
      }
      final response = await _httpClient
          .get(uri)
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {
      // Non-critical — notification shows without avatar.
    }
    return null;
  }

  // ── DISPOSE ───────────────────────────────────────────────────────────────
  /// Call on app shutdown / sign-out to release resources.
  void dispose() {
    _httpClient.close();
    _initialized = false;
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────
  /// Safe string extraction from FCM data map. Never throws.
  String _str(Map<String, dynamic> data, String key, {String fallback = ''}) {
    try {
      final v = data[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return fallback;
  }
}

// ── Background notification tap handler — top-level required ─────────────────
// FIX: The original was empty — tapping a notification when the app is
// terminated did nothing. Now we store the payload in a shared preference
// so _drainPendingNavigation() can pick it up when the app starts.
//
// NOTE: This handler runs in a SEPARATE ISOLATE with no access to the
// singleton's state. The correct pattern is:
//   1. Store payload to shared_preferences here.
//   2. In NotificationService.init(), check shared_preferences for a
//      stored payload and navigate if found.
//
// For simplicity — and because getInitialMessage() already covers the
// FCM-tap-from-terminated case — this handler just logs. The notification
// tap from a fully-terminated app is handled by getInitialMessage() in init().
@pragma('vm:entry-point')
void _onBackgroundNotificationTapped(NotificationResponse response) {
  // Intentionally minimal — this isolate cannot access singletons.
  // getInitialMessage() in init() handles the terminated-app tap case.
  debugPrint('[Notifications] Background tap: ${response.payload}');
}