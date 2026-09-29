"""Voice activity detection.

Default: Silero VAD (ONNX) — better Indic speech / noise rejection than
WebRTC VAD, native 16 kHz, 32 ms windows. Fallback: webrtcvad.

Silero is the endpointing clock. Sub-1 s latency lives or dies here:
cut after ~180 ms of silence, not 400–800 ms.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import structlog

from app.config import Settings

log = structlog.get_logger("vad")

SILERO_WINDOW = 512  # 32 ms @ 16 kHz (Silero v4/v5)
SILERO_ONNX_URL = (
    "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"
)


class EndpointingVad:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._frame_ms = settings.frame_ms
        self._silence_needed = max(1, settings.vad_silence_ms // settings.frame_ms)
        self._min_speech = max(1, settings.vad_min_speech_ms // settings.frame_ms)
        self._max_frames = max(1, settings.vad_max_utterance_ms // settings.frame_ms)
        self._threshold = settings.vad_threshold
        self._backend = settings.vad_backend
        self._silero: _SileroOnnx | None = None
        self._webrtc = None
        if settings.vad_backend == "silero":
            try:
                self._silero = _SileroOnnx(settings)
            except Exception as exc:  # noqa: BLE001
                log.warning("silero.unavailable", error=str(exc), fallback="webrtc")
                self._backend = "webrtc"
        if self._backend == "webrtc":
            import webrtcvad

            self._webrtc = webrtcvad.Vad(settings.vad_aggressiveness)
        self.reset()

    def reset(self) -> None:
        self._in_speech = False
        self._silence_run = 0
        self._speech_frames = 0
        self._buffer = bytearray()
        self._pcm_window = bytearray()
        if self._silero:
            self._silero.reset()

    def push(self, pcm: bytes) -> tuple[bool, bool, bytes | None]:
        """Returns (speech_started, utterance_ended, utterance_pcm_or_None)."""
        if len(pcm) < 2:
            return False, False, None

        voiced = self._is_voiced(pcm)
        self._buffer.extend(pcm)
        started = False

        if voiced:
            if not self._in_speech:
                started = True
            self._in_speech = True
            self._silence_run = 0
            self._speech_frames += 1
        elif self._in_speech:
            self._silence_run += 1

        ended = False
        if (
            self._in_speech
            and self._speech_frames >= self._min_speech
            and self._silence_run >= self._silence_needed
        ):
            ended = True
        if self._speech_frames >= self._max_frames:
            ended = True

        if not ended:
            return started, False, None

        utterance = bytes(self._buffer)
        self.reset()
        return started, True, utterance

    def _is_voiced(self, pcm: bytes) -> bool:
        if self._silero is not None:
            self._pcm_window.extend(pcm)
            need = SILERO_WINDOW * 2
            if len(self._pcm_window) < need:
                return self._in_speech
            window = bytes(self._pcm_window[-need:])
            self._pcm_window = bytearray(window)
            return self._silero.prob(window) >= self._threshold
        assert self._webrtc is not None
        try:
            return bool(self._webrtc.is_speech(pcm, self._settings.sample_rate_hz))
        except Exception:
            return False


class _SileroOnnx:
    def __init__(self, settings: Settings) -> None:
        import onnxruntime as ort

        path = Path(settings.silero_onnx_path)
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            _download(SILERO_ONNX_URL, path)
        opts = ort.SessionOptions()
        opts.inter_op_num_threads = 1
        opts.intra_op_num_threads = 1
        self._session = ort.InferenceSession(str(path), opts, providers=["CPUExecutionProvider"])
        self._inputs = [i.name for i in self._session.get_inputs()]
        self._sr = np.array(settings.sample_rate_hz, dtype=np.int64)
        self.reset()

    def reset(self) -> None:
        # v4: h,c (2,1,64)  |  v5: state (2,1,128)
        if "state" in self._inputs:
            self._state = np.zeros((2, 1, 128), dtype=np.float32)
            self._h = self._c = None
        else:
            self._h = np.zeros((2, 1, 64), dtype=np.float32)
            self._c = np.zeros((2, 1, 64), dtype=np.float32)
            self._state = None

    def prob(self, pcm16: bytes) -> float:
        audio = np.frombuffer(pcm16, dtype=np.int16).astype(np.float32) / 32768.0
        if audio.size < SILERO_WINDOW:
            audio = np.pad(audio, (0, SILERO_WINDOW - audio.size))
        audio = audio[:SILERO_WINDOW].reshape(1, -1)
        if self._state is not None:
            out, self._state = self._session.run(
                None, {"input": audio, "state": self._state, "sr": self._sr}
            )[:2]
        else:
            out, self._h, self._c = self._session.run(
                None, {"input": audio, "h": self._h, "c": self._c, "sr": self._sr}
            )[:3]
        return float(out.squeeze())


def _download(url: str, dest: Path) -> None:
    import urllib.request

    log.info("silero.download", url=url, dest=str(dest))
    urllib.request.urlretrieve(url, dest)
