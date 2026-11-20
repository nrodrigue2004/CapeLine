# music.py: Capeline's own music (composed here, so licence-clean: the only samples are Meta's CC0 piano, the rest is
# synth from dsp.py): the three loops of the spec (city patrol by day and by night, the boss theme), the victory
# sting and the context loops (combat, mission, chase, ceremony, deep, hq; first-30 2026-11-20), as one stereo atlas art/export/audio/Music.ogg + art/export/audio/music.json ({track: [start, length, loop]}).
# Each loop is a whole number of bars with its reverb tail wrapped onto its head, so it loops with no seam.
#   python3 -I art/audio/music.py <download root>
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dsp  # noqa: E402
from dsp import SR, db, horn, hp, lp, thump  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(REPO, "art", "export", "audio")
PIANO = "Meta-open-sound/src/systems/instruments/meta-piano/ogg/"
NAMES = {0: "C", 1: "Cs", 2: "D", 3: "Ds", 4: "E", 5: "F", 6: "Fs", 7: "G", 8: "Gs", 9: "A", 10: "As", 11: "B"}
rng = np.random.default_rng(11)


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def piano(m, vel=2, dur=2.0):
    x = dsp.load(PIANO + "INSPiano_Vel%02d_%s%d_01.ogg" % (vel, NAMES[m % 12], m // 12 - 1))[: int(dur * SR)]
    return dsp.fade(x, 0.001, 0.25)


def kick():
    return thump(130, 45, 0.4, 0.11, 0.6, 2.2)


def snare():
    n = int(0.25 * SR)
    x = dsp.bp(dsp.noise(0.25), 1200, 7000) * dsp.env_exp(n, 0.06)
    t = np.arange(n) / SR
    return x * 0.8 + np.sin(2 * np.pi * 190 * t) * dsp.env_exp(n, 0.04) * 0.6


def hat(open_=False):
    d = 0.3 if open_ else 0.06
    n = int(d * SR)
    return hp(dsp.noise(d), 7000) * dsp.env_exp(n, 0.09 if open_ else 0.018) * 0.5


def tom(f=110):
    return thump(f * 1.6, f, 0.5, 0.16, 0.3, 1.6)


def crash():
    n = int(2.0 * SR)
    return hp(dsp.noise(2.0), 3500) * dsp.env_exp(n, 0.6) * 0.5


def pad(ms, dur, cutoff=1400):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for m in ms:
        for d in (-0.006, 0.0, 0.007):
            ph = 2 * np.pi * hz(m) * (1 + d) * t + rng.uniform(0, 6)
            x += 2 * ((ph / (2 * np.pi)) % 1) - 1
    x = lp(x, cutoff, 2) * dsp.adsr(n, min(0.4, dur / 3), 0.2, 0.9, min(0.5, dur / 3))
    return x / (np.max(np.abs(x)) + 1e-9)


def bass(m, dur, cutoff=500):
    n = int(dur * SR)
    t = np.arange(n) / SR
    ph = 2 * np.pi * hz(m) * t
    x = (2 * ((ph / (2 * np.pi)) % 1) - 1) * 0.6 + np.sin(ph) * 0.7
    return lp(x, cutoff, 2) * dsp.adsr(n, 0.005, 0.08, 0.7, 0.05)


def brass(m, dur, cutoff=2200):
    return horn(hz(m), dur, cutoff=cutoff, vib=0.004, a=0.04, r=0.12) * 0.9


class Track:
    def __init__(self, bpm, bars, tail=3.0):
        self.beat = 60.0 / bpm
        self.len = bars * 4 * self.beat
        n = int((self.len + tail) * SR)
        self.L = np.zeros(n)
        self.R = np.zeros(n)

    def put(self, x, beat, g=0.0, pan=0.0):
        o = int(beat * self.beat * SR)
        if o >= len(self.L):
            return
        x = x[: len(self.L) - o] * db(g)
        self.L[o:o + len(x)] += x * np.sqrt((1 - pan) / 2)
        self.R[o:o + len(x)] += x * np.sqrt((1 + pan) / 2)

    def render(self, room=1.6, mix=0.22, target=-14.0):
        n = int(self.len * SR)
        out = []
        for ch, seed in ((self.L, 0), (self.R, 1)):
            dsp.rng = np.random.default_rng(100 + seed)
            w = dsp.reverb(ch, room, mix)
            y = w[:n].copy()
            tail = w[n:]
            k = min(len(tail), n)
            y[:k] += tail[:k]  # the tail wraps onto the head: a seamless loop
            out.append(y)
        y = np.stack(out, 1)
        y = hp(y.T, 30).T
        rms = 10 * np.log10(np.mean(y ** 2) + 1e-12)
        y = y * db(target - rms)
        k = 96  # a 2 ms dip at the seam so no loop point can click
        y[:k] *= np.linspace(0, 1, k)[:, None]
        y[-k:] *= np.linspace(1, 0, k)[:, None]
        return dsp.limit(y, 0.85)


def chords_of(prog, oct_=48):
    q = {"C": [0, 4, 7], "G": [7, 11, 14], "Am": [9, 12, 16], "F": [5, 9, 12], "Em": [4, 7, 11], "Dm": [2, 5, 9],
         "Bb": [10, 14, 17], "A": [9, 13, 16], "Dsus": [2, 7, 9], "Eb": [3, 7, 10], "Gm": [7, 10, 14]}
    return [[oct_ + i for i in q[c]] for c in prog]


def patrol_day():
    T = Track(112, 16)
    prog = ["C", "G", "Am", "F"] * 2 + ["F", "G", "Em", "Am", "F", "G", "C", "C"]
    roots = {"C": 36, "G": 43, "Am": 45, "F": 41, "Em": 40}
    tune = [  # (bar, beat, midi, beats): the patrol theme, second half only
        (8, 0, 72, 1.5), (8, 1.5, 74, 0.5), (8, 2, 76, 2), (9, 0, 79, 1.5), (9, 1.5, 77, 0.5), (9, 2, 76, 1), (9, 3, 74, 1),
        (10, 0, 76, 3), (11, 0, 72, 1), (11, 1, 74, 1), (11, 2, 76, 1), (11, 3, 79, 1),
        (12, 0, 81, 1.5), (12, 1.5, 79, 0.5), (12, 2, 77, 2), (13, 0, 79, 2), (13, 2, 74, 2), (14, 0, 76, 1), (14, 1, 79, 1),
        (14, 2, 84, 2), (15, 0, 84, 3)]
    for bar, c in enumerate(prog):
        ch = chords_of([c])[0]
        b0 = bar * 4
        for k in range(4):  # piano: offbeat stabs
            for m in ch:
                T.put(piano(m + 12, 2, 0.6), b0 + k + 0.5, -10, -0.2)
        T.put(pad([m + 12 for m in ch], 4 * T.beat), b0, -22, 0.3)
        r = roots[c]
        for k, (d, step) in enumerate(((0.75, 0), (0.25, 0.75), (1, 1.5), (0.5, 2.5), (1, 3))):
            T.put(bass(r, d * T.beat * 0.95), b0 + step, -9)
        for k in range(4):
            T.put(kick(), b0 + k if k in (0, 2) else b0 + k + 0.5 if k == 3 else b0 + k, -6 if k in (0, 2) else -12)
            if k in (1, 3):
                T.put(snare(), b0 + k, -9, 0.1)
            for e in (0, 0.5):
                T.put(hat(), b0 + k + e, -14 if e else -18, -0.4)
        if bar % 8 == 0:
            T.put(crash(), b0, -12, 0.5)
    for bar, beat, m, d in tune:
        T.put(brass(m, d * T.beat * 0.92), bar * 4 + beat, -9, 0.1)
        T.put(piano(m, 3, d * T.beat + 0.3), bar * 4 + beat, -10, -0.1)
    return T.render(1.4, 0.2, -15)


def patrol_night():
    T = Track(84, 16)
    prog = ["Am", "F", "C", "G"] * 2 + ["Dm", "Am", "F", "G", "Am", "F", "Em", "Am"]
    roots = {"Am": 45, "F": 41, "C": 36, "G": 43, "Dm": 38, "Em": 40}
    for bar, c in enumerate(prog):
        ch = chords_of([c])[0]
        b0 = bar * 4
        arp = [ch[0] + 12, ch[1] + 12, ch[2] + 12, ch[1] + 24]
        for k in range(8):  # a slow piano arpeggio
            T.put(piano(arp[k % 4], 1 if k % 2 else 2, 1.4), b0 + k * 0.5, -9, -0.3 + 0.15 * (k % 4))
        T.put(pad([m + 12 for m in ch], 4 * T.beat, 900), b0, -19, 0.35)
        T.put(bass(roots[c], 3.6 * T.beat, 300), b0, -10)
        if bar >= 4:
            T.put(kick(), b0, -12)
            T.put(kick(), b0 + 2.5, -16)
            T.put(snare(), b0 + 3, -18, 0.2)
            for k in range(8):
                T.put(hat(), b0 + k * 0.5, -22 if k % 2 else -19, -0.4)
    for bar, beat, m in ((8, 0, 76), (9, 0, 72), (10, 0, 72), (10, 2, 74), (11, 0, 71), (12, 0, 76), (13, 0, 77),
                         (13, 2, 76), (14, 0, 74), (15, 0, 69)):
        T.put(piano(m + 12, 2, 2.4), bar * 4 + beat, -11, 0.2)
    return T.render(2.2, 0.3, -17)


def boss_theme():
    T = Track(144, 16)
    prog = ["Dm", "Dm", "Bb", "A"] * 2 + ["Gm", "Dm", "Bb", "A", "Gm", "Bb", "A", "A"]
    roots = {"Dm": 38, "Bb": 34, "A": 33, "Gm": 31}
    for bar, c in enumerate(prog):
        ch = chords_of([c])[0]
        b0 = bar * 4
        r = roots[c]
        for k in range(8):  # driving eighth-note bass
            T.put(bass(r + (12 if k % 4 == 3 else 0), 0.45 * T.beat, 700), b0 + k * 0.5, -8)
        for k in range(4):
            T.put(kick(), b0 + k, -5)
            if k in (1, 3):
                T.put(snare(), b0 + k, -7, 0.1)
            T.put(hat(k == 3), b0 + k + 0.5, -15, -0.4)
        if bar % 2 == 1:
            for k, f in enumerate((140, 120, 100, 85)):
                T.put(tom(f), b0 + 3 + k * 0.25, -9, -0.5 + 0.3 * k)
        if bar % 4 == 0:
            T.put(crash(), b0, -10, 0.5)
        for st in (0, 1.5, 3):  # brass stabs
            for m in ch:
                T.put(brass(m + 12, 0.35 * T.beat, 1800), b0 + st, -16, 0.2)
        T.put(pad([m + 24 for m in ch], 4 * T.beat, 2000), b0, -24, -0.3)
    for bar, beat, m, d in ((8, 0, 74, 2), (8, 2, 77, 2), (9, 0, 76, 1), (9, 1, 74, 1), (9, 2, 69, 2), (10, 0, 70, 2), (10, 2, 74, 2),
                            (11, 0, 73, 4), (12, 0, 74, 2), (12, 2, 79, 2), (13, 0, 77, 2), (13, 2, 74, 2), (14, 0, 76, 4), (15, 0, 73, 4)):
        T.put(brass(m, d * T.beat * 0.95, 2600), bar * 4 + beat, -8, 0.1)
    return T.render(1.2, 0.18, -13)


def victory():
    T = Track(120, 2, tail=0.1)
    T.len = 4.2
    for k, m in enumerate((60, 64, 67)):
        T.put(brass(m + 12, 0.22), k * 0.33, -6)
    for m in (60, 64, 67, 72):
        T.put(brass(m + 12, 2.6, 2600), 1.0, -8)
        T.put(piano(m + 12, 4, 3.0), 1.0, -6)
    T.put(bass(36, 2.5), 1.0, -6)
    T.put(kick(), 1.0, -3)
    T.put(crash(), 1.0, -6, 0.3)
    for k in range(3):
        T.put(snare(), k * 0.33, -10)
    y = T.render(1.6, 0.2, -13)
    n = len(y)
    y[-int(0.6 * SR):] *= np.linspace(1, 0, int(0.6 * SR))[:, None]
    return y[:n]


# -- the context loops (first-30, nate 2026-11-20: "Music should change according to context"): Shared.MusicPlan picks
# one by what is going on (a fight, a mission, the prologue's chase and Ceremony, the deep, an HQ or the creator)


def combat_theme():
    T = Track(132, 16)
    prog = ["Em", "Em", "C", "D"] * 2 + ["Am", "Em", "C", "D", "Am", "C", "D", "D"]
    roots = {"Em": 40, "C": 36, "D": 38, "Am": 45}
    for bar, c in enumerate(prog):
        ch = chords_of(["Em" if c == "Em" else c] if c != "D" else ["Dsus"])[0]
        b0 = bar * 4
        r = roots[c]
        for k in range(8):  # a galloping bass: two sixteenths and an eighth
            T.put(bass(r, 0.22 * T.beat, 650), b0 + k * 0.5, -8)
            T.put(bass(r + (7 if k % 4 == 3 else 0), 0.22 * T.beat, 650), b0 + k * 0.5 + 0.25, -11)
        for k in range(4):
            T.put(kick(), b0 + k, -6 if k in (0, 2) else -9)
            if k in (1, 3):
                T.put(snare(), b0 + k, -8, 0.1)
            T.put(hat(), b0 + k + 0.5, -15, -0.4)
        if bar % 4 == 3:
            for k, f in enumerate((150, 130, 110, 95)):
                T.put(tom(f), b0 + 3 + k * 0.25, -10, -0.5 + 0.3 * k)
        if bar % 8 == 0:
            T.put(crash(), b0, -11, 0.5)
        for st in (0, 0.75, 2.5):
            for m in ch:
                T.put(brass(m + 12, 0.3 * T.beat, 2000), b0 + st, -15, 0.25)
    for bar, beat, m, d in ((8, 0, 76, 1.5), (8, 1.5, 79, 0.5), (8, 2, 83, 2), (9, 0, 81, 2), (9, 2, 79, 2),
                            (10, 0, 76, 1), (10, 1, 79, 1), (10, 2, 84, 2), (11, 0, 83, 4), (12, 0, 81, 2), (12, 2, 79, 2),
                            (13, 0, 76, 2), (13, 2, 79, 2), (14, 0, 78, 4), (15, 0, 76, 4)):
        T.put(brass(m - 12, d * T.beat * 0.95, 2400), bar * 4 + beat, -9, 0.1)
    return T.render(1.1, 0.16, -13)


def mission_theme():
    T = Track(96, 16)
    prog = ["Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "A", "A"] * 2
    roots = {"Dm": 38, "Bb": 34, "Gm": 31, "A": 33}
    for bar, c in enumerate(prog):
        ch = chords_of([c])[0]
        b0 = bar * 4
        T.put(pad([m + 12 for m in ch], 4 * T.beat, 1000), b0, -17, -0.2)
        for k in range(8):  # a ticking low pulse: the clock is running
            T.put(bass(roots[c], 0.3 * T.beat, 380), b0 + k * 0.5, -11 if k % 2 == 0 else -15)
        for k in range(8):
            T.put(hat(), b0 + k * 0.5, -20 if k % 2 else -17, 0.4)
        if bar >= 8:
            T.put(kick(), b0, -10)
            T.put(kick(), b0 + 1.5, -14)
            T.put(snare(), b0 + 3, -14, 0.1)
    for bar, beat, m in ((2, 0, 74), (2, 1, 77), (2, 2, 76), (3, 0, 69), (6, 0, 74), (6, 1, 77), (6, 2, 79), (7, 0, 73),
                         (10, 0, 74), (10, 1, 77), (10, 2, 76), (11, 0, 69), (14, 0, 77), (14, 1, 76), (14, 2, 74), (15, 0, 73)):
        T.put(piano(m, 2, 1.6), bar * 4 + beat, -9, 0.15)
    return T.render(1.8, 0.24, -16)


def chase_theme():
    T = Track(156, 16)
    prog = ["Am", "F", "G", "Em"] * 2 + ["F", "G", "Am", "Am", "F", "G", "A", "A"]
    roots = {"Am": 45, "F": 41, "G": 43, "Em": 40, "A": 45}
    for bar, c in enumerate(prog):
        ch = chords_of([c])[0]
        b0 = bar * 4
        r = roots[c]
        for k in range(8):  # octave-jumping eighths
            T.put(bass(r + (12 if k % 2 else 0), 0.42 * T.beat, 800), b0 + k * 0.5, -9)
        for k in range(4):
            T.put(kick(), b0 + k, -6)
            T.put(snare(), b0 + k + 0.5, -11 if k % 2 == 0 else -8, 0.1)
            for e in (0.25, 0.75):
                T.put(hat(), b0 + k + e, -17, -0.4)
        if bar % 4 == 0:
            T.put(crash(), b0, -10, 0.5)
        arp = [ch[0] + 24, ch[1] + 24, ch[2] + 24, ch[1] + 24]
        for k in range(8):
            T.put(piano(arp[k % 4], 2, 0.4), b0 + k * 0.5, -15, -0.3 + 0.2 * (k % 4))
    for bar, beat, m, d in ((8, 0, 76, 2), (8, 2, 77, 2), (9, 0, 79, 3), (9, 3, 77, 1), (10, 0, 76, 2), (10, 2, 72, 2),
                            (11, 0, 76, 4), (12, 0, 77, 2), (12, 2, 79, 2), (13, 0, 81, 3), (13, 3, 79, 1), (14, 0, 81, 2),
                            (14, 2, 83, 2), (15, 0, 81, 4)):
        T.put(brass(m - 12, d * T.beat * 0.95, 2600), bar * 4 + beat, -8, 0.1)
    return T.render(1.0, 0.14, -13)


def ceremony_theme():
    T = Track(100, 8)
    prog = ["C", "F", "G", "C", "Am", "F", "G", "G"]
    roots = {"C": 36, "F": 41, "G": 43, "Am": 45}
    for bar, c in enumerate(prog):
        ch = chords_of([c])[0]
        b0 = bar * 4
        T.put(pad([m + 12 for m in ch], 4 * T.beat, 1800), b0, -18, 0.2)
        T.put(bass(roots[c], 1.8 * T.beat, 420), b0, -9)
        T.put(bass(roots[c] + 7, 1.8 * T.beat, 420), b0 + 2, -11)
        T.put(tom(70), b0, -9)  # a timpani hit on each bar: a stately show
        T.put(tom(70), b0 + 2.5, -14)
        T.put(snare(), b0 + 3.75, -18, 0.2)
        for m in ch:  # a held brass chord: the city's proud show
            T.put(brass(m + 12, 3.6 * T.beat, 1800), b0, -17, -0.2)
    for bar, beat, m, d in ((0, 0, 72, 1), (0, 1, 76, 1), (0, 2, 79, 2), (1, 0, 77, 1.5), (1, 1.5, 76, 0.5), (1, 2, 74, 2),
                            (2, 0, 74, 1), (2, 1, 76, 1), (2, 2, 79, 2), (3, 0, 84, 4), (4, 0, 81, 1.5), (4, 1.5, 79, 0.5),
                            (4, 2, 76, 2), (5, 0, 77, 2), (5, 2, 81, 2), (6, 0, 79, 3), (7, 0, 74, 4)):
        T.put(brass(m, d * T.beat * 0.94, 2600), bar * 4 + beat, -8, 0.05)
    if True:
        T.put(crash(), 0, -14, 0.4)
    return T.render(2.0, 0.26, -15)


def deep_theme():
    T = Track(70, 8)
    prog = ["Dm", "Bb", "F", "A"] * 2
    for bar, c in enumerate(prog):
        ch = chords_of([c])[0]
        b0 = bar * 4
        T.put(pad([m for m in ch] + [ch[0] + 12], 4 * T.beat, 650), b0, -14, -0.3)
        T.put(pad([ch[1] + 24], 4 * T.beat, 1200), b0, -24, 0.4)
        for k, m in enumerate((ch[0] + 24, ch[2] + 24, ch[1] + 36)):
            T.put(piano(m, 1, 3.0), b0 + k * 1.33, -14, -0.4 + 0.4 * k)
    return T.render(3.4, 0.45, -18)


def hq_theme():
    T = Track(90, 8)
    prog = ["F", "Em", "Dm", "C"] * 2
    roots = {"F": 41, "Em": 40, "Dm": 38, "C": 36}
    for bar, c in enumerate(prog):
        ch = chords_of([c])[0]
        b0 = bar * 4
        for st in (0, 1.5, 2.5):  # soft piano comping
            for m in ch:
                T.put(piano(m + 12, 1, 1.2), b0 + st, -13, -0.1)
        T.put(bass(roots[c], 1.4 * T.beat, 300), b0, -11)
        T.put(bass(roots[c] + 7, 0.9 * T.beat, 300), b0 + 2.5, -13)
        T.put(kick(), b0, -15)
        T.put(kick(), b0 + 2.5, -18)
        T.put(snare(), b0 + 1, -21, 0.2)
        T.put(snare(), b0 + 3, -21, 0.2)
        for k in range(4):
            T.put(hat(), b0 + k + 0.5, -23, -0.4)
    for bar, beat, m in ((1, 0, 76), (1, 2, 74), (3, 0, 72), (3, 2, 71), (5, 0, 76), (5, 2, 77), (7, 0, 72)):
        T.put(piano(m + 12, 2, 1.8), bar * 4 + beat, -12, 0.25)
    return T.render(1.6, 0.22, -17)


def main():
    if len(sys.argv) < 2:
        print("usage: python3 -I art/audio/music.py <download root>")
        return 1
    dsp.ROOT = sys.argv[1]
    tracks = [("patrolDay", patrol_day(), True), ("patrolNight", patrol_night(), True), ("boss", boss_theme(), True),
              ("victory", victory(), False), ("combat", combat_theme(), True), ("mission", mission_theme(), True),
              ("chase", chase_theme(), True), ("ceremony", ceremony_theme(), True), ("deep", deep_theme(), True),
              ("hq", hq_theme(), True)]
    if dsp.MISSING:
        print("music.py: missing", sorted(dsp.MISSING))
        return 1
    parts, meta, t = [np.zeros((int(0.05 * SR), 2))], {}, 0.05
    for name, y, loop in tracks:
        meta[name] = [round(t, 4), round(len(y) / SR, 4), loop]
        parts += [y, np.zeros((int(0.25 * SR), 2))]
        t += len(y) / SR + 0.25
    y = np.concatenate(parts)
    import subprocess
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-", "-c:a", "libvorbis",
                    "-q:a", "5", os.path.join(OUT, "Music.ogg")], input=np.clip(y, -1, 1).astype(np.float32).tobytes(), check=True)
    json.dump(meta, open(os.path.join(OUT, "music.json"), "w"), indent=1)
    for k, v in meta.items():
        print("music.py: %s %.1f s%s" % (k, v[1], " loop" if v[2] else ""))
    return 0


sys.exit(main())
