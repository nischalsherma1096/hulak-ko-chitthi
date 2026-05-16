const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.onNewMessage = functions.firestore
  .document("chats/{chatId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    const msg = snap.data();
    if (!msg || msg.isSystem || msg.deletedForEveryone) return;

    const chatId   = context.params.chatId;
    const senderId = msg.senderId;
    const text     = msg.text || "New letter";

    // Get chat data
    const chatDoc  = await admin.firestore().collection("chats").doc(chatId).get();
    const chatData = chatDoc.data();
    if (!chatData) return;

    const participants = chatData.participants || [];

    // Get sender username
    const senderDoc  = await admin.firestore().collection("users").doc(senderId).get();
    const senderName = senderDoc.data()?.username || "Someone";

    const now = Date.now();

    for (const uid of participants) {
      if (uid === senderId) continue;

      const userDoc  = await admin.firestore().collection("users").doc(uid).get();
      const userData = userDoc.data();
      if (!userData) continue;

      const token = userData.fcmToken;
      if (!token) continue;

      // Check mute
      const mutedUntil = userData.mutedChats?.[chatId];
      if (mutedUntil && mutedUntil > now) continue;

      // Check block
      const blocked = userData.blockedUsers || [];
      if (blocked.includes(senderId)) continue;

      const payload = {
        notification: {
          title: chatData.isGroup
            ? `${chatData.groupName}: ${senderName}`
            : senderName,
          body: text.length > 80 ? text.substring(0, 80) + "…" : text,
        },
        data: { chatId, senderId },
        token: token,
      };

      try {
        await admin.messaging().send(payload);
      } catch (e) {
        console.log("FCM error for uid", uid, e.message);
      }
    }
  });