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

ROOT = os.path.dirname(os.path.dirname(HERE))
CELL = 128
SS = 4
BIG = CELL * SS
SHEET = 1024
PER_ROW = SHEET // CELL
PER_SHEET = PER_ROW * PER_ROW

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

    # pack: abilities fill sheets 1 and 2 and spill into 3; the rest follow in order
    out_dir = os.path.join(ROOT, "art", "export", "icons")
    os.makedirs(out_dir, exist_ok=True)
    n_sheets = (len(cells) + PER_SHEET - 1) // PER_SHEET
    sheets = [Image.new("RGBA", (SHEET, SHEET), (0, 0, 0, 0)) for _ in range(n_sheets)]
    layout = {}
    for i, (group, key, img, _) in enumerate(cells):
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
    contact(cells)
    print("icons:", len(cells), "cells on", n_sheets, "sheets ->", out_dir)


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


if __name__ == "__main__":
    build()
