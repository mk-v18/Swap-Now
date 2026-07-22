const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const crypto = require("crypto");

initializeApp();
const db = getFirestore();

// ── Secrets ──────────────────────────────────────────────────────────────
// All set via: firebase functions:secrets:set <NAME>
// Never stored in any file in this repo.
const razorpayKeyId = defineSecret("RAZORPAY_KEY_ID");         // ✅ needed to auth the Orders API call
const razorpayKeySecret = defineSecret("RAZORPAY_KEY_SECRET");
const chatAesKeySecret = defineSecret("CHAT_AES_KEY"); // base64, 32 bytes

// ══════════════════════════════════════════════════════════════════════
// 1. Chat push notifications
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
    // Validate the photo URL before ever putting it in an FCM payload — a
    // malformed/non-http URL makes FCM reject the ENTIRE message, so the
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

      // Skip banned users — they shouldn't receive pushes at all.
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
        // Clean up stale/invalid tokens so future sends don't keep silently
        // failing for this user.
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

// Only allow http/https image URLs through to FCM — anything else (empty
// string, malformed, data:, file:) gets dropped to undefined so the payload
// still sends successfully without the image.
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
// 2a. Create Razorpay order — MUST be called before opening checkout.
//
// This was the missing piece. Razorpay only returns a `razorpay_signature`
// in the client success callback when checkout was opened against a real
// order created via the Orders API. Without this, verifyPayment's
// HMAC(orderId + "|" + paymentId, secret) check can never match, so every
// payment was failing verification regardless of whether the key/secret
// pair was correct.
//
// Amount is intentionally hardcoded server-side (not read from the client)
// so a tampered client can't request a cheaper order.
// ══════════════════════════════════════════════════════════════════════
const RAZORPAY_AMOUNT_PAISE = 9900; // ₹99.00 — keep in sync with _kAmountPaise in payment_page.dart

exports.createRazorpayOrder = onCall(
  { secrets: [razorpayKeyId, razorpayKeySecret] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    // Razorpay caps `receipt` at 40 chars. Full UID (28 chars) + prefix +
    // timestamp blew past that, so truncate the UID to keep this well
    // under the limit while still being useful for support lookups.
    const receipt = `ord_${request.auth.uid.slice(0, 12)}_${Date.now()}`;
    const auth = Buffer.from(
      `${razorpayKeyId.value()}:${razorpayKeySecret.value()}`
    ).toString("base64");

    let res;
    try {
      res = await fetch("https://api.razorpay.com/v1/orders", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Basic ${auth}`,
        },
        body: JSON.stringify({
          amount: RAZORPAY_AMOUNT_PAISE,
          currency: "INR",
          receipt,
          notes: { uid: request.auth.uid },
        }),
      });
    } catch (err) {
      console.error("Razorpay order request failed:", err.message);
      throw new HttpsError("unavailable", "Could not reach payment gateway.");
    }

    if (!res.ok) {
      const errBody = await res.text().catch(() => "");
      console.error("Razorpay order creation failed:", res.status, errBody);
      throw new HttpsError("internal", "Could not create order.");
    }

    const order = await res.json();
    return {
      orderId: order.id,
      amount: order.amount,
      currency: order.currency,
    };
  }
);

// ══════════════════════════════════════════════════════════════════════
// 2b. Payment verification — called from PaymentPage after Razorpay's
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

// ══════════════════════════════════════════════════════════════════════
// 4. Swap request notifications — request sent / accepted / declined,
//    and exchange marked complete. Reuses the same fcmToken stored on
//    users/{uid} by the client's NotificationService, and the same
//    stale-token cleanup pattern as sendChatNotification above.
//
//    NOTE: _sendPushToUser now takes a `channelId` param (defaults to
//    "chat_messages" for backward compatibility with any other caller).
//    All swap/exchange notifications below explicitly pass
//    channelId: "swap_updates" so they land in their own Android channel
//    on the client — including when the app is backgrounded/terminated,
//    where Android displays the notification straight from this payload
//    field rather than via NotificationService's foreground handler.
// ══════════════════════════════════════════════════════════════════════

async function _sendPushToUser(uid, { title, body, data = {}, channelId = "chat_messages" }) {
  if (!uid) return;

  let userDoc;
  try {
    userDoc = await db.collection("users").doc(uid).get();
  } catch (err) {
    console.error(`Failed to fetch user ${uid}:`, err.message);
    return;
  }
  if (!userDoc.exists) return;

  const userData = userDoc.data();
  if (userData.banned === true) return;

  const fcmToken = userData.fcmToken;
  if (!fcmToken) return;

  try {
    await getMessaging().send({
      token: fcmToken,
      notification: { title, body },
      // FCM data payloads must be string-only.
      data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
      android: { priority: "high", notification: { channelId } },
      apns: { payload: { aps: { alert: { title, body }, sound: "default" } } },
    });
  } catch (err) {
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
}

// ── 4a. New swap request → notify the receiver ─────────────────────────────
exports.onSwapRequestCreated = onDocumentCreated("swapRequests/{requestId}", async (event) => {
  const data = event.data?.data();
  if (!data) return null;

  await _sendPushToUser(data.toUserId, {
    title: "New swap request",
    body: `${data.fromUserName || "Someone"} wants to swap for "${data.listedProduct?.title || "your item"}"`,
    data: { type: "swap_request", requestId: event.params.requestId },
    channelId: "swap_updates",
  });
  return null;
});

// ── 4b. Request accepted / declined → notify the requester ─────────────────
exports.onSwapRequestUpdated = onDocumentUpdated("swapRequests/{requestId}", async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!before || !after) return null;
  if (before.status === after.status) return null; // only react to status changes

  if (after.status === "accepted") {
    await _sendPushToUser(after.fromUserId, {
      title: "Request accepted 🎉",
      body: `${after.toUserName || "They"} accepted your swap request. Tap to open the chat.`,
      data: { type: "swap_accepted", chatId: after.chatId || "", requestId: event.params.requestId },
      channelId: "swap_updates",
    });
  } else if (after.status === "declined") {
    await _sendPushToUser(after.fromUserId, {
      title: "Request declined",
      body: `${after.toUserName || "They"} declined your swap request.`,
      data: { type: "swap_declined", requestId: event.params.requestId },
      channelId: "swap_updates",
    });
  }
  return null;
});

// ── 4c. Exchange marked successful → notify the other participant ──────────
exports.onExchangeHistoryCreated = onDocumentCreated("exchangeHistory/{historyId}", async (event) => {
  const data = event.data?.data();
  if (!data) return null;

  const other = (data.participants || []).find((uid) => uid !== data.completedBy);
  if (!other) return null;

  // cancelSwap() also writes to exchangeHistory (status: 'cancelled'),
  // reusing this same trigger — branch the notification copy so a
  // cancelled swap doesn't tell the other participant it "completed".
  const isCancelled = data.status === "cancelled";

  await _sendPushToUser(other, {
    title: isCancelled ? "Swap cancelled" : "Exchange completed ✅",
    body: isCancelled
      ? `Your swap for "${data.listedProduct?.title || "an item"}" was cancelled.`
      : `Your swap for "${data.listedProduct?.title || "an item"}" was marked as completed.`,
    data: {
      type: isCancelled ? "exchange_cancelled" : "exchange_completed",
      historyId: event.params.historyId,
    },
    channelId: "swap_updates",
  });
  return null;
});

// ══════════════════════════════════════════════════════════════════════
// 5. Homepage cleanup on swap completion — when a swapRequests doc
//    transitions to 'completed' (user tapped "Successful" on the Active
//    tab), soft-remove BOTH exchanged listings from UserProductList so
//    they disappear from everyone's HomePage.
//
//    FIX: this previously only marked `listedProduct.id` as exchanged.
//    A swap always involves TWO listings — the seller's `listedProduct`
//    AND whatever the requester offered in `offeredProducts[]`, each its
//    own doc in UserProductList — but only the first was being updated.
//    That's why one side of a completed swap kept showing up on other
//    users' homepages: its status field was never touched. Both sides
//    are now updated in the same batch.
//
//    This has to run server-side with the Admin SDK rather than as a
//    client write, because firestore.rules only lets a listing's OWNER
//    write to UserProductList/{productId}, but "Successful" can be tapped
//    by either swap participant — neither participant necessarily owns
//    BOTH listings involved (the requester owns the offered ones, the
//    original poster owns listedProduct), so a client-side write from
//    either side would get PERMISSION_DENIED on at least one of the two.
//
//    Soft-delete (status: 'exchanged') rather than a hard delete, so the
//    exchangeHistory record's product snapshot, any other swapRequests
//    still referencing these listedProduct.id/offeredProducts ids, and
//    existing wishlist entries all stay intact. HomePage's
//    _processItems() skips any listing with status == 'exchanged'.
//
//    NOT done on cancellation: cancelSwap() only ever runs while status
//    is 'accepted' (Firestore rules block accepted -> cancelled from any
//    other prior state), and this function only reacts to a transition
//    INTO 'completed' — so a cancelled swap's listings are never marked
//    exchanged in the first place, and both stay visible everywhere
//    without any extra code needed.
// ══════════════════════════════════════════════════════════════════════
exports.onSwapCompleted = onDocumentUpdated("swapRequests/{requestId}", async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!before || !after) return null;

  // Only fire on the actual transition into 'completed' — skip no-op
  // writes to an already-completed doc, and deliberately skip 'cancelled'
  // (a cancelled swap should never touch either listing).
  if (before.status === after.status || after.status !== "completed") {
    return null;
  }

  // Collect every UserProductList id involved in this swap: the listing
  // that was requested, plus every item offered in exchange for it.
  const productIds = new Set();
  const listedId = after.listedProduct?.id;
  if (listedId) productIds.add(listedId);
  for (const offered of after.offeredProducts || []) {
    if (offered?.id) productIds.add(offered.id);
  }

  if (productIds.size === 0) {
    console.warn(`swapRequests/${event.params.requestId} completed with no product ids to mark exchanged`);
    return null;
  }

  const batch = db.batch();
  for (const productId of productIds) {
    batch.update(db.collection("UserProductList").doc(productId), {
      status: "exchanged",
      exchangedAt: FieldValue.serverTimestamp(),
    });
  }
  console.log(`onSwapCompleted ${event.params.requestId} productIds:`, [...productIds]);

  try {
    await batch.commit();
  } catch (err) {
    // A batch commit fails atomically — if one listing was already
    // deleted by its owner, the whole batch fails even though the other
    // update was valid. Fall back to updating each independently so a
    // missing doc doesn't block marking the ones that still exist.
    console.warn(`Batch update failed for swapRequests/${event.params.requestId}, falling back to per-doc updates:`, err.message);
    await Promise.all(
      [...productIds].map((productId) =>
        db.collection("UserProductList").doc(productId).update({
          status: "exchanged",
          exchangedAt: FieldValue.serverTimestamp(),
        }).catch((e) => console.warn(`Could not mark UserProductList/${productId} exchanged:`, e.message))
      )
    );
  }

  return null;
});