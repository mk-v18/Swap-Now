import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// AES-256 CBC symmetric encryption with per-message random IV.
///
/// Security model (v2):
///  - The AES key is NO LONGER hardcoded in source. It is fetched once from
///    a Cloud Function (`getChatEncryptionKey`) that returns the shared
///    secret, then cached in flutter_secure_storage (Keychain / Keystore-
///    backed EncryptedSharedPreferences) so every device reads the SAME key
///    without it ever appearing in the compiled APK.
///  - Random 16-byte IV generated per message → same plaintext produces
///    different ciphertexts (semantic security).
///  - IV is prepended to the ciphertext before base64 encoding and stripped
///    on decryption, so no extra Firestore fields are needed.
///  - Falls back gracefully for old messages that were stored without
///    encryption (plain-text stored directly).
///
/// ⚠️ This is still a single shared secret for all chats — it removes the
///    "key extractable from decompiled APK" problem, but NOT the "anyone
///    with valid app credentials can call the Cloud Function and get the
///    key" problem. For true per-chat confidentiality, migrate to a
///    per-chat key derived via X25519/ECDH (server never sees plaintext,
///    server never sees the key either). Treat that as the next hardening
///    step post-launch.
class EncryptionService {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  static const _storage = FlutterSecureStorage();
  static const _keyStorageKey = 'chat_aes_key_v2';

  enc.Encrypter? _encrypter;
  enc.Key? _key;

  // Guards concurrent init calls (e.g. two messages encrypted/decrypted
  // near-simultaneously on app cold start) from firing two Cloud Function
  // calls and racing on the secure storage write.
  Future<void>? _initFuture;

  /// True once [ensureReady] has completed successfully. Callers (e.g.
  /// ChatScreen) can use this to gate UI instead of guessing.
  bool get isReady => _encrypter != null;

  /// Must be awaited once before first use (e.g. in chat screen initState,
  /// or app startup). Safe to call multiple times — subsequent calls
  /// return immediately once initialised. If a previous attempt failed,
  /// calling this again will retry (it does NOT get stuck replaying the
  /// same failed future forever).
  Future<void> ensureReady() {
    if (_encrypter != null) return Future.value();
    return _initFuture ??= _init();
  }

  Future<void> _init() async {
    try {
      // 1. Try local cache first — avoids a network call on every cold start.
      String? rawKey = await _storage.read(key: _keyStorageKey);

      // 2. Not cached yet → fetch from Cloud Function and cache it.
      rawKey ??= await _fetchAndCacheKey();

      _key = enc.Key(base64.decode(rawKey));
      _encrypter = enc.Encrypter(enc.AES(_key!, mode: enc.AESMode.cbc));
    } catch (e) {
      // Reset _initFuture so the NEXT call to ensureReady() actually
      // retries instead of re-awaiting this same failed future forever.
      _initFuture = null;
      // Surface the failure — callers should show a retry state rather
      // than silently sending unencrypted messages.
      throw EncryptionInitException('Failed to initialise chat encryption: $e');
    }
  }

  Future<String> _fetchAndCacheKey() async {
    final callable =
    FirebaseFunctions.instance.httpsCallable('getChatEncryptionKey');
    final result = await callable.call().timeout(const Duration(seconds: 10));
    final rawKey = result.data['key'] as String; // expects base64, 32 bytes
    await _storage.write(key: _keyStorageKey, value: rawKey);
    return rawKey;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Encrypt [plaintext] → base64( randomIV(16) + ciphertext ).
  /// Throws [StateError] if called before [ensureReady] completes.
  String encrypt(String plaintext) {
    _requireReady();
    final iv = _randomIV();
    final encrypted = _encrypter!.encrypt(plaintext, iv: iv);
    final combined = Uint8List(16 + encrypted.bytes.length)
      ..setRange(0, 16, iv.bytes)
      ..setRange(16, 16 + encrypted.bytes.length, encrypted.bytes);
    return base64.encode(combined);
  }

  /// Decrypt base64 ciphertext back to plaintext.
  /// Returns the original string unchanged if decryption fails
  /// (handles legacy unencrypted messages already stored in Firestore),
  /// AND if the service simply isn't ready yet (avoids crashing message
  /// rendering — caller should prefer checking [isReady] first where UX
  /// matters, e.g. to show a "decrypting…" placeholder instead).
  String decrypt(String ciphertext) {
    if (!isReady) return ciphertext;
    try {
      final combined = base64.decode(ciphertext);
      if (combined.length < 17) return ciphertext; // too short to be valid
      final iv = enc.IV(combined.sublist(0, 16));
      final cipherBytes = enc.Encrypted(combined.sublist(16));
      return _encrypter!.decrypt(cipherBytes, iv: iv);
    } catch (_) {
      // Legacy plain-text message or malformed — return as-is.
      return ciphertext;
    }
  }

  /// Call this if the server ever rotates the shared key (e.g. after a
  /// suspected compromise) so the app re-fetches instead of using a stale
  /// cached copy.
  Future<void> invalidateCachedKey() async {
    await _storage.delete(key: _keyStorageKey);
    _encrypter = null;
    _key = null;
    _initFuture = null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _requireReady() {
    if (_encrypter == null) {
      throw StateError(
        'EncryptionService.ensureReady() must complete before encrypt/decrypt. '
            'Call and await it during chat screen init.',
      );
    }
  }

  enc.IV _randomIV() {
    final rng = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(16, (_) => rng.nextInt(256)),
    );
    return enc.IV(bytes);
  }
}

class EncryptionInitException implements Exception {
  final String message;
  EncryptionInitException(this.message);
  @override
  String toString() => message;
}