import { Router } from "express";
import { z } from "zod";
import { query } from "../db/pool.js";
import { rooms } from "../rooms.js";
import { requireAuth, type AuthedRequest } from "../auth/routes.js";
import { normalizePhone } from "../auth/phone.js";

export function contactsRouter(): Router {
  const r = Router();
  r.use(requireAuth);

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
