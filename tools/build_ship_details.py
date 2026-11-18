"""Dress the brigantine: deck props, shaped stern, hull and gun details, lanterns.

Run from the project root; safe to re-run on its own output:
    blender -b assets/models/ship.blend --python tools/build_ship_details.py

Everything generated lives in the "ShipDetails" collection and is rebuilt from
scratch. Existing objects are only touched where noted (stern windows move onto
the new transom, Lantern_-1/Lantern_1 get new meshes, ShipCollider gains boxes).
All generated meshes use ship coordinates: +Y is the bow, Godot z = -Blender y.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

COLLECTION = "ShipDetails"
COLLIDER_BASE = "ShipCollider_BaseMesh"
MAIN_DECK, QUARTER_DECK, FORECASTLE_DECK = 1.6, 2.9, 2.4
I = Matrix.Identity(4)
rng = random.Random(7)
V = Vector
objs = bpy.data.objects


# ---------------------------------------------------------------- mesh builder
class Part:
    """One Blender object under construction, in ship coordinates."""

    def __init__(self):
        self.verts, self.faces, self.face_mats, self.mats = [], [], [], []

    def add(self, verts, faces, mat, m=I):
        if mat not in self.mats:
            self.mats.append(mat)
        slot, base = self.mats.index(mat), len(self.verts)
        self.verts += [m @ V(p) for p in verts]
        for f in faces:
            self.faces.append([base + i for i in f])
            self.face_mats.append(slot)


def lathe(p, profile, sides, mat, m=I, mats=None, cap=(True, True), phase=None):
    """Revolve (radius, z) rings; mats optionally colours each ring-to-ring band."""
    phase = math.pi / sides if phase is None else phase
    verts, bands = [], []
    for r, z in profile:
        for i in range(sides):
            a = phase + i * math.tau / sides
            verts.append((r * math.cos(a), r * math.sin(a), z))
    for k in range(len(profile) - 1):
        quads = []
        for i in range(sides):
            j = (i + 1) % sides
            quads.append([k * sides + i, k * sides + j, (k + 1) * sides + j, (k + 1) * sides + i])
        bands.append(quads)
    # Keep one shared vertex pool per material so rings stay welded per colour.
    groups = {}
    for k, quads in enumerate(bands):
        groups.setdefault(mats[k] if mats else mat, []).extend(quads)
    for name, quads in groups.items():
        p.add(verts, quads, name, m)
    if cap[0]:
        p.add(verts[:sides], [list(range(sides))[::-1]], mats[0] if mats else mat, m)
    if cap[1]:
        p.add(verts[-sides:], [list(range(sides))], mats[-1] if mats else mat, m)


def box(p, center, size, mat, m=I):
    cx, cy, cz = center
    sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
    verts = [(cx + a * sx, cy + b * sy, cz + c * sz) for a in (-1, 1) for b in (-1, 1) for c in (-1, 1)]
    p.add(verts, [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]], mat, m)


def beam(p, a, b, w, mat, h=None, sides=4, up=V((0, 0, 1)), caps=True):
    """Square or n-sided bar from a to b."""
    a, b = V(a), V(b)
    h = h or w
    axis = (b - a).normalized()
    ref = up if abs(axis.dot(up)) < 0.95 else V((1, 0, 0))
    s = axis.cross(ref).normalized()
    t = s.cross(axis).normalized()
    verts = []
    for e in (a, b):
        for i in range(sides):
            ang = math.pi / sides + i * math.tau / sides
            verts.append(e + s * math.cos(ang) * w * 0.707 + t * math.sin(ang) * h * 0.707)
    faces = [[i, (i + 1) % sides, sides + (i + 1) % sides, sides + i] for i in range(sides)]
    if caps:
        faces += [list(range(sides))[::-1], list(range(sides, 2 * sides))]
    p.add(verts, faces, mat)


def torus(p, major, minor, segs, sides, mat, m=I):
    verts, faces = [], []
    for i in range(segs):
        a = i * math.tau / segs
        for j in range(sides):
            b = math.pi / sides + j * math.tau / sides
            r = major + minor * math.cos(b)
            verts.append((r * math.cos(a), r * math.sin(a), minor * math.sin(b)))
    for i in range(segs):
        for j in range(sides):
            n, o = (i + 1) % segs, (j + 1) % sides
            faces.append([i * sides + j, n * sides + j, n * sides + o, i * sides + o])
    p.add(verts, faces, mat, m)


def ball(p, center, radius, mat):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    verts = [tuple(v.co + V(center)) for v in bm.verts]
    bm.verts.index_update()
    faces = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    p.add(verts, faces, mat)


def grid(p, rows, mat, closed=False):
    """Loft equal-length rows of points into quads."""
    n = len(rows[0])
    verts = [tuple(q) for row in rows for q in row]
    faces = []
    for r in range(len(rows) - 1):
        for i in range(n if closed else n - 1):
            j = (i + 1) % n
            faces.append([r * n + i, r * n + j, (r + 1) * n + j, (r + 1) * n + i])
    p.add(verts, faces, mat)


def finish(p, name, collection, obj=None):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in p.verts], [], p.faces)
    for mat in p.mats:
        mesh.materials.append(bpy.data.materials[mat])
    for poly, slot in zip(mesh.polygons, p.face_mats):
        poly.material_index = slot
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0004)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    uv = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        co = mesh.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = (co.x * 0.5 + co.z * 0.25, co.y * 0.5 + co.z * 0.25)
    mesh.update()
    if obj is None:
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
    else:
        obj.data = mesh
    return obj


# ------------------------------------------------------------------- ship data
def bvh_of(name):
    ob = objs[name]
    mesh = ob.data
    verts = [ob.matrix_world @ v.co for v in mesh.vertices]
    return BVHTree.FromPolygons(verts, [tuple(f.vertices) for f in mesh.polygons]), verts


HULL, _ = bvh_of("Hull")
_, RAIL_VERTS = bvh_of("RailCap")


def inner_x(y, z):
    """Inside face of the bulwark on the starboard side (hull is symmetric)."""
    hit = HULL.ray_cast(V((0.4, y, z)), V((1, 0, 0)), 6.0)
    return hit[0].x if hit[0] else None


def outer_x(y, z):
    hit = HULL.ray_cast(V((6.0, y, z)), V((-1, 0, 0)), 6.0)
    return hit[0].x if hit[0] else None


def rail_at(y):
    """Centre x and top z of the rail cap at station y."""
    near = sorted(RAIL_VERTS, key=lambda v: abs(v.y - y))[:16]
    best = abs(near[0].y - y) + 0.001
    pts = [v for v in near if v.x > 0 and abs(v.y - y) <= best + 0.09]
    return sum(v.x for v in pts) / len(pts), max(v.z for v in pts)


def world_bounds(name):
    ob = objs[name]
    pts = [ob.matrix_world @ V(c) for c in ob.bound_box]
    return V([min(q[i] for q in pts) for i in range(3)]), V([max(q[i] for q in pts) for i in range(3)])


# ----------------------------------------------------------------------- props
def cask(c, x, y, z, h=0.62, r=0.24, m=None, sides=8):
    base = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rng.uniform(0, 1), 4, "Z")
    prof = [(0.80, 0.0), (0.86, 0.05), (0.88, 0.11), (0.97, 0.30), (1.0, 0.5), (0.97, 0.70), (0.88, 0.89), (0.86, 0.95), (0.80, 1.0)]
    mats = ["DarkWood", "DarkWood", "HullWood", "HullWood", "HullWood", "HullWood", "DarkWood", "DarkWood"]
    lathe(c, [(a * r, b * h) for a, b in prof], sides, "HullWood", (m or I) @ base if m else base, mats=mats)


def crate(c, x, y, z, s, turn=0.0, tall=1.0):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(turn, 4, "Z")
    h = s * tall
    box(c, (0, 0, h / 2), (s * 0.92, s * 0.92, h * 0.94), "HullWood", m)
    b = s * 0.11
    e = s / 2 - b / 2
    for ax, ay in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        box(c, (ax * e, ay * e, h / 2), (b, b, h), "DarkWood", m)
    for zz in (b / 2, h - b / 2):
        for k in (-1, 1):
            box(c, (0, k * e, zz), (s, b, b), "DarkWood", m)
            box(c, (k * e, 0, zz), (b, s, b), "DarkWood", m)


def coil(c, x, y, z, major=0.24, layers=2):
    for k in range(layers):
        r = major * (1.0 - 0.14 * k)
        m = Matrix.Translation((x, y, z + 0.04 + k * 0.07)) @ Matrix.Rotation(k * 0.4, 4, "Z")
        torus(c, r, 0.05, 10, 4, "Rope", m)


def bucket(c, x, y, z, r=0.14, h=0.26):
    m = Matrix.Translation((x, y, z))
    lathe(c, [(r * 0.78, 0), (r * 0.86, h * 0.45), (r, h)], 8, "HullWood", m, mats=["DarkWood", "HullWood"], cap=(True, False))
    pts = [V((x + r * math.cos(t), y, z + h + r * 0.85 * math.sin(t))) for t in (0, 0.8, 1.57, 2.35, 3.14)]
    for a, b in zip(pts, pts[1:]):
        beam(c, a, b, 0.016, "Iron", sides=3, caps=False)


def pin(c, x, y, z):
    beam(c, (x, y, z - 0.12), (x, y, z + 0.13), 0.042, "DeckWood", sides=4)


def net(c, x0, x1, y0, y1, top, low, n=5, seg=6):
    """Sagging cargo net over a block; thin triangular cords."""
    def height(u, v):
        edge = min(u, 1 - u, v, 1 - v)
        return low + (top - low) * min(1.0, edge / 0.16) ** 0.7 + 0.02 * math.sin(u * 9 + v * 5)

    def point(u, v):
        return V((x0 + (x1 - x0) * u, y0 + (y1 - y0) * v, height(u, v)))

    for i in range(n):
        t = (i + 0.5) / n
        for k in range(seg):
            a, b = k / seg, (k + 1) / seg
            beam(c, point(t, a), point(t, b), 0.024, "Rope", sides=3, caps=False)
            beam(c, point(a, t), point(b, t), 0.024, "Rope", sides=3, caps=False)


def lantern_mesh(p, center, radius, height):
    """Hexagonal iron lantern centred exactly on its flame."""
    r, h = radius, height
    m = Matrix.Translation(center)
    lathe(p, [(r * 0.55, -h * 0.5), (r * 0.92, -h * 0.44), (r * 0.98, -h * 0.36), (r * 0.82, -h * 0.33)], 6, "Iron", m, phase=0.0)
    lathe(p, [(r * 0.74, -h * 0.34), (r * 0.86, h * 0.22)], 6, "LanternGlass", m, phase=0.0)
    lathe(p, [(r * 0.98, h * 0.19), (r * 1.04, h * 0.25), (r * 0.60, h * 0.37), (r * 0.26, h * 0.43), (r * 0.17, h * 0.5)], 6, "Iron", m, phase=0.0)
    for i in range(6):
        a = i * math.tau / 6
        lo = V((r * 0.92 * math.cos(a), r * 0.92 * math.sin(a), -h * 0.36))
        hi = V((r * 0.99 * math.cos(a), r * 0.99 * math.sin(a), h * 0.21))
        beam(p, m @ lo, m @ hi, r * 0.11, "Iron", sides=4, caps=False)


# ------------------------------------------------------------------ stern shape
def lerp(a, b, t):
    return a + (b - a) * t


def keyed(keys, z):
    if z <= keys[0][0]:
        return keys[0][1]
    for (z0, a), (z1, b) in zip(keys, keys[1:]):
        if z <= z1:
            t = (z - z0) / (z1 - z0)
            return lerp(a, b, t * t * (3 - 2 * t))
    return keys[-1][1]


BULGE = [(0.75, 0.0), (1.3, 0.16), (2.1, 0.38), (2.9, 0.56), (3.5, 0.62), (4.25, 0.58)]


def half_width(z):
    return 2.09 if z < 1.11 else 2.09 - (z - 1.11) * 0.0466


def crown(u):
    return 3.9 + 0.3 * (1 - u * u)


def transom(u, z, off=0.0):
    x = u * half_width(z)
    return V((x, -10.0 - keyed(BULGE, z) * max(0.0, 1 - u * u) ** 0.75 - off, z))


def transom_at_x(x, z, off=0.0):
    return transom(max(-1, min(1, x / half_width(z))), z, off)


def build_stern(new):
    us = [-1 + 2 * i / 12 for i in range(13)]
    # Transom shell: bulging counter, arched crown, solid back above the old rail.
    rows = []
    for k in range(9):
        rows.append([transom(u, lerp(0.75, crown(u), k / 8)) for u in us])
    rows.append([V((u * half_width(crown(u)), -9.88, crown(u))) for u in us])
    rows.append([V((u * half_width(3.86), -9.88, 3.86)) for u in us])
    p = Part()
    grid(p, rows, "HullWood")
    new(p, "SternTransom")

    p = Part()
    for z, h, off, mat in ((2.84, 0.11, 0.05, "WaleTrim"), (3.72, 0.10, 0.05, "WaleTrim"), (2.44, 0.07, 0.035, "DarkWood"), (1.72, 0.12, 0.04, "WaleTrim"), (1.28, 0.1, 0.035, "DarkWood")):
        uu = [-0.985 + 1.97 * i / 10 for i in range(11)]
        grid(p, [[transom(u, z - h / 2, 0.0) for u in uu], [transom(u, z - h / 2, off) for u in uu],
                 [transom(u, z + h / 2, off) for u in uu], [transom(u, z + h / 2, 0.0) for u in uu]], mat)
    for x in (-1.62, -0.8, 0.0, 0.8, 1.62):
        a, b = transom_at_x(x, 2.9, 0.03), transom_at_x(x, 3.67, 0.03)
        beam(p, a, b, 0.13, "WaleTrim", h=0.09)
        box(p, transom_at_x(x, 3.64, 0.05), (0.19, 0.08, 0.07), "Gold")
        box(p, transom_at_x(x, 2.93, 0.05), (0.19, 0.08, 0.07), "Gold")
    new(p, "SternMouldings")

    p = Part()
    uu = [-1 + 2 * i / 12 for i in range(13)]
    def cap(u, dy, dz):
        z = crown(u) + dz
        q = transom(u, crown(u))
        return V((u * (half_width(crown(u)) + 0.05), q.y + dy, z))
    grid(p, [[cap(u, -0.07, -0.03) for u in uu], [cap(u, -0.07, 0.07) for u in uu],
             [V((u * (half_width(crown(u)) + 0.05), -9.82, crown(u) + 0.07)) for u in uu],
             [V((u * (half_width(crown(u)) + 0.05), -9.82, crown(u) - 0.03)) for u in uu]], "DarkWood")
    new(p, "SternTaffrail")

    # Carved crest under the gallery.
    p = Part()
    c = transom_at_x(0, 2.2, 0.0)
    m = Matrix.Translation((0, c.y - 0.03, 2.2)) @ Matrix.Rotation(math.pi / 2, 4, "X")
    lathe(p, [(0.0, -0.05), (0.27, -0.05), (0.27, 0.05), (0.0, 0.05)], 6, "Gold", m, cap=(False, False))
    lathe(p, [(0.0, 0.05), (0.19, 0.05), (0.19, 0.085), (0.0, 0.085)], 6, "DarkWood", m, cap=(False, False))
    for s in (-1, 1):
        for i, (dx, dz, w) in enumerate(((0.36, 0.05, 0.13), (0.55, 0.0, 0.11), (0.72, -0.05, 0.08))):
            a = transom_at_x(s * (dx - 0.1), 2.2 + dz, 0.02)
            b = transom_at_x(s * (dx + 0.1), 2.2 + dz - 0.05, 0.02)
            beam(p, a, b, w, "WaleTrim", h=0.05)
    new(p, "SternCrest")

    for s, label in ((-1, "Port"), (1, "Stbd")):
        p = Part()
        yc = -9.15
        rings = [(2.2, 0.02, 0.10), (2.45, 0.22, 0.42), (2.75, 0.40, 0.58), (3.0, 0.46, 0.62), (3.7, 0.46, 0.62),
                 (3.85, 0.53, 0.68), (4.0, 0.30, 0.44), (4.22, 0.03, 0.06)]
        mats = ["DarkWood", "HullWood", "WaleTrim", "HullWood", "WaleTrim", "DarkWood", "DarkWood"]
        angles = [math.radians(a) for a in (-90, -55, -18, 18, 55, 90)]
        rows = []
        for z, d, half in rings:
            xh = (outer_x(yc, min(z, 3.8)) or 2.1) - 0.06
            rows.append([V((s * (xh + d * math.cos(a)), yc + half * math.sin(a), z)) for a in angles])
        for k, mat in enumerate(mats):
            grid(p, [rows[k], rows[k + 1]], mat)
        for i in (1, 2, 3):
            lo0, lo1, hi0, hi1 = rows[3][i], rows[3][i + 1], rows[4][i], rows[4][i + 1]
            out = V((s * 0.018, 0, 0))
            def pane(a, b, inset):
                bottom, top = lo0.lerp(lo1, a), hi0.lerp(hi1, a)
                return bottom.lerp(top, b) + out * inset
            for mat, ins, lift in (("Gold", 0.09, 1.0), ("Iron", 0.2, 2.0)):
                corners = [pane(ins, ins, lift), pane(1 - ins, ins, lift), pane(1 - ins, 1 - ins, lift), pane(ins, 1 - ins, lift)]
                p.add([tuple(q) for q in corners], [[0, 1, 2, 3]], mat)
        ball(p, (s * ((outer_x(yc, 3.8) or 2.1) + 0.0), yc, 4.26), 0.07, "Gold")
        new(p, "QuarterGallery_" + label)


def place_stern_windows():
    """Set the four existing windows into the curved transom, slightly enlarged."""
    for i in range(4):
        frame, glass = objs["SternWindow_%d" % i], objs["SternWindowGlass_%d" % i]
        for ob in (frame, glass):
            if "orig_world" not in ob:
                ob["orig_world"] = [v for row in ob.matrix_world for v in row]
        def original(ob):
            f = list(ob["orig_world"])
            return Matrix([f[0:4], f[4:8], f[8:12], f[12:16]])
        m0 = original(frame)
        c = sum((m0 @ V(q) for q in frame.bound_box), V()) / 8
        target = transom_at_x(c.x, 3.3)
        ahead, behind = transom_at_x(c.x + 0.1, 3.3), transom_at_x(c.x - 0.1, 3.3)
        turn = math.atan2((ahead - behind).y, (ahead - behind).x)
        place = (Matrix.Translation(target + V((0, -0.005, 0))) @ Matrix.Rotation(turn, 4, "Z")
                 @ Matrix.Diagonal((1.25, 1.0, 1.25, 1.0)) @ Matrix.Translation(-c))
        frame.matrix_world = place @ m0
        glass.matrix_world = place @ original(glass)


# ------------------------------------------------------------------- hull parts
def build_channels(new):
    for mast, y0, y1 in (("Main", -3.05, -1.42), ("Fore", 3.15, 4.8)):
        for s, side, label in ((-1, "-1", "Port"), (1, "1", "Stbd")):
            p = Part()
            feet = []
            for k in range(3):
                ob = objs["%sShroud_%s_%d" % (mast, side, k)]
                pts = [ob.matrix_world @ v.co for v in ob.data.vertices]
                low = min(q.z for q in pts)
                near = [q for q in pts if q.z < low + 0.02]
                feet.append(sum(near, V()) / len(near))
            reach = max(abs(f.x) for f in feet) + 0.14
            ring = []
            for i in range(7):
                y = lerp(y0, y1, i / 6)
                xh = (outer_x(y, 2.5) or 2.8) - 0.03
                ring.append((xh, y))
            lo, hi = 2.42, 2.5
            rows = [[V((s * xh, y, lo)) for xh, y in ring], [V((s * reach, y, lo)) for xh, y in ring],
                    [V((s * reach, y, hi)) for xh, y in ring], [V((s * xh, y, hi)) for xh, y in ring]]
            grid(p, rows, "DarkWood")
            p.add([tuple(rows[i][0]) for i in range(4)], [[0, 1, 2, 3]], "DarkWood")
            p.add([tuple(rows[i][-1]) for i in range(4)], [[0, 1, 2, 3]], "DarkWood")
            for f in feet:
                lathe(p, [(0.06, f.z - 0.03), (0.105, f.z + 0.04), (0.06, f.z + 0.12)], 6, "DarkWood",
                      Matrix.Translation((f.x, f.y, 0)))
                bottom = V((s * ((outer_x(f.y, 1.72) or 2.9) + 0.015), f.y, 1.72))
                beam(p, (f.x, f.y, 2.44), bottom, 0.055, "Iron", h=0.03)
                box(p, bottom, (0.05, 0.09, 0.07), "Iron")
            new(p, "Channel_%s%s" % (mast, label))


def build_guns(new):
    for s, tag in ((-1, "P"), (1, "S")):
        for g in range(4):
            name = "Gun%s%d_" % (tag, g)
            lo, hi = world_bounds(name + "Barrel")
            cy, cz = (lo.y + hi.y) / 2, (lo.z + hi.z) / 2
            clo, chi = world_bounds(name + "Carriage")
            inboard = min(abs(clo.x), abs(chi.x))
            outboard = max(abs(clo.x), abs(chi.x))
            rad = (hi.y - lo.y) / 2
            p = Part()
            # Stepped cheeks, the classic truck carriage profile.
            length = outboard - inboard
            for side in (-1, 1):
                y = cy + side * (rad + 0.075)
                steps = [(0.0, 1.98), (0.22, 2.0), (0.22, 2.08), (0.48, 2.08), (0.48, 2.17), (1.0, 2.17)]
                top = [(inboard + t * length, z) for t, z in steps]
                pts = [(inboard, 1.72)] + top + [(outboard, 1.72)]
                n = len(pts)
                verts = [(s * x, y + d, z) for d in (-0.05, 0.05) for x, z in pts]
                faces = [list(range(n)), list(range(2 * n - 1, n - 1, -1))]
                faces += [[i, (i + 1) % n, n + (i + 1) % n, n + i] for i in range(n)]
                p.add(verts, faces, "RedTrim")
            # Trunnion strap over the cheeks and iron bands on the barrel.
            tx = inboard + 0.72 * length
            box(p, (s * tx, cy, 2.205), (0.10, 2 * rad + 0.27, 0.03), "Iron")
            for t in (0.14, 0.55, 0.95):
                x = lerp(abs(hi.x) if s < 0 else abs(lo.x), abs(lo.x) if s < 0 else abs(hi.x), t)
                m = Matrix.Translation((s * x, cy, cz)) @ Matrix.Rotation(math.pi / 2, 4, "Y")
                lathe(p, [(rad * 1.0, -0.026), (rad * 1.15, 0.0), (rad * 1.0, 0.026)], 8, "Iron", m, cap=(False, False))
            # Breeching tackle from the carriage to the bulwark.
            for side in (-1, 1):
                a = V((s * (outboard - 0.04), cy + side * (rad + 0.14), 1.95))
                xi = inner_x(cy + side * 0.46, 2.0) or outboard + 0.5
                b = V((s * (xi - 0.03), cy + side * 0.46, 2.02))
                beam(p, a, a.lerp(b, 0.5) - V((0, 0, 0.05)), 0.035, "Rope", sides=3, caps=False)
                beam(p, a.lerp(b, 0.5) - V((0, 0, 0.05)), b, 0.035, "Rope", sides=3, caps=False)
            new(p, name + "Fittings")

            # Frame the port opening, following the tumblehome of the side.
            hits = [z / 100 for z in range(165, 280) if not _solid(cy, z / 100)]
            z0, z1 = (min(hits), max(hits)) if hits else (1.92, 2.3)
            mid = (z0 + z1) / 2
            wide = [d / 100 for d in range(0, 70) if not _solid(cy + d / 100, mid) and not _solid(cy - d / 100, mid)]
            half = max(wide) if wide else 0.3
            f = Part()
            w = 0.075
            def at(y, z, out):
                return V((s * ((outer_x(y, z) or outer_x(cy + half + 0.1, z) or 2.9) + out), y, z))
            def rect(h, a, b, c, d, out):
                return [at(cy - h, a, out), at(cy + h, a, out), at(cy + h, b, out), at(cy - h, b, out)]
            outer_low = rect(half + w, z0 - w, z1 + w, 0, 0, -0.01)
            outer_top = rect(half + w, z0 - w, z1 + w, 0, 0, 0.05)
            inner_top = [at(cy - half, z0, 0.05), at(cy + half, z0, 0.05), at(cy + half, z1, 0.05), at(cy - half, z1, 0.05)]
            inner_low = [at(cy - half, z0, -0.05), at(cy + half, z0, -0.05), at(cy + half, z1, -0.05), at(cy - half, z1, -0.05)]
            grid(f, [outer_low, outer_top, inner_top, inner_low], "DarkWood", closed=True)
            new(f, name + "PortFrame")


def _solid(y, z):
    """True when the hull side exists at this height (false inside a gun port)."""
    x = outer_x(y, z)
    return x is not None and x > 2.0


def build_anchors(new):
    for s, label in ((-1, "Port"), (1, "Stbd")):
        p = Part()
        y, x = 8.75, 2.28
        rail_x, rail_z = rail_at(y)
        beam(p, (s * (rail_x - 0.32), y, rail_z - 0.02), (s * (x + 0.28), y, rail_z + 0.2), 0.17, "DarkWood")
        box(p, (s * (x + 0.24), y, rail_z + 0.2), (0.2, 0.2, 0.05), "Iron")
        top, bottom = 3.02, 1.62
        beam(p, (s * x, y, rail_z + 0.14), (s * x, y, top + 0.1), 0.035, "Rope", sides=3)
        beam(p, (s * x, y, top), (s * x, y, bottom), 0.085, "Iron")
        torus(p, 0.075, 0.018, 8, 3, "Iron", Matrix.Translation((s * x, y, top + 0.08)) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
        beam(p, (s * x, y - 0.46, top - 0.12), (s * x, y + 0.46, top - 0.12), 0.1, "DarkWood", h=0.12)
        for d in (-1, 1):
            elbow = V((s * x, y + d * 0.24, bottom + 0.05))
            tip = V((s * x, y + d * 0.44, bottom + 0.36))
            beam(p, (s * x, y, bottom + 0.02), elbow, 0.08, "Iron")
            beam(p, elbow, tip, 0.07, "Iron")
            fl = [V((s * x, y + d * 0.30, bottom + 0.14)), V((s * x, y + d * 0.58, bottom + 0.30)), V((s * x, y + d * 0.42, bottom + 0.52))]
            verts = [tuple(q + V((e, 0, 0))) for e in (-0.02, 0.02) for q in fl]
            p.add(verts, [[0, 1, 2], [5, 4, 3], [0, 3, 4, 1], [1, 4, 5, 2], [2, 5, 3, 0]], "Iron")
        new(p, "Anchor_" + label)


# ----------------------------------------------------------------------- decks
def build_deck(new, solid):
    def ix(y, z=2.2):
        v = inner_x(y, z)
        if v is None:
            raise RuntimeError("no bulwark at y=%.2f z=%.2f" % (y, z))
        return v

    d = MAIN_DECK
    # Starboard waist: casks and a bucket.
    x = ix(1.0)
    p = Part()
    cask(p, x - 0.30, 0.44, d)
    new(p, "Cask_WaistS1")
    p = Part()
    cask(p, x - 0.30, 0.98, d)
    new(p, "Cask_WaistS2")
    p = Part()
    cask(p, x - 0.74, 0.70, d, h=0.56, r=0.22)
    new(p, "Cask_WaistS3")
    solid(x - 0.98, x - 0.02, 0.18, 1.24, d, d + 0.62)
    p = Part()
    bucket(p, x - 0.3, 1.55, d)
    new(p, "Bucket_WaistS")

    # Starboard fore: crate stack under a net.
    x = ix(3.8)
    p = Part()
    crate(p, x - 0.37, 3.47, d, 0.62, 0.05)
    new(p, "Crate_ForeS1")
    p = Part()
    crate(p, x - 0.34, 4.13, d, 0.54, -0.1)
    new(p, "Crate_ForeS2")
    p = Part()
    crate(p, x - 0.39, 3.5, d + 0.62, 0.40, 0.4)
    new(p, "Crate_ForeS3")
    p = Part()
    net(p, x - 0.76, x - 0.02, 3.1, 3.92, d + 1.04, d + 0.28)
    new(p, "Net_ForeS")
    solid(x - 0.72, x - 0.02, 3.14, 4.42, d, d + 0.62)

    # Starboard, by the stern stairs: a lone cask and a bucket clear of the ramp.
    x = ix(-1.5)
    p = Part()
    cask(p, x - 0.26, -1.08, d, h=0.56, r=0.2)
    new(p, "Cask_MainS")
    solid(x - 0.47, x - 0.02, -1.3, -0.86, d, d + 0.56)

    # Port waist: shot rack and a coil.
    x = ix(1.05)
    p = Part()
    y0, y1 = 0.26, 1.84
    box(p, (-(x - 0.14), (y0 + y1) / 2, d + 0.04), (0.26, y1 - y0, 0.08), "DarkWood")
    for sx in (-1, 1):
        box(p, (-(x - 0.14) + sx * 0.12, (y0 + y1) / 2, d + 0.12), (0.035, y1 - y0, 0.09), "DarkWood")
    for k in (-1, 1):
        box(p, (-(x - 0.14), (y0 + y1) / 2 + k * (y1 - y0) / 2, d + 0.14), (0.26, 0.04, 0.2), "DarkWood")
    n = 8
    for i in range(n):
        ball(p, (-(x - 0.14), lerp(y0 + 0.11, y1 - 0.11, i / (n - 1)), d + 0.17), 0.088, "Iron")
    for i in range(n - 1):
        ball(p, (-(x - 0.14), lerp(y0 + 0.11, y1 - 0.11, (i + 0.5) / (n - 1)), d + 0.30), 0.088, "Iron")
    new(p, "ShotRack_Waist")
    solid(-(x - 0.01), -(x - 0.28), y0 - 0.02, y1 + 0.02, d, d + 0.38)
    p = Part()
    coil(p, -(x - 0.72), 1.08, d)
    new(p, "Coil_WaistP")
    p = Part()
    bucket(p, -(x - 0.6), 0.44, d)
    new(p, "Bucket_WaistP")

    # Port fore: casks with a netted crate behind them.
    x = ix(3.8)
    for i, (dx, y, h, r) in enumerate(((0.30, 3.3, 0.62, 0.24), (0.30, 3.84, 0.56, 0.22), (0.74, 3.56, 0.62, 0.24))):
        p = Part()
        cask(p, -(x - dx), y, d, h=h, r=r)
        new(p, "Cask_ForeP%d" % (i + 1))
    solid(-(x - 0.02), -(x - 0.98), 3.08, 4.08, d, d + 0.6)
    p = Part()
    crate(p, -(x - 0.36), 4.48, d, 0.56, 0.12)
    new(p, "Crate_ForeP")
    p = Part()
    net(p, -(x - 0.02), -(x - 0.72), 4.12, 4.84, d + 0.58, d + 0.12, n=4, seg=5)
    new(p, "Net_ForeP")
    solid(-(x - 0.02), -(x - 0.66), 4.2, 4.76, d, d + 0.56)

    # Port, aft: a crate tucked by the shrouds, clear of the ramp.
    x = ix(-1.5)
    p = Part()
    crate(p, -(x - 0.26), -1.08, d, 0.42, 0.08)
    new(p, "Crate_MainP")
    solid(-(x - 0.03), -(x - 0.49), -1.31, -0.85, d, d + 0.42)

    # Fife rails with pins and hanging coils at both masts.
    for label, y, hang in (("Main", -1.04, -1.0), ("Fore", 4.05, 1.0)):
        p = Part()
        for sx in (-0.56, 0.56):
            box(p, (sx, y, d + 0.42), (0.1, 0.1, 0.84), "DarkWood")
        box(p, (0, y, d + 0.8), (1.26, 0.16, 0.07), "DarkWood")
        box(p, (0, y, d + 0.42), (1.12, 0.05, 0.06), "HullWood")
        for i in range(6):
            pin(p, -0.42 + i * 0.168, y, d + 0.88)
        new(p, "FifeRail_" + label)
        solid(-0.62, 0.62, y - 0.09, y + 0.09, d, d + 0.84)
        p = Part()
        for sx, major in ((-0.28, 0.13), (0.24, 0.11)):
            m = Matrix.Translation((sx, y + hang * -0.11, d + 0.56)) @ Matrix.Rotation(math.pi / 2, 4, "X")
            torus(p, major, 0.028, 10, 3, "Rope", m)
            torus(p, major * 0.82, 0.028, 10, 3, "Rope", m @ Matrix.Translation((0, 0, 0.03)))
        new(p, "Coil_Fife" + label)

    # Pin rails on the bulwark at the shrouds.
    for label, y0, y1 in (("Main", -2.15, -1.05), ("Fore", 3.15, 4.65)):
        for s, tag in ((-1, "P"), (1, "S")):
            z = 2.36
            xa, xb = ix(y0, z), ix(y1, z)
            p = Part()
            rows = []
            for dx, dz in ((0.0, 0.0), (-0.13, 0.0), (-0.13, 0.055), (0.0, 0.055)):
                rows.append([V((s * (xa + dx), y0, z + dz)), V((s * (xb + dx), y1, z + dz))])
            grid(p, rows, "DarkWood", closed=False)
            count = 5
            for i in range(count):
                t = (i + 0.5) / count
                pin(p, s * (lerp(xa, xb, t) - 0.07), lerp(y0, y1, t), z + 0.07)
            new(p, "PinRail_%s%s" % (label, tag))

    # On and around the hatch.
    p = Part()
    coil(p, 0.4, 1.48, 1.87, major=0.2)
    new(p, "Coil_Hatch")
    p = Part()
    bucket(p, -0.58, 3.72, d)
    new(p, "Bucket_Mast")

    # Quarterdeck.
    d = QUARTER_DECK
    p = Part()
    m = Matrix.Translation((-1.28, -9.28, d)) @ Matrix.Rotation(0.05, 4, "Z")
    box(p, (0, 0, 0.17), (0.86, 0.5, 0.34), "HullWood", m)
    arc = [(0.25 * math.cos(a), 0.34 + 0.17 * math.sin(a)) for a in (0, 0.8, 1.57, 2.35, 3.14)]
    rows = [[m @ V((e, ya, zc)) for ya, zc in arc] for e in (-0.44, 0.44)]
    grid(p, rows, "DarkWood")
    for e in (0, 1):
        p.add([tuple(q) for q in rows[e]], [list(range(5))], "DarkWood")
    for bx in (-0.28, 0.28):
        box(p, (bx, 0, 0.18), (0.06, 0.53, 0.37), "Iron", m)
        band = [m @ V((bx + e, ya * 1.04, 0.34 + (zc - 0.34) * 1.06)) for ya, zc in arc for e in (-0.03, 0.03)]
        p.add([tuple(q) for q in band], [[2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2] for i in range(4)], "Iron")
    new(p, "SeaChest")
    solid(-1.73, -0.83, -9.55, -9.01, d, d + 0.5)

    x = ix(-9.2, 3.2)
    p = Part()
    cask(p, x - 0.32, -9.2, d, h=0.56, r=0.22)
    new(p, "Cask_QuarterAft")
    solid(x - 0.56, x - 0.08, -9.44, -8.96, d, d + 0.56)
    p = Part()
    coil(p, 0.98, -9.3, d, major=0.21)
    new(p, "Coil_Quarter")

    x = ix(-6.0, 3.2)
    p = Part()
    crate(p, x - 0.3, -6.05, d, 0.46, 0.15)
    new(p, "Crate_Quarter")
    solid(x - 0.56, x - 0.04, -6.31, -5.79, d, d + 0.46)
    p = Part()
    cask(p, -(x - 0.28), -6.05, d, h=0.56, r=0.21)
    new(p, "Cask_QuarterFwd")
    solid(-(x - 0.05), -(x - 0.5), -6.28, -5.82, d, d + 0.56)
    p = Part()
    bucket(p, -(x - 0.74), -6.0, d)
    new(p, "Bucket_Quarter")

    # Binnacle ahead of the wheel; Lantern_Helm stands on it.
    p = Part()
    lathe(p, [(0.17, d), (0.13, d + 0.12), (0.12, d + 0.48), (0.19, d + 0.58), (0.19, d + 0.66), (0.08, d + 0.7)], 8, "DarkWood",
          Matrix.Translation((0, -6.1, 0)), mats=["DarkWood", "DarkWood", "WaleTrim", "Gold", "Gold"])
    new(p, "Binnacle")
    solid(-0.19, 0.19, -6.29, -5.91, d, d + 0.66)

    # Forecastle.
    d = FORECASTLE_DECK
    p = Part()
    coil(p, -0.86, 9.1, d, major=0.21)
    new(p, "Coil_Forecastle")
    p = Part()
    cask(p, 0.86, 9.2, d, h=0.5, r=0.19)
    new(p, "Cask_Forecastle")
    p = Part()
    bucket(p, 1.05, 8.62, d)
    new(p, "Bucket_Forecastle")
    # Ship's bell in a small belfry.
    p = Part()
    y = 7.82
    for sx in (-0.24, 0.24):
        beam(p, (sx * 1.25, y, d), (sx, y, d + 0.96), 0.09, "DarkWood")
    box(p, (0, y, d + 1.0), (0.66, 0.13, 0.09), "WaleTrim")
    lathe(p, [(0.15, d + 0.54), (0.115, d + 0.62), (0.08, d + 0.76), (0.055, d + 0.84), (0.0, d + 0.88)], 8, "Gold",
          Matrix.Translation((0, y, 0)), cap=(True, False))
    beam(p, (0, y, d + 0.86), (0, y, d + 0.96), 0.03, "Iron")
    new(p, "ShipBell")
    solid(-0.32, 0.32, y - 0.07, y + 0.07, d, d + 1.04)


# -------------------------------------------------------------------- lanterns
def build_lanterns(new, coll):
    small_r, small_h = 0.115, 0.36

    def lantern(name, c, r=small_r, h=small_h, ob=None):
        p = Part()
        lantern_mesh(p, V(c), r, h)
        o = finish(p, name, coll, ob)
        o.matrix_world = I.copy()
        return o

    # The two existing stern lantern objects keep their names and become the big pair.
    for s, name, label in ((-1, "Lantern_-1", "SternPort"), (1, "Lantern_1", "SternStbd")):
        u = s * 0.8
        t = transom(u, crown(u))
        c = V((s * 1.62, t.y - 0.06, 4.64))
        lantern(name, c, 0.2, 0.62, objs[name])
        p = Part()
        foot = V((s * 1.62, t.y + 0.05, crown(u) + 0.04))
        beam(p, foot, c - V((0, 0, 0.31)), 0.06, "Iron")
        beam(p, foot + V((0, 0.22, 0.0)), c - V((0, -0.02, 0.24)), 0.04, "Iron")
        box(p, foot, (0.2, 0.26, 0.05), "Iron")
        new(p, "IronBracket_" + label)

    d = QUARTER_DECK
    lantern("Lantern_Helm", (0, -6.1, d + 0.7 + small_h / 2 + 0.02))

    for label, yc, ya in (("MainMast", -1.6, 1), ("ForeMast", 4.6, -1)):
        y = yc + ya * 0.45
        z = 3.44
        lantern("Lantern_" + label, (0, y, z))
        p = Part()
        beam(p, (0, yc + ya * 0.2, z + 0.3), (0, y, z + 0.3), 0.05, "Iron")
        beam(p, (0, y, z + 0.3), (0, y, z + small_h / 2), 0.02, "Iron", sides=3)
        beam(p, (0, yc + ya * 0.2, z + 0.02), (0, y - ya * 0.05, z + 0.28), 0.03, "Iron")
        lathe(p, [(0.25, z + 0.275), (0.25, z + 0.325)], 12, "Iron", Matrix.Translation((0, yc, 0)), cap=(False, False))
        new(p, "IronBracket_" + label)

    for label, y in (("Waist", 1.05), ("ForeRail", 3.02), ("Quarter", -7.0)):
        for s, tag in ((-1, "Port"), (1, "Stbd")):
            rx, rz = rail_at(y)
            base = rz + 0.13
            c = (s * rx, y, base + small_h / 2)
            lantern("Lantern_%s%s" % (label, tag), c)
            p = Part()
            beam(p, (s * rx, y, rz - 0.01), (s * rx, y, base + 0.01), 0.035, "Iron")
            box(p, (s * rx, y, rz + 0.012), (0.11, 0.15, 0.025), "Iron")
            new(p, "IronBracket_%s%s" % (label, tag))

    bs = objs["Bowsprit"]
    pts = [bs.matrix_world @ v.co for v in bs.data.vertices]
    tail = [q for q in pts if q.y < min(v.y for v in pts) + 0.3]
    head = [q for q in pts if q.y > max(v.y for v in pts) - 0.3]
    a, b = sum(tail, V()) / len(tail), sum(head, V()) / len(head)
    y = 9.8
    axis = a.lerp(b, (y - a.y) / (b.y - a.y))
    top = axis.z + 0.17
    c = (0, y, top + 0.14 + small_h / 2)
    lantern("Lantern_Bow", c)
    p = Part()
    beam(p, (0, y, top - 0.04), (0, y, top + 0.15), 0.04, "Iron")
    lathe(p, [(0.17, axis.z - 0.05), (0.17, axis.z + 0.05)], 8, "Iron",
          Matrix.Translation((0, y, 0)) @ Matrix.Translation((0, 0, axis.z)) @ Matrix.Rotation(math.pi / 2 - 0.26, 4, "X") @ Matrix.Translation((0, 0, -axis.z)), cap=(False, False))
    new(p, "IronBracket_Bow")


# ----------------------------------------------------------------- walk checks
def keep_clear_zones():
    """(name, xmin, xmax, ymin, ymax, zmin, zmax): must stay free of solid props."""
    d, q, f = MAIN_DECK, QUARTER_DECK, FORECASTLE_DECK
    top = d + 1.8
    zones = [("bosun", -1.35, -0.65, -3.05, 0.15, d, top), ("gunner", 0.7, 1.4, -3.55, 5.95, d, top),
             ("deckhand", -0.9, 0.85, 5.15, 6.45, d, top), ("spawn", 0.4, 1.2, -0.9, -0.1, d, top)]
    for s in (-1, 1):
        a, b = sorted((s * 1.2, s * 2.3))
        zones.append(("stern stairs", a, b, -4.55, -1.35, d, top))
        zones.append(("quarterdeck landing", a, b, -5.6, -4.45, q, q + 1.8))
        a, b = sorted((s * 0.8, s * 1.8))
        zones.append(("bow stairs", a, b, 4.75, 7.1, d, top))
        zones.append(("forecastle landing", a, b, 7.0, 8.1, f, f + 1.8))
    zones.append(("helm", -0.85, 0.85, -8.3, -6.5, q, q + 1.8))
    return zones


def overlaps(a0, a1, b0, b1):
    return a0 < b1 and b0 < a1


def check_clearance(boxes, coll):
    bad = []
    zones = keep_clear_zones()
    for b in boxes:
        for z in zones:
            if overlaps(b[0], b[1], z[1], z[2]) and overlaps(b[2], b[3], z[3], z[4]) and overlaps(b[4], b[5], z[5], z[6]):
                bad.append("collider %s hits %s" % (tuple(round(v, 2) for v in b), z[0]))
    skip = ("Stern", "Quarter", "Channel", "Anchor", "Gun", "IronBracket")
    for ob in coll.objects:
        if ob.name.startswith(skip):
            continue
        pts = [V(v.co) for v in ob.data.vertices]
        lo = [min(q[i] for q in pts) for i in range(3)]
        hi = [max(q[i] for q in pts) for i in range(3)]
        for z in zones:
            if overlaps(lo[0], hi[0], z[1], z[2]) and overlaps(lo[1], hi[1], z[3], z[4]) and overlaps(lo[2], hi[2], z[5], z[6]):
                bad.append("%s hits %s" % (ob.name, z[0]))
    if bad:
        raise RuntimeError("keep-clear violations:\n  " + "\n  ".join(bad))


def extend_collider(boxes):
    ob = objs["ShipCollider"]
    base = bpy.data.meshes.get(COLLIDER_BASE)
    if base is None:
        base = ob.data.copy()
        base.name = COLLIDER_BASE
        base.use_fake_user = True
    bm = bmesh.new()
    bm.from_mesh(base)
    for x0, x1, y0, y1, z0, z1 in boxes:
        vs = [bm.verts.new((x, y, z)) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
        for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            bm.faces.new([vs[i] for i in f])
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


# ------------------------------------------------------------------------ main
def set_color(mat, rgb, roughness=None):
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    if roughness is not None:
        bsdf.inputs["Roughness"].default_value = roughness
    mat.diffuse_color = (*rgb, 1.0)


def triangles():
    dg = bpy.context.evaluated_depsgraph_get()
    total = visible = 0
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH":
            continue
        mesh = ob.evaluated_get(dg).to_mesh()
        mesh.calc_loop_triangles()
        n = len(mesh.loop_triangles)
        ob.evaluated_get(dg).to_mesh_clear()
        total += n
        visible += 0 if ob.name == "ShipCollider" else n
    return total, visible


def main():
    before = triangles()
    old = bpy.data.collections.get(COLLECTION)
    if old:
        for ob in list(old.objects):
            mesh = ob.data
            bpy.data.objects.remove(ob)
            if mesh.users == 0:
                bpy.data.meshes.remove(mesh)
        bpy.data.collections.remove(old)
    coll = bpy.data.collections.new(COLLECTION)
    bpy.context.scene.collection.children.link(coll)

    glass = bpy.data.materials.get("LanternGlass")
    if glass is None:
        glass = bpy.data.materials["Iron"].copy()
        glass.name = "LanternGlass"
        next(n for n in glass.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Metallic"].default_value = 0.0
    set_color(glass, (0.95, 0.80, 0.55), 0.35)
    set_color(bpy.data.materials["RedTrim"], (0.215, 0.098, 0.074), 0.9)

    def new(part, name):
        return finish(part, name, coll)

    boxes = []

    def solid(x0, x1, y0, y1, z0, z1):
        boxes.append((min(x0, x1), max(x0, x1), y0, y1, z0, z1))

    build_stern(new)
    place_stern_windows()
    build_channels(new)
    build_guns(new)
    build_anchors(new)
    build_deck(new, solid)
    build_lanterns(new, coll)
    check_clearance(boxes, coll)
    extend_collider(boxes)

    after = triangles()
    print("DETAILS objects=%d collider_boxes=%d" % (len(coll.objects), len(boxes)))
    print("TRIS before total=%d visible=%d | after total=%d visible=%d" % (*before, *after))
    lanterns = sorted(o.name for o in bpy.context.scene.objects if o.name.startswith("Lantern_"))
    print("LANTERNS", len(lanterns), lanterns)

    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(bpy.data.filepath))))
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_mainfile()
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(root, "assets", "models", "ship.glb"), export_format="GLB",
        use_selection=False, use_visible=False, use_renderable=False, export_apply=True,
        export_yup=True, export_cameras=False, export_lights=False, export_animations=False,
        export_extras=False)
    print("EXPORTED")


main()
