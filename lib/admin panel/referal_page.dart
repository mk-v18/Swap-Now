import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────
//  Responsive helper
//  Breakpoints: small <360 | mobile 360–599 | tablet 600–899 | desktop ≥900
// ─────────────────────────────────────────────────────────
class _R {
  final double w;
  const _R(this.w);

  bool get isSmall   => w < 360;
  bool get isTablet  => w >= 600 && w < 900;
  bool get isDesktop => w >= 900;
  bool get useGrid   => isTablet || isDesktop;

  double get maxContent  => isDesktop ? 700 : double.infinity;
  double get hPad        => isDesktop ? 0 : (isTablet ? 36 : (isSmall ? 14 : 20));
  double get vPad        => (isTablet || isDesktop) ? 24 : 14;
  double get titleSize   => isDesktop ? 24 : (isTablet ? 22 : (isSmall ? 17 : 20));
  double get labelSize   => (isTablet || isDesktop) ? 15 : (isSmall ? 12 : 14);
  double get fieldPadV   => (isTablet || isDesktop) ? 16 : (isSmall ? 11 : 14);
  double get fieldPadH   => (isTablet || isDesktop) ? 16 : (isSmall ? 12 : 14);
  double get btnHeight   => isDesktop ? 62 : (isTablet ? 58 : (isSmall ? 50 : 54));
  double get btnFontSize => (isTablet || isDesktop) ? 16 : (isSmall ? 14 : 15);
  double get cardPad     => (isTablet || isDesktop) ? 18 : (isSmall ? 12 : 14);
  double get cardRadius  => (isTablet || isDesktop) ? 20 : 16;
  double get secTitle    => isDesktop ? 20 : (isTablet ? 18 : (isSmall ? 15 : 17));
  double get gap         => (isTablet || isDesktop) ? 18 : (isSmall ? 10 : 14);
}

// ─────────────────────────────────────────────────────────
//  Page
// ─────────────────────────────────────────────────────────
class AdminReferralPage extends StatefulWidget {
  const AdminReferralPage({super.key});

  @override
  State<AdminReferralPage> createState() => _AdminReferralPageState();
}

class _AdminReferralPageState extends State<AdminReferralPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  DateTime? _expiryDate;
  bool _isCreating = false;

  // Cached stream — never recreated on rebuild
  final Stream<QuerySnapshot> _referralsStream = FirebaseFirestore.instance
      .collection('referrals')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots(includeMetadataChanges: false);

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {required bool isError}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w500)),
          ),
        ]),
        backgroundColor:
        isError ? const Color(0xFFB00020) : const Color(0xFF1B8A4C),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: Duration(seconds: isError ? 3 : 2),
      ));
  }

  String _fmt(DateTime d) =>
      "${d.day.toString().padLeft(2, '0')}-"
          "${d.month.toString().padLeft(2, '0')}-"
          "${d.year}";

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF5800B3),
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Future<void> _createReferral() async {
    final name = _nameController.text.trim();
    final code = _codeController.text.trim().toUpperCase();

    if (name.isEmpty || code.isEmpty || _expiryDate == null) {
      _showSnack("Please fill all fields", isError: true);
      return;
    }

    setState(() => _isCreating = true);
    try {
      final docRef =
      FirebaseFirestore.instance.collection('referrals').doc(code);
      final doc =
      await docRef.get(const GetOptions(source: Source.serverAndCache));
      if (doc.exists) {
        _showSnack("Referral code already exists", isError: true);
        return;
      }
      await docRef.set({
        'name': name,
        'code': code,
        'joinedUsers': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'activeUntil': Timestamp.fromDate(_expiryDate!),
        'active': true,
      });
      _showSnack("Referral code created successfully!", isError: false);
      _nameController.clear();
      _codeController.clear();
      setState(() => _expiryDate = null);
    } catch (_) {
      _showSnack("Error creating referral code", isError: true);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  // ─────────────────────────────────────────────────────────
  //  Build
  //  Layout: everything in one CustomScrollView so the whole
  //  page scrolls — form + section header + referral cards.
  //  No Expanded / Column overflow possible.
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final r = _R(MediaQuery.of(context).size.width);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          "Add Referral",
          style: TextStyle(
            color: const Color(0xFF1A1A2E),
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFF0ECFF)),
        ),
      ),
      body: Center(
        child: SizedBox(
          width: r.maxContent,
          // StreamBuilder lives outside scroll so we can use a
          // SliverList for the referral cards.
          child: StreamBuilder<QuerySnapshot>(
            stream: _referralsStream,
            builder: (context, snapshot) {
              // Build referral sliver content
              Widget referralSliver;

              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                referralSliver = const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(
                          color: Color(0xFF5800B3)),
                    ),
                  ),
                );
              } else if (snapshot.hasError) {
                referralSliver = SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: _EmptyState(
                      icon: Icons.wifi_off_rounded,
                      label: "Failed to load referrals",
                      sub: "Check your connection and try again",
                      r: r,
                    ),
                  ),
                );
              } else {
                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  referralSliver = SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: _EmptyState(
                        icon: Icons.card_giftcard_rounded,
                        label: "No referrals yet",
                        sub: "Create your first referral code above",
                        r: r,
                      ),
                    ),
                  );
                } else if (r.useGrid) {
                  // Tablet / Desktop: 2-column grid
                  referralSliver = SliverPadding(
                    padding: EdgeInsets.only(bottom: r.vPad),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                            (_, i) => _cardFromDoc(docs[i], r),
                        childCount: docs.length,
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                      ),
                      gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 2.7,
                      ),
                    ),
                  );
                } else {
                  // Mobile: single column
                  referralSliver = SliverPadding(
                    padding: EdgeInsets.only(bottom: r.vPad),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                            (_, i) => _cardFromDoc(docs[i], r),
                        childCount: docs.length,
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                      ),
                    ),
                  );
                }
              }

              return CustomScrollView(
                keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  // ── Form (no card/box — flat layout) ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                          r.hPad, r.vPad, r.hPad, 0),
                      child: _buildForm(r),
                    ),
                  ),

                  // ── Section header ─────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                          r.hPad, r.gap * 1.8, r.hPad, r.gap * 0.8),
                      child: Row(children: [
                        Container(
                          width: 4,
                          height: 20,
                          decoration: BoxDecoration(
                            color: const Color(0xFF5800B3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Referrals",
                          style: TextStyle(
                            fontSize: r.secTitle,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A1A2E),
                            letterSpacing: -0.2,
                          ),
                        ),
                      ]),
                    ),
                  ),

                  // ── Cards ─────────────────────────────
                  SliverPadding(
                    padding:
                    EdgeInsets.symmetric(horizontal: r.hPad),
                    sliver: referralSliver is SliverPadding ||
                        referralSliver is SliverGrid ||
                        referralSliver is SliverList
                        ? referralSliver
                    // wrap fill-remaining slivers so they
                    // still sit under the correct padding
                        : SliverToBoxAdapter(child: const SizedBox()),
                  ),

                  // Handle fill-remaining outside the padding sliver
                  if (referralSliver is SliverFillRemaining)
                    referralSliver,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Flat form (no wrapping box) ────────────────────────────
  Widget _buildForm(_R r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // On tablet/desktop: name & code side by side
        if (r.isTablet || r.isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _nameField(r)),
              SizedBox(width: r.gap),
              Expanded(child: _codeField(r)),
            ],
          )
        else ...[
          _nameField(r),
          SizedBox(height: r.gap),
          _codeField(r),
        ],

        SizedBox(height: r.gap),

        // Expiry date
        _FieldLabel("Expiry Date", fontSize: r.labelSize),
        GestureDetector(
          onTap: _pickDate,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: double.infinity,
            padding: EdgeInsets.symmetric(
                horizontal: r.fieldPadH, vertical: r.fieldPadV),
            decoration: BoxDecoration(
              border: Border.all(
                color: _expiryDate != null
                    ? const Color(0xFF5800B3)
                    : const Color(0xFFDDD8FF),
                width: _expiryDate != null ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Icon(
                Icons.calendar_today_rounded,
                size: r.labelSize + 2,
                color: _expiryDate != null
                    ? const Color(0xFF5800B3)
                    : const Color(0xFFBDBDBD),
              ),
              SizedBox(width: r.fieldPadH * 0.6),
              Expanded(
                child: Text(
                  _expiryDate == null
                      ? "Select expiry date"
                      : _fmt(_expiryDate!),
                  style: TextStyle(
                    fontSize: r.labelSize,
                    color: _expiryDate == null
                        ? const Color(0xFFBDBDBD)
                        : const Color(0xFF1A1A2E),
                    fontWeight: _expiryDate != null
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
              Text(
                _expiryDate == null ? "Pick Date" : "Change",
                style: TextStyle(
                  color: const Color(0xFF5800B3),
                  fontWeight: FontWeight.w600,
                  fontSize: r.labelSize - 1,
                ),
              ),
            ]),
          ),
        ),

        SizedBox(height: r.gap * 1.4),

        // Submit button
        SizedBox(
          width: double.infinity,
          height: r.btnHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF5800B3), Color(0xFF26004D)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ElevatedButton(
              onPressed: _isCreating ? null : _createReferral,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _isCreating
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 1.8),
              )
                  : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_circle_outline,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "Create Referral",
                    style: TextStyle(
                      fontSize: r.btnFontSize,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _nameField(_R r) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      _FieldLabel("Referral Name", fontSize: r.labelSize),
      _InputField(
        controller: _nameController,
        hintText: "e.g. Summer Campaign",
        padV: r.fieldPadV,
        padH: r.fieldPadH,
        fontSize: r.labelSize,
        prefixIcon: Icons.person_outline_rounded,
      ),
    ],
  );

  Widget _codeField(_R r) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      _FieldLabel("Referral Code", fontSize: r.labelSize),
      _InputField(
        controller: _codeController,
        hintText: "e.g. MARK50",
        padV: r.fieldPadV,
        padH: r.fieldPadH,
        fontSize: r.labelSize,
        prefixIcon: Icons.code_rounded,
        textCapitalization: TextCapitalization.characters,
      ),
    ],
  );

  // Build a referral card from a Firestore doc snapshot
  Widget _cardFromDoc(QueryDocumentSnapshot doc, _R r) {
    final data = doc.data() as Map<String, dynamic>;
    final au = (data['activeUntil'] as Timestamp).toDate().toLocal();
    final dateStr =
        "${au.year}-${au.month.toString().padLeft(2, '0')}-${au.day.toString().padLeft(2, '0')}";
    return _ReferralCard(
      name: data['name'] ?? '',
      code: data['code'] ?? '',
      activeUntil: dateStr,
      joinedUsers: data['joinedUsers'] ?? 0,
      padding: r.cardPad,
      radius: r.cardRadius,
      fontSize: r.labelSize,
    );
  }
}

// ─────────────────────────────────────────────────────────
//  Field label
// ─────────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String text;
  final double fontSize;
  const _FieldLabel(this.text, {this.fontSize = 14});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: fontSize,
        color: const Color(0xFF1A1A2E),
        letterSpacing: 0.1,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────
//  Styled text field with animated focus border
// ─────────────────────────────────────────────────────────
class _InputField extends StatefulWidget {
  final TextEditingController controller;
  final String? hintText;
  final double padV;
  final double padH;
  final double fontSize;
  final IconData? prefixIcon;
  final TextCapitalization textCapitalization;

  const _InputField({
    required this.controller,
    this.hintText,
    this.padV = 14,
    this.padH = 14,
    this.fontSize = 14,
    this.prefixIcon,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  State<_InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<_InputField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          border: Border.all(
            color: _focused
                ? const Color(0xFF5800B3)
                : const Color(0xFFDDD8FF),
            width: _focused ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: TextField(
          controller: widget.controller,
          textCapitalization: widget.textCapitalization,
          style: TextStyle(
            fontSize: widget.fontSize,
            color: const Color(0xFF1A1A2E),
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: const TextStyle(color: Color(0xFFBDBDBD)),
            prefixIcon: widget.prefixIcon != null
                ? Icon(widget.prefixIcon,
                size: 18, color: const Color(0xFF9966FF))
                : null,
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(
                horizontal: widget.padH, vertical: widget.padV),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  Empty / error state
// ─────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final _R r;
  const _EmptyState(
      {required this.icon,
        required this.label,
        required this.sub,
        required this.r});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFFF0EBFF),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: const Color(0xFF5800B3), size: 30),
        ),
        const SizedBox(height: 14),
        Text(label,
            style: TextStyle(
                fontSize: r.labelSize + 2,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A2E))),
        const SizedBox(height: 6),
        Text(sub,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: r.labelSize - 1,
                color: const Color(0xFF888888))),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────
//  Referral card
// ─────────────────────────────────────────────────────────
class _ReferralCard extends StatelessWidget {
  final String name;
  final String code;
  final String activeUntil;
  final int joinedUsers;
  final double padding;
  final double radius;
  final double fontSize;

  const _ReferralCard({
    required this.name,
    required this.code,
    required this.activeUntil,
    required this.joinedUsers,
    required this.padding,
    required this.radius,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Gradient icon avatar
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF5800B3),Color(0xFF26004D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.card_giftcard_rounded,
                color: Colors.white, size: 20),
          ),

          const SizedBox(width: 12),

          // Name + code chip
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: fontSize + 1,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A2E),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0EBFF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    code,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: fontSize - 1,
                      color: const Color(0xFF5800B3),
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Stats
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.calendar_month_rounded,
                    size: fontSize - 1, color: const Color(0xFF888888)),
                const SizedBox(width: 3),
                Text(
                  activeUntil,
                  style: TextStyle(
                      fontSize: fontSize - 1,
                      color: const Color(0xFF555555)),
                ),
              ]),
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.people_alt_outlined,
                    size: fontSize - 1, color: const Color(0xFF5800B3)),
                const SizedBox(width: 3),
                Text(
                  "$joinedUsers joined",
                  style: TextStyle(
                    fontSize: fontSize - 1,
                    color: const Color(0xFF5800B3),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
            ],
          ),
        ],
      ),
    );
  }
}