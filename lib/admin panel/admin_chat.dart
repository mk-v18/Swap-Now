import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:credbro/chats/chatservice.dart';
import 'package:credbro/custom_loader.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../chats/chatscreen.dart';

// ─── Responsive Layout Helper ────────────────────────────────────────────────
// Matches ChatsPage's _RL exactly (breakpoint-based, not fluid-clamp) so both
// screens share one visual language, plus a few admin-only getters appended
// at the end using the same breakpoint pattern.
class _RL {
  final double w;
  const _RL(this.w);

  bool get isMobile  => w < 600;
  bool get isTablet  => w >= 600 && w < 1024;
  bool get isDesktop => w >= 1024;

  EdgeInsets get listPadding {
    if (isDesktop) return EdgeInsets.symmetric(horizontal: w * 0.2, vertical: 12);
    if (isTablet)  return const EdgeInsets.symmetric(horizontal: 24, vertical: 10);
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
  }

  double get cardMarginBottom {
    if (isDesktop) return 10.0;
    if (isTablet)  return 8.0;
    return 6.0;
  }

  EdgeInsets get cardPadding {
    if (isDesktop) return const EdgeInsets.symmetric(horizontal: 16, vertical: 10);
    if (isTablet)  return const EdgeInsets.symmetric(horizontal: 14, vertical: 9);
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
  }

  double get cardRadius {
    if (isDesktop) return 16.0;
    if (isTablet)  return 14.0;
    return 12.0;
  }

  double get avatarSize {
    if (isDesktop) return 52.0;
    if (isTablet)  return 48.0;
    return 44.0;
  }

  double get avatarRadius {
    if (isDesktop) return 14.0;
    if (isTablet)  return 13.0;
    return 12.0;
  }

  double get avatarFontSize {
    if (isDesktop) return 20.0;
    if (isTablet)  return 18.0;
    return 17.0;
  }

  double get onlineDotSize {
    if (isDesktop) return 11.0;
    if (isTablet)  return 10.0;
    return 9.0;
  }

  double get avatarGap {
    if (isDesktop) return 14.0;
    if (isTablet)  return 12.0;
    return 10.0;
  }

  double get nameFontSize {
    if (isDesktop) return 15.0;
    if (isTablet)  return 14.5;
    return 14.0;
  }

  double get timeFontSize {
    if (isDesktop) return 12.0;
    if (isTablet)  return 11.5;
    return 11.0;
  }

  double get previewFontSize {
    if (isDesktop) return 13.0;
    if (isTablet)  return 12.5;
    return 12.0;
  }

  double get tickSize {
    if (isDesktop) return 15.0;
    if (isTablet)  return 14.0;
    return 13.0;
  }

  double get badgeFontSize {
    if (isDesktop) return 11.0;
    if (isTablet)  return 10.5;
    return 10.0;
  }

  double get badgeMinSize {
    if (isDesktop) return 20.0;
    if (isTablet)  return 19.0;
    return 18.0;
  }

  double get pillFontSize {
    if (isDesktop) return 10.0;
    if (isTablet)  return 9.5;
    return 9.0;
  }

  double get pillIconSize => pillFontSize;

  EdgeInsets get pillPadding {
    if (isDesktop) return const EdgeInsets.symmetric(horizontal: 7, vertical: 2);
    if (isTablet)  return const EdgeInsets.symmetric(horizontal: 6, vertical: 2);
    return const EdgeInsets.symmetric(horizontal: 5, vertical: 2);
  }

  double get emptyIconSize {
    if (isDesktop) return 72.0;
    if (isTablet)  return 64.0;
    return 56.0;
  }

  double get emptyFontSize {
    if (isDesktop) return 17.0;
    if (isTablet)  return 16.0;
    return 15.0;
  }

  // ── Admin-only additions (same breakpoint pattern as above) ───────────────
  double get emptySubFontSize {
    if (isDesktop) return 13.0;
    if (isTablet)  return 12.0;
    return 11.0;
  }

  double get badgeActionFontSize {
    if (isDesktop) return 12.5;
    if (isTablet)  return 11.5;
    return 10.5;
  }

  double get badgeActionIconSize {
    if (isDesktop) return 15.0;
    if (isTablet)  return 13.5;
    return 12.5;
  }
}

// ─── AdminChatPage ────────────────────────────────────────────────────────────
class AdminChatPage extends StatefulWidget {
  const AdminChatPage({super.key});

  @override
  State<AdminChatPage> createState() => _AdminChatPageState();
}

class _AdminChatPageState extends State<AdminChatPage> {
  final ChatService _chatService = ChatService();
  final String _adminId = FirebaseAuth.instance.currentUser!.uid;

  // Cache user docs so outer stream rebuilds don't re-subscribe.
  final Map<String, DocumentSnapshot> _userCache = {};

  // ── Design tokens — same purple accent family as ChatsPage ────────────────
  static const _purple      = Color(0xFF7B1FA2);
  static const _purpleTint  = Color(0xFFFAF5FF);
  static const _lightPurple = Color(0xFFEDE7F6);
  static const _green       = Color(0xFF4CAF50);
  static const _orange      = Color(0xFFD84315); // reserved for "Sell" intent pill
  static const _teal        = Color(0xFF00796B); // reserved for "Swap" intent pill

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final date  = ts.toDate();
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d     = DateTime(date.year, date.month, date.day);
    if (d == today) return DateFormat('h:mm a').format(date);
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    if (now.difference(date).inDays < 7) return DateFormat('EEEE').format(date);
    return DateFormat('d/M/yy').format(date);
  }

  Widget _buildTick(String status, double size) {
    switch (status) {
      case 'seen':
        return Icon(Icons.done_all, size: size, color: const Color(0xFF53BDEB));
      case 'delivered':
        return Icon(Icons.done_all, size: size, color: Colors.grey[400]);
      default:
        return Icon(Icons.done, size: size, color: Colors.grey[400]);
    }
  }

  Widget _pill(String label, Color color, IconData icon, _RL rl) {
    return Container(
      padding: rl.pillPadding,
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: rl.pillIconSize, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: rl.pillFontSize,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget? _intentBadge(Map<String, dynamic>? intent, _RL rl) {
    if (intent == null) return null;
    // Admin chat page only surfaces sell-to-company requests.
    if ((intent['type'] as String? ?? '') == 'sell') {
      return _pill('Sell to Company', _orange, Icons.storefront_outlined, rl);
    }
    return null;
  }

  // Navigate safely — markSeen errors don't block navigation.
  Future<void> _openChat(
      BuildContext ctx, {
        required String chatId,
        required String otherId,
        required String name,
        required String profileImage,
      }) async {
    _chatService.markAllMessagesAsSeenAdmin(chatId).catchError((e) {
      debugPrint('[AdminChat] markAllMessagesAsSeenAdmin error: $e');
    });

    if (!ctx.mounted) return;
    Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId:        chatId,
          receiverId:    otherId,
          receiverName:  name,
          receiverImage: profileImage,
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final rl = _RL(MediaQuery.of(context).size.width);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: _buildAppBar(rl),
      body: StreamBuilder<QuerySnapshot>(
        // Limit to 50 most recent chats — avoids loading ALL chats.
        stream: _chatService.getAllChats(limit: 50),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CustomLoader());
          }

          // Filter sell-intent chats BEFORE building list items so we never
          // open user/count streams for non-sell chats.
          final allChats = snapshot.data!.docs;
          final sellChats = allChats.where((chat) {
            final data      = chat.data() as Map<String, dynamic>;
            final intentRaw = data['intent'];
            final intent    = intentRaw is Map
                ? Map<String, dynamic>.from(intentRaw)
                : null;
            return (intent?['type'] as String? ?? '') == 'sell';
          }).toList();

          if (sellChats.isEmpty) return _buildEmpty(rl);

          return ListView.builder(
            padding:   rl.listPadding,
            itemCount: sellChats.length,
            itemBuilder: (context, index) {
              final chat     = sellChats[index];
              final chatData = chat.data() as Map<String, dynamic>;
              final participants =
              List<String>.from(chatData['participants'] ?? []);

              final otherId = participants.firstWhere(
                    (id) => id != _adminId,
                orElse: () =>
                participants.isNotEmpty ? participants.first : '',
              );
              if (otherId.isEmpty) return const SizedBox.shrink();

              final lastMessage  = (chatData['lastMessage']  ?? '') as String;
              final lastTs       = chatData['timestamp']     as Timestamp?;
              final lastSenderId = (chatData['lastSenderId'] ?? '') as String;
              final lastStatus   = (chatData['lastStatus']   ?? 'sent') as String;
              final isMine       = lastSenderId == _adminId;
              final intentRaw    = chatData['intent'];
              final intent       = intentRaw is Map
                  ? Map<String, dynamic>.from(intentRaw)
                  : null;

              // Single user-doc stream with cache update
              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(otherId)
                    .snapshots(),
                builder: (context, userSnap) {
                  if (userSnap.hasData && userSnap.data!.exists) {
                    _userCache[otherId] = userSnap.data!;
                  }
                  if (!userSnap.hasData || !userSnap.data!.exists) {
                    return const SizedBox.shrink();
                  }

                  final userData     = userSnap.data!.data() as Map<String, dynamic>;
                  final name         = (userData['name']         ?? 'Unknown') as String;
                  final profileImage = (userData['profileImage'] ?? '') as String;
                  final online       = (userData['online']       ?? false) as bool;
                  final banned       = (userData['banned']       ?? false) as bool;

                  return StreamBuilder<int>(
                    stream: _chatService.getUnseenCountAdmin(chat.id),
                    builder: (context, countSnap) {
                      final unseen    = countSnap.data ?? 0;
                      final hasUnread = unseen > 0;

                      return _AdminChatTile(
                        rl:            rl,
                        chatId:        chat.id,
                        otherId:       otherId,
                        name:          name,
                        profileImage:  profileImage,
                        online:        online,
                        banned:        banned,
                        lastMessage:   lastMessage,
                        lastTimestamp: lastTs,
                        lastStatus:    lastStatus,
                        isMine:        isMine,
                        intent:        intent,
                        unseen:        unseen,
                        hasUnread:     hasUnread,
                        badge:         _intentBadge(intent, rl),
                        tick:          _buildTick(lastStatus, rl.tickSize),
                        formattedTime: _formatTime(lastTs),
                        onTap:         () => _openChat(
                          context,
                          chatId:       chat.id,
                          otherId:      otherId,
                          name:         name,
                          profileImage: profileImage,
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // ── AppBar (same shape/typography as ChatsPage's) ──────────────────────────
  PreferredSizeWidget _buildAppBar(_RL rl) {
    return AppBar(
      scrolledUnderElevation: 0,
      backgroundColor:  Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      title: const Text(
        'Sell Chats',
        style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600),
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, thickness: 1, color: Color(0xFFF0ECFF)),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 14),
          padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _purple.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _purple.withOpacity(0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.admin_panel_settings,
                  size: rl.badgeActionIconSize, color: _purple),
              const SizedBox(width: 4),
              Text('Admin',
                  style: TextStyle(
                      fontSize: rl.badgeActionFontSize,
                      color: _purple,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Empty state (same iconography/tone as ChatsPage's) ─────────────────────
  Widget _buildEmpty(_RL rl) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: rl.emptyIconSize, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text('No sell chats yet',
              style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: rl.emptyFontSize)),
          const SizedBox(height: 4),
          Text('Sell-intent conversations will appear here',
              style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: rl.emptySubFontSize)),
        ],
      ),
    );
  }
}

// ─── Admin Chat Tile ──────────────────────────────────────────────────────────
// Structurally identical to ChatsPage's _ChatTile — purple unread accent,
// same avatar/text sizing — with the banned-user state layered on top as the
// one admin-specific visual (red tint/border overrides the purple unread
// treatment when a user is banned).
class _AdminChatTile extends StatelessWidget {
  final _RL            rl;
  final String         chatId;
  final String         otherId;
  final String         name;
  final String         profileImage;
  final bool           online;
  final bool           banned;
  final String         lastMessage;
  final Timestamp?     lastTimestamp;
  final String         lastStatus;
  final bool           isMine;
  final Map<String, dynamic>? intent;
  final int            unseen;
  final bool           hasUnread;
  final Widget?        badge;
  final Widget         tick;
  final String         formattedTime;
  final VoidCallback   onTap;

  static const _purple = Color(0xFF7B1FA2);
  static const _green  = Color(0xFF4CAF50);

  const _AdminChatTile({
    required this.rl,
    required this.chatId,
    required this.otherId,
    required this.name,
    required this.profileImage,
    required this.online,
    required this.banned,
    required this.lastMessage,
    required this.lastTimestamp,
    required this.lastStatus,
    required this.isMine,
    required this.intent,
    required this.unseen,
    required this.hasUnread,
    required this.badge,
    required this.tick,
    required this.formattedTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: rl.cardMarginBottom),
        padding: rl.cardPadding,
        decoration: BoxDecoration(
          color: banned
              ? const Color(0xFFFFF0F0)   // red tint for banned users
              : hasUnread
              ? const Color(0xFFFAF5FF)   // purple tint, matches ChatsPage
              : Colors.white,
          borderRadius: BorderRadius.circular(rl.cardRadius),
          border: banned
              ? Border.all(color: Colors.red.withOpacity(0.2), width: 1)
              : hasUnread
              ? const Border(
              left: BorderSide(color: _purple, width: 3))
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Avatar ──────────────────────────────────────────────────
            Stack(
              children: [
                Container(
                  width:  rl.avatarSize,
                  height: rl.avatarSize,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE7F6),
                    borderRadius: BorderRadius.circular(rl.avatarRadius),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: profileImage.isNotEmpty
                      ? Image.network(
                    profileImage,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _AvatarFallback(name: name, fontSize: rl.avatarFontSize),
                  )
                      : _AvatarFallback(name: name, fontSize: rl.avatarFontSize),
                ),
                if (online)
                  Positioned(
                    right:  1,
                    bottom: 1,
                    child: Container(
                      width:  rl.onlineDotSize,
                      height: rl.onlineDotSize,
                      decoration: BoxDecoration(
                        color: _green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                // Banned indicator on avatar — admin-only state
                if (banned)
                  Positioned(
                    right:  0,
                    top:    0,
                    child: Container(
                      width:  rl.onlineDotSize + 2,
                      height: rl.onlineDotSize + 2,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.block,
                          color: Colors.white, size: 7),
                    ),
                  ),
              ],
            ),

            SizedBox(width: rl.avatarGap),

            // ── Content ────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Name + time row
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize:   rl.nameFontSize,
                                  fontWeight: hasUnread
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            if (banned) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: Colors.red.withOpacity(0.3)),
                                ),
                                child: const Text(
                                  'Banned',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.red,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        formattedTime,
                        style: TextStyle(
                          fontSize: rl.timeFontSize,
                          color: hasUnread
                              ? _purple
                              : Colors.grey[400],
                          fontWeight: hasUnread
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),

                  // Intent badge
                  if (badge != null) ...[
                    const SizedBox(height: 3),
                    badge!,
                  ],

                  const SizedBox(height: 3),

                  // Tick + preview + unread badge
                  Row(
                    children: [
                      if (isMine) ...[
                        tick,
                        const SizedBox(width: 3),
                      ],
                      Expanded(
                        child: Text(
                          lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: rl.previewFontSize,
                            color: hasUnread
                                ? Colors.black54
                                : Colors.grey[400],
                            fontWeight: hasUnread
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 6),
                        _UnreadBadge(count: unseen, rl: rl),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Avatar fallback ──────────────────────────────────────────────────────────
class _AvatarFallback extends StatelessWidget {
  final String name;
  final double fontSize;
  const _AvatarFallback({required this.name, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
            fontSize:   fontSize,
            fontWeight: FontWeight.bold,
            color:      const Color(0xFF7B1FA2)),
      ),
    );
  }
}

// ─── Unread badge ─────────────────────────────────────────────────────────────
class _UnreadBadge extends StatelessWidget {
  final int count;
  final _RL rl;
  const _UnreadBadge({required this.count, required this.rl});

  static const _purple = Color(0xFF7B1FA2);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
      BoxConstraints(minWidth: rl.badgeMinSize, minHeight: rl.badgeMinSize),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: const BoxDecoration(
        color: _purple,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        textAlign: TextAlign.center,
        style: TextStyle(
            color:      Colors.white,
            fontSize:   rl.badgeFontSize,
            fontWeight: FontWeight.w700),
      ),
    );
  }
}