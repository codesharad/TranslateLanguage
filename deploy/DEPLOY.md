# Always-on backend (HTTPS + wss)

The phones must reach a public host. A laptop on your home Wi-Fi stops working as soon as either side changes network. This stack runs the same Docker services on a small Linux server and puts Caddy in front for a free Let's Encrypt certificate. Signaling and the media socket both stay on `https://YOUR_DOMAIN` (`/v1/signal` and `/v1/media`).

Free web hosts that sleep (Render's free instance) will drop live calls. Use a host that stays up: Render Starter, Railway with an always-on service, or a $4–6/month VPS.

## Render (GitHub)

The public service is the Node signaling server. Phones open `wss://translatelanguage.onrender.com/v1/signal` and `wss://translatelanguage.onrender.com/v1/media`. The Python speech service stays on Render's private network. Both bind `process.env.PORT` / `os.environ["PORT"]` and trust `x-forwarded-for` from Render's proxy. `GET /health` is the uptime check.

Do not put API keys in git. Render marks `sync: false` secrets as dashboard-only.

1. Push this repo to GitHub.
2. In the [Render dashboard](https://dashboard.render.com), choose **New** → **Blueprint** and select the repo. Render reads `render.yaml`.
3. When it asks for secrets, paste them into the dashboard fields. They stay on Render, not in the repository:
   - `AZURE_SPEECH_KEY` and `AZURE_TRANSLATOR_KEY` on the orchestrator
   - `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, and `TWILIO_VERIFY_SERVICE_SID` on the web service
   - `JWT_SECRET` is generated for you
4. Wait until both services are live. Open `https://translatelanguage.onrender.com/health`. It should return `"status":"ok"`. If the name `translatelanguage` is taken, use the hostname Render shows and put that same host in `PUBLIC_BASE_URL`.
5. On each phone, open the app, enter that host in **Cloud host** (no `https://`), and turn on **Internet server**. The sockets become `wss://` on port 443. Turn the switch off to go back to the USB connection on this PC.

If the orchestrator restarts with an out-of-memory error, change its plan to Standard (2 GB). A sleeping free instance cannot keep a call open.

## 1. Server

- Ubuntu 22.04 or 24.04
- Docker Engine and the Docker Compose plugin
- A DNS `A` record for `api.example.com` pointing at the server's public IP
- Ports 80 and 443 open

## 2. Start it

On the server:

```bash
git clone <your-repo> TranslateLanguage
cd TranslateLanguage/deploy
cp .env.example .env
# edit DOMAIN, POSTGRES_PASSWORD, JWT_SECRET
docker compose -f compose.prod.yml --env-file .env up -d --build
curl -fsS https://$DOMAIN/health
```

`/health` should return `"status":"ok"`.

## 3. Point the phones at it

From `mobile/` on your PC, with the phones plugged in:

```bash
flutter build apk --release --dart-define=API_HOST=api.example.com --dart-define=API_TLS=true
adb -s <device> install -r build/app/outputs/flutter-apk/app-release.apk
```

`API_TLS=true` uses `https://` and `wss://` on port 443. No USB reverse and no laptop process are required after this.

Set `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, and `TWILIO_VERIFY_SERVICE_SID`. In the Twilio Verify service, use a 6-digit code and a 5-minute expiration.

## What reconnects by itself

The app retries signaling and the media socket with backoff (1s, 2s, 4s, 8s, 16s, then 20s) and sends a ping every 10 seconds. A short signal drop resumes the same call. It cannot survive the server process being asleep or powered off.
