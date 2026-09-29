import type { NextFunction, Request, Response, Router } from "express";
import { Router as makeRouter } from "express";
import { z } from "zod";
import { query } from "../db/pool.js";
import { signAccess, verifyAccess, type AccessClaims } from "./jwt.js";
import { consumeOtp, issueOtp } from "./otp.js";
import { OtpError } from "./otp_error.js";

export type AuthedRequest = Request & { user: AccessClaims };

export function requireAuth(req: Request, res: Response, next: NextFunction): void {
  const header = req.header("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) {
    res.status(401).json({ error: "missing token" });
    return;
  }
  try {
    (req as AuthedRequest).user = verifyAccess(token);
    next();
  } catch {
    res.status(401).json({ error: "invalid token" });
  }
}

const sendSchema = z
  .object({
    phone: z.string().min(6).optional(),
    phoneNumber: z.string().min(6).optional(),
    countryCode: z.string().min(1).max(6).optional(),
  })
  .refine((body) => Boolean(body.phone || body.phoneNumber), { message: "phone number required" });

const verifySchema = z
  .object({
    phone: z.string().min(6).optional(),
    phoneNumber: z.string().min(6).optional(),
    countryCode: z.string().min(1).max(6).optional(),
    code: z.string().min(4).max(8),
    displayName: z.string().min(1).max(80).optional(),
  })
  .refine((body) => Boolean(body.phone || body.phoneNumber), { message: "phone number required" });

const registerSchema = verifySchema.and(
  z.object({
    displayName: z.string().trim().min(1).max(80),
  }),
);

type UserRow = { id: string; display_name: string; default_lang: string; phone_e164: string };

function userPayload(user: UserRow, token: string) {
  return {
    success: true,
    message: "OTP verified",
    accessToken: token,
    user: {
      id: user.id,
      phone: user.phone_e164,
      displayName: user.display_name,
      defaultLang: user.default_lang,
    },
  };
}

async function acceptInvites(phone: string): Promise<void> {
  await query(
    `UPDATE invites SET accepted_at = now()
     WHERE phone_e164 = $1 AND accepted_at IS NULL`,
    [phone],
  );
}

function fail(res: Response, err: unknown): void {
  if (err instanceof z.ZodError) {
    res.status(400).json({ error: "invalid request", code: "invalid_request" });
    return;
  }
  if (err instanceof OtpError) {
    res.status(err.status).json({
      error: err.message,
      code: err.code,
      ...(err.retryAfterSec != null ? { retryAfterSec: err.retryAfterSec } : {}),
    });
    return;
  }
  if (err instanceof Error && err.message === "invalid phone number") {
    res.status(400).json({ error: "Enter a valid phone number.", code: "invalid_phone" });
    return;
  }
  console.error("[auth]", err);
  res.status(500).json({ error: "Something went wrong. Try again.", code: "otp_failed" });
}

export function authRouter(): Router {
  const r = makeRouter();

  const sendOtp = async (req: Request, res: Response) => {
    try {
      const body = sendSchema.parse(req.body);
      const issued = await issueOtp(body.phoneNumber ?? body.phone ?? "", body.countryCode);
      res.json({
        success: true,
        message: "OTP sent successfully",
        phone: issued.phone,
        ttlSec: issued.ttlSec,
        retryAfterSec: issued.retryAfterSec,
      });
    } catch (err) {
      fail(res, err);
    }
  };

  const verifyOtp = async (req: Request, res: Response) => {
    try {
      const body = verifySchema.parse(req.body);
      const phone = await consumeOtp(body.phoneNumber ?? body.phone ?? "", body.code, body.countryCode);
      const existing = await query<UserRow>(
        `SELECT id, display_name, default_lang, phone_e164 FROM users WHERE phone_e164 = $1`,
        [phone],
      );
      const user = existing.rows[0];
      if (!user) {
        res.status(404).json({
          error: "No account for this number. Register first.",
          code: "not_registered",
        });
        return;
      }
      const token = signAccess({ sub: user.id, phone, name: user.display_name });
      res.json(userPayload(user, token));
    } catch (err) {
      fail(res, err);
    }
  };

  const register = async (req: Request, res: Response) => {
    try {
      const body = registerSchema.parse(req.body);
      const phone = await consumeOtp(body.phoneNumber ?? body.phone ?? "", body.code, body.countryCode);
      const existing = await query<{ id: string }>(`SELECT id FROM users WHERE phone_e164 = $1`, [phone]);
      if (existing.rows[0]) {
        res.status(409).json({
          error: "This number is already registered. Sign in instead.",
          code: "already_registered",
        });
        return;
      }
      const created = await query<UserRow>(
        `INSERT INTO users (phone_e164, display_name) VALUES ($1, $2)
         RETURNING id, display_name, default_lang, phone_e164`,
        [phone, body.displayName.trim()],
      );
      const user = created.rows[0];
      await acceptInvites(phone);
      const token = signAccess({ sub: user.id, phone, name: user.display_name });
      res.status(201).json(userPayload(user, token));
    } catch (err) {
      fail(res, err);
    }
  };

  const changePhone = async (req: Request, res: Response) => {
    try {
      const body = verifySchema.parse(req.body);
      const me = (req as AuthedRequest).user.sub;
      const phone = await consumeOtp(body.phoneNumber ?? body.phone ?? "", body.code, body.countryCode);
      const current = await query<UserRow>(
        `SELECT id, display_name, default_lang, phone_e164 FROM users WHERE id = $1`,
        [me],
      );
      const user = current.rows[0];
      if (!user) {
        res.status(404).json({ error: "Account not found.", code: "not_found" });
        return;
      }
      if (user.phone_e164 === phone) {
        res.status(400).json({ error: "That is already your number.", code: "same_phone" });
        return;
      }
      const taken = await query<{ id: string }>(
        `SELECT id FROM users WHERE phone_e164 = $1 AND id <> $2`,
        [phone, me],
      );
      if (taken.rows[0]) {
        res.status(409).json({
          error: "That number is already on another account.",
          code: "phone_taken",
        });
        return;
      }
      await query(`UPDATE users SET phone_e164 = $1 WHERE id = $2`, [phone, me]);
      await query(
        `UPDATE invites SET phone_e164 = $1 WHERE phone_e164 = $2 AND accepted_at IS NULL`,
        [phone, user.phone_e164],
      );
      await acceptInvites(phone);
      user.phone_e164 = phone;
      const token = signAccess({ sub: user.id, phone, name: user.display_name });
      res.json(userPayload(user, token));
    } catch (err) {
      fail(res, err);
    }
  };

  r.post("/otp/request", sendOtp);
  r.post("/send-otp", sendOtp);
  r.post("/otp/verify", verifyOtp);
  r.post("/verify-otp", verifyOtp);
  r.post("/register", register);
  r.post("/phone", requireAuth, changePhone);

  r.get("/me", requireAuth, async (req, res) => {
    const { sub } = (req as AuthedRequest).user;
    const result = await query(
      `SELECT id, phone_e164 AS phone, display_name AS "displayName", default_lang AS "defaultLang"
       FROM users WHERE id = $1`,
      [sub],
    );
    if (!result.rows[0]) {
      res.status(404).json({ error: "not found" });
      return;
    }
    res.json({ user: result.rows[0] });
  });

  return r;
}
