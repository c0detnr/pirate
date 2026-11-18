"""Procedural tropical pirate island.

Usage (headless):  blender -b --python tools/build_island.py
Writes assets/models/island.blend + island.glb (objects Land, Fronds) and
assets/models/distant_islands.glb (objects D1..D4, horizon silhouettes).

Blender is Z-up; the glTF exporter converts to Godot Y-up (Blender +Y -> Godot -Z).
Local origin = waterline. Colours are linear vertex colours per face corner;
alpha = wind-sway weight (Fronds) or haze weight (distant islands).
"""
import math
import os
import random

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "models")


def lin(hexstr):
    h = hexstr.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c)


def mul(c, k):
    return tuple(min(1.0, v * k) for v in c)


def mixc(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


# Muted 18th-century palette.
SAND = lin("#cdb078")
SAND_WET = lin("#8c7752")
SAND_DARK = lin("#6f6046")
DIRT = lin("#a07f52")
GRASS = [lin("#58803a"), lin("#46702f"), lin("#74903f")]
GRASS_DARK = lin("#2f4a2a")
ROCK = [lin("#857968"), lin("#6a6055"), lin("#9a8a70")]
ROCK_DARK = lin("#4b443d")
TRUNK = lin("#7a5430")
TRUNK_DARK = lin("#4a3220")
FROND = [lin("#3c6e30"), lin("#2f5a2a"), lin("#58853a")]
FROND_TIP = lin("#8aa04a")
WOOD = [lin("#8f6c42"), lin("#6f5232"), lin("#a07a4c")]
WOOD_DARK = lin("#4a3524")
HULL_RED = lin("#8a3b2b")
HULL = [lin("#6e4b30"), lin("#5b3e29")]
COCO = lin("#3d2a1a")
FLAG = lin("#9b2d24")
CLOTH = lin("#cbb896")
ASH = lin("#2c2824")

rng = random.Random(7)


def hash2(a, b):
    return (math.sin(a * 127.1 + b * 311.7) * 43758.5453) % 1.0


class Mesh:
    def __init__(self, name):
        self.name = name
        self.v = []
        self.f = []
        self.c = []

    def vert(self, p):
        self.v.append(tuple(p))
        return len(self.v) - 1

    def face(self, idx, col, alpha=1.0):
        self.f.append(tuple(idx))
        c = col if len(col) == 4 else (*col, alpha)
        self.c.append([c] * len(idx))

    def quad(self, a, b, c, d, col, alpha=1.0):
        self.face([self.vert(a), self.vert(b), self.vert(c), self.vert(d)], col, alpha)

    def tri(self, a, b, c, col, alpha=1.0):
        self.face([self.vert(a), self.vert(b), self.vert(c)], col, alpha)

    def tri_up(self, a, b, c, col, alpha=1.0):
        n = cross(sub(b, a), sub(c, a))
        if n[2] < 0:
            b, c = c, b
        self.tri(a, b, c, col, alpha)

    def to_object(self):
        me = bpy.data.meshes.new(self.name)
        me.from_pydata(self.v, [], self.f)
        me.update()
        for p in me.polygons:
            p.use_smooth = False
        attr = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        flat = []
        for poly, cols in zip(me.polygons, self.c):
            for i, loop in enumerate(poly.loop_indices):
                flat.extend(cols[i])
        attr.data.foreach_set("color", flat)
        me.color_attributes.active_color = attr
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


def rotz(p, a):
    c, s = math.cos(a), math.sin(a)
    return (p[0] * c - p[1] * s, p[0] * s + p[1] * c, p[2])


def rotx(p, a):
    c, s = math.cos(a), math.sin(a)
    return (p[0], p[1] * c - p[2] * s, p[1] * s + p[2] * c)


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def scale(a, k):
    return (a[0] * k, a[1] * k, a[2] * k)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def norm(a):
    l = math.sqrt(a[0] ** 2 + a[1] ** 2 + a[2] ** 2) or 1.0
    return (a[0] / l, a[1] / l, a[2] / l)


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def angdiff(a, b):
    return (a - b + math.pi) % (2 * math.pi) - math.pi


def bump(th, c, w):
    return math.exp(-(angdiff(th, c) / w) ** 2)


# ---------------------------------------------------------------- terrain
SHIP_SIDE = math.atan2(-0.906, -0.42)   # direction from island toward the ship spawn
CLIFF_SIDE = math.radians(35)           # exposed rocky side, away from the ship
JETTY_ANG = SHIP_SIDE + math.radians(12)
BOAT_ANG = SHIP_SIDE - math.radians(48)

PEAKS = [(-2.0, 3.0, 15.0, 10.0), (7.0, -4.0, 10.0, 6.5), (-8.0, -6.0, 6.5, 5.5)]


def shore_r(th):
    return (18.0 + 1.2 * math.sin(2 * th + 1.0) + 0.9 * math.sin(3 * th + 2.2) + 0.5 * math.sin(5 * th + 0.3)
            + 0.9 * bump(th, SHIP_SIDE, 0.5) - 0.8 * bump(th, CLIFF_SIDE, 0.5))


def beach_w(th):
    return max(1.0, 6.5 + 3.5 * bump(th, SHIP_SIDE, 0.8) + 1.5 * bump(th, SHIP_SIDE - 1.1, 0.5)
               - 5.0 * bump(th, CLIFF_SIDE, 0.7))


def cliffness(th):
    return bump(th, CLIFF_SIDE, 0.75) + 0.35 * bump(th, CLIFF_SIDE + 2.4, 0.4)


def height(x, y):
    r = math.hypot(x, y)
    th = math.atan2(y, x)
    d = shore_r(th) - r
    bw = beach_w(th)
    if d < 0:
        return 0.04 + 0.34 * d
    s = min(d / bw, 1.0)
    hb = 1.15 * (1 - (1 - s) ** 2)
    cl = min(1.0, cliffness(th))
    start = bw * 0.85
    span = 7.0 - 5.5 * cl
    g = smoothstep(start, start + span, d)
    hill = 0.0
    for px, py, H, sg in PEAKS:
        dd = math.hypot(x - px, y - py)
        hill = max(hill, H * math.exp(-(dd / sg) ** 2.3))
    rough = 0.55 * math.sin(x * 0.7 + 1.3) * math.sin(y * 0.9 - 0.4) + 0.35 * math.sin(x * 1.9 + y * 1.3)
    hill = max(0.0, hill + rough * min(1.0, hill / 3.0))
    stepped = round(hill / 2.4) * 2.4
    hill = hill + (stepped - hill) * 0.35 * cl
    return 0.04 + hb + g * hill


ground = height


def trail_points():
    th0 = JETTY_ANG
    r0 = shore_r(th0) - 1.5
    pts = []
    n = 14
    for i in range(n + 1):
        t = i / n
        th = th0 + 0.9 * t * t + 0.12 * math.sin(t * 9)
        r = r0 * (1 - t) + 4.8 * t
        pts.append((r * math.cos(th), r * math.sin(th)))
    return pts


TRAIL = trail_points()


def trail_dist(x, y):
    return min(math.hypot(x - px, y - py) for px, py in TRAIL)


def slope_at(x, y):
    e = 0.6
    dx = (height(x + e, y) - height(x - e, y)) / (2 * e)
    dy = (height(x, y + e) - height(x, y - e)) / (2 * e)
    return 1.0 / math.sqrt(1 + dx * dx + dy * dy)


def terrain_color(pts):
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    cz = sum(p[2] for p in pts) / len(pts)
    n = norm(cross(sub(pts[1], pts[0]), sub(pts[2], pts[0])))
    if n[2] < 0:
        n = scale(n, -1)
    th = math.atan2(cy, cx)
    r = math.hypot(cx, cy)
    d = shore_r(th) - r
    bw = beach_w(th)
    jitter = hash2(round(cx * 3), round(cy * 3))
    if cz < 0.02:
        return mixc(SAND_WET, SAND_DARK, min(1.0, -cz / 2.4))
    slope = n[2]
    if cz > 0.7 and (slope < 0.36 or (slope < 0.56 and cliffness(th) > 0.35)):
        strata = int(math.floor(cz * 0.8 + jitter * 0.3)) % 3
        base = ROCK[strata]
        if slope < 0.3:
            base = mixc(base, ROCK_DARK, 0.45)
        return mul(base, 0.92 + jitter * 0.16)
    if cz > 12.2:
        return mul(ROCK[2], 0.9 + jitter * 0.2)
    if d < bw * 0.72 and cz < 1.5:
        if cz < 0.34:
            return mixc(SAND_WET, SAND, cz / 0.34)
        return mul(SAND, 0.94 + jitter * 0.12)
    if trail_dist(cx, cy) < 0.95 and slope > 0.7:
        return mul(DIRT, 0.92 + jitter * 0.14)
    if d < bw * 0.95 and cz < 2.0:
        return mixc(SAND, GRASS[0], 0.55)
    g = GRASS[int(jitter * 3) % 3]
    return mixc(GRASS_DARK, g, min(1.0, 0.45 + cz / 9.0))


def build_terrain():
    m = Mesh("Land")
    sectors = 64
    q_in = [0.0, 0.12, 0.24, 0.36, 0.47, 0.57, 0.66, 0.74, 0.81, 0.87, 0.92, 0.96, 1.0]
    out_off = [0.8, 1.8, 3.2, 5.0]
    nin = len(q_in)
    rings = []
    for k in range(nin + len(out_off)):
        ring = []
        for i in range(sectors):
            th = 2 * math.pi * i / sectors
            sr = shore_r(th)
            r = sr * q_in[k] if k < nin else sr + out_off[k - nin]
            jit = 1.0 if (0 < k < nin - 1) else 0.0
            ang_j = (hash2(i, k) - 0.5) * 0.045 * jit
            rad_j = (hash2(k, i + 11) - 0.5) * 0.9 * jit
            x = (r + rad_j) * math.cos(th + ang_j)
            y = (r + rad_j) * math.sin(th + ang_j)
            z = height(x, y)
            if k == nin + len(out_off) - 1:
                z = -3.6
            z += (hash2(i + 5, k) - 0.5) * 0.12 * jit
            ring.append((x, y, z))
        rings.append(ring)
    nr = len(rings)
    for i in range(sectors):
        j = (i + 1) % sectors
        c0 = (0, 0, height(0, 0))
        m.tri_up(c0, rings[1][i], rings[1][j], terrain_color([c0, rings[1][i], rings[1][j]]))
        for k in range(1, nr - 1):
            a, b, c, d = rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]
            tris = ((a, b, c), (a, c, d)) if (k + i) % 2 else ((a, b, d), (b, c, d))
            for t in tris:
                m.tri_up(*t, col=terrain_color(list(t)))
    last = rings[-1]
    bottom = (0, 0, -3.8)
    for i in range(sectors):
        m.tri(bottom, last[(i + 1) % sectors], last[i], SAND_DARK)
    return m


# ---------------------------------------------------------------- primitives
def box(m, c, size, yaw, cols, tilt=0.0):
    sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
    pts = []
    for dz in (-sz, sz):
        for dy in (-sy, sy):
            for dx in (-sx, sx):
                p = (dx, dy, dz)
                if tilt:
                    p = rotx(p, tilt)
                pts.append(add(rotz(p, yaw), c))
    c000, c100, c010, c110, c001, c101, c011, c111 = pts
    faces = [((c001, c101, c111, c011), 0), ((c000, c010, c110, c100), 1),
             ((c000, c100, c101, c001), 2), ((c100, c110, c111, c101), 2),
             ((c110, c010, c011, c111), 2), ((c010, c000, c001, c011), 2)]
    for q, ci in faces:
        col = cols[ci % len(cols)] if isinstance(cols, list) else cols
        m.quad(*q, col=col)


def tube(m, pts, radii, sides, cols, band=2, cap=True, alpha=1.0):
    rings = []
    for i, p in enumerate(pts):
        if i == 0:
            t = norm(sub(pts[1], pts[0]))
        elif i == len(pts) - 1:
            t = norm(sub(pts[-1], pts[-2]))
        else:
            t = norm(sub(pts[i + 1], pts[i - 1]))
        ref = (0, 0, 1) if abs(t[2]) < 0.95 else (1, 0, 0)
        u = norm(cross(t, ref))
        v = cross(t, u)
        ring = []
        for s in range(sides):
            a = 2 * math.pi * s / sides + 0.3
            ring.append(add(p, add(scale(u, math.cos(a) * radii[i]), scale(v, math.sin(a) * radii[i]))))
        rings.append(ring)
    for i in range(len(rings) - 1):
        col = cols[(i // band) % len(cols)]
        for s in range(sides):
            s2 = (s + 1) % sides
            m.quad(rings[i][s], rings[i][s2], rings[i + 1][s2], rings[i + 1][s], col=col, alpha=alpha)
    if cap:
        tip = add(pts[-1], scale(norm(sub(pts[-1], pts[-2])), radii[-1] * 0.4))
        for s in range(sides):
            m.tri(rings[-1][s], rings[-1][(s + 1) % sides], tip, cols[-1], alpha=alpha)


def blob(m, c, size, seed, cols, wob=0.28, base_cut=0.35):
    """Chunky faceted lump (low icosphere) for rocks, bushes, nuts."""
    import bmesh
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    r2 = random.Random(seed)
    for v in bm.verts:
        k = 1.0 + (r2.random() - 0.5) * 2 * wob
        v.co.x *= size[0] * k
        v.co.y *= size[1] * k
        v.co.z *= size[2] * (1.0 + (r2.random() - 0.5) * wob)
        if v.co.z < -size[2] * base_cut:
            v.co.z = -size[2] * base_cut
    yaw = r2.random() * 6.28
    verts = [add(rotz(tuple(v.co), yaw), c) for v in bm.verts]
    base = len(m.v)
    for p in verts:
        m.vert(p)
    index = {v.index: i for i, v in enumerate(bm.verts)}
    for f in bm.faces:
        idx = [base + index[v.index] for v in f.verts]
        pts = [m.v[i] for i in idx]
        n = norm(cross(sub(pts[1], pts[0]), sub(pts[2], pts[0])))
        cen = scale(add(add(pts[0], pts[1]), pts[2]), 1 / 3)
        away = sub(cen, c)
        if n[0] * away[0] + n[1] * away[1] + n[2] * away[2] < 0:
            idx = idx[::-1]
            n = scale(n, -1)
        t = max(0.0, n[2])
        col = cols[int(abs(n[0] * 3 + n[1] * 5)) % len(cols)] if isinstance(cols, list) else cols
        m.face(idx, mul(col, 0.8 + t * 0.35 + r2.random() * 0.06))
    bm.free()


def rock(m, x, y, size, seed, sink=0.35):
    blob(m, (x, y, ground(x, y) - size * sink), (size, size * (0.8 + (seed % 3) * 0.12), size * 0.85), seed, ROCK,
         wob=0.3)


# ---------------------------------------------------------------- vegetation
def frond(m, base, az, length, rise, width, r2):
    segs = 6
    st = []
    side = (-math.sin(az), math.cos(az), 0.0)
    for i in range(segs + 1):
        t = i / segs
        d = length * t
        h = rise * d - 0.63 * d * d / length
        p = add(base, (math.cos(az) * d, math.sin(az) * d, h * 0.9))
        w = width * math.sin(math.pi * (0.1 + 0.8 * t)) ** 0.8
        if i % 2 == 1:
            w *= 0.62   # sawtooth edge reads like cut leaflets
        if i == segs:
            w = 0.0
        st.append((add(p, scale(side, -w)), add(p, (0, 0, 0.14 * w)), add(p, scale(side, w)), t))
    c_a = FROND[r2.randrange(3)]
    for i in range(segs):
        l0, s0, r0, t0 = st[i]
        l1, s1, r1, t1 = st[i + 1]
        tcol = mixc(c_a, FROND_TIP, t1 * t1 * 0.7)
        m.quad(l0, l1, s1, s0, col=tcol, alpha=t0)
        m.quad(s0, s1, r1, r0, col=mul(tcol, 0.82), alpha=t0)


def palm(land, fronds, x, y, height_m, lean_dir, lean, seed):
    r2 = random.Random(seed)
    z0 = ground(x, y) - 0.25
    n = 7
    pts, rad = [], []
    for i in range(n):
        t = i / (n - 1)
        off = lean * (t ** 1.6)
        pts.append((x + math.cos(lean_dir) * off, y + math.sin(lean_dir) * off, z0 + height_m * t))
        rad.append(0.42 * (1 - t) + 0.22 * t if i else 0.55)
    tube(land, pts, rad, 6, [TRUNK, TRUNK_DARK], band=1, cap=True)
    crown = pts[-1]
    for k in range(3):
        a = k * 2.1 + r2.random()
        blob(land, add(crown, (math.cos(a) * 0.35, math.sin(a) * 0.35, -0.3)), (0.17, 0.17, 0.17), seed * 7 + k, COCO,
             wob=0.15, base_cut=1.0)
    for k in range(8):
        az = 2 * math.pi * k / 8 + r2.random() * 0.35
        frond(fronds, crown, az, 3.1 + r2.random() * 0.8, 0.55 + r2.random() * 0.45, 0.7 + r2.random() * 0.25, r2)
    for k in range(3):
        frond(fronds, add(crown, (0, 0, 0.1)), k * 2.2 + r2.random(), 1.8, 1.5, 0.5, r2)


def bush(m, x, y, size, seed):
    g = GRASS[seed % 3]
    blob(m, (x, y, ground(x, y) + size * 0.25), (size, size, size * 0.7), seed,
         [g, mul(g, 0.8), mixc(g, FROND_TIP, 0.25)], wob=0.28, base_cut=0.5)


# ---------------------------------------------------------------- props
def jetty(land):
    ang = JETTY_ANG
    d = (math.cos(ang), math.sin(ang), 0)
    side = (-math.sin(ang), math.cos(ang), 0)
    sr = shore_r(ang)
    r_start, r_end = sr - 1.6, sr + 8.6
    deck_z = 0.95
    n = int((r_end - r_start) / 0.9)
    for i in range(n):
        r = r_start + 0.9 * i + 0.45
        broken = r > sr + 7.0
        zc = deck_z - ((0.35 + 0.15 * (i % 2)) if broken else 0.0)
        tilt = (0.11 if i % 2 else -0.08) if broken else 0.0
        for k in range(3):
            if broken and k == 2 and i % 2:
                continue
            p = add((d[0] * r, d[1] * r, 0), scale(side, (k - 1) * 0.55))
            box(land, (p[0], p[1], zc), (0.52, 0.86, 0.12), ang + math.pi / 2, WOOD[(i + k * 2) % 3], tilt=tilt)
    for sgn in (-1, 1):
        for i in range(0, n + 1, 3):
            r = r_start + 0.9 * i
            if r > sr + 7.5:
                continue
            p = add((d[0] * r, d[1] * r, 0), scale(side, sgn * 0.95))
            top = deck_z + 0.55 + (0.35 if (i // 3 + sgn) % 2 else 0.0)
            box(land, (p[0], p[1], (top - 2.4) / 2), (0.24, 0.24, top + 2.4), ang, [WOOD_DARK, WOOD[1], WOOD_DARK])
    end = add((d[0] * (sr + 8.9), d[1] * (sr + 8.9), 0), scale(side, 0.9))
    box(land, (end[0], end[1], 0.1), (0.26, 0.26, 2.6), ang, [WOOD_DARK, WOOD[1]], tilt=0.22)
    base = add((d[0] * (sr - 1.1), d[1] * (sr - 1.1), 0), scale(side, 1.25))
    gz = ground(base[0], base[1])
    box(land, (base[0], base[1], gz + 1.0), (0.2, 0.2, 2.4), ang, [WOOD_DARK, WOOD[1]])
    box(land, (base[0], base[1], gz + 2.2), (0.55, 0.55, 0.5), ang, [lin("#d9b24c"), lin("#8a6a22")])


def barrel(land, x, y, h=0.95, r=0.45):
    z = ground(x, y) - 0.05
    tube(land, [(x, y, z), (x, y, z + h * 0.5), (x, y, z + h)], [r * 0.85, r, r * 0.85], 7,
         [WOOD[0], WOOD_DARK, WOOD[2]], band=1)
    tube(land, [(x, y, z + h * 0.22), (x, y, z + h * 0.26)], [r * 0.95, r * 0.95], 7, [lin("#3a2f28")], cap=False)


def crate(land, x, y, yaw, s=0.8, stack=0):
    z = ground(x, y) + s / 2 - 0.08 + stack * s
    box(land, (x, y, z), (s, s, s), yaw, [WOOD[2], WOOD[0], WOOD[1]])
    box(land, (x, y, z), (s * 1.02, s * 0.16, s * 1.02), yaw, [WOOD_DARK])


def campfire(land, x, y):
    z = ground(x, y)
    for k in range(8):
        a = k * math.pi / 4
        blob(land, (x + math.cos(a) * 0.85, y + math.sin(a) * 0.85, z + 0.05), (0.3, 0.3, 0.22), 40 + k, ROCK,
             wob=0.2, base_cut=0.3)
    pts = [(x + 0.6 * math.cos(2 * math.pi * s / 8), y + 0.6 * math.sin(2 * math.pi * s / 8), z + 0.06) for s in range(8)]
    for s in range(8):
        land.tri_up((x, y, z + 0.06), pts[s], pts[(s + 1) % 8], ASH)
    for k in range(3):
        box(land, (x, y, z + 0.28), (1.15, 0.2, 0.2), k * 2.1 + 0.4, [lin("#3a2a1c"), lin("#241a12")])
    box(land, (x, y, z + 0.5), (0.18, 0.18, 0.5), 0.7, lin("#d99a35"))


def treasure_x(land, x, y):
    z = ground(x, y) + 0.02
    for yaw in (math.radians(40), math.radians(-40)):
        box(land, (x, y, z), (1.9, 0.26, 0.04), yaw, lin("#7a2a22"))


def wreck(land):
    ang = BOAT_ANG
    sr = shore_r(ang)
    bx, by = math.cos(ang) * (sr - 2.2), math.sin(ang) * (sr - 2.2)
    bz = ground(bx, by) + 0.15
    yaw = ang + math.radians(70)
    roll = math.radians(24)
    stations, length = 9, 5.4

    def tr(p):
        return add(rotz(rotx(scale(p, 1.3), roll), yaw), (bx, by, bz))

    secs = []
    for i in range(stations):
        t = i / (stations - 1)
        x = (t - 0.5) * length
        if t > 0.9:
            w = 0.86
        elif t > 0.42:
            w = 0.15 + 0.95 * math.sqrt(max(0.0, 1 - ((t - 0.42) / 0.58) ** 2))
        else:
            w = 0.15 + 0.95 * math.sqrt(max(0.0, 1 - ((t - 0.42) / 0.42) ** 2))
        rise = 0.9 * (1 - t / 0.42) ** 2 if t < 0.42 else 0.0
        sheer = 0.55 + 0.27 * (1 - t) ** 2
        secs.append([(x, w * ((k - 3) / 3.0), 0.62 * sheer * ((k - 3) / 3.0) ** 2 + rise * (0.3 + 0.7 * ((k - 3) / 3.0) ** 2))
                     for k in range(7)])
    for i in range(stations - 1):
        for k in range(6):
            if i >= 4 and k >= 4 and (i + k) % 3 != 0:
                continue
            if i >= 5 and k <= 1 and i % 2:
                continue
            col = HULL_RED if k == 5 and i < 6 else HULL[(i + k) % 2]
            land.quad(tr(secs[i][k]), tr(secs[i + 1][k]), tr(secs[i + 1][k + 1]), tr(secs[i][k + 1]), col=col)
    for i in range(1, stations - 1, 2):
        for k in range(6):
            mid = scale(add(secs[i][k], secs[i][k + 1]), 0.5)
            box(land, tr(add(mid, (0, 0, 0.05))), (0.12, 0.34, 0.1), yaw, WOOD_DARK)
    sc = secs[-1]
    land.quad(tr(sc[0]), tr(sc[1]), tr(sc[2]), tr(sc[3]), col=HULL[0])
    mp = tr((0.6, 0.0, 0.25))
    box(land, (mp[0], mp[1], mp[2] + 0.9), (0.2, 0.2, 2.2), yaw, [WOOD[1], WOOD_DARK], tilt=0.18)
    box(land, (mp[0] + 0.35, mp[1] + 0.2, mp[2] + 1.55), (0.04, 0.9, 0.7), yaw + 0.3, CLOTH)
    ox, oy = bx + math.cos(ang + 0.9) * 2.0, by + math.sin(ang + 0.9) * 2.0
    box(land, (ox, oy, ground(ox, oy) + 0.9), (0.1, 0.1, 2.2), ang, [WOOD[0], WOOD_DARK], tilt=0.3)


def beacon(land, fronds):
    px, py = PEAKS[0][0] + 0.2, PEAKS[0][1] - 0.2
    z = ground(px, py)
    for k in range(6):
        a = k * math.pi / 3
        blob(land, (px + math.cos(a), py + math.sin(a), z), (0.9, 0.9, 0.7), 70 + k, ROCK, wob=0.25, base_cut=0.3)
    blob(land, (px, py, z + 0.5), (0.9, 0.9, 0.7), 91, ROCK[2], wob=0.2, base_cut=0.3)
    tube(land, [(px, py, z + 0.4), (px, py, z + 3.0), (px + 0.04, py, z + 6.3)], [0.22, 0.17, 0.12], 6,
         [WOOD[1], WOOD_DARK], band=1)
    box(land, (px, py, z + 5.0), (0.14, 1.9, 0.14), 0.0, WOOD_DARK)
    zt = z + 6.25
    st = 6
    for i in range(st):
        t0, t1 = i / st, (i + 1) / st
        h0, h1 = 1.2 * (1 - 0.22 * t0), 1.2 * (1 - 0.22 * t1)
        col = FLAG if i % 2 == 0 else mul(FLAG, 0.86)
        fronds.quad((px + 2 * t0, py + 0.1, zt), (px + 2 * t1, py + 0.1, zt), (px + 2 * t1, py + 0.1, zt - h1),
                    (px + 2 * t0, py + 0.1, zt - h0), col=col, alpha=t0 + 0.05)
    fronds.quad((px + 0.55, py + 0.11, zt - 0.28), (px + 1.0, py + 0.11, zt - 0.28), (px + 1.0, py + 0.11, zt - 0.78),
                (px + 0.55, py + 0.11, zt - 0.78), col=CLOTH, alpha=0.3)


def build_island():
    land = build_terrain()
    fronds = Mesh("Fronds")
    placed = [(CLIFF_SIDE - 0.9, 3.0), (CLIFF_SIDE - 0.4, 4.2), (CLIFF_SIDE + 0.3, 3.4), (CLIFF_SIDE + 0.8, 2.2),
              (CLIFF_SIDE + 1.6, 2.6), (CLIFF_SIDE + 2.4, 1.8), (-0.8, 2.2), (2.2, 1.7), (SHIP_SIDE + 1.1, 1.3),
              (SHIP_SIDE - 1.9, 1.5), (SHIP_SIDE + 2.4, 1.2)]
    for i, (th, s) in enumerate(placed):
        r = shore_r(th) + rng.uniform(-1.4, 0.8)
        rock(land, math.cos(th) * r, math.sin(th) * r, s, 100 + i)
    for i, (th, off, s, hgt) in enumerate([(CLIFF_SIDE + 0.15, 3.6, 2.1, 7.5), (CLIFF_SIDE - 0.55, 3.0, 1.5, 4.5),
                                           (CLIFF_SIDE + 0.75, 3.3, 1.2, 3.2)]):
        r = shore_r(th) + off
        blob(land, (math.cos(th) * r, math.sin(th) * r, -1.2), (s, s * 0.9, hgt), 300 + i, ROCK, wob=0.22, base_cut=0.1)

    r2 = random.Random(5)
    spots = []
    tries = 0
    while len(spots) < 14 and tries < 4000:
        tries += 1
        th = r2.uniform(-math.pi, math.pi)
        r = shore_r(th) - r2.uniform(1.2, 8.5)
        x, y = r * math.cos(th), r * math.sin(th)
        z = ground(x, y)
        if not (0.45 < z < 5.5) or slope_at(x, y) < 0.8:
            continue
        if abs(angdiff(th, JETTY_ANG)) < 0.28 or abs(angdiff(th, BOAT_ANG)) < 0.3:
            continue
        if bump(th, CLIFF_SIDE, 0.5) > 0.35 or trail_dist(x, y) < 1.8:
            continue
        if any(math.hypot(x - sx, y - sy) < 3.6 for sx, sy in spots):
            continue
        spots.append((x, y))
    for i, (x, y) in enumerate(spots):
        palm(land, fronds, x, y, r2.uniform(5.4, 8.0), math.atan2(y, x) + r2.uniform(-0.5, 0.5), r2.uniform(0.9, 2.2),
             500 + i)

    for i in range(60):
        th = r2.uniform(-math.pi, math.pi)
        r = shore_r(th) - r2.uniform(2.5, 14.0)
        x, y = r * math.cos(th), r * math.sin(th)
        z = ground(x, y)
        if z < 0.6 or slope_at(x, y) < 0.75 or trail_dist(x, y) < 1.4 or z > 11.5:
            continue
        if abs(angdiff(th, JETTY_ANG)) < 0.2 or abs(angdiff(th, BOAT_ANG)) < 0.22 or bump(th, CLIFF_SIDE, 0.5) > 0.4:
            continue
        bush(land, x, y, 0.8 + r2.random() * 0.8, i)

    jetty(land)
    wreck(land)
    beacon(land, fronds)
    ja = JETTY_ANG
    sr = shore_r(ja)
    campfire(land, math.cos(ja + 0.45) * (sr - 4.5), math.sin(ja + 0.45) * (sr - 4.5))
    gx, gy = math.cos(ja - 0.28) * (sr - 3.0), math.sin(ja - 0.28) * (sr - 3.0)
    barrel(land, gx, gy)
    barrel(land, gx + 0.9, gy - 0.4, h=0.8)
    crate(land, gx - 0.8, gy + 0.5, 0.5)
    crate(land, gx - 0.6, gy + 0.6, 1.0, s=0.6, stack=1)
    treasure_x(land, math.cos(ja + 1.0) * (sr - 3.0), math.sin(ja + 1.0) * (sr - 3.0))
    return land, fronds


# ---------------------------------------------------------------- distant islands
def distant(name, seed, radius, hgt, humps, stretch=1.0):
    """Craggy low-poly silhouette: lumpy rim, a few sharp peaks, skirt below the waterline."""
    m = Mesh(name)
    r2 = random.Random(seed)
    sectors = 20
    levels = [(1.0, 0.0), (0.86, 0.18), (0.68, 0.42), (0.48, 0.68), (0.26, 0.9), (0.0, 1.0)]
    peaks = [(r2.uniform(-0.45, 0.45), r2.uniform(-0.3, 0.3), r2.uniform(0.55, 1.0), r2.uniform(0.22, 0.38))
             for _ in range(humps)]
    rings = []
    for li, (rf, hf) in enumerate(levels):
        ring = []
        for i in range(sectors):
            th = 2 * math.pi * i / sectors + li * 0.15
            wob = 1.0 + (r2.random() - 0.5) * 0.3
            x = math.cos(th) * radius * rf * wob * stretch
            y = math.sin(th) * radius * rf * wob
            bonus = 0.12
            for hx, hy, hs, sg in peaks:
                dd = math.hypot(x / (radius * stretch) - hx, y / radius - hy)
                bonus = max(bonus, hs * math.exp(-(dd / sg) ** 2.0))
            z = hgt * (0.25 + 0.75 * hf) * bonus * (0.85 + 0.3 * r2.random()) if li else 0.0
            ring.append((x, y, z))
        rings.append(ring)
    skirt = [(p[0] * 1.05, p[1] * 1.05, -14.0) for p in rings[0]]
    for i in range(sectors):
        j = (i + 1) % sectors
        m.quad(skirt[i], skirt[j], rings[0][j], rings[0][i], col=(0.5, 0.5, 0.5), alpha=0.0)
        for li in range(len(rings) - 1):
            a, b, c, d = rings[li][i], rings[li][j], rings[li + 1][j], rings[li + 1][i]
            tone = 0.3 + 0.7 * (li + 1) / len(levels)
            if li == len(rings) - 2:
                m.tri(a, b, c, col=(tone,) * 3, alpha=tone)
            else:
                m.quad(a, b, c, d, col=(tone,) * 3, alpha=tone)
    return m


def export(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_materials="NONE", export_vertex_color="ACTIVE",
                              export_active_vertex_color_when_no_material=True, export_cameras=False,
                              export_lights=False)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    land, fronds = build_island()
    lo = land.to_object()
    fo = fronds.to_object()
    print("TRIS Land", sum(len(f) - 2 for f in land.f), "Fronds", sum(len(f) - 2 for f in fronds.f))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "island.blend"))
    export([lo, fo], os.path.join(OUT, "island.glb"))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    objs = []
    tris = 0
    for name, seed, rad, h, humps, st in [("D1", 11, 55, 34, 3, 1.6), ("D2", 23, 36, 26, 2, 1.5),
                                          ("D3", 37, 60, 22, 4, 2.0), ("D4", 41, 28, 16, 2, 1.3)]:
        dm = distant(name, seed, rad, h, humps, st)
        tris += sum(len(f) - 2 for f in dm.f)
        objs.append(dm.to_object())
    print("TRIS distant", tris)
    export(objs, os.path.join(OUT, "distant_islands.glb"))


main()
