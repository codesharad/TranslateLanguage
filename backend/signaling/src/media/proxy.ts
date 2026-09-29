/**
 * Node media gateway: clients open ws://signaling/v1/media and we proxy
 * binary PCM + JSON control to the Python orchestrator (Silero + STT/MT/TTS).
 * One public host, ML stays in Python.
 */
import type { IncomingMessage } from "node:http";
import { WebSocket } from "ws";
import { config } from "../config.js";

export function proxyMedia(client: WebSocket, _req: IncomingMessage): void {
  const upstream = new WebSocket(config.orchestratorWs);
  const pending: (Buffer | string)[] = [];

  upstream.on("open", () => {
    for (const frame of pending) upstream.send(frame);
    pending.length = 0;
  });
  upstream.on("message", (data, isBinary) => {
    if (client.readyState === WebSocket.OPEN) client.send(data, { binary: isBinary });
  });
  upstream.on("close", (code, reason) => {
    if (client.readyState === WebSocket.OPEN) client.close(code, reason.toString());
  });
  upstream.on("error", () => {
    if (client.readyState === WebSocket.OPEN) client.close(1011, "orchestrator");
  });

  client.on("message", (data, isBinary) => {
    const frame = isBinary ? (data as Buffer) : data.toString();
    if (upstream.readyState === WebSocket.OPEN) upstream.send(frame);
    else pending.push(frame as Buffer | string);
  });
  client.on("close", () => {
    if (upstream.readyState === WebSocket.OPEN) upstream.close();
  });
}
