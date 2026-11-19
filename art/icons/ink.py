"""The icon set's drawing core (gap-icons, 2026-11-19): comic stickers drawn as vector-ish shapes with PIL.

A Sym is a list of groups; each group is a list of primitives (polygons, circles, ellipses, rounded boxes,
thick polylines and arcs) in a 0..100 box. Rendering draws, in order: every group's hard ink shadow (down
and right), then per group its ink outline (the shapes grown by the ink width), its flat fills and a cel
shade on the fills' lower-right rims. So a later group's outline sits over an earlier group's fill, like an
inker drawing the nearer part on top. Deterministic: no randomness anywhere.
"""

import math

import numpy as np
from PIL import Image, ImageDraw

INK = (17, 17, 17, 255)  # Config.Ui.colors.ink
PAPER = (255, 247, 224, 255)  # Config.Ui.colors.paper
WHITE = (255, 253, 245, 255)
GOLD = (255, 210, 60, 255)  # Config.Ui.colors.gold


def rgba(c, a=255):
    return (int(c[0]), int(c[1]), int(c[2]), a if len(c) < 4 else c[3])


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3)) + (255,)


def shade(c, t):
    """Darker (t > 0) toward ink or lighter (t < 0) toward white."""
    return mix(c, (20, 18, 30), t) if t >= 0 else mix(c, (255, 255, 255), -t)


class Sym:
    def __init__(self, ink=4.2, shadow=(3.2, 3.2)):
        self.groups = [[]]
        self.ink = ink
        self.shadow = shadow

    def group(self):
        if self.groups[-1]:
            self.groups.append([])
        return self

    def _add(self, *p):
        self.groups[-1].append(p)
        return self

    def poly(self, pts, c):
        return self._add("poly", [tuple(p) for p in pts], c)

    def circle(self, x, y, r, c):
        return self._add("ell", (x - r, y - r, x + r, y + r), c)

    def ell(self, x0, y0, x1, y1, c):
        return self._add("ell", (x0, y0, x1, y1), c)

    def rect(self, x0, y0, x1, y1, c, r=0):
        return self._add("rect", (min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)), c, r)

    def line(self, pts, w, c):
        return self._add("line", [tuple(p) for p in pts], w, c)

    def arc(self, x, y, r, a0, a1, w, c, steps=None):
        """A thick arc (degrees, 0 = right, 90 = down)."""
        return self.line(arcpts(x, y, r, a0, a1, steps), w, c)

    # ---- rendering ----
    def render(self, size, origin=(0, 0), scale=None, shadow=True):
        """Draws into a new RGBA image of `size` px; the 0..100 box maps to `scale` px from `origin`."""
        k = scale if scale else size / 100.0
        ox, oy = origin
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

        def P(p):
            return (ox + p[0] * k, oy + p[1] * k)

        if shadow and self.shadow:
            sh = Image.new("L", (size, size), 0)
            d = ImageDraw.Draw(sh)
            dx, dy = self.shadow[0] * k, self.shadow[1] * k
            for g in self.groups:
                for prim in g:
                    self._draw(d, prim, P, k, 255, grow=self.ink, off=(dx, dy))
            img.paste(Image.new("RGBA", (size, size), INK), (0, 0), sh)
        for g in self.groups:
            d = ImageDraw.Draw(img)
            for prim in g:
                self._draw(d, prim, P, k, INK, grow=self.ink)
            fill = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            fd = ImageDraw.Draw(fill)
            for prim in g:
                self._draw(fd, prim, P, k, None, grow=0)
            img.alpha_composite(cel(fill, max(2, int(2.6 * k))))
        return img

    @staticmethod
    def _draw(d, prim, P, k, color, grow, off=(0, 0)):
        kind = prim[0]
        g = grow * k
        ox, oy = off

        def Q(p):
            q = P(p)
            return (q[0] + ox, q[1] + oy)

        if kind == "poly":
            pts, c = prim[1], prim[2]
            col = color if color is not None else rgba(c)
            q = [Q(p) for p in pts]
            if g > 0:
                d.line(q + [q[0]], fill=col, width=max(1, int(round(2 * g))), joint="curve")
                for x, y in q:
                    d.ellipse([x - g, y - g, x + g, y + g], fill=col)
            d.polygon(q, fill=col)
        elif kind == "ell":
            (x0, y0, x1, y1), c = prim[1], prim[2]
            col = color if color is not None else rgba(c)
            a, b = Q((x0, y0)), Q((x1, y1))
            d.ellipse([a[0] - g, a[1] - g, b[0] + g, b[1] + g], fill=col)
        elif kind == "rect":
            (x0, y0, x1, y1), c, r = prim[1], prim[2], prim[3]
            col = color if color is not None else rgba(c)
            a, b = Q((x0, y0)), Q((x1, y1))
            d.rounded_rectangle([a[0] - g, a[1] - g, b[0] + g, b[1] + g], radius=r * k + g, fill=col)
        elif kind == "line":
            pts, w, c = prim[1], prim[2], prim[3]
            col = color if color is not None else rgba(c)
            q = [Q(p) for p in pts]
            ww = w * k + 2 * g
            d.line(q, fill=col, width=max(1, int(round(ww))), joint="curve")
            rr = ww / 2
            for x, y in (q[0], q[-1]):
                d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=col)


def cel(fill, s):
    """Flat fills with a hard darker band along their lower-right rims (the comic cel shade)."""
    a = np.asarray(fill).astype(np.int32)
    alpha = a[:, :, 3] > 127
    moved = np.zeros_like(alpha)
    moved[:-s, :-s] = alpha[s:, s:]
    rim = alpha & ~moved
    out = a.copy()
    out[rim, :3] = (out[rim, :3] * 0.72).astype(np.int32)
    return Image.fromarray(out.astype(np.uint8), "RGBA")


# ---- geometry helpers (all in the 0..100 box) ----
def arcpts(x, y, r, a0, a1, steps=None, ry=None):
    ry = r if ry is None else ry
    n = steps or max(6, int(abs(a1 - a0) / 6))
    return [(x + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             y + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def star(x, y, r1, r2, n, rot=-90):
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r2
        a = math.radians(rot + i * 180 / n)
        pts.append((x + r * math.cos(a), y + r * math.sin(a)))
    return pts


def ngon(x, y, r, n, rot=-90):
    return [(x + r * math.cos(math.radians(rot + i * 360 / n)), y + r * math.sin(math.radians(rot + i * 360 / n)))
            for i in range(n)]


def rot(pts, ang, cx=50, cy=50):
    c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    return [(cx + (px - cx) * c - (py - cy) * s, cy + (px - cx) * s + (py - cy) * c) for px, py in pts]


def arrow(x0, y0, x1, y1, w, head):
    """A filled arrow polygon from (x0, y0) to its tip (x1, y1): shaft width w, head length and half width head."""
    dx, dy = x1 - x0, y1 - y0
    L = math.hypot(dx, dy) or 1
    ux, uy = dx / L, dy / L
    nx, ny = -uy, ux
    bx, by = x1 - ux * head, y1 - uy * head
    hw = w / 2
    return [(x0 + nx * hw, y0 + ny * hw), (bx + nx * hw, by + ny * hw), (bx + nx * head * 0.85, by + ny * head * 0.85),
            (x1, y1), (bx - nx * head * 0.85, by - ny * head * 0.85), (bx - nx * hw, by - ny * hw),
            (x0 - nx * hw, y0 - ny * hw)]


def crescent(x, y, r, inner, off, a0=0):
    """A crescent: the outer circle's arc on one side, an offset inner arc on the other (a0 faces the bulge)."""
    pts = arcpts(x, y, r, a0 - 150, a0 + 150, 24)
    ix, iy = x - off * math.cos(math.radians(a0)), y - off * math.sin(math.radians(a0))
    back = arcpts(ix, iy, inner, a0 + 115, a0 - 115, 24)
    return pts + back


def bolt(x, y, s, ang=0):
    """A comic lightning bolt centred on (x, y), s tall."""
    pts = [(0.10, -0.50), (-0.28, 0.06), (-0.02, 0.06), (-0.14, 0.50), (0.30, -0.10), (0.04, -0.10), (0.18, -0.50)]
    out = [(x + px * s, y + py * s) for px, py in pts]
    return rot(out, ang, x, y) if ang else out


def flame(x, y, s, lean=0):
    """A flame tongue, base at (x, y + s/2), s tall."""
    pts = [(0, 0.5), (-0.34, 0.24), (-0.30, -0.06), (-0.12, 0.06), (-0.16, -0.30), (0.02, -0.50), (0.08, -0.20),
           (0.22, -0.30), (0.34, 0.02), (0.32, 0.26)]
    return [(x + (px + lean * (0.5 - py) * 0.3) * s, y + py * s) for px, py in pts]
