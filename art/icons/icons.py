"""The game's icon set in the pure comic UI style (gap-icons, 2026-11-19; nate's comic pick, Kit.luau).

Every power (Config.Abilities: 17 paths, 136 abilities with the supers), the 36 weapons plus the move
badges for their combo and Z X C V moves, the 5 mobility picks, the 4 gadgets, Awakening, the shield
(block) button and the power swap, the 8 gear slots and a frame per gear tier. Each icon is a comic
sticker: bold ink outline, hard ink shadow, flat cel colours, no text.

  * A power's icon = its path's disc (the path colour with the path's element motif drawn tone on tone
    behind, halftone dots, an ink ring; a super gets a gold ring) + a symbol for what the power does
    (bolt, chain, dash, cone, field, wall, ride...: ABILITY below). No two powers in a path share a symbol.
  * A weapon's icon = a disc in its family's colour with the weapon's silhouette; a weapon move shows it
    with a small move badge (combo, or 1 to 4 pips for Z X C V) on top.
  * A gear piece = the tier frame (tier colour, halftone, ink, 1 to 6 pips along the bottom, studs and
    rays on the high tiers) with the slot symbol over it.

Cells are 128 px (drawn at 512 and shrunk, so they read at 48 px on a phone), packed 8 x 8 into 1024 px
sheets. Deterministic: run it again and the PNGs are identical.

The second set (gap-icons2, symbols2.py) starts on sheet 5: the open world (incidents, events, contracts,
bosses and markers, drawn on clear ground and laid by the UI over six white shape backings it tints) and the
books (badge groups, collections, accolades, Journal tabs, Rogues groups, daily rewards, boards, movement
buttons). Preview art/preview/icons2.png.

    python3 art/icons/icons.py      -> art/export/icons/icons_<n>.png,
                                       src/config/Icons.luau (ids from art/icons/ids.json),
                                       art/preview/icons.png (the contact sheet)
"""

import json
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from ink import GOLD, INK, Sym, mix, rgba, shade, star, ngon, arcpts, bolt, flame, crescent, rot  # noqa: E402
from symbols import SYM  # noqa: E402
import symbols2  # noqa: E402,F401  (gap-icons2: the second set's symbols join SYM)

ROOT = os.path.dirname(os.path.dirname(HERE))
CELL = 128
SS = 4
BIG = CELL * SS
SHEET = 1024
PER_ROW = SHEET // CELL
PER_SHEET = PER_ROW * PER_ROW
MOVE_ORDER = []

# ---------------------------------------------------------------- the game's data (read from src/config)


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def abilities():
    src = read("src/config/Abilities.luau")
    out = []
    for m in re.finditer(r'add\((\d+), "(\w+)", \{(.*?)\n\}\)', src, re.S):
        body = m.group(3)

        def field(k):
            f = re.search(r"^\t%s = \"(\w+)\"" % k, body, re.M)
            return f.group(1) if f else None

        out.append({"num": int(m.group(1)), "id": m.group(2), "set": field("set"), "slot": field("slot"),
                    "shape": field("shape")})
    out.sort(key=lambda a: a["num"])
    return out


def order_list(src, name):
    m = re.search(r"%s = \{([^}]*)\}" % name, src)
    return re.findall(r'"(\w+)"', m.group(1))


def weapons():
    src = read("src/config/Weapons.luau")
    return [(int(n), fam, name) for n, fam, name in re.findall(r'\{ (\d+), "(\w+)", "([^"]+)", \d', src)]


# ---------------------------------------------------------------- what each icon shows

# every power's symbol (symbols.py). A new ability must get one here: the script stops if one is missing.
ABILITY = {
    # Volt (Storm)
    "ZapBolt": "zap", "ChainLightning": "chain", "DashStrike": "boltride", "StaticField": "sparkfield",
    "ArcFlash": "cone", "Overcharge": "battery", "GroundSpark": "groundline", "ThunderDrop": "thunder",
    # Frost
    "IceShard": "shard", "FreezeBeam": "beam", "IceSlide": "ramp", "FrostNova": "snowburst",
    "SnowWall": "wall", "GlacierArmor": "armor", "Shatter": "crack", "BlizzardDome": "dome",
    # Titan (Brawler)
    "PunchCombo": "fist", "LiftAndThrow": "throw", "GroundSlam": "slam", "ShoulderCharge": "charge",
    "Brace": "shield", "Haymaker": "haymaker", "RallyRoar": "roar", "MeteorLeap": "meteor",
    # Pulse (Gravity)
    "PushWave": "push", "Pull": "magnet", "Float": "float", "GravityWell": "vortex", "Repulse": "repulse",
    "Weightless": "feather", "Crush": "anvil", "Singularity": "blackhole",
    # Blade (Swordsman)
    "BladeSlash": "swordslash", "FlashStep": "dash", "CrescentWave": "crescent", "RisingBlade": "swordup",
    "ThousandCuts": "crossed", "ParryStance": "parry", "BladeStorm": "tornado", "HeavenSplitter": "splitter",
    # Fire
    "FlareShot": "fireball", "FlameJets": "rocket", "FireWhip": "whip", "EmberRing": "ring",
    "Flashpoint": "explosion", "HeatHaze": "haze", "PhoenixDive": "wingdive", "Sunfall": "sun",
    # Earth
    "PebbleBarrage": "pebbles", "RockRide": "rockride", "StonePillar": "pillar", "Quicksand": "quicksand",
    "MudWave": "wave", "VineSnare": "vine", "Sandstorm": "tornado", "Overgrowth": "sprout",
    # Tide
    "WaterJet": "jet", "WaveSurf": "surf", "BubblePrison": "bubble", "Riptide": "vortex", "Geyser": "geyser",
    "HealingRain": "rain", "TideMirror": "mirror", "Tsunami": "wave",
    # Gunslinger
    "TwinPistols": "twinblaster", "RecoilJump": "launch", "Ricochet": "ricochet", "TrickShot": "trickshot",
    "BulletTime": "hourglass", "GrenadeRoll": "grenade", "DeadeyeMark": "crosshair", "HighNoon": "sheriff",
    # Gadgeteer
    "WristBlaster": "wristblaster", "Hoverboard": "board", "TurretDrop": "turret", "GrappleYank": "hook",
    "ShockMines": "mine", "FixItDrone": "wrench", "HoloDecoy": "decoy", "MechSuit": "mech",
    # Shadow
    "KunaiThrow": "kunai", "ShadowStep": "step", "SmokeBomb": "smoke", "ShadowClones": "clones",
    "ChainSickle": "sickle", "NightMark": "eye", "WallRunStrike": "wallrun", "Eclipse": "eclipse",
    # Martial (Martial Artist)
    "KiStrike": "palm", "SkyStep": "steps", "KiBlast": "orb", "HundredFists": "fists",
    "CounterPalm": "counter", "DragonRise": "rising", "SpiritFocus": "lotus", "HeavenfallBeam": "beamdown",
    # Juggernaut
    "GauntletSmash": "gauntlet", "Unstoppable": "charge", "IronHide": "armor", "GirderSwing": "girder",
    "ShockwaveStomp": "stomp", "Bulldoze": "plow", "Challenge": "challenge", "SiegeMode": "tower",
    # Colossus
    "GiantSwipe": "swipe", "GiantStride": "stride", "Grow": "grow", "CarToss": "car", "ThunderClap": "clap",
    "BoulderFist": "boulder", "ShrinkDodge": "shrink", "TitanForm": "colossus",
    # Mind
    "PsiBolt": "psibolt", "PsiPlatform": "platform", "Telekinesis": "levitate", "Override": "spiral",
    "MindShield": "shield", "PsychicLink": "link", "Foresight": "eye", "PsychicStorm": "storm",
    # Spirit
    "GuardianJab": "fist", "SpiritRide": "wisp", "GuardianRush": "charge", "SoulChains": "chainlinks",
    "WardTotem": "totem", "GuardianShield": "guardian", "SpiritSwap": "swap", "AscendedGuardian": "wings",
    # Light
    "LightLance": "lance", "LightRail": "rail", "PrismBeam": "prism", "RadiantHeal": "heal", "Flash": "flash",
    "Sanctuary": "sanctuary", "HaloBlades": "halo", "Dawnburst": "dawn",
}

WEAPON = {
    1: "w_fists", 2: "w_martial", 3: "w_gauntlet", 4: "w_strikers", 5: "w_sword", 6: "w_katana", 7: "w_axe",
    8: "w_mace", 9: "w_baton", 10: "w_dagger", 11: "w_greatsword", 12: "w_greataxe", 13: "w_hammer",
    14: "w_spear", 15: "w_scythe", 16: "w_staff", 17: "w_twin", 18: "w_claws", 19: "w_sai", 20: "w_tonfa",
    21: "w_nunchucks", 22: "w_roundshield", 23: "w_towershield", 24: "w_swordshield", 25: "w_pistol",
    26: "w_twinblasters", 27: "w_rifle", 28: "w_bow", 29: "w_crossbow", 30: "w_cannon", 31: "w_stars",
    32: "w_whip", 33: "w_fan", 34: "w_yoyo", 35: "w_ropedart", 36: "w_boomerang",
}
MOVE = {"M1": "b_combo", "Z": "b_move1", "X": "b_move2", "C": "b_move3", "V": "b_move4"}
MOBILITY = {"flight": "m_flight", "speed": "m_speed", "leap": "m_leap", "acrobat": "m_acrobat",
            "swing": "m_swing"}
GADGET = {"GrapplingHook": "g_grapple", "SmokeBomb": "g_smoke", "ShieldDrone": "g_drone", "Decoy": "g_decoy"}
ACTION = {"Awaken": "a_awaken", "Block": "a_block", "Power": "a_power"}
# the mobility rework's 20 moves (nate 2026-11-20; Config.Move.moves, offered by the rank rows' `choice`): a third set
# on its own sheet after the second, so the uploaded sheets stay byte-identical. Rank 5's moves get a gold ring.
MOBMOVE = {
    "sonicDive": "wingdive", "slipstream": "jet", "phase": "haze", "blazeRam": "fireball",
    "tornadoRun": "tornado", "afterimage": "decoy", "sonicWake": "wave", "blink": "flash",
    "impactLanding": "stomp", "wallCrusher": "crack", "meteorStrike": "meteor", "moonJump": "rising",
    "kickChain": "wallrun", "ceilingDrop": "slam", "shadowFlip": "clones", "slingshot": "launch",
    "doubleZip": "g_grapple", "yank": "magnet", "wreckingKick": "explosion", "skyHook": "hook",
}

# path discs: the background (Config.Abilities.setColor, deepened where a pale one would wash out a white
# symbol) and the element motif drawn tone on tone behind the symbol
PATH_BG = {
    "Volt": (70, 170, 245), "Frost": (110, 195, 240), "Fire": (250, 105, 40), "Earth": (165, 120, 70),
    "Tide": (40, 135, 240), "Blade": (235, 60, 85), "Gunslinger": (245, 180, 50), "Gadgeteer": (50, 200, 135),
    "Shadow": (115, 75, 195), "Titan": (250, 140, 50), "Martial": (250, 190, 70), "Juggernaut": (125, 140, 160),
    "Colossus": (220, 85, 55), "Pulse": (170, 100, 245), "Mind": (240, 95, 200), "Spirit": (40, 205, 185),
    "Light": (250, 210, 80),
}
FAMILY_BG = {"fists": (245, 140, 60), "one": (225, 70, 80), "two": (150, 90, 210), "dual": (40, 180, 170),
             "shield": (70, 130, 230), "ranged": (80, 190, 100), "exotic": (235, 90, 170)}
OTHER_BG = {"mobility": (255, 210, 60), "gadget": (60, 190, 200), "Awaken": (255, 200, 60),
            "Block": (110, 180, 255), "Power": (120, 210, 255), "move": (255, 210, 60)}
TIER_ORDER = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]


def palette(bg):
    return {
        "bg": rgba(bg), "w": (255, 251, 238, 255), "a": shade(bg, -0.45), "d": shade(bg, 0.28),
        "y": GOLD, "o": (255, 140, 40, 255), "r": (240, 70, 70, 255), "s": (200, 208, 222, 255),
        "k": (70, 74, 92, 255), "b": (80, 150, 255, 255), "g": (90, 215, 110, 255), "v": (185, 120, 255, 255),
        "c": (140, 225, 255, 255), "n": (175, 125, 80, 255),
    }


# ---------------------------------------------------------------- motifs (the path's element, tone on tone)
def motif(path, S, c):
    if path == "Volt":
        for x, y, a in ((22, 28, 20), (80, 30, -20), (24, 78, -30), (80, 76, 30)):
            S.poly(bolt(x, y, 34, a), c)
    elif path == "Frost":
        for a in range(0, 180, 60):
            S.line(rot([(50, 2), (50, 98)], a), 7, c)
            for t in (14, 86):
                S.line(rot([(40, t + (10 if t < 50 else -10)), (50, t), (60, t + (10 if t < 50 else -10))], a),
                       5, c)
    elif path == "Fire":
        for x, s in ((14, 40), (34, 56), (56, 48), (80, 60), (96, 36)):
            S.poly(flame(x, 96 - s / 2, s), c)
    elif path == "Earth":
        for x, y, r in ((18, 24, 14), (82, 20, 12), (14, 78, 16), (86, 80, 14), (50, 94, 12)):
            S.poly(ngon(x, y, r, 6, x), c)
    elif path == "Tide":
        for y in (20, 44, 68, 92):
            S.line([(t * 4, y + 5 * math.sin(t * 0.5)) for t in range(26)], 6, c)
    elif path == "Blade":
        for i in range(-2, 4):
            S.line([(i * 26 - 10, 104), (i * 26 + 50, -4)], 5, c)
    elif path in ("Gunslinger", "Light"):
        for i in range(0, 360, 30):
            a0, a1 = math.radians(i), math.radians(i + 12)
            S.poly([(50, 50), (50 + 80 * math.cos(a0), 50 + 80 * math.sin(a0)),
                    (50 + 80 * math.cos(a1), 50 + 80 * math.sin(a1))], c)
    elif path == "Gadgeteer":
        S.arc(50, 50, 40, 0, 360, 9, c, steps=60)
        for i in range(10):
            S.line(rot([(50, 2), (50, 12)], i * 36), 10, c)
    elif path == "Shadow":
        S.poly(crescent(50, 50, 48, 44, 18, 160), c)
    elif path == "Titan":
        S.poly(star(50, 50, 60, 40, 14), c)
    elif path == "Martial":
        S.line([(50 + (2 + t * 1.8) * math.cos(t * 0.45), 50 + (2 + t * 1.8) * math.sin(t * 0.45))
                for t in range(30)], 6, c)
    elif path == "Juggernaut":
        for v in (34, 66):
            S.line([(v, 0), (v, 100)], 4, c)
            S.line([(0, v), (100, v)], 4, c)
        for x in (18, 50, 82):
            for y in (18, 50, 82):
                S.circle(x, y, 3.5, c)
    elif path == "Colossus":
        S.poly([(0, 100), (0, 70), (24, 40), (40, 60), (62, 22), (100, 74), (100, 100)], c)
    elif path == "Pulse":
        for a in (0, 60, 120):
            S.line([rot([(50 + 46 * math.cos(math.radians(t * 12)), 50 + 18 * math.sin(math.radians(t * 12)))],
                        a)[0] for t in range(31)], 4, c)
    elif path == "Mind":
        for r in (16, 28, 40, 52):
            S.arc(50, 50, r, 0, 360, 4, c, steps=48)
    elif path == "Spirit":
        for x, y in ((18, 26), (82, 24), (20, 80), (80, 82)):
            S.line([(x + 6 * math.sin(t * 0.7), y + 12 - t * 2) for t in range(12)], 6, c)
    elif path == "weapon":
        for i in range(-2, 4):
            S.line([(i * 30 - 10, 104), (i * 30 + 50, -4)], 7, c)


def halftone(size, r_max, color, clip):
    """Halftone dots growing toward the lower right (print shading), clipped to the disc."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    step = size / 13
    for j in range(15):
        for i in range(15):
            x = i * step + (step / 2 if j % 2 else 0)
            y = j * step
            t = ((x + y) / (2 * size) - 0.55) / 0.45
            if t <= 0:
                continue
            r = r_max * min(1, t) * step
            d.ellipse([x - r, y - r, x + r, y + r], fill=color)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), Image.composite(img.getchannel("A"), Image.new("L", img.size, 0), clip))
    return out


def circle_mask(size, r):
    m = Image.new("L", (size, size), 0)
    c = size / 2
    ImageDraw.Draw(m).ellipse([c - r, c - r, c + r, c + r], fill=255)
    return m


def disc(bg, path, ring=None):
    """The round base every power, weapon and button icon sits on (fills the round HUD button)."""
    k = BIG / 100
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = BIG / 2

    def circ(r, col):
        d.ellipse([c - r * k, c - r * k, c + r * k, c + r * k], fill=col)

    circ(50, INK)
    inner = 45
    if ring:
        circ(46, ring)
        circ(40.5, INK)
        inner = 38
    circ(inner, rgba(bg))
    clip = circle_mask(BIG, inner * k)
    if path:
        M = Sym(ink=0, shadow=None)
        motif(path, M, shade(bg, 0.16))
        layer = M.render(BIG, shadow=False)
        img.paste(layer, (0, 0), Image.composite(layer.getchannel("A"), Image.new("L", layer.size, 0), clip))
    img.alpha_composite(halftone(BIG, 0.34, shade(bg, 0.3), clip))
    # the highlight: a pale crescent at the top left (the comic sheen)
    hl = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    r = inner * k
    hd.ellipse([c - r, c - r, c + r, c + r], fill=shade(bg, -0.35))
    hd.ellipse([c - r + 0.16 * r, c - r + 0.16 * r, c + r + 0.08 * r, c + r + 0.08 * r], fill=(0, 0, 0, 0))
    img.alpha_composite(hl)
    if ring:
        # four gold studs on the super's ring
        for a in (45, 135, 225, 315):
            x, y = c + 43 * k * math.cos(math.radians(a)), c + 43 * k * math.sin(math.radians(a))
            d.ellipse([x - 3.2 * k, y - 3.2 * k, x + 3.2 * k, y + 3.2 * k], fill=INK)
            d.ellipse([x - 2 * k, y - 2 * k, x + 2 * k, y + 2 * k], fill=(255, 245, 190, 255))
    return img


def symbol(name, p, scale=1.0):
    S = Sym()
    SYM[name](S, p)
    size = BIG
    s = BIG * scale
    off = (BIG - s) / 2
    return S.render(size, origin=(off, off), scale=s / 100)


def shrink(img):
    return img.resize((CELL, CELL), Image.LANCZOS)


def disc_icon(bg, path, name, ring=None, scale=0.94):
    img = disc(bg, path, ring)
    img.alpha_composite(symbol(name, palette(bg), scale * (0.86 if ring else 1.0)))
    return shrink(img)


def badge_icon(name):
    """A move badge: a small gold disc the UI lays on a weapon icon's lower right."""
    bg = OTHER_BG["move"]
    k = BIG / 100
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = BIG / 2
    d.ellipse([c - 50 * k, c - 50 * k, c + 50 * k, c + 50 * k], fill=INK)
    d.ellipse([c - 41 * k, c - 41 * k, c + 41 * k, c + 41 * k], fill=rgba(bg))
    img.alpha_composite(halftone(BIG, 0.3, shade(bg, 0.25), circle_mask(BIG, 41 * k)))
    S = Sym(ink=6, shadow=(3, 3))
    SYM[name](S, palette(bg))
    img.alpha_composite(S.render(BIG, origin=(BIG * 0.1, BIG * 0.1), scale=BIG * 0.8 / 100))
    return shrink(img)


def slot_icon(name):
    """A gear slot symbol on clear ground (laid over the tier frame)."""
    p = palette((90, 110, 150))
    p["a"] = (150, 210, 255, 255)
    S = Sym(ink=5)
    SYM[name](S, p)
    return shrink(S.render(BIG, origin=(BIG * 0.06, BIG * 0.06), scale=BIG * 0.88 / 100))


def tier_frame(tier, n):
    """A rounded square card in the tier colour: ink border, halftone, 1 to 6 pips, studs and rays up top."""
    col = TIER_COLORS[tier]
    k = BIG / 100
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if n >= 5:
        # Legendary and Mythic: comic rays burst out behind the card's corners
        rays = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
        rd = ImageDraw.Draw(rays)
        pts = star(50, 50, 70, 50, 16, -90)
        rd.polygon([(x * k, y * k) for x, y in pts], fill=shade(col, -0.3))
        img.alpha_composite(rays)
    e = 7 if n >= 5 else 2  # Legendary and Mythic cards sit inset so their rays show at the corners
    d.rounded_rectangle([e * k, e * k, (100 - e) * k, (100 - e) * k], radius=18 * k, fill=INK)
    i0, i1 = (e + 5) * k, (95 - e) * k
    d.rounded_rectangle([i0, i0, i1, i1], radius=13 * k, fill=rgba(col))
    clip = Image.new("L", (BIG, BIG), 0)
    ImageDraw.Draw(clip).rounded_rectangle([i0, i0, i1, i1], radius=13 * k, fill=255)
    img.alpha_composite(halftone(BIG, 0.36, shade(col, 0.22), clip))
    # the sheen along the top and a darker band at the bottom for the pips
    sheen = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.rounded_rectangle([12 * k, 11 * k, 88 * k, 20 * k], radius=5 * k, fill=shade(col, -0.4)[:3] + (150,))
    sd.rectangle([0, 76 * k, BIG, BIG], fill=shade(col, 0.3))
    sheen2 = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    sheen2.paste(sheen, (0, 0), Image.composite(sheen.getchannel("A"), Image.new("L", sheen.size, 0), clip))
    img.alpha_composite(sheen2)
    d = ImageDraw.Draw(img)
    # pips: the tier's number as small stars, so colourblind players read it too
    gap = 12.5
    x0 = 50 - (n - 1) * gap / 2
    py = 84 if n >= 5 else 86.5
    for i in range(n):
        pts = star(x0 + i * gap, py, 7.2, 3.2, 5)
        d.polygon([(x * k, y * k) for x, y in pts], fill=INK)
        pts = star(x0 + i * gap, py, 4.8, 2.1, 5)
        d.polygon([(x * k, y * k) for x, y in pts], fill=(255, 250, 230, 255))
    if n >= 3:
        for x, y in ((e + 12, e + 12), (88 - e, e + 12)):
            d.ellipse([(x - 3.6) * k, (y - 3.6) * k, (x + 3.6) * k, (y + 3.6) * k], fill=INK)
            d.ellipse([(x - 2.2) * k, (y - 2.2) * k, (x + 2.2) * k, (y + 2.2) * k], fill=(255, 250, 230, 255))
    if n >= 4:
        d.rounded_rectangle([i0 + 3 * k, i0 + 3 * k, i1 - 3 * k, i1 - 3 * k], radius=11 * k, outline=shade(col, -0.5),
                            width=int(2 * k))
    return shrink(img)


TIER_COLORS = {}


def tier_colors():
    src = read("src/config/Gear.luau")
    for name in TIER_ORDER:
        m = re.search(r"%s = \{ color = \{ (\d+), (\d+), (\d+) \}" % name, src)
        TIER_COLORS[name] = (int(m.group(1)), int(m.group(2)), int(m.group(3)))


# ---------------------------------------------------------------- the second set (gap-icons2, 2026-11-19)
# The open world and the books: every incident, event and contract type, the world markers, the Badge Book's
# groups, collections and accolades, the Journal's tabs, the Rogues File's groups, the daily rewards, the weekly
# boards and the movement buttons. It starts on a fresh sheet (icons_5), so the four uploaded sheets never change.

INCIDENT = {
    "RobotHeist": "i_heist", "TowerFire": "i_fire", "RunawayTram": "i_tram", "FallingSign": "i_sign",
    "RooftopChase": "i_chase", "CatOnCrane": "i_cat", "RaidPrep": "i_raid", "VaultBreach": "i_vault",
    "ShardCrate": "i_crate", "CommSabotage": "i_comm", "SniperNest": "i_sniper", "MedicConvoy": "i_medic",
    "CaptainWarband": "i_warband", "MimicCrowd": "i_mimic", "BomberBarrage": "i_bomber", "GrapplerTow": "i_tow",
    "ScaffoldCollapse": "i_scaffold", "CraneLoad": "i_craneload", "WaterMain": "i_water", "DroneSwarm": "i_swarm",
    "ShieldWall": "i_shieldwall", "SkyAmbush": "i_skyambush", "DepotRaid": "i_depot", "SignalJam": "i_jam",
    "SuspiciousHero": "i_suspect",
}
EVENT = {
    "MeteorShower": "e_meteors", "RobotRampage": "e_rampage", "TidalSurge": "e_surge", "VaultBreach": "e_vault",
    "TrainHijack": "e_train", "Blackout": "e_blackout", "AirshipDrop": "e_airship", "BridgeSiege": "e_bridge",
    "StadiumLockdown": "e_stadium", "PowerPlantOverload": "e_plant", "ParadeGoneWrong": "e_parade",
    "HarbourFog": "e_fog", "YourDouble": "e_double", "DataTruck": "e_datatruck", "UptownVault": "e_upvault",
    "SparkShipment": "e_crystals",
}
CONTRACT = {
    "DroneSweep": "c_sweep", "RescueRun": "c_rescue", "ShardRecovery": "c_core", "Escort": "c_escort",
    "VaultJob": "c_safe", "Stakeout": "c_stakeout", "Bounty": "c_bounty", "Demolition": "c_demo",
    "RooftopCourier": "c_courier", "Defusal": "c_defuse", "PhotoRecon": "c_photo", "GeneratorHold": "c_generator",
}
MARKER = {
    "boss": "k_boss", "RustjawPrime": "k_rustjaw", "LumenMaw": "k_maw", "LeviathanEngine": "k_leviathan",
    "NullWarFrame": "k_warframe", "giver": "k_giver", "site": "k_site", "quest": "k_quest",
    "safehouse": "k_safehouse", "beacon": "k_beacon", "hqHero": "k_hqhero", "hqVillain": "k_hqvillain",
    "squad": "k_squad", "help": "k_help", "here": "k_here", "danger": "k_danger",
}
MARKER_ORDER = list(MARKER)
# bosses-3 (2026-11-20, DRAFT bosses): the new world bosses' markers go at the very end of the set (after the move
# keys), so no cell before them moves and only the last sheet changes
MARKER_EXTRA = {"StormColossus": "k_storm", "SwarmQueen": "k_swarm", "QuarryTitan": "k_titan"}
# the colorblind-safe shapes (Ui/Shapes.luau) as white comic backings the UI tints with ImageColor3; inner is
# where the symbol sits on each (centre x, centre y, size; fractions of the cell)
SHAPES = ["circle", "diamond", "triangle", "star", "square", "hex"]
SHAPE_INNER = {"circle": (0.5, 0.5, 0.66), "diamond": (0.5, 0.5, 0.56), "triangle": (0.5, 0.63, 0.5),
               "star": (0.5, 0.55, 0.5), "square": (0.5, 0.5, 0.68), "hex": (0.5, 0.5, 0.64)}
BADGE_GROUP = {"explore": ("compass", (60, 180, 230)), "defeat": ("brokenbot", (125, 140, 160)),
               "rescue": ("lifebuoy", (235, 80, 80)), "story": ("book", (150, 95, 215)),
               "combat": ("starfist", (245, 140, 50)), "groups": ("trio", (60, 190, 120)),
               "nemesis": ("versus", (190, 60, 110)), "showoff": ("spotlight", (240, 100, 190)),
               "pvp": ("crater", (220, 70, 60)), "episodes": ("tv", (70, 130, 230))}
COLLECT = {"ComicCovers": ("comicbook", (70, 150, 240)), "LostToys": ("windkey", (240, 130, 60)),
           "ShipBells": ("bell", (40, 150, 200)), "DeepRelics": ("amphora", (40, 120, 170)),
           "RoofPigeons": ("pigeon", (130, 170, 210)), "CometShards": ("charm", (150, 90, 220)),
           "RobotParts": ("gearnut", (110, 125, 150)), "BossPlates": ("plate", (230, 110, 50)),
           "NemesisCores": ("core", (120, 60, 160)), "ContestRibbons": ("rosette", (235, 90, 150)),
           "MentorKeepsakes": ("locket", (60, 180, 160)), "TaskForcePatches": ("crest", (70, 160, 90))}
ACCOLADE = {"compassGlow": "glowcompass", "scrapTrim": "rivets", "thumbsUp": "thumbs", "inkTrim": "nib",
            "guardSpark": "guardspark", "huddle": "hands"}
JOURNAL = {"story": "book", "quests": "j_quests", "rep": "j_rep", "perks": "j_perks", "rogues": "j_rogues",
           "badges": "j_medal", "mentor": "j_mentor", "showdown": "j_showdown"}
ROGUES = {"robots": ("r_robot", (90, 170, 240)), "fakes": ("r_fake", (240, 110, 170)),
          "villains": ("r_villain", (140, 90, 210)), "bosses": ("k_boss", (245, 140, 50))}
DAILY = {"credits": "d_credits", "renown": "d_renown", "dust": "d_dust", "title": "d_title", "got": "d_got"}
BOARD = {"BossMvp": "b_mvp", "Rescues": "lifebuoy", "PvpWins": "b_trophy"}
MOVEKEY = {"Leap": "v_leap", "Boost": "v_boost", "Down": "v_down"}


def mark_icon(name, scale=0.9):
    """A symbol on clear ground (laid over a tinted shape backing, a row or a tab)."""
    p = palette((90, 110, 150))
    p["a"] = (150, 210, 255, 255)
    S = Sym(ink=5.5, shadow=(3.4, 3.4))
    SYM[name](S, p)
    o = (1 - scale) / 2
    return shrink(S.render(BIG, origin=(BIG * o, BIG * o), scale=BIG * scale / 100))


def shape_backing(shape):
    """A white comic shape (ink edge, hard shadow, halftone and a grey cel rim) the UI tints per marker."""
    white = (255, 255, 255)
    S = Sym(ink=6.5, shadow=(4, 4))
    if shape == "circle":
        S.circle(48, 48, 40, white)
    elif shape == "diamond":
        S.poly([(48, 6), (90, 48), (48, 90), (6, 48)], white)
    elif shape == "triangle":
        S.poly([(48, 8), (90, 86), (6, 86)], white)
    elif shape == "star":
        S.poly(star(48, 52, 46, 24, 5), white)
    elif shape == "square":
        S.rect(10, 10, 86, 86, white, 12)
    elif shape == "hex":
        S.poly(ngon(48, 48, 43, 6, 0), white)
    img = S.render(BIG)
    # halftone dots in light grey on the lower right, inside the shape
    a = img.getchannel("A")
    inside = Image.eval(np_to_l(np.asarray(img)), lambda v: v)
    img.alpha_composite(halftone(BIG, 0.3, (205, 205, 212, 255), Image.composite(inside, Image.new("L", a.size, 0), a)))
    return shrink(img)


def np_to_l(arr):
    """A mask of the near-white fill (not the ink or the shadow)."""
    m = (arr[:, :, 0] > 200) & (arr[:, :, 3] > 200)
    return Image.fromarray((m * 255).astype(np.uint8), "L")


def ring_disc_icon(bg, name):
    """An accolade: a disc with a gold ring and studs (like a super) and its symbol."""
    return disc_icon(bg, None, name, GOLD)


def set2_cells():
    incidents = order_list(read("src/config/Incidents.luau"), "order")
    ev_src = read("src/config/Events.luau")
    events = order_list(ev_src, "order") + order_list(ev_src, r"\n\trare") + order_list(ev_src, r"\n\tside")
    contracts = order_list(read("src/config/Contracts.luau"), "order")
    bosses = [m.group(1) for m in re.finditer(r"^\t\t(\w+) = \{\n\t\t\tname = ", read("src/config/Boss.luau"), re.M)]
    badges = re.findall(r'^\t\t\tid = "(\w+)",\n\t\t\tat = ', read("src/config/Badges.luau"), re.M)
    accolades = re.findall(r'accolade = \{\s*kind = "\w+",\s*id = "(\w+)"', read("src/config/Badges.luau"))
    collects = re.findall(r'^\t\t\tid = "(\w+)",\n\t\t\tname = ', read("src/config/Collect.luau"), re.M)
    rogues = re.findall(r'\{ id = "(\w+)", name = "[^"]+" \}', read("src/config/Rogues.luau"))
    boards = re.findall(r'\{ id = "(\w+)", name = "[^"]+", unit', read("src/config/Boards.luau"))
    assert incidents == list(INCIDENT), incidents
    assert events == list(EVENT), events
    assert contracts == list(CONTRACT), contracts
    for b in bosses:
        assert b in MARKER or b in MARKER_EXTRA, "no marker for boss " + b
    assert badges == list(BADGE_GROUP), badges
    assert accolades == list(ACCOLADE), accolades
    assert collects == list(COLLECT), collects
    assert rogues == list(ROGUES), rogues
    assert boards == list(BOARD), boards
    # unique symbols inside each group (the first set's rule)
    for gname, table in (("incident", INCIDENT), ("event", EVENT), ("contract", CONTRACT),
                         ("marker", dict(MARKER, **MARKER_EXTRA)),
                         ("badgeGroup", {k: v[0] for k, v in BADGE_GROUP.items()}),
                         ("collect", {k: v[0] for k, v in COLLECT.items()}), ("accolade", ACCOLADE),
                         ("journal", JOURNAL), ("rogues", {k: v[0] for k, v in ROGUES.items()}), ("daily", DAILY),
                         ("board", BOARD), ("moveKey", MOVEKEY)):
        names = list(table.values())
        for n in names:
            assert n in SYM, "unknown symbol " + n
        assert len(set(names)) == len(names), gname + " repeats a symbol"
    cells = []
    for key in SHAPES:
        cells.append(("shape", key, shape_backing(key), "shapes"))
    for key in incidents:
        cells.append(("incident", key, mark_icon(INCIDENT[key]), "incidents"))
    for key in events:
        cells.append(("event", key, mark_icon(EVENT[key]), "events"))
    for key in contracts:
        cells.append(("contract", key, mark_icon(CONTRACT[key]), "contracts"))
    for key in MARKER_ORDER:
        cells.append(("marker", key, mark_icon(MARKER[key]), "markers"))
    for key, (name, bg) in BADGE_GROUP.items():
        cells.append(("badgeGroup", key, disc_icon(bg, None, name), "badges"))
    for key, (name, bg) in COLLECT.items():
        cells.append(("collect", key, disc_icon(bg, None, name), "collect"))
    acc_bg = {m.group(1): tuple(int(v) for v in m.group(2, 3, 4)) for m in re.finditer(
        r'id = "(\w+)",\s*name = "[^"]+",\s*(?:color|emote) = \{? ?(\d+),? ?(\d*),? ?(\d*)',
        read("src/config/Badges.luau")) if m.group(3)}
    for key, name in ACCOLADE.items():
        bg = acc_bg.get(key, (255, 200, 60))
        if sum(bg) < 200:
            bg = (90, 90, 110)  # the ink trim: a dark slate so the ink symbol still reads
        cells.append(("accolade", key, ring_disc_icon(bg, name), "accolades"))
    for key, name in JOURNAL.items():
        cells.append(("journal", key, mark_icon(name, 0.84), "journal"))
    for key, (name, bg) in ROGUES.items():
        cells.append(("rogues", key, disc_icon(bg, None, name), "rogues"))
    for key, name in DAILY.items():
        cells.append(("daily", key, mark_icon(name, 0.84), "daily"))
    for key, name in BOARD.items():
        cells.append(("board", key, disc_icon(OTHER_BG["move"], None, name), "boards"))
    for key, name in MOVEKEY.items():
        cells.append(("moveKey", key, disc_icon(OTHER_BG["mobility"], None, name), "move keys"))
    for key, name in MARKER_EXTRA.items():
        cells.append(("marker", key, mark_icon(name), "markers"))
    return cells


SET2_GROUPS = [
    ("shape", "gap-icons2: the colorblind-safe marker shapes as white comic backings (tint with ImageColor3)", SHAPES),
    ("incident", "every incident (Config.Incidents.order), a symbol on clear ground", None),
    ("event", "every event (Config.Events order, rare and side), a symbol on clear ground", None),
    ("contract", "every contract type (Config.Contracts.order), a symbol on clear ground", None),
    ("marker", "world markers: the bosses, givers, sites, quest steps, safehouses, beacons, HQs, squad, pings",
     MARKER_ORDER + list(MARKER_EXTRA)),
    ("badgeGroup", "the Badge Book's groups (Config.Badges.groups), discs", None),
    ("collect", "the collections (Config.Collect.sets), discs", None),
    ("accolade", "the accolades (Config.Badges groups' accolade ids), gold-ringed discs", None),
    ("journal", "the Journal's tabs, symbols on clear ground", None),
    ("rogues", "the Rogues File's groups (Config.Rogues.groups), discs", None),
    ("daily", "the daily card's rewards and the got tick, symbols on clear ground", None),
    ("board", "the weekly boards (Config.Boards.boards), discs", None),
    ("moveKey", "the movement buttons (LEAP, BOOST, DOWN; FLY shows the mobility pick's icon)", None),
]


# ---------------------------------------------------------------- build


def build():
    tier_colors()
    abil = abilities()
    gear = read("src/config/Gear.luau")
    slots = order_list(gear, "slotOrder")
    gadgets = order_list(gear, "gadgetOrder")
    mobility = order_list(read("src/config/Move.luau"), "mobilityOrder")
    weps = weapons()
    tiers = order_list(gear, "tierOrder")
    assert tiers == TIER_ORDER, tiers
    assert len(abil) == 136, len(abil)
    assert len(weps) == 36, len(weps)

    # every ability has a symbol, and no two powers in one path share one
    seen = {}
    for a in abil:
        name = ABILITY.get(a["id"])
        assert name, "no icon symbol for ability " + a["id"]
        assert name in SYM, "unknown symbol " + name
        key = (a["set"], name)
        assert key not in seen, "%s and %s share the %s symbol in %s" % (seen[key], a["id"], name, a["set"])
        seen[key] = a["id"]
    for name in list(WEAPON.values()) + list(MOVE.values()) + list(MOBILITY.values()) + list(GADGET.values()) + \
            list(ACTION.values()) + ["s_" + s for s in slots]:
        assert name in SYM, "unknown symbol " + name
    assert set(GADGET) == set(gadgets), gadgets
    assert set(MOBILITY) == set(mobility), mobility

    cells = []  # (group, key, image)
    for a in abil:
        bg = PATH_BG[a["set"]]
        ring = GOLD if a["slot"] == "super" else None
        cells.append(("ability", a["id"], disc_icon(bg, a["set"], ABILITY[a["id"]], ring), a["set"]))
    fam = {n: f for n, f, _ in weps}
    for n, f, _ in weps:
        cells.append(("weapon", n, disc_icon(FAMILY_BG[f], "weapon", WEAPON[n], scale=0.96), "weapon"))
    for key in ("M1", "Z", "X", "C", "V"):
        cells.append(("move", key, badge_icon(MOVE[key]), "badge"))
    for key in mobility:
        cells.append(("mobility", key, disc_icon(OTHER_BG["mobility"], None, MOBILITY[key]), "mobility"))
    for key in gadgets:
        cells.append(("gadget", key, disc_icon(OTHER_BG["gadget"], None, GADGET[key]), "gadget"))
    for key in ("Awaken", "Block", "Power"):
        cells.append(("action", key, disc_icon(OTHER_BG[key], "Titan" if key == "Awaken" else None, ACTION[key]),
                      "action"))
    for key in slots:
        cells.append(("slot", key, slot_icon("s_" + key), "slot"))
    for i, key in enumerate(TIER_ORDER):
        cells.append(("tier", key, tier_frame(key, i + 1), "tier"))
    del fam
    n_first = len(cells)
    # gap-icons2: the second set starts on a fresh sheet so the uploaded ones stay byte-identical
    first_sheets = (n_first + PER_SHEET - 1) // PER_SHEET
    cells2 = set2_cells()

    # pack: abilities fill sheets 1 and 2 and spill into 3; the rest follow in order
    out_dir = os.path.join(ROOT, "art", "export", "icons")
    os.makedirs(out_dir, exist_ok=True)
    placed = list(enumerate(cells)) + [(first_sheets * PER_SHEET + i, c) for i, c in enumerate(cells2)]
    # the third set (the mobility rework's moves) on a fresh sheet after the second
    third = ((placed[-1][0] + PER_SHEET) // PER_SHEET) * PER_SHEET
    moves_src = read("src/config/Move.luau")
    rank5 = set()
    move_order = []
    for m in re.finditer(r'name = "([^"]+)",\n\t+choice = \{ "(\w+)", "(\w+)" \}', moves_src):
        move_order += [m.group(2), m.group(3)]
    for m in re.finditer(r'name = "(Sound Barrier|Lightning Legs|Meteor|Triple Jump|Skyline)",\n\t+choice = \{ "(\w+)", "(\w+)" \}', moves_src):
        rank5 |= {m.group(2), m.group(3)}
    assert len(move_order) == 20 and set(move_order) == set(MOBMOVE), move_order
    cells3 = []
    for key in move_order:
        assert MOBMOVE[key] in SYM, "unknown symbol " + MOBMOVE[key]
        ring = GOLD if key in rank5 else None
        cells3.append(("mobmove", key, disc_icon(OTHER_BG["mobility"], None, MOBMOVE[key], ring), "mobility moves"))
    placed += [(third + i, c) for i, c in enumerate(cells3)]
    global MOVE_ORDER
    MOVE_ORDER = move_order
    n_sheets = (placed[-1][0] + PER_SHEET) // PER_SHEET
    sheets = [Image.new("RGBA", (SHEET, SHEET), (0, 0, 0, 0)) for _ in range(n_sheets)]
    layout = {}
    for i, (group, key, img, _) in placed:
        s, idx = divmod(i, PER_SHEET)
        x, y = (idx % PER_ROW) * CELL, (idx // PER_ROW) * CELL
        sheets[s].paste(img, (x, y))
        layout.setdefault(group, {})[key] = (s + 1, idx)
    files = []
    for s, img in enumerate(sheets):
        name = "icons_%d.png" % (s + 1)
        img.save(os.path.join(out_dir, name), optimize=True)
        files.append(name)
    write_config(files, layout, slots, mobility, gadgets)
    contact(cells + cells3)
    contact2(cells2)
    print("icons:", len(cells) + len(cells2), "cells on", n_sheets, "sheets ->", out_dir)


def write_config(files, layout, slots, mobility, gadgets):
    ids_path = os.path.join(HERE, "ids.json")
    ids = json.load(open(ids_path)) if os.path.exists(ids_path) else {}
    L = []
    L.append("-- Icons: the comic icon set's sprite sheets (gap-icons, 2026-11-19). GENERATED by art/icons/icons.py from")
    L.append("-- Config.Abilities, Weapons, Gear and Move; edit the script, not this file. Every sheet is 1024 x 1024 with")
    L.append("-- 128 px cells, 8 to a row. A key's entry is { sheet, cell } (cell counted from 0, left to right, top to")
    L.append("-- bottom): the UI shows it with ImageRectOffset = (cell % 8, cell // 8) x 128 and ImageRectSize 128 x 128.")
    L.append("-- A sheet's id 0 means not uploaded yet: Kit.icon gives nil and the UI keeps today's short names.")
    L.append("return {")
    L.append("\tcell = %d," % CELL)
    L.append("\tperRow = %d," % PER_ROW)
    L.append("\tsheetSize = %d," % SHEET)
    L.append("\tsheets = {")
    for f in files:
        L.append('\t\t{ file = "%s", id = %d },' % (f, int(ids.get(f, 0))))
    L.append("\t},")
    groups = [
        ("ability", "every power (Config.Abilities.list), by ability id", None),
        ("weapon", "the 36 weapons' silhouettes, by weapon id", None),
        ("move", "a weapon move's badge (laid on the weapon's icon): the combo and Z X C V", ["M1", "Z", "X", "C", "V"]),
        ("mobility", "the 5 mobility picks (Config.Move.mobilityOrder)", mobility),
        ("gadget", "the 4 gadgets (Config.Gear.gadgetOrder)", gadgets),
        ("action", "the HUD's Awakening, shield (block) and power-swap buttons", ["Awaken", "Block", "Power"]),
        ("slot", "the 8 gear slots (Config.Gear.slotOrder), drawn on clear ground over a tier frame", slots),
        ("tier", "a gear tier's frame (Config.Gear.tierOrder): colour, 1 to 6 pips", TIER_ORDER),
    ] + SET2_GROUPS + [
        ("mobmove", "the mobility rework's 20 moves (Config.Move.moves), rank 5's gold-ringed", MOVE_ORDER),
    ]
    for group, text, order in groups:
        L.append("\t-- %s" % text)
        L.append("\t%s = {" % group)
        entries = layout[group]
        keys = order if order else list(entries.keys())
        for key in keys:
            s, idx = entries[key]
            k = "[%d]" % key if isinstance(key, int) else key
            L.append("\t\t%s = { %d, %d }," % (k, s, idx))
        L.append("\t},")
    L.append("\t-- where a symbol sits on each shape backing: { centre x, centre y, size } as fractions of the cell")
    L.append("\tshapeInner = {")
    for key in SHAPES:
        x, y, sz = SHAPE_INNER[key]
        L.append("\t\t%s = { %s, %s, %s }," % (key, x, y, sz))
    L.append("\t},")
    L.append("}")
    with open(os.path.join(ROOT, "src", "config", "Icons.luau"), "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")


def contact(cells):
    """art/preview/icons.png: every icon by group at 64 px, and each path's row again at 48 px (phone size)."""
    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    font = ImageFont.truetype(font_path, 15) if os.path.exists(font_path) else ImageFont.load_default()
    rows = []
    cur = None
    for group, key, img, row in cells:
        if row != cur:
            rows.append((row, []))
            cur = row
        rows[-1][1].append(img)
    big, small, label = 64, 48, 112
    width = label + 18 * (big + 6) + 30 + 8 * (small + 4)
    height = 20 + sum(((len(r[1]) + 17) // 18) * (big + 8) for r in rows) + big + 28
    sheet = Image.new("RGBA", (width, height), (255, 247, 224, 255))
    d = ImageDraw.Draw(sheet)
    y = 14
    for name, imgs in rows:
        d.text((10, y + 22), name, fill=(17, 17, 17), font=font)
        for i, img in enumerate(imgs):
            r, c = divmod(i, 18)
            sheet.alpha_composite(img.resize((big, big), Image.LANCZOS), (label + c * (big + 6), y + r * (big + 8)))
        if len(imgs) == 8:  # a power path: the phone-size strip on the right
            for i, img in enumerate(imgs):
                sheet.alpha_composite(img.resize((small, small), Image.LANCZOS),
                                      (label + 8 * (big + 6) + 30 + i * (small + 4), y + 8))
        y += ((len(imgs) + 17) // 18) * (big + 8)
    # gear cards as the UI draws them: each slot icon (inset) over a tier frame
    frames = [img for g, _, img, _ in cells if g == "tier"]
    slots = [img for g, _, img, _ in cells if g == "slot"]
    d.text((10, y + 22), "cards", fill=(17, 17, 17), font=font)
    for i, s in enumerate(slots):
        card = frames[i % len(frames)].resize((big, big), Image.LANCZOS)
        card.alpha_composite(s.resize((int(big * 0.7), int(big * 0.7)), Image.LANCZOS), (int(big * 0.15), int(big * 0.06)))
        sheet.alpha_composite(card, (label + i * (big + 6), y))
        sheet.alpha_composite(card.resize((small, small), Image.LANCZOS), (label + 8 * (big + 6) + 30 + i * (small + 4), y + 8))
    path = os.path.join(ROOT, "art", "preview", "icons.png")
    sheet.convert("RGB").save(path)
    print(path)


# how the UI lays a world symbol on its shape (WorldHud, Radar, MapScreen, ContractBoard): shape and tint
VIGIL, SYNDICATE, GOLDC, CONTRACTC = (70, 150, 255), (235, 70, 80), (255, 200, 60), (255, 150, 70)
MARKER_SHAPE = {"boss": ("diamond", (255, 90, 60)), "RustjawPrime": ("diamond", (255, 90, 60)),
                "LumenMaw": ("diamond", (255, 90, 60)), "LeviathanEngine": ("diamond", (255, 90, 60)),
                "NullWarFrame": ("diamond", (255, 90, 60)), "StormColossus": ("diamond", (255, 90, 60)),
                "SwarmQueen": ("diamond", (255, 90, 60)), "QuarryTitan": ("diamond", (255, 90, 60)), "giver": ("circle", GOLDC), "site": ("square", GOLDC),
                "quest": ("circle", GOLDC), "safehouse": ("square", (90, 200, 120)), "beacon": ("circle", GOLDC),
                "hqHero": ("square", VIGIL), "hqVillain": ("square", SYNDICATE), "squad": ("square", (90, 200, 120)),
                "help": ("circle", (255, 220, 90)), "here": ("circle", (120, 220, 255)),
                "danger": ("triangle", (255, 90, 80))}


def compose(shapes, shape, tint, sym, px):
    """A tinted backing with the symbol on it at px, as the game draws it."""
    back = shapes[shape].resize((px, px), Image.LANCZOS)
    arr = np.asarray(back).astype(np.float32)
    arr[:, :, :3] *= np.array(tint, np.float32) / 255.0
    out = Image.fromarray(arr.astype(np.uint8), "RGBA")
    x, y, sz = SHAPE_INNER[shape]
    sp = max(1, int(round(px * sz)))
    out.alpha_composite(sym.resize((sp, sp), Image.LANCZOS), (int(round(px * x - sp / 2)), int(round(px * y - sp / 2))))
    return out


def contact2(cells):
    """art/preview/icons2.png: the second set by group at 64 px, world symbols on their tinted shapes at 64,
    48 and 24 px (the radar's size), the rest as drawn and again at 48 px."""
    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    font = ImageFont.truetype(font_path, 15) if os.path.exists(font_path) else ImageFont.load_default()
    shapes = {k: img for g, k, img, _ in cells if g == "shape"}
    rows = []
    for group, key, img, row in cells:
        if not rows or rows[-1][0] != row:
            rows.append((row, []))
        if group == "incident":
            tint = SYNDICATE if len(rows[-1][1]) % 4 == 3 else VIGIL
            img2 = compose(shapes, "circle", tint, img, 128)
        elif group == "event":
            img2 = compose(shapes, "star", GOLDC, img, 128)
        elif group == "contract":
            img2 = compose(shapes, "hex", CONTRACTC, img, 128)
        elif group == "marker":
            sh, tint = MARKER_SHAPE[key]
            img2 = compose(shapes, sh, tint, img, 128)
        else:
            img2 = None
        rows[-1][1].append((img, img2))
    big, small, tiny, label = 64, 48, 24, 112
    per = 14
    width = label + per * (big + 6) + 20
    height = 20
    for name, items in rows:
        n = (len(items) + per - 1) // per
        height += n * (big + 8) + (n * (big + 8) + n * (small + 6) if items[0][1] is not None else n * (small + 6))
    sheet = Image.new("RGBA", (width, height), (255, 247, 224, 255))
    night = (34, 38, 58, 255)
    d = ImageDraw.Draw(sheet)
    y = 14
    for name, items in rows:
        d.text((10, y + 22), name, fill=(17, 17, 17), font=font)
        n = (len(items) + per - 1) // per
        for i, (img, _) in enumerate(items):
            r, c = divmod(i, per)
            sheet.alpha_composite(img.resize((big, big), Image.LANCZOS), (label + c * (big + 6), y + r * (big + 8)))
        y += n * (big + 8)
        if items[0][1] is not None:
            # on their shapes over a dark HUD strip: 64 px, then 48 px and 24 px side by side
            d.rectangle([label - 6, y - 4, width - 8, y + n * (big + 8) + n * (small + 6)], fill=night)
            for i, (_, img2) in enumerate(items):
                r, c = divmod(i, per)
                sheet.alpha_composite(img2.resize((big, big), Image.LANCZOS), (label + c * (big + 6), y + r * (big + 8)))
            y += n * (big + 8)
            for i, (_, img2) in enumerate(items):
                r, c = divmod(i, per)
                x0 = label + c * (big + 6)
                sheet.alpha_composite(img2.resize((small, small), Image.LANCZOS), (x0, y + r * (small + 6)))
                sheet.alpha_composite(img2.resize((tiny, tiny), Image.LANCZOS), (x0 + small + 2, y + r * (small + 6) + 12))
            y += n * (small + 6)
        else:
            for i, (img, _) in enumerate(items):
                r, c = divmod(i, per)
                sheet.alpha_composite(img.resize((small, small), Image.LANCZOS), (label + c * (big + 6), y + r * (small + 6)))
            y += n * (small + 6)
    path = os.path.join(ROOT, "art", "preview", "icons2.png")
    sheet.convert("RGB").save(path)
    print(path)


if __name__ == "__main__":
    build()
