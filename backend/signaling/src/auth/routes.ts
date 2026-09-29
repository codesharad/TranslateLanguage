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
      const existing = await query<{ id: string; display_name: string; default_lang: string }>(
        `SELECT id, display_name, default_lang FROM users WHERE phone_e164 = $1`,
        [phone],
      );
      let user = existing.rows[0];
      if (!user) {
        const created = await query<{ id: string; display_name: string; default_lang: string }>(
          `INSERT INTO users (phone_e164, display_name) VALUES ($1, $2)
           RETURNING id, display_name, default_lang`,
          [phone, body.displayName ?? phone],
        );
        user = created.rows[0];
      } else if (body.displayName) {
        await query(`UPDATE users SET display_name = $1 WHERE id = $2`, [body.displayName, user.id]);
        user.display_name = body.displayName;
      }
      const token = signAccess({ sub: user.id, phone, name: user.display_name });
      res.json({
        success: true,
        message: "OTP verified",
        accessToken: token,
        user: {
          id: user.id,
          phone,
          displayName: user.display_name,
          defaultLang: user.default_lang,
        },
      });
    } catch (err) {
      fail(res, err);
    }
  };

  r.post("/otp/request", sendOtp);
  r.post("/send-otp", sendOtp);
  r.post("/otp/verify", verifyOtp);
  r.post("/verify-otp", verifyOtp);

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
