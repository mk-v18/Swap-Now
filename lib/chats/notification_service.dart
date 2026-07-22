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

  bool _initialized = false;

  // Active chat suppression — set from ChatScreen via setActiveChatId().
  String? _currentChatId;

  // Reusable HTTP client for avatar bitmap loads. Closed in dispose().
  final _httpClient = http.Client();

  // Pending cold-start navigation — stores the initial message's data payload
  // (as JSON) when getInitialMessage() fires before the widget tree is ready.
  // Drained by _drainPendingNavigation() once the navigator is available.
  String? _pendingNavigationPayload;

  static const _chatChannelId   = 'chat_messages';
  static const _chatChannelName = 'Chat Messages';

  // NEW: separate channel for swap-request / accept / decline / exchange
  // notifications so they don't get grouped visually with chat messages,
  // and so background/terminated-state deliveries (which use the
  // channelId set server-side in the FCM payload) land correctly too.
  static const _swapChannelId   = 'swap_updates';
  static const _swapChannelName = 'Swap Updates';

  // NEW: the full set of "type" values the swap/exchange Cloud Functions
  // send. Anything in this set is routed differently from chat messages —
  // no chatId/senderName/senderPhoto shape, and title/body come from the
  // FCM `notification` block rather than `data`.
  static const _swapNotificationTypes = {
    'swap_request',
    'swap_accepted',
    'swap_declined',
    'exchange_completed',
    'exchange_cancelled',
  };

  static const _allowedSchemes = {'https', 'http'};

  bool _isSwapType(String type) => _swapNotificationTypes.contains(type);

  // ── INIT ──────────────────────────────────────────────────────────────────
  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    if (_initialized) return;
    _initialized = true;
    _navigatorKey = navigatorKey;

    await _messaging.requestPermission(
      alert:       true,
      badge:       true,
      sound:       true,
      provisional: false,
    );

    const androidSettings = AndroidInitializationSettings('ic_notification');
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

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
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

    // NEW: swap/exchange channel.
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _swapChannelId,
        _swapChannelName,
        description:      'Swap request, accept/decline, and exchange notifications',
        importance:       Importance.max,
        playSound:        true,
        enableVibration:  true,
        showBadge:        true,
      ),
    );

    await _saveToken();
    _messaging.onTokenRefresh.listen(_updateToken);

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);

    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      _pendingNavigationPayload = jsonEncode(initial.data);
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
    } catch (e) {
      debugPrint('[Notifications] Token save failed: $e');
    }
  }

  Future<void> _updateToken(String token) => _saveToken(token);

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
      _initialized = false;
    } catch (e) {
      debugPrint('[Notifications] Token clear failed: $e');
    }
  }

  // ── FOREGROUND HANDLER ────────────────────────────────────────────────────
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final type = _str(data, 'type', fallback: 'text');

    // NEW: swap/exchange notifications take a completely different shape
    // (no chatId/senderName — title/body live in message.notification),
    // so branch them off before touching any of the chat-specific fields.
    if (_isSwapType(type)) {
      await _handleSwapForegroundMessage(message, type);
      return;
    }

    final chatId      = _str(data, 'chatId');
    final senderName  = _str(data, 'senderName',  fallback: 'Someone');
    final senderPhoto = _str(data, 'senderPhoto');
    final body        = _str(data, 'body',         fallback: 'New message');

    if (chatId.isEmpty) return;
    if (_currentChatId == chatId) return;

    final largeIcon = await _safeFetchBitmap(senderPhoto);

    await _showLocalNotification(
      chatId:      chatId,
      senderName:  senderName,
      senderPhoto: senderPhoto,
      body:        body,
      payload:     jsonEncode(data),
      largeIcon:   largeIcon,
    );
  }

  // NEW: shows the local notification for swap_request / swap_accepted /
  // swap_declined / exchange_completed / exchange_cancelled. Title/body come
  // from the FCM `notification` block the Cloud Function already set — we
  // only fall back to a generic title if that's somehow missing (e.g. a
  // data-only test message).
  Future<void> _handleSwapForegroundMessage(RemoteMessage message, String type) async {
    final title = message.notification?.title ?? _swapTitleFor(type);
    final body  = message.notification?.body  ?? '';
    final payload = jsonEncode(message.data);
    final notifId = _swapNotifId(message.data, type);

    final androidDetails = AndroidNotificationDetails(
      _swapChannelId,
      _swapChannelName,
      channelDescription: 'Swap request, accept/decline, and exchange notifications',
      importance:         Importance.max,
      priority:           Priority.high,
      styleInformation:   BigTextStyleInformation(body),
      color:              const Color(0xFF6A1B9A),
      icon:               'ic_notification',
      playSound:          true,
      enableVibration:    true,
      when:               DateTime.now().millisecondsSinceEpoch,
      showWhen:           true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert:     true,
      presentBadge:     true,
      presentSound:     true,
      threadIdentifier: 'swap',
    );

    await _localNotifications.show(
      notifId,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  String _swapTitleFor(String type) {
    switch (type) {
      case 'swap_request':        return 'New swap request';
      case 'swap_accepted':       return 'Request accepted';
      case 'swap_declined':       return 'Request declined';
      case 'exchange_completed':  return 'Exchange completed';
      case 'exchange_cancelled':  return 'Swap cancelled';
      default:                    return 'Amoeba';
    }
  }

  // Stable notif id namespaced by type+id so it can never collide with a
  // chat notification's chatId-based id, and so e.g. a "declined" and a
  // later "accepted" push for the same request don't stomp each other.
  int _swapNotifId(Map<String, dynamic> data, String type) {
    final id = _str(data, 'requestId').isNotEmpty
        ? _str(data, 'requestId')
        : _str(data, 'historyId');
    return 'swap_${type}_$id'.hashCode & 0x7FFFFFFF;
  }

  // ── SHOW LOCAL NOTIFICATION (chat) ───────────────────────────────────────
  Future<void> _showLocalNotification({
    required String    chatId,
    required String    senderName,
    required String    senderPhoto,
    required String    body,
    required String    payload,
    Uint8List?         largeIcon,
  }) async {
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

  // ── NOTIFICATION TAP ───────────────────────────────────────────────────────
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    final actionId = response.actionId;

    // Reply / mark-read actions only ever exist on chat notifications
    // (swap notifications don't add these actions), so it's safe to check
    // these first regardless of type.
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

    Map<String, dynamic> data;
    try {
      data = jsonDecode(payload) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[Notifications] Tap payload parse error: $e');
      return;
    }

    _routeNotification(data);
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
      final receiverId = _str(data, 'senderId');

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
          'encrypted' : false,
        }),
        chatRef.update({
          'lastMessage' : replyText,
          'lastSenderId': uid,
          'lastStatus'  : 'sent',
          'timestamp'   : FieldValue.serverTimestamp(),
        }),
      ]);

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
    _routeNotification(message.data);
  }

  void _drainPendingNavigation() {
    final payload = _pendingNavigationPayload;
    if (payload == null) return;
    _pendingNavigationPayload = null;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      _routeNotification(data);
    } catch (e) {
      debugPrint('[Notifications] Drain navigation parse error: $e');
    }
  }

  // NEW: single entry point that decides where a payload should navigate —
  // a chat screen for ordinary messages, or the requests/history pages for
  // swap and exchange updates.
  void _routeNotification(Map<String, dynamic> data) {
    final type = _str(data, 'type', fallback: 'text');
    if (_isSwapType(type)) {
      _navigateForSwap(type, data);
    } else {
      _navigateToChat(data);
    }
  }

  /// Navigate to /chat. Safe to call at any time — guards against null navigator.
  void _navigateToChat(Map<String, dynamic> data) {
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
      _pendingNavigationPayload = jsonEncode(data);
      WidgetsBinding.instance.addPostFrameCallback((_) => _drainPendingNavigation());
      return;
    }

    nav.pushNamed('/chat', arguments: {
      'chatId'       : chatId,
      'receiverId'   : senderId,
      'receiverName' : senderName,
      'receiverImage': senderPhoto,
    });
  }

  // NEW: routes each swap/exchange type to the right screen+tab. We don't
  // have a receiverId/receiverName/receiverImage in these payloads (only
  // chatId on the 'accepted' case), so rather than opening ChatScreen with
  // incomplete data, we land on the Requests page's matching tab — the
  // user can tap into the chat from there.
  void _navigateForSwap(String type, Map<String, dynamic> data) {
    final nav = _navigatorKey?.currentState;
    if (nav == null) {
      _pendingNavigationPayload = jsonEncode(data);
      WidgetsBinding.instance.addPostFrameCallback((_) => _drainPendingNavigation());
      return;
    }

    switch (type) {
      case 'swap_request':
        nav.pushNamed('/swap-requests', arguments: {'tab': 0}); // Incoming
        break;
      case 'swap_accepted':
        nav.pushNamed('/swap-requests', arguments: {'tab': 1}); // Active
        break;
      case 'swap_declined':
        nav.pushNamed('/swap-requests', arguments: {'tab': 2}); // Sent
        break;
      case 'exchange_completed':
      case 'exchange_cancelled':
        nav.pushNamed('/exchange-history');
        break;
      default:
        debugPrint('[Notifications] Unknown swap notification type: $type');
    }
  }

  // ── ACTIVE CHAT MANAGEMENT ────────────────────────────────────────────────
  void setActiveChatId(String? chatId) => _currentChatId = chatId;

  // ── CANCEL NOTIFICATIONS ──────────────────────────────────────────────────
  Future<void> cancelChatNotifications(String chatId) async {
    await _localNotifications.cancel(
      chatId.hashCode & 0x7FFFFFFF,
      tag: chatId,
    );
  }

  // ── BITMAP LOADER ─────────────────────────────────────────────────────────
  Future<Uint8List?> _safeFetchBitmap(String url) async {
    if (url.isEmpty) return null;
    try {
      final uri = Uri.parse(url);
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
  void dispose() {
    _httpClient.close();
    _initialized = false;
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────
  String _str(Map<String, dynamic> data, String key, {String fallback = ''}) {
    try {
      final v = data[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return fallback;
  }
}

@pragma('vm:entry-point')
void _onBackgroundNotificationTapped(NotificationResponse response) {
  debugPrint('[Notifications] Background tap: ${response.payload}');
}