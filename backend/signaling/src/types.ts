export type SignalKind =
  | "auth"
  | "register"
  | "presence.sync"
  | "dial-user"
  | "incoming-call"
  | "accept-call"
  | "reject-call"
  | "end-call"
  | "call.invite"
  | "call.accept"
  | "call.reject"
  | "call.hangup"
  | "webrtc.offer"
  | "webrtc.answer"
  | "webrtc.ice"
  | "languages.set"
  | "language.set"
  | "ping"
  | "pong"
  | "error";

export interface ClientInfo {
  userId: string;
  deviceId: string;
  platform: "ios" | "android";
  pushToken?: string;
  displayName: string;
  language?: string;
  phone?: string;
}

export interface CallRecord {
  callId: string;
  callerId: string;
  calleeId: string;
  callerLang: string;
  calleeLang: string;
  state: "ringing" | "active" | "ended";
  createdAt: number;
}

export interface WireMessage {
  type: SignalKind;
  callId?: string;
  to?: string;
  from?: string;
  sdp?: string;
  candidate?: RTCIceCandidateInit | Record<string, unknown>;
  srcLang?: string;
  dstLang?: string;
  hearLang?: string;
  callerHear?: string;
  calleeHear?: string;
  token?: string;
  payload?: Record<string, unknown>;
}

export interface RTCIceCandidateInit {
  candidate?: string;
  sdpMid?: string | null;
  sdpMLineIndex?: number | null;
  usernameFragment?: string | null;
}

export function canonicalEvent(type: string): SignalKind {
  switch (type) {
    case "dial-user":
    case "call.invite":
      return "dial-user";
    case "incoming-call":
      return "incoming-call";
    case "accept-call":
    case "call.accept":
      return "accept-call";
    case "reject-call":
    case "call.reject":
      return "reject-call";
    case "end-call":
    case "call.hangup":
      return "end-call";
    default:
      return type as SignalKind;
  }
}
