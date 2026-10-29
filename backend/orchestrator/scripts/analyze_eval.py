"""Turn the JSON files written by eval_pipeline.py into the numbers and figures of the paper.

    python analyze_eval.py <results_dir> <out_dir>

<results_dir> holds clips.json, recog_run1.json, recog.json (run 2), mt.json, e2e.json,
switch.json, echo.json and a clips/ folder with the raw PCM. Writes numbers.json and fig_*.png.
"""

from __future__ import annotations

import array
import json
import math
import random
import statistics as st
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

RES, OUT = sys.argv[1].rstrip("/") + "/", sys.argv[2].rstrip("/") + "/"
random.seed(1)
LANGS = ["en-IN", "hi-IN", "mr-IN", "ta-IN"]
MODES = ["fixed", "pinned", "pinned_filled", "catalog"]
MODE_LABEL = {"fixed": "Fixed language", "pinned": "Detect: 2 call languages",
              "pinned_filled": "Detect: 2 pinned + fill to 10", "catalog": "Detect: 10, catalog order"}


def jload(name):
    with open(RES + name, encoding="utf-8") as fh:
        return json.load(fh)


def pct(v, q):
    s = sorted(v)
    k = (len(s) - 1) * q
    lo, hi = int(k), min(int(k) + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def boot(vals, n=4000):
    ms = sorted(st.fmean(random.choices(vals, k=len(vals))) for _ in range(n))
    return ms[int(0.025 * n)], ms[int(0.975 * n)]


plt.rcParams.update({"font.size": 6.5, "axes.linewidth": 0.5, "font.family": "serif",
                     "xtick.major.width": 0.5, "ytick.major.width": 0.5})
COL = ["#2b6cb0", "#dd8a2f", "#3b9b6a", "#8a6bb8"]
HATCH = ["", "//", "..", "xx"]
num: dict = {}

# ── recognition ──
runs = {1: jload("recog_run1.json"), 2: jload("recog.json")}
rec: dict = {}
for mode in MODES:
    rec[mode] = {}
    for r, rows in runs.items():
        g = [x for x in rows if x["mode"] == mode]
        la = [x for x in g if x["lang_ok"] is not None]
        rec[mode][r] = {
            "wer": 100 * st.fmean(x["wer"] for x in g), "cer": 100 * st.fmean(x["cer"] for x in g),
            "lang_ok": sum(x["lang_ok"] for x in la) if la else None, "lang_n": len(la),
            "empty": sum(1 for x in g if not x["hyp"].strip()), "n": len(g),
            "by_lang": {l: 100 * st.fmean(x["wer"] for x in g if x["lang"] == l) for l in LANGS},
            "lang_by_lang": {l: (sum(x["lang_ok"] for x in la if x["lang"] == l),
                                 len([x for x in la if x["lang"] == l])) for l in LANGS} if la else None,
        }
num["recog"] = rec
key = lambda x: (x["mode"], x["lang"], x["idx"])  # noqa: E731
d2 = {key(x): x["wer"] for x in runs[2]}
d1 = {key(x): x["wer"] for x in runs[1]}
pair = {}
for m in ("pinned", "pinned_filled", "catalog"):
    diffs = [50 * ((d1[(m, l, i)] - d1[("fixed", l, i)]) + (d2[(m, l, i)] - d2[("fixed", l, i)]))
             for l in LANGS for i in range(10)]
    lo, hi = boot(diffs)
    pair[m] = {"mean": st.fmean(diffs), "lo": lo, "hi": hi}
num["recog_paired_vs_fixed"] = pair
num["recog_identical"] = {m: sum(1 for x in runs[1] if x["mode"] == m and
                                 any(key(x) == key(y) and x["hyp"] == y["hyp"] for y in runs[2]))
                          for m in MODES}
clips = jload("clips.json")
secs = [c["seconds"] for l in clips for c in clips[l]]
num["clips"] = {"n": len(secs), "min": min(secs), "max": max(secs), "mean": st.fmean(secs)}

# figure 2: WER per language and condition (mean of the two runs, bar = range)
fig, ax = plt.subplots(figsize=(3.4, 1.7))
groups = LANGS + ["all"]
w = 0.2
for k, mode in enumerate(MODES):
    means, lows, highs = [], [], []
    for gname in groups:
        vals = [(rec[mode][r]["by_lang"][gname] if gname != "all" else rec[mode][r]["wer"]) for r in (1, 2)]
        means.append(st.fmean(vals))
        lows.append(st.fmean(vals) - min(vals))
        highs.append(max(vals) - st.fmean(vals))
    xs = [i + (k - 1.5) * w for i in range(len(groups))]
    ax.bar(xs, means, w, yerr=[lows, highs], color=COL[k], hatch=HATCH[k], edgecolor="black",
           linewidth=0.4, error_kw={"linewidth": 0.5, "capsize": 1}, label=MODE_LABEL[mode])
ax.set_xticks(range(len(groups)))
ax.set_xticklabels(["English", "Hindi", "Marathi", "Tamil", "All"])
ax.set_ylabel("Word error rate (%)")
ax.legend(fontsize=5.2, frameon=False, loc="upper left")
ax.set_ylim(0, 100)
ax.spines[["top", "right"]].set_visible(False)
fig.tight_layout(pad=0.3)
fig.savefig(OUT + "fig_recog.png", dpi=300)
plt.close(fig)

# ── translation ──
mt = jload("mt.json")
fw = [x for x in mt if x["kind"] == "forward" and x["variant"] == "with_retry"]
num["mt"] = {"by_lang": {}, "n": len(fw), "median_ms": st.median(x["ms"] for x in fw),
             "mean_ms": st.fmean(x["ms"] for x in fw), "p95_ms": pct([x["ms"] for x in fw], 0.95)}
for l in ["hi-IN", "ta-IN", "te-IN", "ml-IN", "gu-IN", "mr-IN", "bn-IN"]:
    g = [x for x in fw if x["lang"] == l]
    num["mt"]["by_lang"][l] = {"script": 100 * st.fmean(x["script_share"] for x in g),
                               "chrf": st.fmean(x["roundtrip_chrf"] for x in g),
                               "ms": st.median(x["ms"] for x in g)}
num["mt"]["latin_heavy_forward"] = sum(x["latin_heavy"] for x in mt if x["kind"] == "forward")
num["mt"]["forward_total"] = sum(1 for x in mt if x["kind"] == "forward")
ro = [x for x in mt if x["kind"] == "romanized"]
num["mt"]["romanized_total"] = len([x for x in ro if x["variant"] == "no_retry"])
num["mt"]["romanized_latin_heavy"] = sum(x["latin_heavy"] for x in ro)
num["mt"]["romanized_script_min"] = 100 * min(x["script_share"] for x in ro)

# ── end-to-end latency ──
e2e = jload("e2e.json")


def trail_ms(lang, i):
    a = array.array("h")
    with open(f"{RES}clips/{lang}_{i}.pcm", "rb") as fh:
        a.frombytes(fh.read())
    rms = [math.sqrt(sum(v * v for v in a[k:k + 320]) / 320) for k in range(0, len(a) - 319, 320)]
    last = max(k for k, v in enumerate(rms) if v > max(rms) * 0.03)
    return (len(rms) - 1 - last) * 20


rows = []
for x in e2e:
    if x.get("error"):
        continue
    tr = trail_ms(x["src"], x["idx"])
    s = x["server_stages"] or {}
    rows.append({
        "conc": x["concurrency"], "trail": tr, "src": x["src"], "dst": x["dst"],
        "sf": x["stt_final_ms"] + tr, "fa": x["first_audio_ms"] + tr,
        "mt": s["mt_done"] - s["stt_final"], "tts": s["tts_first_byte"] - s["mt_done"],
        "audio_s": x["audio_seconds"], "seconds": x["seconds"],
    })
lat: dict = {"trail_median": st.median(r["trail"] for r in rows), "n_total": len(rows)}
for conc in (1, 3):
    g = [r for r in rows if r["conc"] == conc]
    late = [r for r in g if r["fa"] >= 0]
    lat[conc] = {"n": len(g), "n_late": len(late)}
    for k, src in (("sf", g), ("mt", g), ("tts", g), ("fa", late)):
        v = [r[k] for r in src]
        lat[conc][k] = {"median": st.median(v), "p95": pct(v, 0.95), "min": min(v), "max": max(v)}
    # translated audio completeness: heard length vs spoken length is not comparable across
    # languages, so only report that every run produced audio
    lat[conc]["audio_ok"] = sum(1 for r in g if r["audio_s"] > 0.5)
num["lat"] = lat

fig, ax = plt.subplots(figsize=(3.4, 1.65))
budget = [("Recognition", 330), ("Translation", 80), ("First voice byte", 150)]
meas = [lat[1]["sf"]["median"], lat[1]["mt"]["median"], lat[1]["tts"]["median"]]
colors = ["#9ec1e6", "#f2c38b", "#9fd3b4"]
for row, vals in enumerate(([b[1] for b in budget], meas)):
    left = 0
    for k, v in enumerate(vals):
        ax.barh(row, v, left=left, color=colors[k], edgecolor="black", linewidth=0.4,
                label=budget[k][0] if row == 0 else None)
        ax.text(left + v / 2, row, f"{v:.0f}", ha="center", va="center", fontsize=5.5)
        left += v
    ax.text(left + 25, row, f"total {left:.0f} ms", va="center", fontsize=6)
ax.set_yticks([0, 1])
ax.set_yticklabels(["Budget (Table I)", "Measured (median)"], fontsize=5.8)
ax.set_xlabel("Milliseconds after the end of speech")
ax.set_xlim(0, 1900)
ax.invert_yaxis()
ax.legend(fontsize=5, frameon=False, loc="upper center", bbox_to_anchor=(0.4, -0.38), ncol=3, columnspacing=0.8, handlelength=1.2)
ax.spines[["top", "right"]].set_visible(False)
fig.tight_layout(pad=0.3)
fig.savefig(OUT + "fig_latency.png", dpi=300)
plt.close(fig)

# ── language switch ──
sw = [x for x in jload("switch.json") if not x.get("error")]
num["switch"] = {}
for label, cond in (("switch_0.3", (0.3, True)), ("switch_1.0", (1.0, True)), ("none", (1.0, False))):
    g = [x for x in sw if (x["gap_s"], x["switched"]) == cond]
    num["switch"][label] = {
        "n": len(g), "wer": 100 * st.fmean(x["wer"] for x in g), "cer": 100 * st.fmean(x["cer"] for x in g),
        "exact": sum(1 for x in g if x["wer"] == 0),
        "by_pair": {f'{p}->{q}': 100 * st.fmean(x["wer"] for x in g if (x["first"], x["second"]) == (p, q))
                    for p, q in (("hi-IN", "en-IN"), ("en-IN", "mr-IN"))},
    }

# ── echo guard ──
echo = jload("echo.json")
num["echo"] = echo
fig, ax = plt.subplots(figsize=(3.4, 1.4))
labels = [f'{r["lang"][:2]} {r["audio_s"]:.1f} s' for r in echo]
xs = range(len(echo))
ax.bar([i - 0.2 for i in xs], [100 * r["old_coverage"] for r in echo], 0.38, color=COL[1], hatch="//",
       edgecolor="black", linewidth=0.4, label="Per-chunk gate")
ax.bar([i + 0.2 for i in xs], [100 * r["new_coverage"] for r in echo], 0.38, color=COL[2], hatch="..",
       edgecolor="black", linewidth=0.4, label="Queue-length gate")
ax.set_xticks(list(xs))
ax.set_xticklabels(labels, fontsize=5.5)
ax.set_ylabel("Playback covered (%)")
ax.set_ylim(0, 118)
ax.legend(fontsize=5.5, frameon=False, ncol=2, loc="upper left")
ax.spines[["top", "right"]].set_visible(False)
fig.tight_layout(pad=0.3)
fig.savefig(OUT + "fig_echo.png", dpi=300)
plt.close(fig)

with open(OUT + "numbers.json", "w", encoding="utf-8") as fh:
    json.dump(num, fh, indent=1, ensure_ascii=False)
print("ok")
