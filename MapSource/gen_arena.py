#!/usr/bin/env python3
"""Generates Game/scenes/maps/arena.tscn (the gray-box TDM map) and
Docs/MAP.md (top-down diagram + dimensions).

The map is described here as a list of boxes and ramps in metres, so the
layout is easy to change and always symmetric: most pieces are added with
mirror=True, which also adds the same piece rotated 180 degrees about the
map centre, giving both teams an identical side.

Axes: +X = east, +Z = south, +Y = up. Team 0 spawns south (z = +55),
team 1 spawns north (z = -55).

Run:  python3 MapSource/gen_arena.py      (from the repo root)
"""
import math, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_SCENE = os.path.join(ROOT, "Game", "scenes", "maps", "arena.tscn")
OUT_DOC = os.path.join(ROOT, "Docs", "MAP.md")

# kind -> (material file, surface type used for bullet impact effects)
KINDS = {
    "ground": ("ground", "concrete"),
    "brick": ("brick", "brick"),
    "concrete": ("concrete", "concrete"),
    "plaster": ("plaster", "concrete"),
    "roof": ("roof", "concrete"),
    "ramp": ("ramp", "metal"),
    "metal_blue": ("metal_blue", "metal"),
    "metal_red": ("metal_red", "metal"),
    "metal_green": ("metal_green", "metal"),
    "wood": ("wood", "wood"),
}

boxes = []      # dicts: name kind c(x,y,z centre) s(size) cover
ramps = []      # dicts: name a b width
spawns = [[], []]        # per team: (x, y, z, yaw_degrees)
sniper_spots = [[], []]  # per team: (x, y, z)
hotspots = []


def box(name, kind, x, y0, z, sx, sy, sz, cover=False, mirror=True):
    """A box with its base at height y0, centred on (x, z)."""
    boxes.append(dict(name=name, kind=kind, c=(x, y0 + sy / 2.0, z), s=(sx, sy, sz), cover=cover))
    if mirror:
        boxes.append(dict(name=name + "M", kind=kind, c=(-x, y0 + sy / 2.0, -z), s=(sx, sy, sz), cover=cover))


def wall_x(name, kind, x, z0, z1, h, t=0.4, y0=0.0, mirror=True):
    """A wall running north-south at the given x, from z0 to z1."""
    box(name, kind, x, y0, (z0 + z1) / 2.0, t, h, abs(z1 - z0), mirror=mirror)


def wall_z(name, kind, z, x0, x1, h, t=0.4, y0=0.0, mirror=True):
    """A wall running east-west at the given z, from x0 to x1."""
    box(name, kind, (x0 + x1) / 2.0, y0, z, abs(x1 - x0), h, t, mirror=mirror)


def ramp(name, a, b, width, mirror=True):
    """A walkable slope whose top surface runs from point a (low) to b (high)."""
    ramps.append(dict(name=name, a=a, b=b, width=width))
    if mirror:
        ramps.append(dict(name=name + "M", a=(-a[0], a[1], -a[2]), b=(-b[0], b[1], -b[2]), width=width))


def spawn(team, x, z, mirror=True):
    spawns[team].append((x, 0.05, z, 0.0 if team == 0 else 180.0))
    if mirror:
        other = 1 - team
        spawns[other].append((-x, 0.05, -z, 0.0 if other == 0 else 180.0))


def sniper(x, y, z):
    sniper_spots[0 if z > 0 else 1].append((x, y, z))
    sniper_spots[0 if -z > 0 else 1].append((-x, y, -z))


def hotspot(x, y, z):
    hotspots.append((x, y, z))
    hotspots.append((-x, y, -z))


# ============================================================== LAYOUT
# ---- Ground and perimeter (120 x 120 m playable) ----
box("Ground", "ground", 0, -1, 0, 122, 1, 122, mirror=False)
box("PerimeterN", "brick", 0, 0, -60.5, 122, 6, 1, mirror=False)
box("PerimeterS", "brick", 0, 0, 60.5, 122, 6, 1, mirror=False)
box("PerimeterW", "brick", -60.5, 0, 0, 1, 6, 120, mirror=False)
box("PerimeterE", "brick", 60.5, 0, 0, 1, 6, 120, mirror=False)

# ---- Spawn zone (south; the mirror makes the north one) ----
# A 4 m wall at z = 42 with three 6 m exits: west, centre, east.
for i, (x0, x1) in enumerate([(-60, -23), (-17, -3), (3, 17), (23, 60)]):
    wall_z("SpawnWall%d" % i, "brick", 42, x0, x1, 4.0, t=0.6)
# A container behind each exit so nobody can shoot straight into spawn.
box("SpawnShieldC", "metal_blue", 0, 0, 47, 6, 2.6, 2.4, cover=True)
box("SpawnShieldW", "metal_red", -20, 0, 47, 6, 2.6, 2.4, cover=True)
box("SpawnShieldE", "metal_green", 20, 0, 47, 6, 2.6, 2.4, cover=True)
box("SpawnCrateA", "wood", -10, 0, 51, 1.5, 1.2, 1.5, cover=True)
box("SpawnCrateB", "wood", 10, 0, 50, 1.5, 1.5, 1.5, cover=True)
for x in (-21, -15, -9, -3, 3, 9, 15, 21):
    spawn(0, x, 55)
spawn(0, -50, 50)
spawn(0, 50, 50)

# ---- Sniper nest at the end of the centre lane ----
box("Nest", "concrete", 0, 0, 36, 8, 1.2, 4)
box("NestParapet", "concrete", 0, 1.2, 34.2, 8, 0.9, 0.4)
ramp("NestRampW", (-8, 0, 36), (-4, 1.2, 36), 3)
ramp("NestRampE", (8, 0, 36), (4, 1.2, 36), 3)
sniper(0, 1.2, 36.3)

# ---- Central yard: open, with a clear sniper lane along x = 0 ----
box("YardContainerA", "metal_red", -9, 0, 22, 2.4, 2.6, 6, cover=True)
box("YardContainerB", "metal_blue", 10, 0, 26, 6, 2.6, 2.4, cover=True)
box("YardCrateA", "wood", -6, 0, 30, 1.5, 1.5, 1.5, cover=True)
box("YardCrateB", "wood", 6, 0, 31, 1.2, 1.2, 1.2, cover=True)
box("YardCrateC", "wood", -13, 0, 14, 2, 1.2, 2, cover=True)
box("YardCrateD", "wood", 13, 0, 16, 1.5, 1.5, 1.5, cover=True)
box("YardCrateDTop", "wood", 13, 1.5, 16, 1.2, 1.2, 1.2)
box("YardBarrel", "metal_green", -15, 0, 28, 1, 1.2, 1, cover=True)
box("YardCrateE", "wood", 15, 0, 6, 1.6, 1.6, 1.6, cover=True)
box("YardLowWallA", "concrete", -7, 0, 10, 4, 1.1, 0.5, cover=True)
box("YardLowWallB", "concrete", 7, 0, 8, 0.5, 1.1, 4, cover=True)
box("YardBlock", "concrete", 5, 0, 18, 2, 1.4, 1, cover=True)
box("YardCrateF", "wood", -4.6, 0, 18, 1.5, 1.5, 1.5, cover=True)
box("YardCrateG", "wood", 4.6, 0, 12.5, 1.5, 1.2, 1.5, cover=True)
box("Truck", "metal_green", 7, 0, 1, 2.6, 2.8, 7, cover=True)

# ---- Walls between the yard and the two flanks ----
wall_x("DividerWS", "brick", -20, 14, 34, 3.5, t=0.5)
wall_x("DividerES", "brick", 20, 14, 34, 3.5, t=0.5)
wall_x("DividerWMid", "brick", -20, -5, 5, 3.5, t=0.5)

# ---- Flank warehouse (west; mirrored to the east) ----
# Footprint x -52..-28, z -16..16. Ground floor 3.2 m high, flat roof on top
# reached by two outside ramps. Doors 2.4 m wide.
H = 3.2
wall_z("WhSouthA", "plaster", 16, -52, -41.2, H)
wall_z("WhSouthB", "plaster", 16, -38.8, -28, H)
wall_z("WhNorthA", "plaster", -16, -52, -48, H)
wall_z("WhNorthB", "plaster", -16, -45.6, -28, H)
wall_x("WhEastA", "plaster", -28, -16, -9, H)
wall_x("WhEastB", "plaster", -28, -7, -1.2, H)
wall_x("WhEastC", "plaster", -28, 1.2, 7, H)
wall_x("WhEastD", "plaster", -28, 9, 16, H)
for i, zc in enumerate((-8, 8)):                      # two windows facing the yard
    box("WhSill%d" % i, "plaster", -28, 0, zc, 0.4, 1.0, 2)
    box("WhLintel%d" % i, "plaster", -28, 2.2, zc, 0.4, 1.0, 2)
wall_x("WhWestA", "plaster", -52, -16, -1.2, H)
wall_x("WhWestB", "plaster", -52, 1.2, 16, H)
wall_z("WhInnerA", "plaster", 5, -52, -43, H)        # inner walls make 3 rooms
wall_z("WhInnerB", "plaster", 5, -40.6, -28, H)
wall_x("WhInnerC", "plaster", -40, -16, -7, H)
wall_x("WhInnerD", "plaster", -40, -4.6, 5, H)
box("WhRoof", "roof", -40, H, 0, 24.4, 0.3, 32.4)
box("WhLandingW", "roof", -53.475, H, -2.5, 2.55, 0.3, 3)
ramp("WhRampW", (-53.5, 0, -15), (-53.5, 3.5, -4), 2.5)
box("WhLandingN", "roof", -41.5, H, -17.475, 3, 0.3, 2.55)
ramp("WhRampN", (-29, 0, -17.5), (-40, 3.5, -17.5), 2.5)
P = 3.5                                               # roof surface height
wall_x("WhParapetE", "plaster", -27.95, -16.2, 16.2, 1.0, t=0.3, y0=P)
wall_z("WhParapetS", "plaster", 16.05, -52.2, -27.8, 1.0, t=0.3, y0=P)
wall_x("WhParapetWA", "plaster", -52.05, -16.2, -4, 1.0, t=0.3, y0=P)
wall_x("WhParapetWB", "plaster", -52.05, -1, 16.2, 1.0, t=0.3, y0=P)
wall_z("WhParapetNA", "plaster", -16.05, -52.2, -43, 1.0, t=0.3, y0=P)
wall_z("WhParapetNB", "plaster", -16.05, -40, -27.8, 1.0, t=0.3, y0=P)
box("WhRoofUnitA", "metal_green", -36, P, -6, 2, 1.2, 1.5)
box("WhRoofUnitB", "metal_green", -46, P, 8, 2, 1.2, 1.5)
box("WhCrateA", "wood", -34, 0, 10, 1.5, 1.2, 1.5, cover=True)
box("WhCrateB", "wood", -46, 0, -10, 1.5, 1.5, 1.5, cover=True)
box("WhCrateC", "wood", -45, 0, 10.5, 1.2, 1.2, 1.2, cover=True)
box("WhLowWall", "concrete", -33, 0, -11, 2, 1.1, 0.5, cover=True)
sniper(-29.3, P, 11)

# ---- Alley between the warehouse and the yard wall ----
box("AlleyLowWall", "concrete", -24, 0, 9, 0.5, 1.1, 3, cover=True)
box("AlleyCrate", "wood", -22, 0, -9, 1.5, 1.5, 1.5, cover=True)

# ---- South-west yard: a small shed and containers (close quarters) ----
S = 3.0
wall_z("ShedNorthA", "brick", 24, -56, -52.2, S)
wall_z("ShedNorthB", "brick", 24, -49.8, -46, S)
wall_z("ShedSouth", "brick", 34, -56, -46, S)
wall_x("ShedWest", "brick", -56, 24, 34, S)
wall_x("ShedEastA", "brick", -46, 24, 27.8, S)
wall_x("ShedEastB", "brick", -46, 30.2, 34, S)
box("ShedRoof", "roof", -51, S, 29, 10.4, 0.3, 10.4)
box("ShedCrate", "wood", -53.5, 0, 31.5, 1.5, 1.2, 1.5, cover=True)
box("SwContainerA", "metal_blue", -36, 0, 24, 2.4, 2.6, 6, cover=True)
box("SwContainerB", "metal_green", -33, 0, 31, 6, 2.6, 2.4, cover=True)
box("SwCrateA", "wood", -24, 0, 22, 1.5, 1.5, 1.5, cover=True)
box("SwCrateB", "wood", -27, 0, 37, 2, 1.2, 2, cover=True)
box("SwCrateC", "wood", -42, 0, 20, 1.5, 1.2, 1.5, cover=True)
box("SwCrateD", "wood", -41, 0, 37, 1.6, 1.6, 1.6, cover=True)
box("SwCrateE", "wood", -56, 0, 20, 1.2, 1.2, 1.2, cover=True)
box("SwLowWall", "concrete", -30, 0, 19, 4, 1.1, 0.5, cover=True)

# ---- North-west yard (its mirror is the south-east yard) ----
box("NwContainerA", "metal_red", -34, 0, -26, 6, 2.6, 2.4, cover=True)
box("NwContainerB", "metal_blue", -46, 0, -31, 2.4, 2.6, 6, cover=True)
box("NwCrateA", "wood", -40, 0, -37, 1.5, 1.5, 1.5, cover=True)
box("NwCrateB", "wood", -26, 0, -31, 1.6, 1.6, 1.6, cover=True)
box("NwCrateC", "wood", -55, 0, -24, 1.5, 1.2, 1.5, cover=True)
box("NwCrateD", "wood", -24, 0, -23, 2, 1.2, 2, cover=True)
box("NwLowWallA", "concrete", -52, 0, -38, 0.5, 1.1, 4, cover=True)
box("NwLowWallB", "concrete", -33, 0, -36, 4, 1.1, 0.5, cover=True)

# ---- Far west alley (behind the warehouse) ----
box("FarCrateA", "wood", -57, 0, 6, 1.5, 1.5, 1.5, cover=True)
box("FarCrateB", "wood", -58, 0, -8, 1.5, 1.5, 1.5, cover=True)

# ---- Objectives the bots roam between ----
hotspot(-12, 0, 6)
hotspot(9, 0, 20)
hotspot(0, 0, 21)
hotspot(-24, 0, 0)
hotspot(-34, 0, -3)
hotspot(-40, 0, 10)
hotspot(-41, 0, 28)
hotspot(-36, P, 4)
hotspot(-56, 0, 12)
hotspot(-22.5, 0, -29)


# ========================================================== VALIDATION
def footprint(b):
    (x, y, z), (sx, sy, sz) = b["c"], b["s"]
    return x - sx / 2, x + sx / 2, z - sz / 2, z + sz / 2, y - sy / 2, y + sy / 2


def blocked(x, z, margin=0.45, y_low=0.1, y_high=1.7):
    for b in boxes:
        if b["name"] == "Ground":
            continue
        x0, x1, z0, z1, y0, y1 = footprint(b)
        if y1 < y_low or y0 > y_high:
            continue
        if x0 - margin < x < x1 + margin and z0 - margin < z < z1 + margin:
            return True
    for r in ramps:
        ax, ay, az = r["a"]; bx, by, bz = r["b"]
        w = r["width"] / 2 + margin
        if min(ax, bx) - w < x < max(ax, bx) + w and min(az, bz) - w < z < max(az, bz) + w:
            return True
    return False


cover_points = []
for b in boxes:
    if not b["cover"]:
        continue
    x0, x1, z0, z1, y0, y1 = footprint(b)
    if abs(y0) > 0.01:
        continue
    cx, cz = b["c"][0], b["c"][2]
    for px, pz in ((x0 - 0.9, cz), (x1 + 0.9, cz), (cx, z0 - 0.9), (cx, z1 + 0.9)):
        if abs(px) < 58 and abs(pz) < 58 and not blocked(px, pz):
            cover_points.append((round(px, 2), 0.0, round(pz, 2)))

for team in (0, 1):
    for (x, y, z, yaw) in spawns[team]:
        assert not blocked(x, z), "spawn inside geometry: %s" % ((x, z),)
for (x, y, z) in hotspots:
    if y < 1:
        assert not blocked(x, z), "hotspot inside geometry: %s" % ((x, z),)


# ============================================================== OUTPUT
def fmt(v):
    s = "%.4f" % v
    s = s.rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def xform(basis_rows, origin):
    return "Transform3D(" + ", ".join(fmt(v) for v in list(basis_rows) + list(origin)) + ")"


IDENTITY = (1, 0, 0, 0, 1, 0, 0, 0, 1)


def ramp_transform(r):
    ax, ay, az = r["a"]; bx, by, bz = r["b"]
    f = (bx - ax, by - ay, bz - az)
    length = math.sqrt(sum(c * c for c in f))
    f = tuple(c / length for c in f)
    up = (0.0, 1.0, 0.0)
    rgt = (f[1] * up[2] - f[2] * up[1], f[2] * up[0] - f[0] * up[2], f[0] * up[1] - f[1] * up[0])
    n = math.sqrt(sum(c * c for c in rgt)); rgt = tuple(c / n for c in rgt)
    u = (rgt[1] * f[2] - rgt[2] * f[1], rgt[2] * f[0] - rgt[0] * f[2], rgt[0] * f[1] - rgt[1] * f[0])
    zax = (-f[0], -f[1], -f[2])
    thick = 0.3
    centre = tuple((a + b) / 2 - uu * thick / 2 for a, b, uu in zip(r["a"], r["b"], u))
    rows = (rgt[0], u[0], zax[0], rgt[1], u[1], zax[1], rgt[2], u[2], zax[2])
    return rows, centre, (r["width"], thick, length)


def write_scene():
    sizes = {}
    def size_id(s):
        key = tuple(round(v, 4) for v in s)
        if key not in sizes:
            sizes[key] = len(sizes)
        return sizes[key]

    nodes = []
    def add_body(name, kind, transform, size):
        sid = size_id(size)
        material, surface = KINDS[kind]
        nodes.append('[node name="%s" type="StaticBody3D" parent="Navigation"]\n'
                     'transform = %s\nmetadata/surface = "%s"\n' % (name, transform, surface))
        nodes.append('[node name="Mesh" type="MeshInstance3D" parent="Navigation/%s"]\n'
                     'mesh = SubResource("mesh_%d")\n'
                     'surface_material_override/0 = ExtResource("m_%s")\n' % (name, sid, material))
        nodes.append('[node name="Shape" type="CollisionShape3D" parent="Navigation/%s"]\n'
                     'shape = SubResource("shape_%d")\n' % (name, sid))

    used = {}
    def unique(name):
        used[name] = used.get(name, 0) + 1
        return name if used[name] == 1 else "%s%d" % (name, used[name])

    for b in boxes:
        add_body(unique(b["name"]), b["kind"], xform(IDENTITY, b["c"]), b["s"])
    for r in ramps:
        rows, centre, size = ramp_transform(r)
        add_body(unique(r["name"]), "ramp", xform(rows, centre), size)

    materials = sorted(set(m for m, _ in KINDS.values()))
    out = []
    load_steps = len(materials) + 2 * len(sizes) + 1
    out.append("[gd_scene load_steps=%d format=3]\n" % load_steps)
    for m in materials:
        out.append('[ext_resource type="Material" path="res://assets/materials/%s.tres" id="m_%s"]' % (m, m))
    out.append("")
    for key, sid in sizes.items():
        vec = "Vector3(%s, %s, %s)" % tuple(fmt(v) for v in key)
        out.append('[sub_resource type="BoxMesh" id="mesh_%d"]\nsize = %s\n' % (sid, vec))
        out.append('[sub_resource type="BoxShape3D" id="shape_%d"]\nsize = %s\n' % (sid, vec))
    out.append('[node name="Arena" type="Node3D"]\n')
    out.append('[node name="Navigation" type="NavigationRegion3D" parent="."]\n')
    out.extend(nodes)

    def packed(points):
        return "PackedVector3Array(" + ", ".join(fmt(v) for p in points for v in p) + ")"

    out.append('[node name="Markers" type="Node3D" parent="."]\n'
               'metadata/cover_points = %s\nmetadata/hotspots = %s\n'
               % (packed(cover_points), packed(hotspots)))
    for team in (0, 1):
        for i, (x, y, z, yaw) in enumerate(spawns[team]):
            c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
            rows = (c, 0, s, 0, 1, 0, -s, 0, c)
            out.append('[node name="Spawn%d_%d" type="Marker3D" parent="Markers" groups=["spawn_team_%d"]]\n'
                       'transform = %s\n' % (team, i, team, xform(rows, (x, y, z))))
        for i, p in enumerate(sniper_spots[team]):
            out.append('[node name="Sniper%d_%d" type="Marker3D" parent="Markers" groups=["sniper_spot_%d"]]\n'
                       'transform = %s\n' % (team, i, team, xform(IDENTITY, p)))
    os.makedirs(os.path.dirname(OUT_SCENE), exist_ok=True)
    with open(OUT_SCENE, "w", newline="\n") as fh:
        fh.write("\n".join(out))


def ascii_map(cell=2.0):
    n = int(120 / cell)
    grid = [["." for _ in range(n)] for _ in range(n)]
    def paint(x0, x1, z0, z1, ch):
        for iz in range(n):
            for ix in range(n):
                cx = -60 + (ix + 0.5) * cell; cz = -60 + (iz + 0.5) * cell
                if x0 - 0.01 <= cx <= x1 + 0.01 and z0 - 0.01 <= cz <= z1 + 0.01:
                    grid[iz][ix] = ch
    def mark(x, z, ch):
        ix = min(n - 1, max(0, int((x + 60) / cell))); iz = min(n - 1, max(0, int((z + 60) / cell)))
        grid[iz][ix] = ch
    order = {"roof": 0, "concrete": 1, "wood": 2, "metal_blue": 3, "metal_red": 3, "metal_green": 3,
             "brick": 4, "plaster": 4}
    for b in sorted(boxes, key=lambda b: order.get(b["kind"], 0)):
        if b["name"] in ("Ground",) or b["name"].startswith("Perimeter"):
            continue
        x0, x1, z0, z1, y0, y1 = footprint(b)
        k = b["kind"]
        # widen thin walls so they show up at 2 m per character
        if x1 - x0 < cell: x0, x1 = (x0 + x1) / 2 - cell / 2, (x0 + x1) / 2 + cell / 2
        if z1 - z0 < cell: z0, z1 = (z0 + z1) / 2 - cell / 2, (z0 + z1) / 2 + cell / 2
        ch = {"roof": "r", "concrete": "o", "wood": "c", "brick": "#", "plaster": "#"}.get(k, "C")
        if y0 > 3.4: continue
        paint(x0, x1, z0, z1, ch)
    for r in ramps:
        ax, _, az = r["a"]; bx, _, bz = r["b"]; w = r["width"] / 2
        paint(min(ax, bx) - (w if ax == bx else 0), max(ax, bx) + (w if ax == bx else 0),
              min(az, bz) - (w if az == bz else 0), max(az, bz) + (w if az == bz else 0), "/")
    for team in (0, 1):
        for (x, y, z, yaw) in spawns[team]: mark(x, z, "A" if team == 0 else "B")
        for (x, y, z) in sniper_spots[team]: mark(x, z, "S")
    return "\n".join("".join(row) for row in grid)


def write_doc():
    text = """# Arena map (gray-box)

Generated by `MapSource/gen_arena.py`. Do not edit this file by hand: change
the generator and run it again.

- Size: 120 x 120 m, walled. 1 character below = 2 x 2 m. North is up.
- Team B (index 1) spawns at the top (north), team A (index 0) at the bottom.
- The layout is point-symmetric (rotate 180 degrees and it is identical),
  so both teams get exactly the same map.

```
%s
```

Legend: `#` wall, `r` flat roof you can stand on (over a building),
`C` shipping container / truck (2.6 m, full cover), `c` wooden crate,
`o` concrete block, low wall or platform, `/` ramp, `A`/`B` spawn points,
`S` sniper spot, `.` open ground.

## Areas and dimensions

| Area | Position (x, z) | Size | Notes |
|---|---|---|---|
| Whole arena | -60..60, -60..60 | 120 x 120 m | 6 m perimeter wall |
| Spawn zone (each team) | -60..60, 42..60 | 120 x 18 m | 4 m wall with three 6 m exits (west, centre, east), a container behind each exit blocks the view in |
| Sniper nest (each team) | -4..4, 34..38 | 8 x 4 m, 1.2 m high | Ramps at both ends, 0.9 m parapet facing the lane |
| Sniper lane | -2.5..2.5, -34..34 | 5 x 68 m | The only long open sight line; nest to nest |
| Central yard | -20..20, -34..34 | 40 x 68 m | Crates, low walls, 2 containers and a truck per half; cover every 5-8 m |
| Yard / flank walls | x = -20 and x = 20 | 3.5 m high | Gaps at z 5..14 and 34..42 (and mirrored) link the yard to the flanks |
| Flank alley (each side) | -28..-20, -34..34 | 8 x 68 m | Between the warehouse and the yard wall |
| Warehouse (each side) | -52..-28, -16..16 | 24 x 32 m, 3.2 m ceiling | 3 rooms, 4 doors (2.4 m), 2 windows onto the alley |
| Warehouse roof | same footprint | 24 x 32 m at 3.5 m | 1 m parapet; reached by two outside ramps (west side and north side) |
| Far alley (each side) | -60..-52, -42..42 | 8 x 84 m | Behind the warehouse; hidden long flank |
| Shed (each team side) | -56..-46, 24..34 | 10 x 10 m, 3 m ceiling | 2 doors; shotgun range |
| Container yards | corners between spawn and warehouse | about 30 x 22 m | Containers and crates for SMG fights |

(Positions are for the west / south copy; the other copy is the same thing
rotated 180 degrees.)

## Routes between the spawns (3 lanes, each with branches)

1. **Centre**: centre exit, around the sniper nest, through the yard cover.
2. **West flank**: west exit, container yard, then the alley, through the
   warehouse, over its roof, or round the far alley behind it.
3. **East flank**: the same on the other side.

## Counts

- Boxes: %d, ramps: %d
- Spawn points: %d per team
- Cover points for bots: %d
- Bot objectives: %d
""" % (ascii_map(), len(boxes), len(ramps), len(spawns[0]), len(cover_points), len(hotspots))
    with open(OUT_DOC, "w", newline="\n") as fh:
        fh.write(text)


write_scene()
write_doc()
print("boxes", len(boxes), "ramps", len(ramps), "cover", len(cover_points),
      "spawns", len(spawns[0]), len(spawns[1]), "hotspots", len(hotspots))
