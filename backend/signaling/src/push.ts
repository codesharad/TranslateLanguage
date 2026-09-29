/**
 * Wake a callee so CallKit / ConnectionService can ring.
 *
 * iOS: APNs push type `voip`, topic `{bundleId}.voip`, priority 10.
 *      The app MUST report a CallKit incoming call on receipt.
 * Android: FCM HTTP v1 data-only, android.priority HIGH, full-screen intent.
 */

import http2 from "node:http2";
import jwt from "jsonwebtoken";
import { config, readApnsKey } from "./config.js";
import { query } from "./db/pool.js";
import type { CallRecord, ClientInfo } from "./types.js";

export interface PushPayload {
  callId: string;
  callerId: string;
  callerName: string;
  callerPhone?: string;
  callerLang: string;
  calleeLang: string;
  handle: string;
  hasVideo: false;
  uuid: string;
}

export async function wakeCallee(
  callee: ClientInfo | undefined,
  call: CallRecord,
  callerName: string,
  callerPhone?: string,
): Promise<void> {
  const payload: PushPayload = {
    callId: call.callId,
    uuid: call.callId,
    callerId: call.callerId,
    callerName,
    callerPhone,
    callerLang: call.callerLang,
    calleeLang: call.calleeLang,
    handle: callerPhone ?? callerName,
    hasVideo: false,
  };

  const tokens = await loadDeviceTokens(call.calleeId, callee);
  const jobs: Promise<void>[] = [];
  if (tokens.voip) jobs.push(sendApnsVoip(tokens.voip, payload));
  if (tokens.fcm) jobs.push(sendFcm(tokens.fcm, payload));
  if (jobs.length === 0) {
    console.warn(`[push] no tokens for ${call.calleeId}; callee must be online on WS`);
    return;
  }
  await Promise.allSettled(jobs);
}

async function loadDeviceTokens(
  userId: string,
  live?: ClientInfo,
): Promise<{ voip?: string; fcm?: string }> {
  const row = await query<{ voip_token: string | null; fcm_token: string | null; platform: string }>(
    `SELECT voip_token, fcm_token, platform FROM devices
     WHERE user_id = $1 ORDER BY updated_at DESC LIMIT 1`,
    [userId],
  );
  const db = row.rows[0];
  if (live?.platform === "ios") {
    return { voip: live.pushToken ?? db?.voip_token ?? undefined, fcm: db?.fcm_token ?? undefined };
  }
  if (live?.platform === "android") {
    return { fcm: live.pushToken ?? db?.fcm_token ?? undefined, voip: db?.voip_token ?? undefined };
  }
  return { voip: db?.voip_token ?? undefined, fcm: db?.fcm_token ?? undefined };
}

async function sendApnsVoip(deviceToken: string, payload: PushPayload): Promise<void> {
  const key = readApnsKey();
  if (!key || !config.apns.keyId || !config.apns.teamId) {
    console.info("[push] APNs p8 not configured");
    return;
  }
  const host = config.apns.production ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const token = jwt.sign({ iss: config.apns.teamId, iat: Math.floor(Date.now() / 1000) }, key, {
    algorithm: "ES256",
    keyid: config.apns.keyId,
  });
  const client = http2.connect(`https://${host}`);
  try {
    const body = JSON.stringify({
      aps: { "content-available": 1 },
      ...payload,
    });
    await new Promise<void>((resolve, reject) => {
      const req = client.request({
        ":method": "POST",
        ":path": `/3/device/${deviceToken}`,
        authorization: `bearer ${token}`,
        "apns-topic": `${config.apns.bundleId}.voip`,
        "apns-push-type": "voip",
        "apns-priority": "10",
        "apns-expiration": "0",
        "content-type": "application/json",
      });
      req.setEncoding("utf8");
      let data = "";
      req.on("data", (c) => {
        data += c;
      });
      req.on("response", (headers) => {
        const status = Number(headers[":status"] ?? 0);
        if (status >= 400) reject(new Error(`apns ${status} ${data}`));
      });
      req.on("end", () => resolve());
      req.on("error", reject);
      req.end(body);
    });
    console.info("[push] APNs VoIP sent", { deviceToken: deviceToken.slice(0, 8) });
  } finally {
    client.close();
  }
}

async function sendFcm(deviceToken: string, payload: PushPayload): Promise<void> {
  if (!config.fcm.projectId || !config.fcm.clientEmail || !config.fcm.privateKey) {
    console.info("[push] FCM v1 not configured");
    return;
  }
  const access = await googleAccessToken();
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${config.fcm.projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${access}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: deviceToken,
          android: {
            priority: "HIGH",
            ttl: "30s",
            fcm_options: { analytics_label: "incoming_call" },
          },
          data: Object.fromEntries(Object.entries(payload).map(([k, v]) => [k, String(v)])),
        },
      }),
    },
  );
  if (!res.ok) {
    throw new Error(`fcm ${res.status} ${await res.text()}`);
  }
  console.info("[push] FCM sent", { deviceToken: deviceToken.slice(0, 8) });
}

async function googleAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const assertion = jwt.sign(
    {
      iss: config.fcm.clientEmail,
      sub: config.fcm.clientEmail,
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
    },
    config.fcm.privateKey,
    { algorithm: "RS256" },
  );
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`google token ${res.status}`);
  const json = (await res.json()) as { access_token: string };
  return json.access_token;
}
