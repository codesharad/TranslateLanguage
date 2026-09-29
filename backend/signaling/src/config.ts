import fs from "node:fs";

function orchestratorUrl(): string {
  const explicit = process.env.ORCHESTRATOR_WS_URL;
  if (explicit) return explicit;
  const hostport = process.env.ORCHESTRATOR_HOSTPORT;
  if (hostport) return `ws://${hostport}/v1/media`;
  return "ws://127.0.0.1:8090/v1/media";
}

export const config = {
  port: Number(process.env.PORT ?? process.env.SIGNALING_PORT ?? 8080),
  host: process.env.HOST ?? "0.0.0.0",
  jwtSecret: process.env.JWT_SECRET ?? "dev-only-change-me",
  jwtTtlSec: Number(process.env.JWT_TTL_SEC ?? 60 * 60 * 24 * 14),
  databaseUrl:
    process.env.DATABASE_URL ?? "postgres://translate:translate@127.0.0.1:5432/translate",
  orchestratorWs: orchestratorUrl(),
  publicBaseUrl: process.env.PUBLIC_BASE_URL ?? "http://127.0.0.1:8080",
  otpTtlSec: Number(process.env.OTP_TTL_SEC ?? 300),
  twilio: {
    accountSid: process.env.TWILIO_ACCOUNT_SID ?? "",
    authToken: process.env.TWILIO_AUTH_TOKEN ?? "",
    verifyServiceSid: process.env.TWILIO_VERIFY_SERVICE_SID ?? "",
    from: process.env.TWILIO_FROM ?? "",
  },
  apns: {
    keyPath: process.env.APNS_KEY_PATH ?? "",
    keyId: process.env.APNS_KEY_ID ?? "",
    teamId: process.env.APNS_TEAM_ID ?? "",
    bundleId: process.env.APNS_BUNDLE_ID ?? "com.translatelanguage.app",
    production: process.env.APNS_PRODUCTION === "true",
  },
  fcm: {
    projectId: process.env.FCM_PROJECT_ID ?? "",
    clientEmail: process.env.FCM_CLIENT_EMAIL ?? "",
    privateKey: (process.env.FCM_PRIVATE_KEY ?? "").replace(/\\n/g, "\n"),
  },
};

export function readApnsKey(): string | null {
  if (!config.apns.keyPath) return null;
  try {
    return fs.readFileSync(config.apns.keyPath, "utf8");
  } catch {
    return null;
  }
}
