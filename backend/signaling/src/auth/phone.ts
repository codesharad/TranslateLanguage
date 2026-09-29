/** E.164: leading + and 8–15 digits, no spaces. */
const E164 = /^\+[1-9]\d{7,14}$/;

/**
 * Turn a local number plus a calling code into E.164.
 * `9876543210` with country code `91` becomes `+919876543210`.
 * A value that already starts with `+` is kept and checked.
 */
export function normalizePhone(raw: string, countryCode?: string): string {
  const trimmed = raw.trim();
  if (trimmed.startsWith("+")) {
    const e164 = `+${trimmed.replace(/\D/g, "")}`;
    if (!E164.test(e164)) throw new Error("invalid phone number");
    return e164;
  }

  const cc = (countryCode ?? "91").replace(/\D/g, "") || "91";
  let national = trimmed.replace(/\D/g, "").replace(/^0+/, "");
  if (national.startsWith(cc) && national.length - cc.length >= 6 && national.length - cc.length <= 12) {
    national = national.slice(cc.length);
  }
  const e164 = `+${cc}${national}`;
  if (!E164.test(e164)) throw new Error("invalid phone number");
  return e164;
}
