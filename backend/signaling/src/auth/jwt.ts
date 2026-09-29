import jwt from "jsonwebtoken";
import { config } from "../config.js";

export interface AccessClaims {
  sub: string;
  phone: string;
  name: string;
}

export function signAccess(claims: AccessClaims): string {
  return jwt.sign(claims, config.jwtSecret, {
    expiresIn: `${config.jwtTtlSec}s`,
    issuer: "translatelanguage",
  } as jwt.SignOptions);
}

export function verifyAccess(token: string): AccessClaims {
  const payload = jwt.verify(token, config.jwtSecret, { issuer: "translatelanguage" }) as AccessClaims;
  if (!payload.sub || !payload.phone) throw new Error("invalid token");
  return payload;
}
