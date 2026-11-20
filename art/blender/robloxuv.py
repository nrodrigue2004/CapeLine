# robloxuv.py (fix-respawn, 2026-11-19; nate's playtest: "Clothes dont fit on certain body sizes"): gives a body set's
# torso the UVs of Roblox's OWN blocky R15 torso, so classic Shirt and Pants land on it exactly as on Roblox's body.
# Why: Roblox does not sample a Shirt or Pants template at an R15 MeshPart's UVs. It composites the template into
# its own per-limb texture first, laid out the way its R15 body meshes are UV-mapped (build/robloxbody: the torso's
# faces wrap round in a strip, the arms and legs share one atlas a side), and the MeshPart samples that. The body
# sets' torsos (art/blender/bodies.py, Art.BodyTorsos, worn by LookKit.wearBodySet on every body but Male Medium)
# carried template_uv.py's classic-template UVs, which point at the wrong places in that atlas: the clothes came out
# scrambled on every Female, Small, Large and Titan body. Here each face corner of our torso takes the UV of the
# nearest point, on a face that looks the same way, of Roblox's own torso (build/robloxbody/<part>.json from
# art/fit/robloxbody.py, scaled to our box), so whatever Roblox composites, our torso reads it as Roblox's does.
# Used by bodies.py --torsos on the drawn (unturned) geometry; the UVs then ride with the pre-turn.
import json
import os

from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BODY = os.path.join(ROOT, "build", "robloxbody")


def _key(n):
    ax = max(range(3), key=lambda k: abs(n[k]))
    return ax * 2 + (0 if n[ax] > 0 else 1)


def _closest(p, a, b, c):
    """Closest point on triangle abc to p, as barycentric weights (Ericson, Real-Time Collision Detection 5.1.5)."""
    ab, ac, ap = b - a, c - a, p - a
    d1, d2 = ab.dot(ap), ac.dot(ap)
    if d1 <= 0 and d2 <= 0:
        return 1.0, 0.0, 0.0
    bp = p - b
    d3, d4 = ab.dot(bp), ac.dot(bp)
    if d3 >= 0 and d4 <= d3:
        return 0.0, 1.0, 0.0
    vc = d1 * d4 - d3 * d2
    if vc <= 0 and d1 >= 0 and d3 <= 0:
        v = d1 / (d1 - d3)
        return 1 - v, v, 0.0
    cp = p - c
    d5, d6 = ab.dot(cp), ac.dot(cp)
    if d6 >= 0 and d5 <= d6:
        return 0.0, 0.0, 1.0
    vb = d5 * d2 - d1 * d6
    if vb <= 0 and d2 >= 0 and d6 <= 0:
        w = d2 / (d2 - d6)
        return 1 - w, 0.0, w
    va = d3 * d6 - d5 * d4
    if va <= 0 and (d4 - d3) >= 0 and (d5 - d6) >= 0:
        w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        return 0.0, 1 - w, w
    den = 1.0 / (va + vb + vc)
    v, w = vb * den, vc * den
    return 1 - v - w, v, w


def roblox_tris(part):
    """Roblox's torso as Blender-frame triangles (x, -z, y) grouped by the way they face, with mesh-file UVs."""
    d = json.load(open(os.path.join(BODY, part + ".json")))
    pos = [Vector((p[0], -p[2], p[1])) for p in d["pos"]]
    groups = {}
    for f in d["faces"]:
        a, b, c = (pos[i] for i in f[:3])
        n = (b - a).cross(c - a)
        if n.length < 1e-9:
            continue
        groups.setdefault(_key(n), []).append(((a, b, c), tuple(d["uv"][i] for i in f[:3])))
    lo = Vector([min(p[k] for p in pos) for k in range(3)])
    hi = Vector([max(p[k] for p in pos) for k in range(3)])
    return groups, lo, hi


def uv_at(groups, key, p):
    best, out = 1e18, (0.0, 0.0)
    for (a, b, c), uv in groups.get(key, ()):
        wa, wb, wc = _closest(p, a, b, c)
        q = a * wa + b * wb + c * wc
        dist = (q - p).length_squared
        if dist < best:
            best = dist
            out = (uv[0][0] * wa + uv[1][0] * wb + uv[2][0] * wc, uv[0][1] * wa + uv[1][1] * wb + uv[2][1] * wc)
    return out, best


def transfer(ob, part):
    """Our torso object (drawn frame, any position) takes Roblox's torso UVs. Returns the worst match distance."""
    groups, rlo, rhi = roblox_tris(part)
    me = ob.data
    vs = [v.co.copy() for v in me.vertices]
    lo = Vector([min(v[k] for v in vs) for k in range(3)])
    hi = Vector([max(v[k] for v in vs) for k in range(3)])
    # our box onto Roblox's box, axis by axis (the sets fill Roblox's torso box; the chest shelf stays in front).
    # Across (x) each height is stretched to the full width: a tapered torso (the V of the big builds, the female
    # waist) wears the whole template squeezed to its shape, not a cropped middle of it.
    bins = 24
    span = max(hi[2] - lo[2], 1e-6)
    wlo, whi = [1e9] * bins, [-1e9] * bins
    for v in vs:
        i = min(bins - 1, int((v[2] - lo[2]) / span * bins))
        wlo[i], whi[i] = min(wlo[i], v[0]), max(whi[i], v[0])
    for i in range(bins):  # (an empty band takes its neighbour's width)
        if wlo[i] > whi[i]:
            j = i - 1 if i > 0 and wlo[i - 1] <= whi[i - 1] else i + 1
            wlo[i], whi[i] = (wlo[j], whi[j]) if 0 <= j < bins and wlo[j] <= whi[j] else (lo[0], hi[0])

    def width_at(z):
        f = (z - lo[2]) / span * bins - 0.5
        i = max(0, min(bins - 1, int(f)))
        j = min(bins - 1, i + 1)
        t = max(0.0, min(1.0, f - i))
        return wlo[i] + (wlo[j] - wlo[i]) * t, whi[i] + (whi[j] - whi[i]) * t

    def to_roblox(v):
        a, b = width_at(v[2])
        out = [rlo[k] + (v[k] - lo[k]) / max(hi[k] - lo[k], 1e-6) * (rhi[k] - rlo[k]) for k in range(3)]
        tx = max(0.0, min(1.0, (v[0] - a) / max(b - a, 1e-6)))
        out[0] = rlo[0] + tx * (rhi[0] - rlo[0])
        return Vector(out)

    layer = me.uv_layers.active or me.uv_layers.new(name="UVMap")
    worst = 0.0
    for poly in me.polygons:
        key = _key(poly.normal)
        for li in poly.loop_indices:
            p = to_roblox(vs[me.loops[li].vertex_index])
            (u, v), dist = uv_at(groups, key, p)
            worst = max(worst, dist)
            layer.data[li].uv = (u, 1.0 - v)  # Blender's v is up; Roblox's mesh v (as stored) is down
    me.update()
    return worst ** 0.5
