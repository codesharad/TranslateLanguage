import { config } from "../config.js";
import { query } from "../db/pool.js";
import { normalizePhone } from "./phone.js";
import { OtpError } from "./otp_error.js";
import { checkSmsVerification, createSmsVerification } from "./twilio_verify.js";

const COOLDOWN_MS = 60_000;
const MAX_SENDS_PER_HOUR = 3;
const MAX_VERIFY_ATTEMPTS = 5;

export async function issueOtp(
  rawPhone: string,
  countryCode?: string,
): Promise<{ phone: string; retryAfterSec: number; ttlSec: number }> {
  const phone = normalizePhone(rawPhone, countryCode);
  const recent = await query<{ sent_at: Date }>(
    `SELECT sent_at FROM otp_sends
     WHERE phone_e164 = $1 AND sent_at > now() - interval '1 hour'
     ORDER BY sent_at DESC`,
    [phone],
  );
  if (recent.rows.length >= MAX_SENDS_PER_HOUR) {
    throw new OtpError(
      "Too many codes for this number. Try again in an hour.",
      "otp_rate_limited",
      429,
    );
  }
  const latest = recent.rows[0];
  if (latest) {
    const elapsed = Date.now() - new Date(latest.sent_at).getTime();
    if (elapsed < COOLDOWN_MS) {
      const retryAfterSec = Math.ceil((COOLDOWN_MS - elapsed) / 1000);
      throw new OtpError(
        `Wait ${retryAfterSec}s before requesting another code.`,
        "otp_cooldown",
        429,
        retryAfterSec,
      );
    }
  }

  await createSmsVerification(phone);
  const expires = new Date(Date.now() + config.otpTtlSec * 1000);
  await query(
    `INSERT INTO otp_challenges (phone_e164, code_hash, expires_at, attempts)
     VALUES ($1, 'twilio-verify', $2, 0)
     ON CONFLICT (phone_e164)
     DO UPDATE SET code_hash = 'twilio-verify', expires_at = EXCLUDED.expires_at, attempts = 0, created_at = now()`,
    [phone, expires.toISOString()],
  );
  await query(`INSERT INTO otp_sends (phone_e164) VALUES ($1)`, [phone]);
  await query(`DELETE FROM otp_sends WHERE sent_at < now() - interval '1 day'`);
  console.info(`[otp] sent ****${phone.slice(-4)}`);
  return { phone, retryAfterSec: 60, ttlSec: config.otpTtlSec };
}

export async function consumeOtp(rawPhone: string, code: string, countryCode?: string): Promise<string> {
  const phone = normalizePhone(rawPhone, countryCode);
  const trimmed = code.trim();
  if (!/^\d{4,8}$/.test(trimmed)) {
    throw new OtpError("Enter the code from the SMS.", "otp_invalid", 400);
  }

  const row = await query<{ expires_at: Date; attempts: number }>(
    `SELECT expires_at, attempts FROM otp_challenges WHERE phone_e164 = $1`,
    [phone],
  );
  const challenge = row.rows[0];
  if (!challenge) throw new OtpError("Request a code first.", "otp_not_requested", 400);
  if (challenge.attempts >= MAX_VERIFY_ATTEMPTS) {
    throw new OtpError("Too many wrong codes. Request a new one.", "otp_locked", 429);
  }
  if (new Date(challenge.expires_at).getTime() < Date.now()) {
    throw new OtpError("That code has expired. Request a new one.", "otp_expired", 400);
  }

  const status = await checkSmsVerification(phone, trimmed);
  if (status !== "approved") {
    await query(`UPDATE otp_challenges SET attempts = attempts + 1 WHERE phone_e164 = $1`, [phone]);
    if (status === "canceled" || status === "expired") {
      throw new OtpError("That code has expired. Request a new one.", "otp_expired", 400);
    }
    throw new OtpError("That code is wrong.", "otp_invalid", 400);
  }

  await query(`DELETE FROM otp_challenges WHERE phone_e164 = $1`, [phone]);
  return phone;
}
