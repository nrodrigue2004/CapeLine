# build.py: Capeline's sound set (nate's playtest 2026-11-19: "need better sounds badly").
# Mixes every game sound from CC0 sources (licences in notes/Tools.md "Sounds") plus synth layers of our own
# (dsp.py: low thumps, rumbles, air, bells, horns, sirens), loudness-matched, into a few atlas files (one Roblox
# audio asset each, every sound a PlaybackRegion inside it) so the whole set is a handful of uploads:
#   Hits  - punches, impacts, blocks, robots breaking, every power path's cast, super, hit and charge
#   World - movement (leap, land, pound, boost, sonic boom, swing, dash), destruction, the living city
#   Ui    - buttons, rewards, stamps, stings, the boss siren
#   Loops - held sounds (flight wind, super-speed rush, the Downed heartbeat) and the city beds
#   Ambient - (alive-world, 2026-11-20) the Ceremony crowd's applause loop and gasp, the scanner drone's hum, Patch's
#           radio key-up, harbour gull cries, the Docks crane's winch, the park's birdsong bed and the rain bed
#   python3 -I art/audio/build.py <download root> --only Ambient   builds just that atlas (the others' files, regions
#           and uploads stay as they are: every upload counts against Roblox's monthly audio limit)
# Writes art/export/audio/<Atlas>.ogg, art/export/audio/clips.json ({atlas: {clip: [start, length, loop]}}) and
# src/config/AudioClips.luau (the regions; asset ids from art/audio/ids.json once uploaded).
#   python3 -I art/audio/build.py <download root>     (the root holds one folder per downloaded pack)
#   python3 -I art/audio/build.py --ids               (after art/audio/upload.py: the ids into AudioClips.luau)
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)  # our own dsp.py only (the downloads are never on the path)
import dsp  # noqa: E402
from dsp import SR, bell, chord, cut, db, fade, finish, hp, horn, lp, place, rate, reverb, rumble, sat, thump, whoosh  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(REPO, "art", "export", "audio")

KI = "impact/src/addons/kenney impact sounds/"
KS = "kenney-sci-fi-sounds-for-godot/src/addons/kenney sci-fi sounds/"
KR = "kenney-rpg-audio-for-godot/src/addons/kenney rpg audio/"
KD = "kenney-digital-audio-for-godot/src/addons/kenney digital audio/"
KF = "kenney-interface-sounds/src/addons/kenney_interface_sounds/"
KU = "kenney-ui-audio/src/addons/kenney_ui_audio/"
KJ = "kenney-music-jingles-for-godot/src/addons/kenney music jingles/"
FS = "Free-SFX/src/"
RD = FS + "rubberduck/"
OW = FS + "Owlish/Sound Effects Pack/"
PIANO = "Meta-open-sound/src/systems/instruments/meta-piano/ogg/"

ATLASES = {}  # atlas -> [(clip name, array, loop)]
SOURCES = set()


def src(rel, g=0.0, r=1.0, s=0.0, d=None, hpf=None, lpf=None, fo=0.03, rev=False, peak=None):
    """A source layer: cut, varispeed, filtered, gained. `peak` moves its loudest moment to that many seconds in
    (a long whoosh whose rush comes late would lag its action)."""
    SOURCES.add(rel.split("/")[0])
    x = dsp.load(rel)
    if peak is not None and len(x):
        e = np.convolve(np.abs(x), np.ones(441) / 441, "same")
        s = max(s, np.argmax(e) / SR - peak / r)
    x = cut(x, s, d)
    x = rate(x, r)
    if hpf:
        x = hp(x, hpf)
    if lpf:
        x = lp(x, lpf)
    x = fade(x, 0.001, fo)
    if rev:
        x = x[::-1].copy()
    return x * db(g)


NOTES = {"C": 0, "Cs": 1, "D": 2, "Ds": 3, "E": 4, "F": 5, "Fs": 6, "G": 7, "Gs": 8, "A": 9, "As": 10, "B": 11}
NAMES = {v: k for k, v in NOTES.items()}


def piano(midi, vel=3, dur=1.6, g=0.0):
    """A Meta piano note (CC0), tails faded at `dur`."""
    name = "%s%d" % (NAMES[midi % 12], midi // 12 - 1)
    return fade(src(PIANO + "INSPiano_Vel%02d_%s_01.ogg" % (vel, name), g, d=dur, fo=0.3), 0.001, 0.3)


def keys(notes, gap=0.0, vel=3, dur=1.6):
    return place([(piano(n, vel, dur), i * gap) for i, n in enumerate(notes)])


def nrm(x, peak=1.0):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def add(atlas, name, x, target=-12.0, loop=False, max_len=None):
    if loop:
        y = x
    else:
        y = finish(x, target, max_len=max_len)
    ATLASES.setdefault(atlas, []).append((name, y, loop))


def loop_clip(atlas, name, x, target=-16.0, xf=0.4):
    x = dsp.hp(x, 25)
    x = x * db(target - dsp.short_rms_db(x, 0.4))
    x = dsp.limit(dsp.seamless(x, xf))
    ATLASES.setdefault(atlas, []).append((name, x, True))


def pick(seq, i):
    return seq[i % len(seq)]


# ---------------------------------------------------------------------------------------------------------
# Hits: the impact layer under every landed hit (body + crack + tail), blocks, robots, combat moments
# ---------------------------------------------------------------------------------------------------------
def build_hits():
    punch_m = [KI + "impact_punch_medium_00%d.ogg" % i for i in range(5)]
    punch_h = [KI + "impact_punch_heavy_00%d.ogg" % i for i in range(5)]
    for i in range(4):  # impact.hit: a punch with a short low body and a little grit
        add("Hits", "hit_%d" % (i + 1), place([
            (src(punch_m[i], 0, 1 + 0.04 * i), 0),
            (thump(120 - 8 * i, 48, 0.22, 0.07, 0.5) * 0.55, 0),
            (src(RD + "BreakingFalling/bfh1_hit_%02d.opus" % (9 + i), -14, 1.1, hpf=1500), 0.004),
        ]), -11)
    for i in range(3):  # impact.heavy: a heavy punch, a deep saturated thump and a crunchy tail
        add("Hits", "heavy_%d" % (i + 1), place([
            (src(punch_h[i], 0, 0.92), 0),
            (thump(95, 36, 0.5, 0.16, 0.7, 2.6) * 0.8, 0),
            (src(KI + "impact_mining_00%d.ogg" % i, -9, 0.8, lpf=3500), 0.01),
            (reverb(src(RD + "BreakingFalling/bfh1_rock_falling_0%d.opus" % (4 + i), -16), 0.6, 0.4), 0.05),
        ]), -9)
    for i in range(3):  # impact.clank: the robot shell answering
        add("Hits", "clank_%d" % (i + 1), place([
            (src(KI + "impact_metal_light_00%d.ogg" % i, 0, 0.9), 0),
            (src(KI + "impact_plate_light_00%d.ogg" % (i + 1), -6, 1.0), 0.003),
        ]), -14)
    sw_short = [FS + "qubodup/Swooshes/swosh-%02d.opus" % n for n in (6, 9, 10, 27)]
    for i in range(4):  # basic: the swing of a basic attack (the hit itself plays the impact layer)
        add("Hits", "basic_%d" % (i + 1), place([
            (src(sw_short[i], 0, 1.15 + 0.05 * i, lpf=7000, peak=0.05), 0),
            (whoosh(0.16, 900, 3500, 0.55) * 0.25, 0),
        ]), -15)
    for i in range(3):  # cast: a charged release, a whoosh with an energy edge
        add("Hits", "cast_%d" % (i + 1), place([
            (src(FS + "qubodup/Swooshes/swosh-%02d.opus" % (24, 30, 40)[i], 0, 1.05, peak=0.08), 0),
            (src(KS + "force_field_00%d.ogg" % (i + 2), -10, 1.3, d=0.5, hpf=300), 0.02),
            (thump(160, 70, 0.18, 0.06, 0.2) * 0.3, 0.03),
        ]), -13)
    for i in range(2):  # super: a rising charge, then the big boom with a sub drop and a debris tail
        riser = whoosh(0.7, 200, 3000, 0.95) * 0.5
        add("Hits", "super_%d" % (i + 1), place([
            (riser, 0),
            (src(KS + "force_field_00%d.ogg" % (1 + i), -8, 0.7, d=0.7, hpf=200), 0),
            (thump(85, 30, 1.0, 0.35, 1.0, 3.0), 0.68),
            (src(KS + "low_frequency_explosion_00%d.ogg" % i, -2, 0.9), 0.68),
            (src(KS + "explosion_crunch_00%d.ogg" % (1 + 3 * i), -6, 0.85), 0.69),
            (reverb(src(RD + "BreakingFalling/bfh1_rock_breaking_0%d.opus" % (1 + i), -12), 1.4, 0.45), 0.78),
        ]), -7, max_len=3.2)
    for i in range(2):  # crit: the heavy body plus a bright metallic ping
        add("Hits", "crit_%d" % (i + 1), place([
            (src(punch_h[3 + i], -2, 1.05), 0),
            (thump(140, 50, 0.3, 0.1, 0.8, 2.4) * 0.6, 0),
            (bell(2200 + 300 * i, 0.5, 0.18) * 0.35, 0.006),
            (src(KI + "impact_metal_light_00%d.ogg" % (3 + i), -6, 1.3), 0.004),
        ]), -9)
    for i in range(3):  # defeat: the robot breaks: a crunch, sparks, its parts clattering down
        add("Hits", "defeat_%d" % (i + 1), place([
            (src(KI + "impact_metal_heavy_00%d.ogg" % i, 0, 0.85), 0),
            (thump(110, 45, 0.3, 0.1, 0.4) * 0.5, 0),
            (src(FS + "Electricity/groundhit.opus", -8, 1.0 + 0.1 * i), 0.02),
            (src(RD + "BreakingFalling/bfh1_metal_falling_0%d.opus" % (1 + i), -4), 0.12),
            (src(RD + "WoodMetal/metal_hit_0%d.opus" % (1 + i), -10, 1.2), 0.3),
        ]), -11)
    for i in range(2):  # clash: two heavy hits meeting: a boom, a ring, a pressure wave
        add("Hits", "clash_%d" % (i + 1), place([
            (thump(70, 28, 1.0, 0.3, 1.0, 3.0), 0),
            (src(KI + "impact_metal_heavy_00%d.ogg" % (3 + i), 0, 0.7), 0),
            (src(KS + "explosion_crunch_00%d.ogg" % (2 + i), -4, 0.8), 0.005),
            (bell(320, 1.4, 0.6) * 0.18, 0.01),
            (whoosh(0.8, 3000, 300, 0.05) * 0.3, 0.02),
        ]), -7, max_len=2.5)
    for i in range(3):  # block: a dull guarded clank
        add("Hits", "block_%d" % (i + 1), place([
            (src(KI + "impact_metal_medium_00%d.ogg" % i, 0, 0.8, lpf=4000), 0),
            (src(KI + "impact_soft_medium_00%d.ogg" % i, -2), 0),
            (thump(130, 70, 0.15, 0.05, 0.2) * 0.4, 0),
        ]), -13)
    for i in range(2):  # perfectBlock: a bright ting over the clank
        add("Hits", "perfectBlock_%d" % (i + 1), place([
            (src(KI + "impact_bell_heavy_00%d.ogg" % i, -2, 1.5), 0),
            (bell(1760 * (1 + 0.12 * i), 0.9, 0.35) * 0.5, 0),
            (src(KI + "impact_metal_light_00%d.ogg" % (1 + i), -4, 1.2), 0),
        ]), -11)
    for i in range(2):  # shatter: a guard broken: glass, crunch, body
        add("Hits", "shatter_%d" % (i + 1), place([
            (src(KI + "impact_glass_heavy_00%d.ogg" % i, 0), 0),
            (src(RD + "BreakingFalling/bfh1_glass_breaking_0%d.opus" % (1 + 2 * i), -3), 0.01),
            (thump(100, 40, 0.35, 0.12, 0.6) * 0.7, 0),
        ]), -9)
    add("Hits", "interrupt", place([(src(KF + "glitch_002.wav", 0), 0), (src(KF + "scratch_002.wav", -4), 0.02),
                                    (src(punch_m[4], -4, 1.2), 0)]), -12)
    add("Hits", "chargeFull", place([(src(KD + "power_up_4.ogg", -2, 1.0, d=0.6), 0), (bell(1568, 0.7, 0.3) * 0.5, 0.05),
                                     (bell(2349, 0.6, 0.25) * 0.3, 0.1)]), -12)
    for i in range(2):  # grab: a grunt-free cloth and body grip
        add("Hits", "grab_%d" % (i + 1), place([(src(KI + "impact_soft_heavy_00%d.ogg" % i, 0), 0),
                                               (src(KR + "cloth_%d.ogg" % (1 + i), -2), 0.01),
                                               (src(KR + "drop_leather.ogg", -6), 0.04)]), -12)
    for i in range(3):  # throwLand: something big thrown down: crash, thump, debris
        add("Hits", "throwLand_%d" % (i + 1), place([
            (thump(80, 32, 0.7, 0.22, 0.8, 2.8), 0),
            (src(KI + "impact_plate_heavy_00%d.ogg" % i, -2, 0.8), 0),
            (src(KI + "impact_mining_00%d.ogg" % (2 + i), -4, 0.85), 0.01),
            (src(RD + "BreakingFalling/bfh1_falling_0%d.opus" % (2 + i), -6), 0.08),
        ]), -8)
    add("Hits", "aimLock", place([(src(KS + "computer_noise_001.ogg", -6, 1.2, d=0.4), 0),
                                  (bell(2637, 0.35, 0.12, partials=((1, 1), (3, 0.3))) * 0.6, 0),
                                  (bell(2637, 0.35, 0.12, partials=((1, 1), (3, 0.3))) * 0.6, 0.12)]), -12)
    for i in range(2):  # grenadeBoom
        add("Hits", "grenadeBoom_%d" % (i + 1), place([
            (src(KS + "explosion_crunch_00%d.ogg" % (i * 4), 0, 0.9), 0),
            (src(KS + "low_frequency_explosion_001.ogg", -3, 1.1), 0),
            (thump(90, 30, 0.6, 0.2, 0.9, 2.5) * 0.7, 0),
            (reverb(src(RD + "BreakingFalling/bfh1_rock_falling_0%d.opus" % (1 + i), -12), 1.0, 0.4), 0.1),
        ]), -8, max_len=2.4)
    add("Hits", "rally", place([(horn(147, 0.9, cutoff=1400, vib=0.006), 0), (horn(220, 0.7, cutoff=1600) * 0.6, 0.15),
                                (src(KS + "force_field_000.ogg", -8, 0.8, d=0.6), 0)]), -12)
    add("Hits", "reveal", place([(src(KF + "glitch_004.wav", 0), 0), (whoosh(0.4, 3000, 500, 0.2) * 0.6, 0),
                                 (src(KS + "door_open_001.ogg", -6, 1.4), 0.05)]), -12)
    add("Hits", "lungeWind", place([(src(KD + "phaser_up_3.ogg", -2, 1.0), 0), (whoosh(0.7, 300, 2500, 0.9) * 0.5, 0)]), -13)
    add("Hits", "braceWarn", place([(src(KS + "force_field_001.ogg", 0, 0.7), 0), (horn(73, 1.1, cutoff=500) * 0.5, 0),
                                    (src(KS + "computer_noise_002.ogg", -10, d=0.8), 0)]), -11)
    for i in range(3):  # wreckSpark: a wreck spitting sparks
        add("Hits", "wreckSpark_%d" % (i + 1), src(FS + "Electricity/crackleelectricityloop.opus", 0, 0.9 + 0.15 * i,
                                                    s=0.05 * i, d=0.3), -18)
    for i in range(2):  # wreckPop: the wreck popping apart
        add("Hits", "wreckPop_%d" % (i + 1), place([(src(KS + "explosion_crunch_00%d.ogg" % (2 + i), -2, 1.3, d=0.7), 0),
                                                   (src(RD + "BreakingFalling/bfh1_metal_falling_0%d.opus" % (4 + i), -4), 0.05),
                                                   (thump(150, 60, 0.2, 0.07, 0.4) * 0.5, 0)]), -12)
    add("Hits", "unmask", place([(src(KI + "impact_glass_medium_001.ogg", 0, 0.8), 0),
                                 (src(KI + "impact_metal_light_002.ogg", -2, 0.7), 0.03),
                                 (whoosh(0.5, 4000, 400, 0.1) * 0.4, 0), (thump(90, 40, 0.4, 0.15) * 0.6, 0)]), -10)
    add("Hits", "nemesisArrive", place([(horn(55, 1.8, cutoff=700, vib=0.004), 0), (horn(82.4, 1.6, cutoff=900) * 0.7, 0.05),
                                        (thump(60, 28, 1.0, 0.4, 0.6, 2.5), 0), (whoosh(1.0, 200, 1500, 0.15) * 0.4, 0)]), -9,
        max_len=2.5)
    add("Hits", "nemesisEscape", place([(src(FS + "Electricity/teleport.opus", 0), 0), (whoosh(0.5, 600, 6000, 0.3) * 0.5, 0)]),
        -11)


# ---------------------------------------------------------------------------------------------------------
# Paths: every power path's own layer (cast, super, hit, charge), element by element
# ---------------------------------------------------------------------------------------------------------
def build_paths():
    E = FS + "Electricity/"
    sw = lambda n: FS + "qubodup/Swooshes/swosh-%02d.opus" % n  # noqa: E731

    def boom(g=0, low=1.0):
        return place([(thump(75 * low, 28, 0.9, 0.3, 0.8, 3.0) * db(g), 0),
                      (src(KS + "low_frequency_explosion_000.ogg", g - 3, 0.95), 0)])

    P = {}
    # Volt: electric snaps and zaps
    P["Volt"] = dict(
        cast=[place([(src(E + "hit.opus", 0, 1.1, d=0.5), 0), (src(KS + "laser_retro_00%d.ogg" % i, -6), 0)]) for i in (1, 4)],
        super=[place([(src(E + "powerup.opus", -2, 1.2, d=1.0), 0), (src(E + "killconfirmed.opus", 0, d=1.4), 0.5), (boom(-4), 0.55)])],
        hit=[src(E + "groundhit.opus", 0, 1.0 + 0.12 * i) for i in range(2)],
        charge=[src(E + "charge.opus", 0, 1.2, d=1.0)],
    )
    # Frost: crystal cracks, cold air
    P["Frost"] = dict(
        cast=[place([(src(KI + "impact_glass_light_00%d.ogg" % i, 0, 0.9), 0), (whoosh(0.45, 6000, 1500, 0.2) * 0.5, 0),
                     (bell(2900 + 200 * i, 0.6, 0.2) * 0.25, 0.02)]) for i in (0, 2)],
        super=[place([(whoosh(1.2, 300, 5000, 0.6) * 0.6, 0), (src(KI + "impact_glass_heavy_002.ogg", 0, 0.7), 0.7),
                      (src(RD + "BreakingFalling/bfh1_glass_breaking_06.opus", -2, 0.8), 0.72), (boom(-6, 1.2), 0.7),
                      (chord([1760, 2637, 3520], 1.2, 0.5, 0.05) * 0.2, 0.75)])],
        hit=[place([(src(KI + "impact_glass_medium_00%d.ogg" % i, 0), 0), (src(KI + "impact_glass_light_00%d.ogg" % ((i + 3) % 5), -6, 1.3), 0)])
             for i in (1, 3)],
        charge=[place([(whoosh(1.0, 2000, 7000, 0.8) * 0.5, 0), (src(KI + "impact_glass_light_001.ogg", -6, 1.6), 0.85)])],
    )
    # Fire: roaring whooshes and crackles
    fireloop = FS + "PagDev/fire_loop.opus"
    P["Fire"] = dict(
        cast=[place([(src(FS + "Superpowers/top-down-shooter/flame-thrower.opus", 0, 1.0 - 0.1 * i, peak=0.06, d=0.7, fo=0.25), 0),
                     (src(sw(7 + 9 * i), -4, 0.8, lpf=2500, peak=0.05), 0), (src(fireloop, -8, s=1 + i, d=0.5, fo=0.2), 0)]) for i in range(2)],
        super=[place([(whoosh(0.8, 150, 1800, 0.9) * 0.5, 0), (src(KS + "explosion_crunch_004.ogg", 0, 0.8), 0.7), (boom(-2), 0.7),
                      (src(fireloop, -4, s=3, d=1.6), 0.72)])],
        hit=[place([(src(fireloop, -2, 1.2, s=0.5 + i, d=0.35), 0), (src(KS + "explosion_crunch_00%d.ogg" % i, -8, 1.6, d=0.4), 0)])
             for i in range(2)],
        charge=[place([(src(fireloop, 0, 1.0, s=4, d=1.0), 0), (whoosh(1.0, 200, 900, 0.9) * 0.6, 0)])],
    )
    # Earth: rock cracks and heavy ground
    P["Earth"] = dict(
        cast=[place([(src(KI + "impact_mining_00%d.ogg" % i, 0, 0.85), 0), (thump(100, 40, 0.4, 0.14, 0.4) * 0.6, 0),
                     (src(RD + "BreakingFalling/bfh1_rock_falling_0%d.opus" % (1 + i), -6), 0.05)]) for i in (0, 3)],
        super=[place([(rumble(1.6, 120, 0.4, 0.8) * 0.7, 0), (boom(0, 0.9), 0.6), (src(RD + "BreakingFalling/bfh1_rock_breaking_01.opus", 0, 0.8), 0.6),
                      (src(KI + "impact_mining_004.ogg", -2, 0.7), 0.62)])],
        hit=[place([(src(KI + "impact_mining_00%d.ogg" % i, 0, 1.0), 0), (src(RD + "BreakingFalling/bfh1_rock_hit_01.opus", -4), 0)])
             for i in (1, 2)],
        charge=[rumble(1.0, 160, 0.6, 2.0) * 0.8],
    )
    W = RD + "WaterSplashSlime/"
    P["Tide"] = dict(
        cast=[place([(src(W + "splash_%02d.opus" % n, 0, peak=0.03), 0.02), (src(sw(5), -6, 0.9, lpf=3000, peak=0.04), 0)]) for n in (3, 7)],
        super=[place([(whoosh(0.8, 200, 1500, 0.9) * 0.5, 0), (src(W + "splash_12.opus", 0, 0.7), 0.7), (src(W + "splash_14.opus", -2, 0.8), 0.75),
                      (boom(-6), 0.7)])],
        hit=[src(W + "splash_%02d.opus" % n, 0, 1.15) for n in (1, 9)],
        charge=[place([(src(W + "bubble_0%d.opus" % n, 0, 1.0), 0.25 * k) for k, n in enumerate((1, 2, 3))])],
    )
    P["Blade"] = dict(
        cast=[place([(src(RD + "RPG/blade_0%d.opus" % i, 0), 0), (src(sw(12 + i), -2, 1.3), 0)]) for i in (1, 2)],
        super=[place([(src(sw(41), 0, 1.1), 0)] + [(src(KR + "draw_knife_%d.ogg" % k, -2), 0.25 * k) for k in (1, 2, 3)] +
                     [(src(RD + "RPG/blade_03.opus", 0, 0.8), 0.95), (boom(-8, 1.3), 0.95)])],
        hit=[place([(src(KR + "knife_slice%s.ogg" % ("" if i == 0 else "_2"), 0), 0), (src(KI + "impact_metal_light_00%d.ogg" % i, -8, 1.4), 0)])
             for i in range(2)],
        charge=[place([(src(KR + "draw_knife_1.ogg", 0, 0.8), 0), (bell(3136, 0.6, 0.25) * 0.2, 0.1)])],
    )
    WS = FS + "Superpowers/western-fps-2d/"
    P["Gunslinger"] = dict(
        cast=[place([(src(WS + "gun-%d.opus" % i, 0), 0), (thump(160, 60, 0.15, 0.05, 0.6) * 0.4, 0)]) for i in (1, 3)],
        super=[place([(src(WS + "gun-%d.opus" % (1 + k % 5), -1, 1.0 + 0.03 * k), 0.12 * k) for k in range(6)] + [(boom(-6, 1.2), 0.75)])],
        hit=[src(WS + "impact-%d.opus" % i, 0) for i in (1, 2)],
        charge=[src(WS + "reload.opus", 0)],
    )
    P["Gadgeteer"] = dict(
        cast=[place([(src(KD + "laser_%d.ogg" % i, -2, d=0.5), 0), (src(RD + "WoodMetal/tools_0%d.opus" % (i % 9 + 1), -6), 0)]) for i in (2, 4)],
        super=[place([(src(KD + "power_up_%d.ogg" % k, -4, d=0.4), 0.15 * k) for k in (1, 2, 3)] + [(src(KS + "explosion_crunch_001.ogg", 0), 0.6),
                                                                                              (boom(-6), 0.6)])],
        hit=[place([(src(KI + "impact_tin_medium_00%d.ogg" % i, 0), 0), (src(KF + "click_00%d.wav" % (i + 1), -6), 0)]) for i in (0, 2)],
        charge=[src(KS + "computer_noise_000.ogg", -2, d=1.0)],
    )
    SD = FS + "Owlish/Sound Effects Pack/Scifi/"
    P["Shadow"] = dict(
        cast=[place([(src(sw(13 + 8 * i), 0, 0.7, lpf=1800, peak=0.06), 0), (src(SD + "blackhole%s.opus" % ("" if i == 0 else "1"), -8, 1.2, d=0.6, fo=0.2), 0)])
              for i in range(2)],
        super=[place([(src(SD + "blackhole2.opus", 0, 0.8, d=1.4), 0), (whoosh(1.0, 4000, 120, 0.85) * 0.5, 0), (boom(-3, 0.8), 1.0)])],
        hit=[place([(src(sw(9 + i), 0, 0.75, lpf=2000), 0), (thump(90, 40, 0.25, 0.08, 0.2) * 0.5, 0)]) for i in range(2)],
        charge=[src(FS + "qubodup/Ghost Moans/qubodup-GhostMoan0%d.opus" % 2, -4, 0.8, d=1.0, lpf=2500)],
    )
    P["Titan"] = dict(
        cast=[place([(thump(80, 32, 0.6, 0.2, 0.8, 2.8), 0), (src(KI + "impact_punch_heavy_00%d.ogg" % i, -2, 0.75), 0),
                     (src(KI + "impact_metal_heavy_00%d.ogg" % i, -6, 0.7), 0)]) for i in (0, 2)],
        super=[place([(rumble(1.2, 100, 0.6, 0.7) * 0.6, 0), (boom(0, 0.8), 0.7), (src(KI + "impact_plate_heavy_001.ogg", 0, 0.6), 0.7),
                      (src(RD + "BreakingFalling/bfh1_falling_04.opus", -4), 0.8)])],
        hit=[place([(src(KI + "impact_punch_heavy_00%d.ogg" % i, 0, 0.8), 0), (thump(70, 30, 0.4, 0.14, 0.6, 2.6) * 0.8, 0)])
             for i in (1, 4)],
        charge=[rumble(1.0, 110, 0.8, 2.0)],
    )
    P["Martial"] = dict(
        cast=[place([(src(sw(16 + i), 0, 1.2), 0), (src(sw(19 + i), -4, 1.4), 0.08)]) for i in range(2)],
        super=[place([(src(sw(n), -1, 1.2), 0.1 * k) for k, n in enumerate((5, 14, 16, 19, 21))] +
                     [(src(KI + "impact_punch_heavy_003.ogg", 0, 0.8), 0.55), (boom(-4, 1.1), 0.56)])],
        hit=[place([(src(FS + "Owlish/Sound Effects Pack/Impacts/slap2.opus", 0), 0), (src(KI + "impact_punch_medium_00%d.ogg" % i, -4, 1.1), 0)])
             for i in (1, 3)],
        charge=[place([(whoosh(0.9, 400, 1800, 0.85) * 0.5, 0), (src(KR + "cloth_belt.ogg", -4), 0.7)])],
    )
    P["Juggernaut"] = dict(
        cast=[place([(src(KI + "impact_metal_heavy_00%d.ogg" % i, 0, 0.6), 0), (thump(70, 30, 0.5, 0.18, 0.5, 2.6) * 0.7, 0),
                     (src(KS + "engine_circular_00%d.ogg" % i, -10, 0.7, d=0.5), 0)]) for i in (1, 3)],
        super=[place([(src(KS + "space_engine_large_001.ogg", -2, 0.7, d=1.2), 0), (boom(0, 0.7), 1.0), (src(KI + "impact_metal_heavy_004.ogg", 0, 0.5), 1.0)])],
        hit=[place([(src(RD + "WoodMetal/metal_hit_0%d.opus" % i, 0, 0.7), 0), (thump(80, 34, 0.3, 0.1, 0.4) * 0.6, 0)]) for i in (2, 4)],
        charge=[src(KS + "engine_circular_002.ogg", 0, 0.6, d=1.0)],
    )
    P["Colossus"] = dict(
        cast=[place([(thump(55, 24, 0.9, 0.3, 0.6, 3.0), 0), (src(KS + "low_frequency_explosion_001.ogg", -4, 0.7), 0),
                     (src(KI + "impact_mining_00%d.ogg" % i, -6, 0.6), 0)]) for i in (0, 4)],
        super=[place([(rumble(1.8, 90, 0.8, 1.0), 0), (boom(0, 0.6), 1.0), (src(RD + "BreakingFalling/bfh1_rock_breaking_02.opus", 0, 0.6), 1.0),
                      (src(KS + "low_frequency_explosion_000.ogg", 0, 0.7), 1.02)])],
        hit=[place([(thump(60, 26, 0.5, 0.2, 0.5, 3.0), 0), (src(KI + "impact_soft_heavy_00%d.ogg" % i, 0, 0.7), 0)]) for i in (0, 2)],
        charge=[rumble(1.2, 70, 1.0, 3.0)],
    )
    P["Pulse"] = dict(
        cast=[place([(src(KS + "force_field_00%d.ogg" % i, 0, 0.9, d=0.6), 0), (thump(120, 60, 0.3, 0.1, 0.1) * 0.6, 0)]) for i in (0, 3)],
        super=[place([(src(KD + "phaser_up_5.ogg", -2), 0), (whoosh(0.8, 5000, 200, 0.05) * 0.6, 0.6), (boom(-2), 0.6),
                      (src(KS + "force_field_004.ogg", 0, 0.6), 0.62)])],
        hit=[place([(src(KD + "zap_%d.ogg" % i, -2, 0.7, d=0.35), 0), (thump(150, 70, 0.2, 0.06, 0.1) * 0.5, 0)]) for i in (1, 2)],
        charge=[src(KS + "force_field_001.ogg", 0, 0.7)],
    )
    P["Mind"] = dict(
        cast=[place([(src(KD + "phaser_up_%d.ogg" % i, 0), 0), (bell(740 * (1 + 0.1 * i), 0.8, 0.4, bright=0.6) * 0.3, 0)]) for i in (1, 4)],
        super=[place([(src(SD + "alien effects.opus", 0, d=1.4), 0)] + [(src(KD + "phase_jump_%d.ogg" % k, -4), 0.2 * k) for k in (1, 3)] +
                     [(boom(-6, 1.2), 0.8), (chord([370, 554, 740], 1.4, 0.8, 0.0, bright=0.5) * 0.3, 0.8)])],
        hit=[src(KD + "phase_jump_%d.ogg" % i, 0, d=0.4) for i in (2, 5)],
        charge=[src(KD + "phaser_up_7.ogg", 0)],
    )
    P["Spirit"] = dict(
        cast=[place([(src(FS + "JaggedStone/Magic Spell SFX/magical_1.opus", 0, 1.0 + 0.1 * i, d=0.8), 0),
                     (chord([880 * (1 + 0.06 * i), 1319, 1760], 0.9, 0.5, 0.04) * 0.25, 0)]) for i in range(2)],
        super=[place([(whoosh(1.0, 300, 4000, 0.85) * 0.4, 0), (chord([523, 659, 784, 1047, 1319], 1.6, 0.9, 0.08) * 0.4, 0.4),
                      (boom(-6, 1.1), 0.9), (src(FS + "qubodup/Ghost Moans/qubodup-GhostMoan04.opus", -8, 1.2, d=1.2, lpf=4000), 0.3)])],
        hit=[place([(bell(1175 + 220 * i, 0.5, 0.2) * 0.6, 0), (src(sw(25), -4, 1.4), 0)]) for i in range(2)],
        charge=[place([(chord([659, 988, 1319], 1.0, 0.8, 0.15) * 0.6, 0), (whoosh(1.0, 800, 3000, 0.9) * 0.3, 0)])],
    )
    P["Light"] = dict(
        cast=[place([(src(KS + "laser_large_00%d.ogg" % i, 0, 1.0), 0), (bell(2093 + 300 * i, 0.5, 0.2) * 0.3, 0)]) for i in (0, 2)],
        super=[place([(src(KD + "power_up_%d.ogg" % k, -6), 0.1 * k) for k in (5, 6, 7)] + [(src(KS + "laser_large_004.ogg", 0, 0.7), 0.7),
                                                                                       (boom(-4, 1.2), 0.7),
                                                                                       (chord([1047, 1319, 1568, 2093], 1.4, 0.6, 0.0) * 0.35, 0.72)])],
        hit=[place([(src(KS + "laser_small_00%d.ogg" % i, 0), 0), (bell(2637, 0.35, 0.12) * 0.4, 0)]) for i in (0, 4)],
        charge=[place([(src(KD + "power_up_11.ogg", 0, d=0.9), 0), (whoosh(1.0, 1500, 7000, 0.9) * 0.3, 0)])],
    )
    targets = dict(cast=-13, super=-9, hit=-14, charge=-16)
    lengths = dict(cast=1.2, super=3.0, hit=0.8, charge=1.2)
    for path, row in P.items():
        for moment, variants in row.items():
            for i, x in enumerate(variants):
                add("Hits", "%s_%s_%d" % (path, moment, i + 1), x, targets[moment], max_len=lengths[moment])
    return list(P)


# ---------------------------------------------------------------------------------------------------------
# World: moving, breaking, the living city
# ---------------------------------------------------------------------------------------------------------
def build_world():
    sw = lambda n: FS + "qubodup/Swooshes/swosh-%02d.opus" % n  # noqa: E731
    for i in range(2):  # leap: the take-off push and the rush of air
        add("World", "leap_%d" % (i + 1), place([(thump(110, 55, 0.25, 0.08, 0.3) * 0.6, 0), (src(KI + "footstep_concrete_00%d.ogg" % i, -4, 0.7), 0),
                                                 (src(sw((37, 24)[i]), 0, 0.9, peak=0.08), 0.02), (whoosh(0.6, 300, 1800, 0.35) * 0.4, 0.02)]), -12)
    for i in range(3):  # land: a heavy thud, the body and grit
        add("World", "land_%d" % (i + 1), place([(thump(85, 34, 0.55, 0.18, 0.6, 2.8), 0), (src(KI + "impact_soft_heavy_00%d.ogg" % i, 0, 0.85), 0),
                                                 (src(KI + "impact_mining_00%d.ogg" % (i + 1), -8, 0.9, lpf=5000), 0.01),
                                                 (src(RD + "BreakingFalling/bfh1_rock_falling_0%d.opus" % (5 + i), -14), 0.06)]), -9)
    add("World", "glide", place([(whoosh(1.2, 250, 900, 0.4, kind="pink") * 0.7, 0), (src(sw(23), -6, 0.8, d=1.2, lpf=2500), 0)]), -16)
    for i in range(2):  # boost: thruster burst and a big whoosh
        add("World", "boost_%d" % (i + 1), place([(src(KS + "thruster_fire_00%d.ogg" % (1 + i), -2, 0.9, d=0.9, fo=0.4), 0),
                                                  (src(sw(32 - i), 0, 0.8, peak=0.1), 0), (thump(120, 60, 0.3, 0.1, 0.3) * 0.5, 0)]), -11)
    for i in range(2):  # sonicBoom: crossing the top speed: a crack, a double boom, the air tearing
        add("World", "sonicBoom_%d" % (i + 1), place([
            (dsp.hp(dsp.noise(0.02), 2000) * dsp.env_exp(int(0.02 * SR), 0.004), 0),
            (thump(70, 28, 1.0, 0.3, 1.0, 3.2), 0), (thump(60, 26, 0.9, 0.3, 0.5, 3.0) * 0.8, 0.09),
            (src(KS + "low_frequency_explosion_00%d.ogg" % i, -3, 1.1), 0),
            (whoosh(1.2, 2500, 200, 0.05) * 0.5, 0.01),
        ]), -7, max_len=2.6)
    add("World", "dash", place([(src(sw(14), 0, 1.1), 0), (whoosh(0.3, 800, 4000, 0.4) * 0.4, 0)]), -13)
    for i in range(2):  # pound: the ground pound slam (dive whoosh into a crater boom)
        add("World", "pound_%d" % (i + 1), place([(thump(70, 26, 1.0, 0.32, 1.0, 3.2), 0), (src(KS + "explosion_crunch_00%d.ogg" % (4 - i), -2, 0.8), 0),
                                                  (src(KI + "impact_mining_00%d.ogg" % i, -2, 0.7), 0),
                                                  (reverb(src(RD + "BreakingFalling/bfh1_rock_breaking_0%d.opus" % (1 + i), -8), 1.0, 0.4), 0.05)]),
            -7, max_len=2.5)
    add("World", "bounce", place([(src(RD + "SFX100/spring_0%d.opus" % 3, 0), 0), (thump(160, 80, 0.2, 0.07, 0.2) * 0.5, 0),
                                  (src(sw(19), -4, 1.2), 0.03)]), -12)
    add("World", "splash", place([(src(RD + "WaterSplashSlime/splash_13.opus", 0), 0), (src(RD + "WaterSplashSlime/splash_05.opus", -4, 0.8), 0.05),
                                  (thump(90, 40, 0.3, 0.1, 0.1) * 0.4, 0)]), -11)
    for i in range(2):
        add("World", "swingShoot_%d" % (i + 1), place([(src(sw(9 + i), 0, 1.6), 0), (src(KU + "click%d.wav" % (2 + i), -6, 0.8), 0),
                                                       (whoosh(0.18, 3000, 7000, 0.3) * 0.3, 0)]), -14)
    for i in range(2):
        add("World", "swingRelease_%d" % (i + 1), place([(src(sw((24, 30)[i]), 0, 0.95, peak=0.05), 0), (whoosh(0.7, 400, 2200, 0.4) * 0.35, 0)]), -12)
    add("World", "swingMiss", place([(src(KF + "back_002.wav", 0, 0.8), 0), (src(sw(2), -6, 0.8), 0)]), -16)
    for i in range(2):
        add("World", "styleBurst_%d" % (i + 1), place([(src(sw((30, 40)[i]), 0, 1.0, peak=0.06), 0), (src(KD + "power_up_%d.ogg" % (8 + i), -8, d=0.5), 0.05)]), -12)
    add("World", "fastTravel", place([(whoosh(1.4, 200, 5000, 0.7) * 0.7, 0), (src(KD + "phaser_up_6.ogg", -6), 0.2), (src(sw(23), -4, d=1.6), 0)]), -12)
    add("World", "respawn", place([(src(KD + "power_up_2.ogg", -2), 0), (chord([523, 784, 1047], 1.0, 0.6, 0.1) * 0.3, 0.1),
                                   (src(KS + "force_field_002.ogg", -8, 1.1), 0)]), -13)
    add("World", "revive", place([(chord([392, 523, 659, 784, 1047], 1.2, 0.7, 0.07) * 0.6, 0), (src(KD + "power_up_5.ogg", -6), 0)]), -12)
    add("World", "moveTrain", place([(whoosh(0.9, 300, 3500, 0.85) * 0.6, 0), (chord([784, 1175, 1568], 0.8, 0.4, 0.05) * 0.35, 0.7)]), -12)
    for i in range(2):  # collapse: a building going down: groan, a deep rumble, cracking, the long debris rain
        add("World", "collapse_%d" % (i + 1), place([
            (src(RD + "WoodMetal/wood_cracking_0%d.opus" % (1 + i), -6, 0.6, lpf=2500), 0),
            (rumble(4.5, 110, 0.4, 2.0) * 0.9, 0.1),
            (thump(55, 24, 1.4, 0.5, 0.5, 3.0), 0.35),
            (src(KS + "low_frequency_explosion_000.ogg", -2, 0.75), 0.35),
            (src(RD + "BreakingFalling/bfh1_breaking_0%d.opus" % (1 + i), -2, 0.7), 0.4),
            (src(RD + "BreakingFalling/bfh1_rock_breaking_0%d.opus" % (2 + i), -4, 0.75), 0.9),
            (src(RD + "BreakingFalling/bfh1_glass_falling_0%d.opus" % (1 + i), -8), 1.2),
            (reverb(src(RD + "BreakingFalling/bfh1_rock_falling_0%d.opus" % (1 + 2 * i), -6, 0.8), 1.6, 0.5), 1.6),
            (reverb(src(RD + "BreakingFalling/bfh1_falling_0%d.opus" % (4 + i), -6, 0.8), 1.6, 0.5), 2.2),
        ]), -7, max_len=5.5)
    for i in range(2):  # crater: a crunch into the ground
        add("World", "crater_%d" % (i + 1), place([(thump(75, 28, 0.8, 0.25, 0.8, 3.0), 0), (src(KI + "impact_mining_00%d.ogg" % (2 + i), 0, 0.75), 0),
                                                   (src(RD + "BreakingFalling/bfh1_rock_breaking_03.opus", -4), 0.03),
                                                   (src(RD + "BreakingFalling/bfh1_rock_falling_0%d.opus" % (8 + i), -8), 0.2)]), -8)
    for i in range(3):  # wallSmash: crashing through a wall: crunch, boom, glass and chunks
        add("World", "wallSmash_%d" % (i + 1), place([(thump(80, 30, 0.8, 0.25, 0.9, 3.0), 0), (src(KI + "impact_plate_heavy_00%d.ogg" % (2 + i), 0, 0.75), 0),
                                                      (src(RD + "BreakingFalling/bfh1_breaking_0%d.opus" % (1 + i), -1), 0.01),
                                                      (src(RD + "BreakingFalling/bfh1_glass_breaking_0%d.opus" % (2 + i), -8), 0.04),
                                                      (src(RD + "BreakingFalling/bfh1_rock_falling_0%d.opus" % (3 + i), -6), 0.25)]), -7)
    for i in range(2):  # vehicleFlip: a car going over: metal whomp and rattle
        add("World", "vehicleFlip_%d" % (i + 1), place([(thump(90, 36, 0.6, 0.2, 0.6, 2.6) * 0.8, 0), (src(KI + "impact_metal_heavy_00%d.ogg" % (1 + i), 0, 0.6), 0),
                                                        (src(RD + "WoodMetal/metal_sheet_0%d.opus" % (2 + i), -4, 0.8), 0.05),
                                                        (src(KI + "impact_glass_light_00%d.ogg" % i, -10), 0.08)]), -9)
    # the living city (Config.Life.sounds)
    for i in range(2):  # honk: a cartoon car horn (two detuned square tones through a speaker band)
        f = (392, 349)[i]
        h = place([(horn(f, 0.32, "square", 3200, detune=0.002, a=0.01, r=0.06), 0), (horn(f * 1.26, 0.32, "square", 3200, detune=0.002, a=0.01, r=0.06) * 0.8, 0)])
        h = dsp.bp(h, 300, 3500)
        add("World", "honk_%d" % (i + 1), place([(h, 0), (h * 0.9, 0.42)]) if i == 0 else h, -15)
    flap = place([(dsp.bp(dsp.noise(0.04), 600, 4000) * dsp.env_exp(int(0.04 * SR), 0.012), k * 0.055 + 0.004 * ((k * 7) % 3)) for k in range(12)])
    add("World", "flutter", flap * np.linspace(1, 0.4, len(flap)), -16)
    add("World", "spray", place([(src(RD + "WaterSplashSlime/loop_water_02.opus", 0, d=1.5, fo=0.5), 0), (whoosh(1.5, 3000, 2000, 0.1) * 0.4, 0)]), -16)
    for i in range(2):
        add("World", "cans_%d" % (i + 1), place([(src(KI + "impact_tin_medium_00%d.ogg" % (2 * i + k % 2), -2, 1.0 + 0.1 * k), 0.07 * k + 0.02 * i) for k in range(4)]), -14)
    add("World", "pop", place([(src(KI + "impact_plate_medium_002.ogg", 0), 0), (thump(140, 60, 0.25, 0.08, 0.5) * 0.6, 0),
                               (src(RD + "WoodMetal/metal_hit_03.opus", -6), 0.02)]), -12)
    n = int(1.2 * SR)
    t = np.arange(n) / SR
    buzz = sum(np.sin(2 * np.pi * f * t * (1 + 0.01 * np.sin(2 * np.pi * 3 * t))) / (k + 1) for k, f in enumerate((180, 360, 540, 720)))
    buzz = dsp.bp(buzz + 0.3 * dsp.noise(1.2), 150, 3000) * dsp.adsr(n, 0.2, 0.1, 1, 0.3)
    add("World", "drone", buzz, -20)
    # lore, collectables and the rest of the world one-shots
    add("World", "collectNear", bell(2349, 0.6, 0.25) * 0.8, -22)
    add("World", "loreNear", place([(bell(1568, 0.8, 0.35) * 0.6, 0), (bell(2093, 0.7, 0.3) * 0.4, 0.12)]), -22)


# ---------------------------------------------------------------------------------------------------------
# Ui: buttons, rewards and stings (bells and the CC0 piano for the musical bits, Kenney's interface clicks)
# ---------------------------------------------------------------------------------------------------------
def build_ui():
    for i, f in enumerate(("click_002.wav", "click_003.wav", "click_005.wav")):
        add("Ui", "ui_%d" % (i + 1), place([(src(KF + f, 0), 0), (src(KU + "click%d.wav" % (i + 1), -8), 0)]), -18)
    C4 = 60

    def stack(*parts):
        return place(list(parts))

    major = [0, 4, 7, 12]
    add("Ui", "rescue", stack((keys([C4 + 7 + n for n in major], 0.07, 3), 0), (bell(1568, 1.0, 0.5) * 0.3, 0.25)), -12)
    add("Ui", "incidentClear", stack((keys([C4, C4 + 4, C4 + 7], 0.09, 3), 0), (keys([C4 + 12, C4 + 16, C4 + 19, C4 + 24], 0.0, 4, 2.0), 0.3),
                                     (src(KI + "impact_bell_heavy_002.ogg", -10, 1.6), 0.3)), -10)
    add("Ui", "levelUp", stack((keys([C4 + n for n in (0, 4, 7, 12, 16, 19, 24)], 0.06, 4, 1.8), 0), (chord([2093, 2637, 3136], 1.4, 0.7, 0.04) * 0.3, 0.4),
                               (src(KD + "power_up_12.ogg", -10), 0)), -9)
    add("Ui", "skillRank", stack((src(KF + "select_004.wav", 0), 0), (bell(1319, 0.6, 0.25) * 0.5, 0.04)), -15)
    add("Ui", "gearDrop", stack((bell(1047, 1.0, 0.45) * 0.7, 0), (bell(1568, 0.9, 0.4) * 0.5, 0.06), (src(KF + "glass_002.wav", -6), 0)), -13)
    add("Ui", "bossDefeated", stack((keys([C4 - 5, C4, C4 + 4, C4 + 7, C4 + 12], 0.1, 4, 2.4), 0), (keys([C4 - 12, C4 - 5, C4 + 12, C4 + 16], 0.0, 4, 2.4), 0.55),
                                    (src(RD + "Bang/fw_0%d.opus" % 1, -6), 0.6), (src(RD + "Bang/fw_0%d.opus" % 3, -8), 1.1)), -9, max_len=3.4)
    add("Ui", "combo", stack((keys([C4 + 7, C4 + 11, C4 + 14], 0.0, 3, 1.2), 0), (src(KF + "confirmation_002.wav", -8), 0)), -13)
    add("Ui", "purchase", stack((src(RD + "RPG/item_coins_0%d.opus" % 2, 0), 0), (bell(1760, 0.9, 0.4) * 0.5, 0.05)), -13)
    add("Ui", "photo", stack((src(KF + "switch_005.wav", 0, 0.8), 0), (dsp.hp(dsp.noise(0.05), 1500) * dsp.env_exp(int(0.05 * SR), 0.015) * 0.6, 0.04),
                             (src(KF + "switch_003.wav", -2, 1.2), 0.09)), -14)
    add("Ui", "contractDone", stack((src(KF + "confirmation_004.wav", 0), 0), (keys([C4 + 12, C4 + 19], 0.08, 3), 0.05)), -12)
    add("Ui", "pvpFlag", stack((horn(196, 0.7, cutoff=1800, vib=0.004), 0), (horn(294, 0.5, cutoff=2000) * 0.7, 0.1)), -12)
    sirenx = dsp.siren(3.2, 600, 1250, 1.6)
    add("Ui", "bossWarning", stack((reverb(dsp.bp(sirenx, 400, 3500) * dsp.adsr(len(sirenx), 0.2, 0.1, 1, 0.6), 1.4, 0.35), 0),
                                   (horn(49, 2.6, cutoff=500, vib=0.003, a=0.2, r=0.8), 0.2), (thump(60, 30, 1.0, 0.4, 0.2) * 0.6, 0.2)), -8, max_len=4.2)
    roar = src(RD + "RPG/creature_roar_0%d.opus" % 2, 0, 0.7, lpf=4000)
    add("Ui", "bossPhase", stack((roar, 0), (thump(60, 24, 1.2, 0.4, 0.6, 3.0), 0), (src(KS + "low_frequency_explosion_000.ogg", -4, 0.8), 0.05)), -8, max_len=3.0)
    add("Ui", "mentorPanel", stack((src(FS + "Owlish/Sound Effects Pack/Paper/pageturn1.opus", 0), 0), (src(KR + "book_flip_2.ogg", -4), 0)), -15)
    add("Ui", "mentorReward", stack((chord([1047, 1319, 1568, 2093], 1.2, 0.6, 0.06) * 0.7, 0), (src(KD + "power_up_3.ogg", -10), 0)), -12)
    add("Ui", "badgeEarned", stack((src(KI + "impact_plank_medium_001.ogg", 0, 0.7), 0), (thump(120, 50, 0.25, 0.08, 0.5) * 0.6, 0),
                                   (keys([C4 + 12, C4 + 16, C4 + 19], 0.06, 3), 0.12)), -11)
    add("Ui", "collectFind", stack((chord([1568, 2093, 2637], 0.8, 0.4, 0.05) * 0.7, 0), (src(KF + "glass_005.wav", -6), 0)), -13)
    add("Ui", "lorePage", stack((src(FS + "Owlish/Sound Effects Pack/Paper/paper-sketchbook-page-flips-1.opus", 0, d=0.7), 0),
                                (keys([C4 + 9, C4 + 12, C4 + 16], 0.1, 2, 1.8), 0.15)), -13)
    add("Ui", "contestCall", stack((horn(262, 0.5, cutoff=2200), 0), (horn(392, 0.7, cutoff=2400) * 0.9, 0.18), (src(FS + "qubodup/Swooshes/swosh-31.opus", -6), 0)), -11)
    add("Ui", "contestWin", stack((keys([C4 + 5, C4 + 9, C4 + 12, C4 + 17], 0.07, 4), 0), (src(RD + "Bang/fw_0%d.opus" % 2, -10), 0.3)), -10)
    add("Ui", "roguePage", stack((src(KR + "book_flip_1.ogg", 0), 0), (bell(1175, 0.7, 0.3) * 0.5, 0.1)), -13)
    add("Ui", "passTier", stack((keys([C4 + 2, C4 + 7, C4 + 11, C4 + 14], 0.06, 3), 0), (src(FS + "qubodup/Swooshes/swosh-26.opus", -6, 1.2), 0)), -12)
    add("Ui", "passClaim", stack((src(RD + "RPG/item_coins_0%d.opus" % 1, 0), 0), (bell(2349, 0.6, 0.25) * 0.4, 0.04)), -13)
    add("Ui", "episodeIntro", stack((src(FS + "Owlish/Sound Effects Pack/Paper/pageturn2.opus", 0), 0), (keys([C4 - 3, C4 + 4], 0.12, 2, 1.6), 0.1)), -14)
    add("Ui", "boardReward", stack((keys([C4 + 7, C4 + 12, C4 + 16, C4 + 19], 0.08, 4), 0), (src(KI + "impact_bell_heavy_001.ogg", -10, 1.4), 0.3)), -11)
    add("Ui", "dailyClaim", stack((src(RD + "RPG/item_coins_0%d.opus" % 3, 0), 0), (src(RD + "RPG/item_coins_0%d.opus" % 4, -4), 0.12),
                                  (keys([C4 + 12, C4 + 16, C4 + 19], 0.07, 3), 0.1)), -11)
    add("Ui", "dailyQuest", stack((bell(1568, 0.8, 0.35) * 0.6, 0), (bell(2093, 0.8, 0.35) * 0.5, 0.08), (src(KF + "confirmation_001.wav", -8), 0)), -13)
    add("Ui", "questAccept", stack((src(FS + "qubodup/Swooshes/swosh-29.opus", 0, 1.1), 0), (keys([C4 + 2, C4 + 9], 0.1, 3), 0.1)), -12)
    add("Ui", "questStep", stack((bell(1319, 0.8, 0.35) * 0.6, 0), (bell(1976, 0.7, 0.3) * 0.5, 0.07), (src(KF + "select_002.wav", -8), 0)), -13)
    add("Ui", "questVillain", stack((keys([C4 - 24, C4 - 23, C4 - 12], 0.0, 4, 2.0), 0), (horn(55, 1.6, cutoff=600, vib=0.004), 0),
                                    (thump(60, 28, 0.8, 0.3, 0.3) * 0.6, 0)), -10)
    add("Ui", "questEncore", stack((horn(98, 0.9, cutoff=1400), 0), (horn(147, 0.8, cutoff=1500) * 0.7, 0.05), (src(FS + "qubodup/Swooshes/swosh-41.opus", -4, 0.8), 0)), -10)
    add("Ui", "questFinale", stack((thump(70, 28, 0.9, 0.3, 0.8, 3.0), 0), (src(KS + "explosion_crunch_001.ogg", -6), 0),
                                   (keys([C4, C4 + 7, C4 + 12, C4 + 16], 0.0, 4, 2.0), 0.1)), -9)
    add("Ui", "questDone", stack((keys([C4 + 7, C4 + 12, C4 + 16, C4 + 19, C4 + 24], 0.08, 4, 2.0), 0), (chord([2093, 2637, 3136], 1.2, 0.6, 0.0) * 0.3, 0.45)), -10)
    add("Ui", "questRetry", stack((keys([C4 + 7, C4 + 3, C4 - 2], 0.14, 2, 1.4), 0),), -15)
    for nm, f, part in (("radio", 2400, (src(KF + "tick_002.wav", -4), 0)), ("guideLodestar", 880, (src(KF + "tick_004.wav", -6, 0.7), 0)),
                        ("guideCrane", 660, (src(KF + "drop_002.wav", -4, 0.9), 0)), ("guideInsider", 1760, (src(KF + "tick_001.wav", -6), 0)),
                        ("guideFake", 1320, (src(KF + "glitch_001.wav", -10), 0))):
        add("Ui", nm, stack((bell(f, 0.25, 0.06, partials=((1, 1), (2, 0.3))) * 0.6, 0), part), -20)


# ---------------------------------------------------------------------------------------------------------
# Loops: held sounds and the city beds (each a seamless loop, played with a LoopRegion)
# ---------------------------------------------------------------------------------------------------------
def wind(dur, lo=200, hi=1200, gust=0.15, seed_shift=0.0):
    """Wind: pink noise in a slowly wandering band, with gusts."""
    n = int(dur * SR)
    x = dsp.noise(dur, "pink")
    t = np.arange(n) / SR
    g = 0.65 + gust * np.sin(2 * np.pi * (t / 3.7 + seed_shift)) + gust * 0.7 * np.sin(2 * np.pi * (t / 1.9 + 0.3))
    a = dsp.bp(x, lo, hi) * g
    b = dsp.bp(x[::-1].copy(), hi * 0.8, hi * 2.2) * (1.2 - g) * 0.4
    return a + b


def build_loops():
    loop_clip("Loops", "flyCruise", wind(6.4, 180, 1100, 0.18), -14)
    run = wind(4.4, 500, 2500, 0.1) + dsp.bp(dsp.sweep_sine(4.4, 1800, 1800, 0) * 0.2, 1000, 3000) * 0.3
    loop_clip("Loops", "speedRun", run, -14)
    beat = place([(thump(62, 40, 0.18, 0.06, 0.05, 1.6), 0), (thump(55, 38, 0.2, 0.07, 0.05, 1.6) * 0.75, 0.24)])
    hb = np.zeros(int(0.92 * SR))
    hb[: len(beat)] += beat
    hb = lp(hb, 500, 2)
    hb = np.concatenate([hb, hb])
    ATLASES.setdefault("Loops", []).append(("downed", dsp.limit(hb * db(-14 - dsp.short_rms_db(hb))), True))
    # Downtown: the traffic hum (CC0 highway loop under a low city drone), far sirens and a horn or two
    hw = src(RD + "SFX100V2/sfx100v2_loop_highway.opus", 0, lpf=2600)
    traffic = np.concatenate([hw, hw[::-1].copy(), hw])[: int(44 * SR)]
    drone = lp(dsp.noise(44, "brown"), 160, 2) * 0.5
    far = lambda x, d=0.0: reverb(lp(x, 1800, 2), 2.0, 0.6)  # noqa: E731
    s1 = far(dsp.siren(7.0, 680, 1300, 2.4)) * 0.06
    s2 = far(dsp.siren(5.0, 900, 1500, 0.5, "yelp")) * 0.04
    h1 = far(dsp.bp(horn(415, 0.25, "square", 3000, a=0.01, r=0.05), 300, 3000)) * 0.05
    down = place([(traffic, 0), (drone, 0), (s1, 9.0), (s2, 29.0), (h1, 17.5), (h1 * 0.8, 38.0)])[: int(44 * SR)]
    loop_clip("Loops", "bedDowntown", down, -22, 1.5)
    # Docks: water lapping, a harbour bell, a far foghorn, gulls, a breeze
    w1 = src(RD + "SFX100V2/sfx100v2_loop_water_02.opus", 0, lpf=3000)
    water = np.concatenate([w1, w1[::-1].copy(), w1, w1[::-1].copy(), w1])[: int(40 * SR)]

    def gull(f=1500):
        n = int(0.42 * SR)
        t = np.linspace(0, 1, n)
        fr = f * (1 + 0.5 * np.sin(np.pi * t) - 0.35 * t)
        ph = 2 * np.pi * np.cumsum(fr) / SR
        g = (np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.3 * np.sin(3 * ph)) * np.sin(np.pi * t) ** 0.6
        return dsp.bp(g + 0.1 * dsp.noise(0.42), 800, 5000)

    cries = place([(gull(1400 + 120 * k) * (0.8 if k % 2 else 1), k * 0.5) for k in range(3)])
    foghorn = horn(73, 3.2, cutoff=420, a=0.4, r=1.0)
    docks = place([(water, 0), (wind(40, 200, 800, 0.2) * 0.25, 0), (far(src(FS + "ShipsBells/tang.opus", 0)) * 0.12, 6.0),
                   (far(foghorn) * 0.16, 15.0), (far(cries) * 0.1, 3.0), (far(cries[::-1].copy()) * 0.08, 24.0),
                   (far(cries) * 0.07, 33.0), (far(src(FS + "ShipsBells/tang.opus", 0)) * 0.1, 30.0)])[: int(40 * SR)]
    loop_clip("Loops", "bedDocks", docks, -22, 1.5)
    # Outskirts: open air, far traffic, a crow or two
    out = place([(wind(40, 150, 700, 0.22) * 0.6, 0), (lp(traffic[: int(40 * SR)], 900) * 0.25, 0),
                 (far(src(FS + "Superpowers/western-fps-2d/raven-2.opus", 0)) * 0.12, 12.0)])[: int(40 * SR)]
    loop_clip("Loops", "bedOutskirts", out, -24, 1.5)
    # Rooftops: the wind up high (mixed in by camera height)
    loop_clip("Loops", "bedRooftop", wind(24, 250, 1600, 0.28, 0.4) + wind(24, 100, 400, 0.2) * 0.5, -20, 1.2)


# ---------------------------------------------------------------------------------------------------------
# Ambient (alive-world, 2026-11-20): the sounds the city and the prologue still lacked. Sources: Owlish's CC0 clap
# and gasp and rubberduck's CC0 rain loops (OpenGameArt, in Free-SFX), Kenney's CC0 sci-fi engines and RPG clicks,
# and our own synth (gulls, birds, the crowd's murmur, the radio's static and beep)
# ---------------------------------------------------------------------------------------------------------
def vari(x, ratio):
    """Resample with a time-varying speed (ratio: an array as long as the output, 1 = as recorded)."""
    pos = np.cumsum(ratio)
    pos = pos[pos < len(x) - 2]
    i = pos.astype(int)
    f = pos - i
    return x[i] * (1 - f) + x[i + 1] * f


def onsets(x, thr_db=-30, gap=0.12):
    """The starts of the separate hits in a clip (a clap take): where the 5 ms envelope jumps over thr_db."""
    w = int(0.005 * SR)
    e = np.convolve(np.abs(x), np.ones(w) / w, "same")
    thr = np.max(e) * db(thr_db)
    out, last = [], -1e9
    for k in np.where(e > thr)[0]:
        if k - last > gap * SR:
            out.append(k)
        last = k if k - last > gap * SR else last
    return out


def build_ambient():
    g = np.random.default_rng(20261120)
    # --- applause: 46 people clapping, each their own rate and hands (the single clap take's claps), near ones
    # brighter, far ones darker; a few whistles; a low murmur of voices under it (filtered noise in vowel bands)
    take = dsp.load(OW + "Human/solo-clap.opus")
    claps = []
    for k in onsets(take):
        c = take[max(0, k - int(0.004 * SR)): k + int(0.11 * SR)]
        if len(c) > int(0.05 * SR):
            claps.append(fade(c.copy(), 0.0005, 0.04))
    dur = 16.0
    n = int(dur * SR)
    gen = dur + 2.5  # clap on past the loop's end, so its crossfade blends clapping into clapping
    clapping = np.zeros(int(gen * SR) + SR)
    for person in range(46):
        near = g.random()
        hz = 3.2 + g.random() * 2.4
        t = g.random() * 0.4
        tone = rate(claps[person % len(claps)], 0.85 + g.random() * 0.4)
        tone = lp(tone, 2500 + 6000 * near) * (0.25 + 0.75 * near)
        while t < gen:
            a = int(t * SR)
            clapping[a: a + len(tone)] += tone * (0.7 + 0.3 * g.random())
            t += (1 / hz) * (0.9 + 0.2 * g.random())
    n = int(gen * SR)
    clapping = clapping[:n]
    murmur = np.zeros(n)
    base = dsp.noise(gen, "pink")
    for lo, hi, rate_hz in ((300, 700, 2.1), (800, 1300, 3.3), (1700, 2600, 2.7)):
        tt = np.arange(n) / SR
        wob = 0.55 + 0.45 * np.sin(2 * np.pi * (rate_hz * tt + g.random())) * np.sin(2 * np.pi * (0.37 * tt + g.random()))
        murmur += dsp.bp(base, lo, hi) * wob
    whistles = []
    for path in (OW + "Human/wolf-whistle.opus", OW + "Human/attention-whistle.opus"):
        whistles.append(reverb(lp(src(path, -4), 6000), 1.4, 0.35))
    crowd = place([(clapping, 0), (murmur * 0.05, 0), (whistles[0] * 0.18, 3.1), (whistles[1] * 0.14, 9.4),
                   (rate(whistles[0], 1.12) * 0.12, 13.0)])[:n]
    crowd = reverb(crowd, 1.6, 0.22)[int(1.0 * SR): n]  # the reverb settled at the head, the tail still clapping
    loop_clip("Ambient", "crowdCheer", crowd, -17, 0.8)
    # --- the crowd's gasp: the one gasp take (its first breath in) as fourteen voices, pitched for men, women and
    # kids, a hair apart, in the plaza's reverb
    gasp = cut(dsp.load(OW + "Human/gasp1.opus"), 0.12, 0.55)
    gasp = fade(hp(gasp, 180), 0.004, 0.12)
    for v in range(2):
        layers = []
        for k in range(14):
            r = (0.82, 0.95, 1.08, 1.25)[k % 4] * (0.95 + 0.1 * g.random())
            layers.append((lp(rate(gasp, r), 3000 + 5000 * g.random()) * (0.5 + 0.5 * g.random()), 0.12 * g.random()))
        add("Ambient", "crowdGasp_%d" % (v + 1), reverb(place(layers), 1.3, 0.3), -14)
    # --- the scanner drone's hum: Kenney's low engine under a slow electric throb and a faint high whine
    eng = src(KS + "space_engine_low_002.ogg", 0, 0.8, lpf=1800)
    eng = np.concatenate([eng, eng[::-1].copy()] * 4)[: int(8 * SR)]
    tt = np.arange(int(8 * SR)) / SR
    throb = (np.sin(2 * np.pi * 55 * tt) + 0.5 * np.sin(2 * np.pi * 110 * tt)) * (0.6 + 0.4 * np.sin(2 * np.pi * 1.0 * tt))
    whine = np.sin(2 * np.pi * (1760 * tt + 6 * np.sin(2 * np.pi * 0.5 * tt))) * 0.04
    loop_clip("Ambient", "scanHum", eng * 0.7 + throb * 0.25 + whine, -20, 0.5)
    # --- Patch's radio: a key-up click, a squelch of band-passed static and a two-tone beep (a walkie-talkie)
    static = dsp.bp(dsp.noise(0.16), 900, 3200) * np.linspace(1, 0.2, int(0.16 * SR))
    beep = np.concatenate([np.sin(2 * np.pi * 1320 * np.arange(int(0.06 * SR)) / SR),
                           np.sin(2 * np.pi * 1760 * np.arange(int(0.07 * SR)) / SR)])
    radio = place([(src(KF + "tick_002.wav", -2), 0), (static * 2.2, 0.01), (fade(beep, 0.003, 0.02) * 0.5, 0.11)])
    add("Ambient", "patchRadio", dsp.bp(radio, 300, 3800), -18)
    # --- harbour gulls: a "kee-ow" call (a rising then falling cry with a rough edge), two to four in a row
    def cry(f, dur):
        m = int(dur * SR)
        t = np.linspace(0, 1, m)
        fr = f * (1 + 0.55 * np.sin(np.pi * np.minimum(t * 1.4, 1)) - 0.45 * t)
        ph = 2 * np.pi * np.cumsum(fr) / SR
        rough = 1 + 0.35 * np.sin(2 * np.pi * 42 * t * dur)
        y = (np.sin(ph) + 0.6 * np.sin(2 * ph) + 0.35 * np.sin(3 * ph) + 0.2 * np.sin(4 * ph)) * rough
        y *= np.sin(np.pi * t) ** 0.5 * (1 - 0.6 * t)
        return dsp.bp(y + 0.08 * dsp.noise(dur), 700, 6000)
    for v in range(3):
        calls = []
        t = 0.0
        for k in range(2 + v):
            d = 0.28 + 0.14 * g.random()
            calls.append((cry(1300 + 260 * g.random(), d) * (1 - 0.15 * k), t))
            t += d + 0.06 + 0.1 * g.random()
        add("Ambient", "gull_%d" % (v + 1), reverb(place(calls), 0.9, 0.18), -15)
    # --- the crane's winch: a motor whine that spins up, runs and spins down (Kenney's circular engine at a
    # varying speed), a ratchet's clicks at the gear's rate, a clunk at the start and the stop. As long as one run
    # of the trolley (Config.Life.cranes: |b - a| / speed x 1.5 = 11.57 s), easing like it
    run = 11.57
    motor = src(KS + "engine_circular_001.ogg", 0)
    motor = np.concatenate([motor, motor[::-1].copy()] * 16)
    m = int(run * SR)
    curve = ([0, 1.0, run - 1.6, run], [0.45, 1.2, 1.2, 0.4])
    sp = np.interp(np.arange(m) / SR, *curve)
    whine = fade(vari(motor, sp)[:m], 0.05, 0.8)
    clicks = []
    t = 0.3
    while t < run - 0.5:
        clicks.append((src(KR + "metal_click.ogg", -14, 1.6), t))
        t += 0.11 / float(np.interp(t, *curve))
    winch = place([(whine, 0), (src(KI + "impact_metal_heavy_001.ogg", -6, 0.8), 0),
                   (src(KI + "impact_metal_heavy_003.ogg", -8, 0.85), run - 0.3)] + clicks)
    add("Ambient", "winch", winch, -16)
    # --- the park's bed: birds (several kinds of chirp, trill and whistle, scattered), a breeze in the leaves and
    # the far city under it
    def chirp(f0, f1, d):
        m = int(d * SR)
        t = np.linspace(0, 1, m)
        fr = f0 + (f1 - f0) * t ** 0.7
        y = np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.sin(np.pi * t) ** 1.5
        return y

    def song(kind):
        if kind == 0:  # a quick rising chirp, repeated
            return place([(chirp(3200, 4800, 0.06), 0.09 * k) for k in range(4)])
        if kind == 1:  # a trill
            return place([(chirp(5200, 4400, 0.03), 0.045 * k) for k in range(12)])
        if kind == 2:  # a two-note whistle, falling
            return place([(chirp(2600, 2700, 0.18), 0), (chirp(2100, 2000, 0.22), 0.24)])
        return place([(chirp(4000, 2800, 0.08), 0), (chirp(3600, 4200, 0.07), 0.12), (chirp(4400, 3000, 0.1), 0.22)])

    pdur = 32.0
    birds = []
    t = 0.3
    while t < pdur - 1.5:
        kind = int(g.integers(0, 4))
        dist = g.random()
        b = song(kind)
        b = rate(b, 0.9 + 0.2 * g.random())
        birds.append((reverb(lp(b, 9000 - 5000 * dist), 0.8, 0.2 + 0.3 * dist) * (0.5 - 0.35 * dist), t))
        t += 0.35 + 1.4 * g.random()
    hw = src(RD + "SFX100V2/sfx100v2_loop_highway.opus", 0, lpf=900)
    far = np.concatenate([hw, hw[::-1].copy()] * 8)[: int(pdur * SR)]
    park = place([(wind(pdur, 300, 2200, 0.25, 0.7) * 0.18, 0), (far * 0.08, 0)] + birds)[: int(pdur * SR)]
    loop_clip("Ambient", "bedPark", park, -24, 1.5)
    # --- rain: two CC0 rain loops (a steady wash and a closer patter), long enough not to repeat by ear, with the
    # roofs' low drumming under it
    r1 = src(RD + "Loops/rain.opus", 0)
    r2 = src(RD + "WaterSplashSlime/loop_rain.opus", 0)
    rdur = 14.0
    a = np.concatenate([r1, r1[::-1].copy()] * 3)[: int(rdur * SR)]
    b = np.concatenate([r2, r2[::-1].copy()] * 2)[: int(rdur * SR)]
    drum = lp(dsp.noise(rdur, "brown"), 220) * 0.35
    loop_clip("Ambient", "rain", place([(a, 0), (b * 0.7, 0), (drum, 0)])[: int(rdur * SR)], -20, 1.0)


GAP = 0.25


def merged(meta):
    """The clips.json on disk with this run's atlases replaced (an --only build)."""
    path = os.path.join(OUT, "clips.json")
    out = json.load(open(path)) if os.path.isfile(path) else {}
    out.update(meta)
    json.dump(out, open(path, "w"), indent=1)
    return out


def write_atlases(dump=True):
    os.makedirs(OUT, exist_ok=True)
    meta = {}
    for atlas, clips in ATLASES.items():
        parts, t, rows = [], 0.0, {}
        parts.append(np.zeros(int(0.05 * SR)))
        t = 0.05
        for name, x, loop in clips:
            n = len(x)
            rows[name] = [round(t, 4), round(n / SR, 4), loop]
            parts.append(x)
            parts.append(np.zeros(int(GAP * SR)))
            t += n / SR + GAP
        y = np.concatenate(parts)
        dsp.write_ogg(y, os.path.join(OUT, atlas + ".ogg"), 5 if atlas != "Loops" else 4)
        meta[atlas] = rows
        print("build.py: %s %d clips, %.1f s" % (atlas, len(clips), len(y) / SR))
    if dump:
        json.dump(meta, open(os.path.join(OUT, "clips.json"), "w"), indent=1)
    return meta


def write_luau(meta):
    meta = dict(meta)
    mj = os.path.join(OUT, "music.json")
    if os.path.isfile(mj):
        meta["Music"] = json.load(open(mj))  # music.py's tracks (one stereo atlas)
    ids_path = os.path.join(HERE, "ids.json")
    ids = json.load(open(ids_path)) if os.path.isfile(ids_path) else {}
    L = ["-- AudioClips: GENERATED by art/audio/build.py (do not edit by hand). The sound atlases (one Roblox audio asset",
         "-- each, art/export/audio/<Atlas>.ogg uploaded by art/audio/upload.py) and every clip's region inside its atlas:",
         "-- clips[name] = { atlas, start, length, loop }. Config.Audio and Config.Life rows name clips (`clip`, variants",
         "-- `clip_1`..`clip_n`); Shared.SoundPick resolves a row to its atlas id and a region. Sources and licences:",
         "-- notes/Tools.md \"Sounds\" (all CC0, plus our own synth layers). An atlas id of 0 means not uploaded yet",
         "-- (the row's built-in fallback plays).", "", "return {", "\tatlases = {"]
    for atlas in sorted(meta):
        L.append("\t\t%s = %d," % (atlas, int(ids.get(atlas, 0))))
    L.append("\t},")
    L.append("\tclips = {")
    for atlas in sorted(meta):
        for name, (s, n, loop) in meta[atlas].items():
            L.append("\t\t%s = { \"%s\", %s, %s%s }," % (name, atlas, repr(s), repr(n), ", true" if loop else ""))
    L.append("\t},")
    L.append("}")
    open(os.path.join(REPO, "src", "config", "AudioClips.luau"), "w").write("\n".join(L) + "\n")


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--ids":  # only rewrite AudioClips.luau (after an upload)
        write_luau(json.load(open(os.path.join(OUT, "clips.json"))))
        return 0
    if len(sys.argv) < 2:
        print("usage: python3 -I art/audio/build.py <download root> | --ids")
        return 1
    dsp.ROOT = sys.argv[1]
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    builders = {"Hits": [build_hits, build_paths], "World": [build_world], "Ui": [build_ui], "Loops": [build_loops],
                "Ambient": [build_ambient]}
    for name, fns in builders.items():
        if only is None or only == name:
            for fn in fns:
                fn()
    if dsp.MISSING:
        print("build.py: missing sources:\n  " + "\n  ".join(sorted(dsp.MISSING)))
        return 1
    meta = write_atlases(dump=only is None)
    if only:
        meta = merged(meta)  # keep the other atlases' regions as they were built (their files are not rewritten)
    write_luau(meta)
    print("build.py: sources used:", ", ".join(sorted(SOURCES)))
    return 0


sys.exit(main())
