import { WebSocket } from "ws";
import { randomUUID } from "node:crypto";
import type { CallRecord, ClientInfo, WireMessage } from "./types.js";

interface SocketClient {
  ws: WebSocket;
  info: ClientInfo;
}

export class RoomManager {
  private readonly clients = new Map<string, SocketClient>();
  private readonly calls = new Map<string, CallRecord>();

  register(ws: WebSocket, info: ClientInfo): void {
    const existing = this.clients.get(info.userId);
    if (existing && existing.ws !== ws) {
      existing.ws.close(4001, "replaced");
    }
    this.clients.set(info.userId, { ws, info });
    this.broadcastPresence();
  }

  unregister(userId: string, ws: WebSocket): void {
    const current = this.clients.get(userId);
    if (current?.ws === ws) {
      this.clients.delete(userId);
      this.broadcastPresence();
    }
  }

  getClient(userId: string): SocketClient | undefined {
    return this.clients.get(userId);
  }

  listPresence(excludeUserId?: string): ClientInfo[] {
    return [...this.clients.values()]
      .map((c) => c.info)
      .filter((info) => info.userId !== excludeUserId);
  }

  broadcastPresence(): void {
    for (const [userId, client] of this.clients) {
      if (client.ws.readyState !== WebSocket.OPEN) continue;
      client.ws.send(
        JSON.stringify({
          type: "presence.sync",
          payload: { users: this.listPresence(userId) },
        }),
      );
    }
  }

  createCall(
    callerId: string,
    calleeId: string,
    callerLang: string,
    calleeLang: string,
    callId = randomUUID(),
  ): CallRecord {
    const call: CallRecord = {
      callId,
      callerId,
      calleeId,
      callerLang,
      calleeLang,
      state: "ringing",
      createdAt: Date.now(),
    };
    this.calls.set(call.callId, call);
    return call;
  }

  getCall(callId: string): CallRecord | undefined {
    return this.calls.get(callId);
  }

  setState(callId: string, state: CallRecord["state"]): void {
    const call = this.calls.get(callId);
    if (call) call.state = state;
  }

  send(userId: string, message: WireMessage): boolean {
    const client = this.clients.get(userId);
    if (!client || client.ws.readyState !== WebSocket.OPEN) return false;
    client.ws.send(JSON.stringify(message));
    return true;
  }

  peerOf(call: CallRecord, userId: string): string {
    return call.callerId === userId ? call.calleeId : call.callerId;
  }
}

export const rooms = new RoomManager();
