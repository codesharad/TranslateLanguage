export class OtpError extends Error {
  constructor(
    message: string,
    readonly code: string,
    readonly status = 400,
    readonly retryAfterSec?: number,
  ) {
    super(message);
    this.name = "OtpError";
  }
}
