# Azure setup

The orchestrator needs two Azure resources when `PIPELINE_PROVIDER=azure`:

| Resource | Used for | Settings it fills |
|----------|----------|-------------------|
| **Speech** | Speech to text (`azure_stt.py`) and neural text to speech (`azure_tts.py`) | `AZURE_SPEECH_KEY`, `AZURE_SPEECH_REGION` |
| **Translator** | Text translation (`azure_translate.py`) | `AZURE_TRANSLATOR_KEY`, `AZURE_TRANSLATOR_REGION`, `AZURE_TRANSLATOR_ENDPOINT` |

You don't need anything else from Azure: no storage, no App Service, no Azure OpenAI.

Put both resources in **Central India**. That's closest to the users and to Render's Singapore servers, and it is the region the code defaults to.

## 1. Resource group

1. Sign in at https://portal.azure.com.
2. Search **Resource groups** → **Create**.
3. Subscription: yours. Name: `translatelanguage`. Region: **Central India**.
4. **Review + create** → **Create**.

## 2. Speech

1. Search **Speech services** (under Azure AI services) → **Create**.
2. Resource group: `translatelanguage`.
3. Region: **Central India**.
4. Name: something unique, for example `translatelanguage-speech`.
5. Pricing tier: **Free F0** for testing (only one F0 Speech resource per subscription), or **Standard S0** for real calls. F0 limits audio hours and concurrent requests, so two people talking at once can hit them.
6. **Review + create** → **Create**, then **Go to resource**.
7. Open **Keys and Endpoint**. Copy **KEY 1** and note **Location/Region** (`centralindia`).

## 3. Translator

1. Search **Translators** (under Azure AI services) → **Create**.
2. Resource group: `translatelanguage`.
3. Region: **Central India**. Don't pick *Global*. The code sends the region header, and a regional key has to match it.
4. Name: for example `translatelanguage-translator`.
5. Pricing tier: **Free F0** for testing, **S1** for real use.
6. **Review + create** → **Create**, then **Go to resource**.
7. Open **Keys and Endpoint**. Copy **KEY 1** and note **Location/Region** (`centralindia`). Leave the endpoint as `https://api.cognitive.microsofttranslator.com`. The portal also shows a custom-domain endpoint, which you don't need.

## 4. Local server (this PC)

Edit `.env` in the repo root (never commit it):

```
PIPELINE_PROVIDER=azure
AZURE_SPEECH_KEY=<Speech KEY 1>
AZURE_SPEECH_REGION=centralindia
AZURE_TRANSLATOR_KEY=<Translator KEY 1>
AZURE_TRANSLATOR_REGION=centralindia
AZURE_TRANSLATOR_ENDPOINT=https://api.cognitive.microsofttranslator.com
```

Restart the orchestrator so it reads the new keys:

```bash
docker compose up -d orchestrator
```

Check it:

```bash
curl http://127.0.0.1:8090/health
```

It should report `"stt":"azure"`, `"translator":"azure"`, `"tts":"azure"`.

## 5. Hosted server (Render, for phones far apart)

1. Open https://dashboard.render.com, then the **translatelanguage-orchestrator** private service. If you deleted it, apply the blueprint again (**Blueprints** → this repo → **Sync**) so Render recreates it from `render.yaml`.
2. **Environment**: set `AZURE_SPEECH_KEY` and `AZURE_TRANSLATOR_KEY` to the new keys. Regions and endpoint already come from `render.yaml`.
3. Open the **translatelanguage** web service → **Environment**. Delete `ORCHESTRATOR_WS_URL` if it's there. Its value `ws://orchestrator:8090/v1/media` only works inside Docker on this PC. Without it, the server uses `ORCHESTRATOR_HOSTPORT` from the blueprint.
4. Click **Save, rebuild, and deploy** on both services.
5. Check `https://translatelanguage.onrender.com/health`. `orchestratorWs` should now show the Render private host, not `orchestrator:8090`.

## 6. Check the keys without the app

PowerShell, from the repo root. These print only HTTP status codes, never the keys:

```powershell
$speech = (Select-String '^AZURE_SPEECH_KEY=(.*)' .env).Matches[0].Groups[1].Value
$tr = (Select-String '^AZURE_TRANSLATOR_KEY=(.*)' .env).Matches[0].Groups[1].Value
(Invoke-WebRequest -Method Post -Uri https://centralindia.api.cognitive.microsoft.com/sts/v1.0/issueToken -Headers @{ 'Ocp-Apim-Subscription-Key' = $speech } -Body '').StatusCode
(Invoke-WebRequest -Method Post -Uri 'https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&to=hi' -Headers @{ 'Ocp-Apim-Subscription-Key' = $tr; 'Ocp-Apim-Subscription-Region' = 'centralindia' } -ContentType 'application/json' -Body '[{"Text":"hello"}]').StatusCode
```

Both should print `200`. A `401` means the key is wrong or the resource was deleted. A `401` only on Translator usually means the region doesn't match the resource.

## Keys and cost

- Each resource has KEY 1 and KEY 2. If a key leaks, regenerate it under **Keys and Endpoint**, then update `.env` and Render.
- To avoid surprise bills, set a budget in **Cost Management** → **Budgets** for the `translatelanguage` resource group.
- Deleting the resource group deletes both resources and their keys.
