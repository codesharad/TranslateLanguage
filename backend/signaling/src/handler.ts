import type { IncomingMessage } from "node:http";
import type { WebSocket } from "ws";
import { z } from "zod";
import { verifyAccess } from "./auth/jwt.js";
import { normalizePhone } from "./auth/phone.js";
import { query } from "./db/pool.js";
import { rooms } from "./rooms.js";
import { wakeCallee } from "./push.js";
import { canonicalEvent, type ClientInfo, type WireMessage } from "./types.js";

const registerSchema = z.object({
  deviceId: z.string().min(1),
  platform: z.enum(["ios", "android"]),
  pushToken: z.string().nullish(),
  language: z.string().nullish(),
});

export function attachClient(ws: WebSocket, req: IncomingMessage): void {
  let userId: string | null = null;

  const boot = tokenFromRequest(req);
  if (boot) {
    try {
      userId = verifyAccess(boot).sub;
    } catch {
      ws.close(4401, "invalid token");
      return;
    }
  }

  ws.on("message", async (raw) => {
    let msg: WireMessage & Record<string, unknown>;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      ws.send(JSON.stringify({ type: "error", payload: { message: "invalid json" } }));
      return;
    }
    try {
      if (msg.type === "ping") {
        ws.send(JSON.stringify({ type: "pong", t: (msg as { t?: number }).t ?? Date.now() }));
        return;
      }
      if (msg.type === "auth" && msg.token) {
        const claims = verifyAccess(msg.token);
        userId = claims.sub;
        ws.send(JSON.stringify({ type: "auth", payload: { ok: true, userId } }));
        return;
      }
      if (msg.type === "register") {
        if (!userId) {
          // Legacy: register.userId still accepted for local two-device demos.
          const legacyId = (msg as { userId?: string }).userId;
          if (!legacyId) throw new Error("auth required");
          userId = legacyId;
        }
        const body = registerSchema.parse({ ...msg, ...msg.payload });
        const profile = await loadUser(userId);
        const info: ClientInfo = {
          userId,
          deviceId: body.deviceId,
          platform: body.platform,
          displayName: profile?.display_name ?? (msg as { displayName?: string }).displayName ?? userId,
          pushToken: body.pushToken ?? undefined,
          language: body.language ?? profile?.default_lang,
          phone: profile?.phone_e164,
        };
        rooms.register(ws, info);
        if (profile) {
          await query(`UPDATE users SET last_seen_at = now() WHERE id = $1`, [userId]);
        }
        if (info.language) await rememberLanguage(userId, info.language);
        ws.send(
          JSON.stringify({
            type: "register",
            payload: { ok: true, userId, users: rooms.listPresence(userId) },
          }),
        );
        return;
      }
      if (!userId) {
        ws.send(JSON.stringify({ type: "error", payload: { message: "auth required" } }));
        return;
      }
      await handle(userId, { ...msg, type: canonicalEvent(msg.type) });
    } catch (err) {
      const message = err instanceof Error ? err.message : "handler error";
      ws.send(JSON.stringify({ type: "error", payload: { message } }));
    }
  });

  ws.on("close", () => {
    if (userId) rooms.unregister(userId, ws);
  });
}

async function handle(userId: string, msg: WireMessage): Promise<void> {
  switch (msg.type) {
    case "dial-user": {
      const calleeId = await resolveCallee(msg.to ?? (msg.payload?.to as string | undefined));
      const caller = rooms.getClient(userId);
      const calleeLive = rooms.getClient(calleeId);
      const callerRow = await loadUser(userId);
      const calleeRow = await loadUser(calleeId);
      const callerHear =
        msg.hearLang ??
        msg.callerHear ??
        (msg.payload?.hearLang as string | undefined) ??
        (msg.payload?.callerHear as string | undefined) ??
        msg.srcLang ??
        (msg.payload?.srcLang as string | undefined) ??
        caller?.info.language ??
        callerRow?.default_lang ??
        "en-IN";
      const calleeHear = calleeLive?.info.language ?? calleeRow?.default_lang ?? "en-IN";
      const call = rooms.createCall(userId, calleeId, callerHear, calleeHear);
      try {
        await query(
          `INSERT INTO calls (id, caller_id, callee_id, caller_lang, callee_lang, state)
           VALUES ($1, $2, $3, $4, $5, 'ringing')
           ON CONFLICT (id) DO NOTHING`,
          [call.callId, userId, calleeId, callerHear, calleeHear],
        );
      } catch (err) {
        console.warn("[call] persist skipped", err);
      }
      const incoming: WireMessage = {
        type: "incoming-call",
        callId: call.callId,
        from: userId,
        to: calleeId,
        srcLang: callerHear,
        dstLang: calleeHear,
        hearLang: callerHear,
        callerHear,
        calleeHear,
        payload: {
          callerName: caller?.info.displayName ?? callerRow?.display_name ?? "Unknown",
          callerPhone: callerRow?.phone_e164,
          handle: callerRow?.phone_e164,
          callerHear,
          calleeHear,
        },
      };
      const delivered = rooms.send(calleeId, incoming);
      console.log(
        `[dial] ${userId} -> ${calleeId} delivered=${delivered} call=${call.callId} calleeLive=${Boolean(calleeLive)}`,
      );
      if (!delivered) {
        rooms.send(userId, {
          type: "error",
          payload: { message: "Other phone is not online. Keep the app open on both phones." },
        });
        return;
      }
      await wakeCallee(
        calleeLive?.info,
        call,
        incoming.payload?.callerName as string,
        callerRow?.phone_e164,
      );
      rooms.send(userId, {
        type: "dial-user",
        callId: call.callId,
        hearLang: callerHear,
        callerHear,
        calleeHear,
        payload: { ringing: true, to: calleeId, callerHear, calleeHear },
      });
      return;
    }
    case "accept-call": {
      const call = requireCall(msg.callId);
      rooms.setState(call.callId, "active");
      await query(`UPDATE calls SET state = 'active' WHERE id = $1`, [call.callId]);
      const peer = rooms.peerOf(call, userId);
      rooms.send(peer, { type: "accept-call", callId: call.callId, from: userId });
      return;
    }
    case "reject-call":
    case "end-call": {
      const call = requireCall(msg.callId);
      rooms.setState(call.callId, "ended");
      await query(`UPDATE calls SET state = 'ended', ended_at = now() WHERE id = $1`, [call.callId]);
      const peer = rooms.peerOf(call, userId);
      rooms.send(peer, { type: msg.type, callId: call.callId, from: userId });
      return;
    }
    case "webrtc.offer":
    case "webrtc.answer":
    case "webrtc.ice": {
      const call = requireCall(msg.callId);
      const peer = rooms.peerOf(call, userId);
      rooms.send(peer, { ...msg, from: userId });
      return;
    }
    case "language.set": {
      const hear = preferredLanguage(msg);
      if (!hear) throw new Error("language.set requires hearLang");
      await rememberLanguage(userId, hear);
      rooms.broadcastPresence();
      return;
    }
    case "languages.set": {
      const call = requireCall(msg.callId);
      const hear = preferredLanguage(msg);
      if (!hear) throw new Error("languages.set requires hearLang");
      if (call.callerId === userId) call.callerLang = hear;
      else if (call.calleeId === userId) call.calleeLang = hear;
      else throw new Error("not on this call");
      await rememberLanguage(userId, hear);
      const peer = rooms.peerOf(call, userId);
      rooms.send(peer, {
        type: "languages.set",
        callId: call.callId,
        from: userId,
        hearLang: hear,
        srcLang: hear,
      });
      return;
    }
    default:
      throw new Error(`unknown type ${msg.type}`);
  }
}

function preferredLanguage(msg: WireMessage): string {
  return (
    msg.hearLang ??
    (msg.payload?.hearLang as string | undefined) ??
    msg.srcLang ??
    (msg.payload?.srcLang as string | undefined) ??
    ""
  );
}

async function rememberLanguage(userId: string, language: string): Promise<void> {
  const client = rooms.getClient(userId);
  if (client) client.info.language = language;
  try {
    await query(`UPDATE users SET default_lang = $2 WHERE id = $1`, [userId, language]);
  } catch (err) {
    console.warn("[lang] persist skipped", err);
  }
}

async function resolveCallee(to: string | undefined): Promise<string> {
  if (!to) throw new Error("dial-user requires to (userId or phone)");
  const byId = await query<{ id: string }>(`SELECT id FROM users WHERE id = $1`, [to]);
  if (byId.rows[0]) return byId.rows[0].id;
  try {
    const phone = normalizePhone(to);
    const byPhone = await query<{ id: string }>(`SELECT id FROM users WHERE phone_e164 = $1`, [phone]);
    if (byPhone.rows[0]) return byPhone.rows[0].id;
  } catch {
    /* not a phone */
  }
  if (rooms.getClient(to)) return to;
  throw new Error("callee not registered");
}

async function loadUser(id: string) {
  try {
    const result = await query<{ display_name: string; phone_e164: string; default_lang: string }>(
      `SELECT display_name, phone_e164, default_lang FROM users WHERE id = $1`,
      [id],
    );
    return result.rows[0];
  } catch {
    return undefined;
  }
}

function requireCall(callId: string | undefined) {
  if (!callId) throw new Error("callId required");
  const call = rooms.getCall(callId);
  if (!call) throw new Error("unknown call");
  return call;
}

function tokenFromRequest(req: IncomingMessage): string | null {
  const url = new URL(req.url ?? "/", "http://localhost");
  const q = url.searchParams.get("token");
  if (q) return q;
  const header = req.headers.authorization;
  if (header?.startsWith("Bearer ")) return header.slice(7);
  return null;
}
