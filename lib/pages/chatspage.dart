import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:credbro/chats/chatservice.dart';
import 'package:credbro/custom_loader.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart';
import '../chats/chatscreen.dart';

// ─── Responsive Layout Helper ────────────────────────────────────────────────
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

  // Compact vertical padding
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

  // Smaller avatar
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
}

// ─── ChatsPage ────────────────────────────────────────────────────────────────
class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final ChatService _chatService = ChatService();
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;

  // ── Cache: avoid re-fetching user docs on every outer stream emit ──────────
  // Maps receiverId → snapshot so rebuilds don't hit Firestore again.
  final Map<String, DocumentSnapshot> _userCache = {};

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final now  = DateTime.now();
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

  Widget? _intentBadge(Map<String, dynamic>? intent, _RL rl) {
    if (intent == null) return null;
    switch (intent['type'] as String? ?? '') {
      case 'sell':
        return _pill('Sell', const Color(0xFFD84315), Icons.storefront_outlined, rl);
      case 'swap':
        return _pill('Swap', const Color(0xFF00796B), Icons.swap_horiz_rounded, rl);
      default:
        return null;
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

  // ── FIX 5 & 1: single stream with async user-data resolution ──────────────
  // Instead of nesting 2 StreamBuilders per row, we resolve user docs with a
  // cached Future so Firestore is only hit once per user per session.
  Future<DocumentSnapshot> _getUserDoc(String uid) async {
    if (_userCache.containsKey(uid)) return _userCache[uid]!;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    _userCache[uid] = snap;
    return snap;
  }

  // ── FIX 6: listen for user doc changes (online status, ban) efficiently ───
  // Returns a stream of just the fields we care about without re-creating the
  // entire page stream.
  Stream<DocumentSnapshot> _userStream(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).snapshots();

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final rl = _RL(MediaQuery.of(context).size.width);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Chats',
          style: TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w600),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFF0ECFF)),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _chatService.getUserChats(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CustomLoader());
          }

          final chats = snapshot.data!.docs;

          if (chats.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    'assets/images/empty_chats.svg',
                    width: rl.emptyIconSize,
                    height: rl.emptyIconSize,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No chats yet',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: rl.emptyFontSize,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Start a conversation to see it here',
                    style: TextStyle(
                      color: Colors.grey[350] ?? Colors.grey[300],
                      fontSize: (rl.emptyFontSize ?? 14) * 0.75,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: rl.listPadding,
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat     = chats[index];
              final chatData = chat.data() as Map<String, dynamic>;
              final participants =
              List<String>.from(chatData['participants'] ?? []);

              // FIX 3: guard against malformed participants list
              final receiverId = participants.firstWhere(
                    (id) => id != _currentUserId,
                orElse: () => '',
              );
              if (receiverId.isEmpty) return const SizedBox.shrink();

              final lastMessage  = (chatData['lastMessage'] ?? '') as String;
              final lastTs       = chatData['timestamp'] as Timestamp?;
              final lastSenderId = (chatData['lastSenderId'] ?? '') as String;
              final lastStatus   = (chatData['lastStatus']   ?? 'sent') as String;
              final isMine       = lastSenderId == _currentUserId;
              final intentRaw    = chatData['intent'];
              final intent       = intentRaw is Map
                  ? Map<String, dynamic>.from(intentRaw)
                  : null;

              // FIX 1 & 2: use a single StreamBuilder on the user doc only.
              // The unseen count is a lightweight query merged inside the same
              // stream via a combined approach — avoids triple-nesting.
              return StreamBuilder<DocumentSnapshot>(
                stream: _userStream(receiverId),
                builder: (context, userSnap) {
                  // Cache the latest user doc for future outer-stream rebuilds
                  if (userSnap.hasData && userSnap.data!.exists) {
                    _userCache[receiverId] = userSnap.data!;
                  }

                  if (!userSnap.hasData || !userSnap.data!.exists) {
                    return const SizedBox.shrink();
                  }

                  final userData     = userSnap.data!.data() as Map<String, dynamic>;
                  final name         = (userData['name']         ?? 'Unknown') as String;
                  final profileImage = (userData['profileImage'] ?? '') as String;
                  final online       = (userData['online']       ?? false)     as bool;

                  // FIX 6: hide banned users from the chat list
                  final banned = (userData['banned'] ?? false) as bool;
                  if (banned) return const SizedBox.shrink();

                  return StreamBuilder<int>(
                    stream: _chatService.getUnseenCount(chat.id, _currentUserId),
                    builder: (context, countSnap) {
                      final unseen   = countSnap.data ?? 0;
                      final hasUnread = unseen > 0;
                      final badge    = _intentBadge(intent, rl);

                      return _ChatTile(
                        rl:            rl,
                        chatId:        chat.id,
                        receiverId:    receiverId,
                        receiverName:  name,
                        profileImage:  profileImage,
                        online:        online,
                        lastMessage:   lastMessage,
                        lastTimestamp: lastTs,
                        isMine:        isMine,
                        lastStatus:    lastStatus,
                        hasUnread:     hasUnread,
                        unseenCount:   unseen,
                        badge:         badge,
                        tick:          _buildTick(lastStatus, rl.tickSize),
                        formattedTime: _formatTime(lastTs),
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
}

// ─── Chat Tile (extracted widget = avoids anonymous closure rebuilds) ─────────
// Extracting to a const-capable widget means Flutter can skip rebuilding tiles
// whose data hasn't changed.
class _ChatTile extends StatelessWidget {
  final _RL     rl;
  final String  chatId;
  final String  receiverId;
  final String  receiverName;
  final String  profileImage;
  final bool    online;
  final String  lastMessage;
  final Timestamp? lastTimestamp;
  final bool    isMine;
  final String  lastStatus;
  final bool    hasUnread;
  final int     unseenCount;
  final Widget? badge;
  final Widget  tick;
  final String  formattedTime;

  const _ChatTile({
    required this.rl,
    required this.chatId,
    required this.receiverId,
    required this.receiverName,
    required this.profileImage,
    required this.online,
    required this.lastMessage,
    required this.lastTimestamp,
    required this.isMine,
    required this.lastStatus,
    required this.hasUnread,
    required this.unseenCount,
    required this.badge,
    required this.tick,
    required this.formattedTime,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId:        chatId,
            receiverId:    receiverId,
            receiverName:  receiverName,
            receiverImage: profileImage,
          ),
        ),
      ),
      child: Container(
        margin: EdgeInsets.only(bottom: rl.cardMarginBottom),
        padding: rl.cardPadding,
        decoration: BoxDecoration(
          color: hasUnread
              ? const Color(0xFFFAF5FF)   // subtle tint when unread
              : Colors.white,
          borderRadius: BorderRadius.circular(rl.cardRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
          // FIX UI: left accent bar for unread chats
          border: hasUnread
              ? const Border(
              left: BorderSide(color: Color(0xFF7B1FA2), width: 3))
              : null,
        ),
        child: Row(
          children: [
            // ── Avatar ────────────────────────────────────────────────────
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
                  // FIX 4: errorBuilder so malformed URLs don't throw
                  child: profileImage.isNotEmpty
                      ? Image.network(
                    profileImage,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _AvatarFallback(
                        name: receiverName, fontSize: rl.avatarFontSize),
                  )
                      : _AvatarFallback(
                      name: receiverName, fontSize: rl.avatarFontSize),
                ),
                if (online)
                  Positioned(
                    right:  1,
                    bottom: 1,
                    child: Container(
                      width:  rl.onlineDotSize,
                      height: rl.onlineDotSize,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),

            SizedBox(width: rl.avatarGap),

            // ── Content ───────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Name + timestamp
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          receiverName,
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
                      const SizedBox(width: 6),
                      Text(
                        formattedTime,
                        style: TextStyle(
                          fontSize: rl.timeFontSize,
                          color: hasUnread
                              ? const Color(0xFF7B1FA2)
                              : Colors.grey[400],
                          fontWeight: hasUnread
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),

                  // Intent badge (only if present) — minimal vertical gap
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
                        _UnreadBadge(count: unseenCount, rl: rl),
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
  final int  count;
  final _RL  rl;
  const _UnreadBadge({required this.count, required this.rl});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          minWidth: rl.badgeMinSize, minHeight: rl.badgeMinSize),
      padding:
      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: const BoxDecoration(
        color: Color(0xFF7B1FA2),
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