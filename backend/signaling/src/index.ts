import http from "node:http";
import cors from "cors";
import express from "express";
import { WebSocketServer } from "ws";
import { authRouter } from "./auth/routes.js";
import { config } from "./config.js";
import { contactsRouter } from "./contacts/routes.js";
import { migrate } from "./db/pool.js";
import { devicesRouter } from "./devices/routes.js";
import { attachClient } from "./handler.js";
import { proxyMedia } from "./media/proxy.js";
import { rooms } from "./rooms.js";

const app = express();
app.set("trust proxy", 1);
app.use(cors());
app.use(express.json({ limit: "1mb" }));

app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    orchestratorWs: config.orchestratorWs,
    db: Boolean(config.databaseUrl),
  });
});

app.use("/v1/auth", authRouter());
app.use("/api/auth", authRouter());
app.use("/v1/contacts", contactsRouter());
app.use("/v1/devices", devicesRouter());

app.get("/v1/users", (_req, res) => {
  res.json({ users: rooms.listPresence() });
});

const server = http.createServer(app);
const wss = new WebSocketServer({ noServer: true });

function track(ws: import("ws").WebSocket): void {
  const sock = ws as import("ws").WebSocket & { isAlive?: boolean };
  sock.isAlive = true;
  sock.on("pong", () => {
    sock.isAlive = true;
  });
}

setInterval(() => {
  for (const client of wss.clients) {
    const sock = client as import("ws").WebSocket & { isAlive?: boolean };
    if (sock.isAlive === false) {
      sock.terminate();
      continue;
    }
    sock.isAlive = false;
    sock.ping();
  }
}, 15_000).unref();

server.on("upgrade", (req, socket, head) => {
  const url = new URL(req.url ?? "/", "http://localhost");
  const forwarded = req.headers["x-forwarded-for"];
  const client =
    (typeof forwarded === "string" ? forwarded.split(",")[0].trim() : "") ||
    req.socket.remoteAddress ||
    "";
  if (url.pathname === "/v1/signal") {
    console.log(`[ws] signal from ${client}`);
    wss.handleUpgrade(req, socket, head, (ws) => {
      track(ws);
      attachClient(ws, req);
    });
    return;
  }
  if (url.pathname === "/v1/media") {
    console.log(`[ws] media from ${client}`);
    wss.handleUpgrade(req, socket, head, (ws) => {
      track(ws);
      proxyMedia(ws, req);
    });
    return;
  }
  socket.destroy();
});

async function main(): Promise<void> {
  try {
    await migrate();
  } catch (err) {
    console.warn("[db] migrate skipped — auth/contacts need Postgres", err);
  }
  server.listen(config.port, config.host, () => {
    console.log(`[signaling] ${config.host}:${config.port}  signal=/v1/signal  media=/v1/media`);
  });
}

main();
