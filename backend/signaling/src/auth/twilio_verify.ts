import { config } from "../config.js";
import { OtpError } from "./otp_error.js";

type TwilioJson = {
  status?: string;
  message?: string;
  code?: number;
};

function credentials(): { accountSid: string; authToken: string; serviceSid: string } {
  const { accountSid, authToken, verifyServiceSid } = config.twilio;
  if (!accountSid || !authToken || !verifyServiceSid) {
    throw new OtpError("SMS is not configured on the server.", "sms_unconfigured", 503);
  }
  return { accountSid, authToken, serviceSid: verifyServiceSid };
}

async function verifyRequest(path: string, fields: Record<string, string>): Promise<TwilioJson> {
  const { accountSid, authToken, serviceSid } = credentials();
  const auth = Buffer.from(`${accountSid}:${authToken}`).toString("base64");
  const res = await fetch(`https://verify.twilio.com/v2/Services/${serviceSid}${path}`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${auth}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams(fields),
  });
  const json = (await res.json().catch(() => ({}))) as TwilioJson;
  if (res.ok) return json;

  console.warn("[otp] twilio", res.status, json.code ?? "", json.message ?? "");
  if (res.status === 429 || json.code === 60203 || json.code === 60212) {
    throw new OtpError("Too many codes for this number. Try again later.", "otp_rate_limited", 429);
  }
  if (res.status === 404 || json.code === 20404) {
    throw new OtpError("That code has expired. Request a new one.", "otp_expired", 400);
  }
  if (json.code === 60202) {
    throw new OtpError("Too many wrong codes. Request a new one.", "otp_locked", 429);
  }
  throw new OtpError("Could not send the SMS. Try again.", "sms_failed", 502);
}

/** Twilio Verify: client.verify.v2.services(sid).verifications.create({ to, channel: 'sms' }) */
export async function createSmsVerification(to: string): Promise<void> {
  await verifyRequest("/Verifications", { To: to, Channel: "sms" });
}

/** Twilio Verify: client.verify.v2.services(sid).verificationChecks.create({ to, code }) */
export async function checkSmsVerification(to: string, code: string): Promise<string> {
  const json = await verifyRequest("/VerificationCheck", { To: to, Code: code });
  return json.status ?? "pending";
}
