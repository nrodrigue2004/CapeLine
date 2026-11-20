# dsp.py: the small sound kit art/audio/build.py and music.py mix with (numpy and scipy only, mono 44.1 kHz floats).
# Sources are decoded with ffmpeg; everything else (filters, pitch, synth layers, reverb, loudness) is here.
import os
import subprocess

import numpy as np
from scipy import signal

SR = 44100
_cache = {}
MISSING = set()
ROOT = ""  # the download root (set by build.py from its argument)


def secs(n):
    return n / SR


def load(rel):
    """A source file (path under the download root) as mono floats at 44.1 kHz."""
    if rel in _cache:
        return _cache[rel]
    path = os.path.join(ROOT, rel)
    if not os.path.isfile(path):
        MISSING.add(rel)
        return np.zeros(441)
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(out, dtype=np.float32).astype(np.float64)
    _cache[rel] = x
    return x


def rate(x, r):
    """Varispeed: r > 1 is higher and shorter, r < 1 lower and longer (tape style, keeps the transient)."""
    if abs(r - 1) < 1e-4 or len(x) < 4:
        return x
    from fractions import Fraction
    f = Fraction(r).limit_denominator(64)
    return signal.resample_poly(x, f.denominator, f.numerator)


def hp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, "highpass", fs=SR, output="sos"), x) if f else x


def lp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, min(f, SR / 2 - 100), "lowpass", fs=SR, output="sos"), x) if f else x


def bp(x, lo, hi, order=2):
    return signal.sosfilt(signal.butter(order, [lo, min(hi, SR / 2 - 100)], "bandpass", fs=SR, output="sos"), x)


def peak_eq(x, f, gain_db, q=1.0):
    """A bell boost or cut (RBJ cookbook)."""
    a = 10 ** (gain_db / 40)
    w = 2 * np.pi * f / SR
    al = np.sin(w) / (2 * q)
    b = [1 + al * a, -2 * np.cos(w), 1 - al * a]
    aa = [1 + al / a, -2 * np.cos(w), 1 - al / a]
    return signal.lfilter(np.array(b) / aa[0], np.array(aa) / aa[0], x)


def db(g):
    return 10 ** (g / 20)


def fade(x, fi=0.002, fo=0.02):
    x = x.copy()
    a, b = int(fi * SR), int(fo * SR)
    if a > 0 and len(x) > a:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0 and len(x) > b:
        x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def cut(x, start=0.0, dur=None):
    a = int(start * SR)
    b = len(x) if dur is None else min(len(x), a + int(dur * SR))
    return x[a:b]


def sat(x, drive=1.5):
    """Soft saturation for weight (tanh, gain kept)."""
    return np.tanh(x * drive) / np.tanh(drive)


def env_exp(n, decay):
    t = np.arange(n) / SR
    return np.exp(-t / max(decay, 1e-4))


def adsr(n, a=0.005, d=0.1, s=0.6, r=0.2):
    e = np.ones(n) * s
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = min(na, n)
    e[:na] = np.linspace(0, 1, na) if na else e[:na]
    nd = min(nd, max(0, n - na))
    e[na:na + nd] = np.linspace(1, s, nd)
    if nr and n > nr:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


rng = np.random.default_rng(7)


def noise(dur, kind="white"):
    n = int(dur * SR)
    w = rng.standard_normal(n)
    if kind == "pink":
        f = np.fft.rfft(w)
        k = np.arange(len(f))
        k[0] = 1
        w = np.fft.irfft(f / np.sqrt(k), n)
    elif kind == "brown":
        w = np.cumsum(w)
        w = hp(w, 15)
    return w / (np.max(np.abs(w)) + 1e-9)


def sweep_sine(dur, f0, f1, curve=4.0, shape="sine"):
    """A tone whose pitch glides f0 -> f1 (exponential)."""
    n = int(dur * SR)
    t = np.linspace(0, 1, n)
    f = f1 + (f0 - f1) * np.exp(-t * curve) if curve > 0 else f0 + (f1 - f0) * t
    ph = 2 * np.pi * np.cumsum(f) / SR
    if shape == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1) - 1
    if shape == "square":
        return np.sign(np.sin(ph))
    if shape == "tri":
        return 2 * np.abs(2 * ((ph / (2 * np.pi)) % 1) - 1) - 1
    return np.sin(ph)


def thump(f0=110, f1=42, dur=0.35, decay=0.12, click=0.4, drive=2.0):
    """The low body under a hit: a pitch-dropping sine, a click on top, saturated."""
    n = int(dur * SR)
    x = sweep_sine(dur, f0, f1, curve=18) * env_exp(n, decay)
    c = hp(noise(0.012), 1500) * env_exp(int(0.012 * SR), 0.003) * click
    x[:len(c)] += c
    return sat(x, drive)


def rumble(dur=2.5, cutoff=140, attack=0.05, decay=1.0, kind="brown"):
    n = int(dur * SR)
    x = lp(noise(dur, kind), cutoff, 4)
    e = np.minimum(1, np.arange(n) / max(1, attack * SR)) * env_exp(n, decay)
    return x / (np.max(np.abs(x)) + 1e-9) * e


def whoosh(dur=0.5, f0=400, f1=2500, peak=0.5, q=1.2, kind="pink"):
    """Air: band-passed noise whose centre sweeps f0 -> f1, swelling to `peak` (0..1 of the length)."""
    n = int(dur * SR)
    x = noise(dur, kind)
    hop = 256
    out = np.zeros(n)
    win = np.hanning(hop * 2)
    for i in range(0, n - hop * 2, hop):
        t = i / n
        fc = f0 * (f1 / f0) ** t
        bw = fc / q
        seg = x[i:i + hop * 2] * win
        sos = signal.butter(2, [max(30, fc - bw / 2), min(SR / 2 - 200, fc + bw / 2)], "bandpass", fs=SR, output="sos")
        out[i:i + hop * 2] += signal.sosfilt(sos, seg)
    t = np.linspace(0, 1, n)
    e = np.where(t < peak, (t / peak) ** 1.6, ((1 - t) / (1 - peak)) ** 1.3)
    return out / (np.max(np.abs(out)) + 1e-9) * e


def bell(freq=880, dur=1.2, decay=0.45, partials=((1, 1), (2.0, 0.5), (2.76, 0.35), (5.4, 0.18), (8.93, 0.08)), bright=1.0):
    """A struck bell / chime: inharmonic partials, the high ones dying faster."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for ratio, amp in partials:
        x += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t / (decay / (ratio ** 0.5 * bright)))
    a = int(0.002 * SR)
    x[:a] *= np.linspace(0, 1, a)
    return x / (np.max(np.abs(x)) + 1e-9)


def chord(freqs, dur=1.2, decay=0.6, gap=0.0, **kw):
    """Bells struck in turn `gap` seconds apart (an arpeggio when gap > 0)."""
    n = int((dur + gap * len(freqs)) * SR)
    x = np.zeros(n)
    for i, f in enumerate(freqs):
        b = bell(f, dur, decay, **kw)
        o = int(i * gap * SR)
        x[o:o + len(b)] += b
    return x / (np.max(np.abs(x)) + 1e-9)


def horn(freq=110, dur=1.5, shape="saw", cutoff=900, vib=0.0, detune=0.004, a=0.06, r=0.4):
    """A brass-like horn (detuned saws through a low-pass): stings, the foghorn, the boss horn."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    v = 1 + vib * np.sin(2 * np.pi * 5.2 * t)
    x = np.zeros(n)
    for d in (-detune, 0, detune):
        ph = 2 * np.pi * np.cumsum(freq * (1 + d) * v) / SR
        x += (2 * ((ph / (2 * np.pi)) % 1) - 1) if shape == "saw" else np.sign(np.sin(ph))
    x = lp(x, cutoff, 2)
    x = x * adsr(n, a, 0.15, 0.85, r)
    return x / (np.max(np.abs(x)) + 1e-9)


def siren(dur=6.0, lo=650, hi=1350, period=2.6, kind="wail"):
    n = int(dur * SR)
    t = np.arange(n) / SR
    if kind == "wail":
        f = lo + (hi - lo) * (0.5 - 0.5 * np.cos(2 * np.pi * t / period))
    else:  # yelp
        f = lo + (hi - lo) * ((t / period * 6) % 1)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph)
    return x / np.max(np.abs(x))


def reverb(x, t60=1.2, mix=0.25, lowcut=6000, pre=0.012):
    """A plain convolution room: decaying noise IR, darker as it goes."""
    n = int(t60 * SR)
    ir = rng.standard_normal(n) * np.exp(-6.9 * np.arange(n) / n)
    ir = lp(ir, lowcut, 2)
    ir = np.concatenate([np.zeros(int(pre * SR)), ir])
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    wet = signal.fftconvolve(x, ir)[: len(x) + len(ir)]
    dry = np.concatenate([x, np.zeros(len(wet) - len(x))])
    return dry * (1 - mix) + wet * mix * 1.2


def place(layers):
    """Mix (array, at_seconds) pairs into one array."""
    n = max(int(at * SR) + len(a) for a, at in layers)
    out = np.zeros(n)
    for a, at in layers:
        o = int(at * SR)
        out[o:o + len(a)] += a
    return out


def short_rms_db(x, win=0.05):
    w = int(win * SR)
    if len(x) < w:
        return 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)
    cs = np.concatenate([[0.0], np.cumsum(x ** 2)])
    c = (cs[w:] - cs[:-w]) / w
    return 10 * np.log10(np.max(c) + 1e-12)


def limit(x, ceiling=0.85):
    """A soft knee limiter: below 0.7 of the ceiling untouched, above it eased in with tanh."""
    k = 0.7 * ceiling
    y = x.copy()
    m = np.abs(y) > k
    y[m] = np.sign(y[m]) * (k + (ceiling - k) * np.tanh((np.abs(y[m]) - k) / (ceiling - k)))
    return y


def finish(x, target=-12.0, tail_db=-58, max_len=None):
    """Loudness (the loudest 50 ms at `target` dBFS), a soft limit, the silent tail trimmed."""
    x = hp(x, 25)
    g = target - short_rms_db(x)
    x = limit(x * db(g))
    thr = db(tail_db)
    idx = np.where(np.abs(x) > thr)[0]
    if len(idx):
        x = x[: min(len(x), idx[-1] + int(0.02 * SR))]
    # no dead air in front: a sound starts the frame its action does
    lead = np.where(np.abs(x) > np.max(np.abs(x)) * db(-36))[0]
    if len(lead) and lead[0] > int(0.004 * SR):
        x = x[lead[0] - int(0.002 * SR):]
    if max_len:
        x = x[: int(max_len * SR)]
    return fade(x, 0.001, min(0.04, len(x) / SR / 4))


def seamless(x, xf=0.5):
    """A loop with no click: the tail cross-faded into the head (length shrinks by xf)."""
    n = int(xf * SR)
    head, body, tail = x[:n], x[n:-n] if n else x, x[-n:]
    t = np.linspace(0, 1, n)
    mixed = tail * np.cos(t * np.pi / 2) + head * np.sin(t * np.pi / 2)
    return np.concatenate([body, mixed]) if n else x


def write_ogg(x, path, quality=5):
    pcm = np.clip(x, -1, 1).astype(np.float32).tobytes()
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", str(quality), path], input=pcm, check=True)
