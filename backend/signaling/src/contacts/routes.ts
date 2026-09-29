import { Router } from "express";
import { z } from "zod";
import { query } from "../db/pool.js";
import { rooms } from "../rooms.js";
import { requireAuth, type AuthedRequest } from "../auth/routes.js";
import { normalizePhone } from "../auth/phone.js";

const inviteSchema = z.object({
  phone: z.string().min(6).optional(),
  phoneNumber: z.string().min(6).optional(),
  countryCode: z.string().min(1).max(6).optional(),
}).refine((body) => Boolean(body.phone || body.phoneNumber), { message: "phone number required" });

export function contactsRouter(): Router {
  const r = Router();
  r.use(requireAuth);

  r.post("/invite", async (req, res) => {
    try {
      const body = inviteSchema.parse(req.body);
      const me = (req as AuthedRequest).user;
      const phone = normalizePhone(body.phoneNumber ?? body.phone ?? "", body.countryCode);
      if (phone === me.phone) {
        res.status(400).json({ error: "That is already your number.", code: "same_phone" });
        return;
      }
      const existing = await query<{
        id: string;
        display_name: string;
        default_lang: string;
      }>(
        `SELECT id, display_name, default_lang FROM users WHERE phone_e164 = $1`,
        [phone],
      );
      const found = existing.rows[0];
      if (found) {
        await query(
          `INSERT INTO invites (inviter_id, phone_e164, accepted_at)
           VALUES ($1, $2, now())
           ON CONFLICT (inviter_id, phone_e164)
           DO UPDATE SET accepted_at = COALESCE(invites.accepted_at, now())`,
          [me.sub, phone],
        );
        res.json({
          status: "already_registered",
          contact: {
            userId: found.id,
            phone,
            displayName: found.display_name,
            language: found.default_lang,
            registered: true,
            online: rooms.listPresence().some((u) => u.userId === found.id),
          },
        });
        return;
      }
      await query(
        `INSERT INTO invites (inviter_id, phone_e164)
         VALUES ($1, $2)
         ON CONFLICT (inviter_id, phone_e164) DO NOTHING`,
        [me.sub, phone],
      );
      res.status(201).json({ status: "invited", phone });
    } catch (err) {
      if (err instanceof z.ZodError) {
        res.status(400).json({ error: "Enter a valid phone number.", code: "invalid_request" });
        return;
      }
      if (err instanceof Error && err.message === "invalid phone number") {
        res.status(400).json({ error: "Enter a valid phone number.", code: "invalid_phone" });
        return;
      }
      console.error("[invite]", err);
      res.status(500).json({ error: "Could not send the invite.", code: "invite_failed" });
    }
  });

  r.get("/invites", async (req, res) => {
    const me = (req as AuthedRequest).user;
    const online = new Set(rooms.listPresence().map((u) => u.userId));
    const people = await query<{
      id: string;
      phone_e164: string;
      display_name: string;
      default_lang: string;
    }>(
      `SELECT DISTINCT u.id, u.phone_e164, u.display_name, u.default_lang
       FROM users u
       JOIN invites i ON (
         (i.inviter_id = $1 AND i.phone_e164 = u.phone_e164 AND i.accepted_at IS NOT NULL)
         OR (i.phone_e164 = $2 AND i.inviter_id = u.id AND i.accepted_at IS NOT NULL)
       )
       WHERE u.id <> $1`,
      [me.sub, me.phone],
    );
    const pending = await query<{ phone_e164: string }>(
      `SELECT phone_e164 FROM invites
       WHERE inviter_id = $1 AND accepted_at IS NULL
       ORDER BY created_at DESC`,
      [me.sub],
    );
    res.json({
      contacts: people.rows.map((row) => ({
        userId: row.id,
        phone: row.phone_e164,
        displayName: row.display_name,
        language: row.default_lang,
        registered: true,
        online: online.has(row.id),
      })),
      pending: pending.rows.map((row) => ({
        userId: row.phone_e164,
        phone: row.phone_e164,
        displayName: row.phone_e164,
        registered: false,
        online: false,
      })),
    });
  });

  r.post("/match", async (req, res) => {
    const body = z.object({ phones: z.array(z.string()).max(2000) }).parse(req.body);
    const me = (req as AuthedRequest).user.sub;
    const normalized: string[] = [];
    for (const p of body.phones) {
      try {
        normalized.push(normalizePhone(p));
      } catch {
        /* skip junk address-book rows */
      }
    }
    if (normalized.length === 0) {
      res.json({ matches: [] });
      return;
    }
    const result = await query<{
      id: string;
      phone_e164: string;
      display_name: string;
      default_lang: string;
    }>(
      `SELECT id, phone_e164, display_name, default_lang
       FROM users
       WHERE phone_e164 = ANY($1::text[]) AND id <> $2`,
      [normalized, me],
    );
    const online = new Set(rooms.listPresence().map((u) => u.userId));
    res.json({
      matches: result.rows.map((row) => ({
        userId: row.id,
        phone: row.phone_e164,
        displayName: row.display_name,
        language: row.default_lang,
        registered: true,
        online: online.has(row.id),
      })),
    });
  });

  return r;
}
