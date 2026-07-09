const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const crypto = require("crypto");

initializeApp();
const db = getFirestore();

// ── Secrets ──────────────────────────────────────────────────────────────
// Both set via: firebase functions:secrets:set <NAME>
// Never stored in any file in this repo.
const razorpayKeySecret = defineSecret("RAZORPAY_KEY_SECRET");
const chatAesKeySecret = defineSecret("CHAT_AES_KEY"); // base64, 32 bytes

// ══════════════════════════════════════════════════════════════════════
// 1. Chat push notifications (unchanged from your existing version)
// ══════════════════════════════════════════════════════════════════════
exports.sendChatNotification = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    const message = event.data.data();
    const { chatId } = event.params;

    const senderId   = message.senderId;
    const receiverId = message.receiverId;
    const type       = message.type || "text";
    const encrypted  = message.encrypted || false;

    if (!senderId || !receiverId) return null;

    // ── 1. Fetch sender (wrapped — a transient Firestore error here ─────────
    //       must not crash the whole function and silently drop the notif)
    let sender;
    try {
      const senderDoc = await db.collection("users").doc(senderId).get();
      if (!senderDoc.exists) return null;
      sender = senderDoc.data();
    } catch (err) {
      console.error("Failed to fetch sender:", err.message);
      return null;
    }
    const senderName  = sender.name || "Someone";
    // FIX: validate the photo URL before ever putting it in an FCM payload —
    // a malformed/non-http URL makes FCM reject the ENTIRE message, so the
    // text notification is lost too, not just the image.
    const senderPhoto = _safeImageUrl(sender.profileImage);

    // ── 2. Build notification body ───────────────────────────────────────────
    const body = encrypted ? _previewForType(type) : (message.text || _previewForType(type));

    // ── 3. Find admin UID (wrapped — query failure shouldn't crash) ─────────
    let adminUid = null;
    try {
      const adminSnap = await db.collection("users")
        .where("role", "==", "admin")
        .limit(1)
        .get();
      adminUid = adminSnap.empty ? null : adminSnap.docs[0].id;
    } catch (err) {
      console.error("Failed to fetch admin uid:", err.message);
      // Continue — receiver notification should still go out even if
      // admin lookup fails.
    }

    // ── 4. Collect recipients: receiver + admin (if neither is sender) ──────
    const recipients = new Set();
    if (receiverId !== senderId) recipients.add(receiverId);
    if (adminUid && adminUid !== senderId) recipients.add(adminUid);

    // ── 5. Send to each recipient — each gets ONLY their own token ──────────
    const sendPromises = [...recipients].map(async (uid) => {
      let userDoc;
      try {
        userDoc = await db.collection("users").doc(uid).get();
      } catch (err) {
        console.error(`Failed to fetch user ${uid}:`, err.message);
        return;
      }
      if (!userDoc.exists) return;

      const userData = userDoc.data();

      // FIX: skip banned users — they shouldn't receive pushes at all.
      if (userData.banned === true) {
        console.log(`Skipping notification — ${uid} is banned`);
        return;
      }

      const fcmToken = userData.fcmToken;
      if (!fcmToken) return;

      const fcmPayload = {
        token: fcmToken, // ← this user's own token only, never shared/broadcast
        data: {
          chatId,
          senderId,
          receiverId: uid,
          senderName,
          senderPhoto,
          type,
          body,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "high",
          notification: {
            channelId: "chat_messages",
            title: senderName,
            body,
            imageUrl: senderPhoto || undefined,
            icon: "ic_notification",
            color: "#7B1FA2",
            tag: chatId,
            defaultVibrateTimings: true,
            defaultSound: true,
          },
        },
        apns: {
          payload: {
            aps: {
              alert: { title: senderName, body },
              sound: "default",
              badge: 1,
              "thread-id": chatId,
            },
          },
          headers: { "apns-priority": "10" },
        },
        notification: {
          title: senderName,
          body,
          imageUrl: senderPhoto || undefined,
        },
      };

      try {
        await getMessaging().send(fcmPayload);
        console.log(`Notification sent to ${uid} for chat ${chatId}`);
      } catch (err) {
        // FIX: clean up stale/invalid tokens so future sends don't keep
        // silently failing for this user (and so they eventually stop
        // getting notifications entirely until they re-open the app).
        if (
          err.code === "messaging/registration-token-not-registered" ||
          err.code === "messaging/invalid-registration-token"
        ) {
          console.log(`Stale token for ${uid} — removing`);
          await db.collection("users").doc(uid)
            .update({ fcmToken: FieldValue.delete() })
            .catch(() => {});
        } else {
          console.error(`FCM error for ${uid}:`, err.message);
        }
      }
    });

    await Promise.all(sendPromises);
    return null;
  }
);

function _previewForType(type) {
  switch (type) {
    case "image":    return "📷 Photo";
    case "video":    return "🎥 Video";
    case "audio":    return "🎤 Voice message";
    case "location": return "📍 Location";
    default:         return "New message";
  }
}

// FIX: only allow http/https image URLs through to FCM — anything else
// (empty string, malformed, data:, file:) gets dropped to undefined so the
// payload still sends successfully without the image.
function _safeImageUrl(url) {
  if (!url || typeof url !== "string") return undefined;
  try {
    const u = new URL(url);
    if (u.protocol === "http:" || u.protocol === "https:") return url;
  } catch (_) {
    // invalid URL
  }
  return undefined;
}

// ══════════════════════════════════════════════════════════════════════
// 2. Payment verification — called from PaymentPage after Razorpay's
//    success callback. This is the ONLY place `hasPaid` should be set
//    to true in production; the client-side write in payment_page.dart
//    should eventually be removed once this is wired up and tested.
// ══════════════════════════════════════════════════════════════════════
exports.verifyPayment = onCall(
  { secrets: [razorpayKeySecret] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    const { orderId, paymentId, signature } = request.data;
    if (!orderId || !paymentId || !signature) {
      throw new HttpsError("invalid-argument", "Missing payment fields.");
    }

    const expected = crypto
      .createHmac("sha256", razorpayKeySecret.value())
      .update(`${orderId}|${paymentId}`)
      .digest("hex");

    if (expected !== signature) {
      throw new HttpsError("permission-denied", "Signature mismatch.");
    }

    // Signature verified — safe to mark the user as paid now.
    await db.collection("users").doc(request.auth.uid).update({
      hasPaid: true,
      paymentId,
      paidAt: FieldValue.serverTimestamp(),
      onboardingStep: "starting_page",
    });

    return { verified: true };
  }
);

// ══════════════════════════════════════════════════════════════════════
// 3. Chat encryption key — called once per device from
//    encryption_service.dart, result cached in flutter_secure_storage
//    on the client so this only runs on first launch / cache miss.
// ══════════════════════════════════════════════════════════════════════
exports.getChatEncryptionKey = onCall(
  { secrets: [chatAesKeySecret] },
  async (request) => {
    // Only signed-in users can retrieve the key — never expose this
    // endpoint to unauthenticated callers.
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    return { key: chatAesKeySecret.value() };
  }
);