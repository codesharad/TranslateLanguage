# Third-party components

These packages are used by the app and are **not** part of the work being registered. Each keeps its own
licence. The licence names below are from memory and must be checked against each package before you
rely on them (open the package page on pub.dev, npm or PyPI).

## Mobile app (Flutter, `mobile/pubspec.yaml`)
| Package | Licence (verify) |
|---|---|
| Flutter SDK | BSD-3-Clause |
| cupertino_icons | MIT |
| flutter_webrtc | MIT |
| flutter_callkit_incoming | MIT |
| web_socket_channel | BSD-3-Clause |
| permission_handler | MIT |
| record | MIT |
| uuid | MIT |
| provider | MIT |
| google_fonts | Apache-2.0 |
| wakelock_plus | BSD-3-Clause |
| http | BSD-3-Clause |
| shared_preferences | BSD-3-Clause |
| flutter_contacts | MIT |

## Signalling server (Node.js, `backend/signaling/package.json`)
| Package | Licence (verify) |
|---|---|
| cors, express, jsonwebtoken, pg, uuid, ws, zod | MIT |
| typescript, tsx (development only) | Apache-2.0 / MIT |

## Media orchestrator (Python, `backend/orchestrator/requirements.txt`)
| Package | Licence (verify) |
|---|---|
| fastapi, pydantic, pydantic-settings, h2, webrtcvad, onnxruntime | MIT |
| uvicorn, websockets, numpy, httpx, protobuf, python-dotenv | BSD-3-Clause |
| soxr | LGPL-2.1 (check how it is linked and whether this matters for you) |
| orjson, structlog | Apache-2.0 or MIT |
| google-cloud-speech, google-cloud-translate, google-cloud-texttospeech | Apache-2.0 |
| azure-cognitiveservices-speech | Microsoft licence terms (not open source) |

## Models and services
- Silero VAD voice-activity model: MIT (verify, and check whether the model file is stored in the repository).
- Microsoft Azure Speech and Translator, and optionally Google Cloud, Sarvam AI, OpenAI and Anthropic APIs:
  used as paid services under their own terms. No service code is copied into this project.

## Not code
- Neural voices are produced by Azure at run time and are not stored in the repository.
- The test clips used in `docs/paper-results` were produced by Azure voices; check Azure's terms before
  redistributing audio.
