# preview.py: a look at every clip in the sound atlases (art/preview/sounds.png): one tile per clip with its
# spectrogram (low at the bottom, log frequency) and waveform, its loudness and peak, flagged red when it is
# silent, clipped or far off its group's level. Also checks each clip decodes from the encoded .ogg at its region
# (what Roblox will play), so a bad region or an empty clip shows here, not in Studio.
#   python3 -I art/audio/preview.py [Atlas]   (one atlas: bigger tiles in art/preview/sounds_<Atlas>.png)
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
AUD = os.path.join(REPO, "art", "export", "audio")
SR = 44100
TW, TH = 220, 92


def decode(path):
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype=np.float32).astype(np.float64)


def spec_img(x, w, h):
    n = 1024
    hop = max(64, (len(x) - n) // w + 1) if len(x) > n else 64
    frames = [x[i:i + n] * np.hanning(n) for i in range(0, max(1, len(x) - n), hop)][:w] or [np.zeros(n)]
    S = np.abs(np.fft.rfft(np.array(frames), axis=1)) / (n / 4) + 1e-9
    f = np.fft.rfftfreq(n, 1 / SR)
    bins = np.geomspace(30, 16000, h + 1)
    out = np.zeros((h, len(frames)))
    for j in range(h):
        m = (f >= bins[j]) & (f < bins[j + 1])
        out[h - 1 - j] = 20 * np.log10(S[:, m].mean(1) if m.any() else S[:, np.argmin(np.abs(f - bins[j]))])
    out = np.clip((out + 80) / 70, 0, 1)
    rgb = np.stack([out ** 0.8 * 255, out ** 1.6 * 230, (1 - out) * 80 + out ** 3 * 255], -1).astype(np.uint8)
    return Image.fromarray(rgb).resize((w, h))


def main():
    global TW, TH
    meta = json.load(open(os.path.join(AUD, "clips.json")))
    only = sys.argv[1] if len(sys.argv) > 1 else None
    if only:
        meta = {only: meta[only]}
        TW, TH = 520, 96
    tiles, report = [], []
    for atlas in meta:
        y = decode(os.path.join(AUD, atlas + ".ogg"))
        for name, (s, n, loop) in meta[atlas].items():
            a, b = int(s * SR), int((s + n) * SR)
            x = y[a:b]
            pk = 20 * np.log10(np.max(np.abs(x)) + 1e-9)
            w = 2205
            cs = np.concatenate([[0.0], np.cumsum(x ** 2)])
            st = 10 * np.log10(np.max((cs[w:] - cs[:-w]) / w) + 1e-12) if len(x) > w else -99
            bad = []
            if st < -40:
                bad.append("SILENT")
            if pk > -0.05:
                bad.append("CLIP")
            if len(x) < 0.03 * SR:
                bad.append("SHORT")
            report.append((atlas, name, n, st, pk, bad))
            tile = Image.new("RGB", (TW, TH), (20, 22, 28))
            tile.paste(spec_img(x, TW, 52), (0, 0))
            d = ImageDraw.Draw(tile)
            env = np.abs(x)
            k = max(1, len(env) // TW)
            env = env[: k * TW].reshape(-1, k).max(1) if len(env) >= TW else env
            for i, v in enumerate(env[:TW]):
                hgt = int(v * 18)
                d.line([(i, 72 - hgt), (i, 72 + hgt)], fill=(120, 200, 255))
            col = (255, 90, 90) if bad else (230, 230, 230)
            d.text((3, 2), "%s/%s" % (atlas, name), fill=col)
            d.text((3, 80), "%.2fs  %.0f dB  pk %.1f%s%s" % (n, st, pk, "  LOOP" if loop else "", "  " + " ".join(bad) if bad else ""),
                   fill=col)
            tiles.append(tile)
    cols = 2 if only else 8
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (TW + 4), rows * (TH + 4)), (8, 8, 12))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % cols) * (TW + 4), (i // cols) * (TH + 4)))
    os.makedirs(os.path.join(REPO, "art", "preview"), exist_ok=True)
    sheet.save(os.path.join(REPO, "art", "preview", "sounds_%s.png" % only if only else "sounds.png"))
    flagged = [r for r in report if r[5]]
    print("preview.py: %d clips, %d flagged" % (len(report), len(flagged)))
    for r in flagged:
        print("  %s/%s %.2fs %.1f dB pk %.1f %s" % r[:5] + (r[5],) if False else "  %s/%s %.2fs %.1f dB pk %.1f %s" % (r[0], r[1], r[2], r[3], r[4], r[5]))
    return 1 if flagged else 0


sys.exit(main())
