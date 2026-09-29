import { Router } from "express";
import { z } from "zod";
import { query } from "../db/pool.js";
import { requireAuth, type AuthedRequest } from "../auth/routes.js";

export function devicesRouter(): Router {
  const r = Router();
  r.use(requireAuth);

  r.put("/", async (req, res) => {
    const body = z
      .object({
        deviceId: z.string().min(1),
        platform: z.enum(["ios", "android"]),
        voipToken: z.string().optional(),
        fcmToken: z.string().optional(),
      })
      .parse(req.body);
    const userId = (req as AuthedRequest).user.sub;
    await query(
      `INSERT INTO devices (user_id, device_id, platform, voip_token, fcm_token)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (user_id, device_id) DO UPDATE SET
         platform = EXCLUDED.platform,
         voip_token = COALESCE(EXCLUDED.voip_token, devices.voip_token),
         fcm_token = COALESCE(EXCLUDED.fcm_token, devices.fcm_token),
         updated_at = now()`,
      [userId, body.deviceId, body.platform, body.voipToken ?? null, body.fcmToken ?? null],
    );
    res.json({ ok: true });
  });

  return r;
}
