#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Генератор epic_combat.rbxlx — эпичная система боёвки для Roblox Studio.

Что внутри:
  * тёмная неоновая АРЕНА 260×260 с колоннами, арками, платформами, рампой,
    светящимися контурами и «бездной» по краям;
  * центральный БОЕВОЙ ПИЛОН, откуда падают бойцы;
  * 8 белых МАНЕКЕНОВ трёх типов (манекен / тяжёлый / титан) на постах;
  * ТАБЛО «ЛУЧШИЕ БОЙЦЫ АРЕНЫ» (урон, нокауты, комбо) — обновляется сервером;
  * стартовая площадка арены и белые тренировочные манекены на подиумах;
  * ReplicatedStorage с боевыми модулями и RemoteEvent'ами;
  * ServerScriptService: боёвка, VFX, манекены;
  * StarterPlayerScripts: клиент (HUD, камера, управление, аниматор).

Все Lua-исходники лежат отдельными файлами в tools/lua/ и вшиваются сюда.

Запуск:  python3 tools/generate_epic_combat.py
Открыть: File → Open from File… → epic_combat.rbxlx
"""

import math
import os
import random

RNG = random.Random(20260929)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_PATH = os.path.join(ROOT, "epic_combat.rbxlx")
LUA_DIR = os.path.join(HERE, "lua")


DUMMY_RADIUS = 42.0     # радиус круга, на котором стоят манекены (см. Config.Dummy)


def ConfigDummyRadius():
    return DUMMY_RADIUS


def read_lua(name):
    with open(os.path.join(LUA_DIR, name), "r", encoding="utf-8") as f:
        return f.read()


# ---------------------------------------------------------------------------
# ГЕОМЕТРИЯ АРЕНЫ
# ---------------------------------------------------------------------------
FLOOR_TOP = 0.0       # верх пола

# Материалы (Enum.Material) — значения сверены с документацией Roblox
M_PLASTIC = 256
M_SMOOTH = 272
M_NEON = 288
M_WOOD = 512
M_SLATE = 800
M_CONCRETE = 816
M_GRANITE = 832
M_PAVEMENT = 836
M_BRICK = 848
M_PEBBLE = 864
M_COBBLESTONE = 880
M_ROCK = 896
M_METAL = 1088
M_GRASS = 1280
M_LEAFY = 1284
M_SAND = 1296
M_FABRIC = 1312
M_ICE = 1536
M_GLASS = 1568
M_ASPHALT = 1376

SHAPE_BALL = 0
SHAPE_BLOCK = 1
SHAPE_CYLINDER = 2

# Цвета — спокойная природная палитра, никакого неона
C_GRASS = (92, 128, 62)
C_GRASS2 = (74, 108, 52)
C_DIRT = (124, 100, 70)
C_ASPHALT = (62, 62, 66)
C_ASPHALT2 = (80, 80, 84)
C_CONCRETE = (172, 170, 162)
C_CONCRETE2 = (146, 144, 138)
C_BRICK = (152, 84, 68)
C_BRICK2 = (126, 68, 54)
C_WALL = (216, 210, 196)
C_ROOF = (104, 82, 72)
C_ROOF2 = (74, 62, 60)
C_WOOD = (140, 102, 64)
C_WOOD2 = (104, 74, 46)
C_METAL = (132, 136, 142)
C_METAL2 = (92, 96, 102)
C_GLASS = (178, 208, 224)
C_TRUNK = (94, 70, 48)
C_LEAF = (72, 116, 54)
C_LEAF2 = (98, 144, 68)
C_SAND = (198, 180, 142)
C_ROCK = (126, 126, 128)
C_WHITE = (240, 240, 238)
C_RED = (168, 60, 52)
C_BLUE = (56, 88, 148)
C_YELLOW = (208, 172, 60)

# ---------------------------------------------------------------------------
# НИЗКОУРОВНЕВЫЙ RBXLX-БИЛДЕР
# ---------------------------------------------------------------------------


def esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if v == int(v) and abs(v) < 1e15:
        return str(int(v))
    return repr(round(float(v), 6))


class Builder(object):
    def __init__(self):
        self.counter = 0

    def referent(self):
        self.counter += 1
        return "RBX%032X" % self.counter


B = Builder()


def p_str(n, v):
    return '<string name="%s">%s</string>' % (n, esc(v))


def p_bool(n, v):
    return '<bool name="%s">%s</bool>' % (n, "true" if v else "false")


def p_float(n, v):
    return '<float name="%s">%s</float>' % (n, fmt(v))


def p_int(n, v):
    return '<int name="%s">%d</int>' % (n, int(v))


def p_token(n, v):
    return '<token name="%s">%d</token>' % (n, int(v))


def p_color3(n, rgb):
    r, g, b = (c / 255.0 for c in rgb)
    return ('<Color3 name="%s"><R>%s</R><G>%s</G><B>%s</B></Color3>'
            % (n, fmt(r), fmt(g), fmt(b)))


def p_color3uint8(n, rgb):
    r, g, b = rgb
    return '<Color3uint8 name="%s">%d</Color3uint8>' % (n, 0xFF000000 | (r << 16) | (g << 8) | b)


def p_v3(n, x, y, z):
    return '<Vector3 name="%s"><X>%s</X><Y>%s</Y><Z>%s</Z></Vector3>' % (n, fmt(x), fmt(y), fmt(z))


def p_v2(n, x, y):
    return '<Vector2 name="%s"><X>%s</X><Y>%s</Y></Vector2>' % (n, fmt(x), fmt(y))


def p_udim2(n, xs, xo, ys, yo):
    return '<UDim2 name="%s"><XS>%s</XS><XO>%d</XO><YS>%s</YS><YO>%d</YO></UDim2>' % (
        n, fmt(xs), int(xo), fmt(ys), int(yo))


def p_ref(n, r):
    return '<Ref name="%s">%s</Ref>' % (n, r)


def p_cframe(n, pos, mat):
    x, y, z = pos
    return ('<CoordinateFrame name="%s">'
            '<X>%s</X><Y>%s</Y><Z>%s</Z>'
            '<R00>%s</R00><R01>%s</R01><R02>%s</R02>'
            '<R10>%s</R10><R11>%s</R11><R12>%s</R12>'
            '<R20>%s</R20><R21>%s</R21><R22>%s</R22>'
            '</CoordinateFrame>' % (n, fmt(x), fmt(y), fmt(z),
                                    fmt(mat[0]), fmt(mat[1]), fmt(mat[2]),
                                    fmt(mat[3]), fmt(mat[4]), fmt(mat[5]),
                                    fmt(mat[6]), fmt(mat[7]), fmt(mat[8])))


def p_protected(n, source):
    assert "]]>" not in source, "исходник содержит ]]>"
    return '<ProtectedString name="%s"><![CDATA[%s]]></ProtectedString>' % (n, source)


def mat_id():
    return (1, 0, 0, 0, 1, 0, 0, 0, 1)


def mat_from_ru(right, up):
    rx, ry, rz = right
    ux, uy, uz = up
    bx = ry * uz - rz * uy
    by = rz * ux - rx * uz
    bz = rx * uy - ry * ux
    return (rx, ux, bx, ry, uy, by, rz, uz, bz)


def mat_rotx(a):
    c, s = math.cos(a), math.sin(a)
    return mat_from_ru((1, 0, 0), (0, c, s))


def mat_roty(a):
    c, s = math.cos(a), math.sin(a)
    return mat_from_ru((c, 0, -s), (0, 1, 0))


def mat_rotz(a):
    c, s = math.cos(a), math.sin(a)
    return mat_from_ru((c, s, 0), (-s, c, 0))


def _norm(v):
    l = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2) or 1.0
    return (v[0] / l, v[1] / l, v[2] / l)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def mat_look(look):
    look = _norm(look)
    back = (-look[0], -look[1], -look[2])
    up = (0, 1, 0)
    if abs(look[0]) < 1e-6 and abs(look[1]) > 0.99:
        up = (1, 0, 0)
    right = _norm(_cross(up, back))
    up = _cross(back, right)
    return mat_from_ru(right, up)


def item(class_name, props, children=()):
    return (class_name, B.referent(), list(props), list(children))


def emit(it, indent=0):
    cls, ref, props, children = it
    pad = "\t" * indent
    out = [pad + '<Item class="%s" referent="%s">' % (cls, ref),
           pad + "\t<Properties>"]
    for p in props:
        out.append(pad + "\t\t" + p)
    out.append(pad + "\t</Properties>")
    for ch in children:
        out.extend(emit(ch, indent + 1))
    out.append(pad + "</Item>")
    return out


def part_props(name, size, pos, rgb, mat=M_SMOOTH, transparency=0.0, reflectance=0.0,
               rotation=None, shape=None, cancollide=True, castshadow=True, anchored=True):
    props = [
        p_str("Name", name),
        p_bool("Anchored", anchored),
        p_bool("CanCollide", cancollide),
        p_bool("CanQuery", cancollide),
        p_bool("CanTouch", cancollide),
        p_bool("CastShadow", castshadow),
        p_color3uint8("Color3uint8", rgb),
        p_cframe("CFrame", pos, rotation if rotation is not None else mat_id()),
        p_token("Material", mat),
        p_float("Reflectance", reflectance),
        p_token("TopSurface", 0),
        p_token("BottomSurface", 0),
        p_float("Transparency", transparency),
        p_v3("size", *size),
    ]
    if shape is not None:
        props.append(p_token("shape", shape))
    return props


def add_part(p, name, size, pos, rgb, **kw):
    p[3].append(item("Part", part_props(name, size, pos, rgb, **kw)))


def add_part_rot(p, name, size, pos, rgb, rot, **kw):
    kw["rotation"] = rot
    p[3].append(item("Part", part_props(name, size, pos, rgb, **kw)))


def add_part_shape(p, name, size, pos, rgb, shape, **kw):
    kw["shape"] = shape
    p[3].append(item("Part", part_props(name, size, pos, rgb, **kw)))


def add_light(p, name, rgb, br, rng, shadows=False):
    p[3].append(item("PointLight", [
        p_str("Name", name), p_float("Brightness", br),
        p_color3("Color", rgb), p_bool("Enabled", True),
        p_float("Range", rng), p_bool("Shadows", shadows)]))


def add_label(parent, name, text, font, pos, size, color,
              xalign=0, transparency=1.0, stroke=0.4, wrap=False):
    """TextLabel внутри SurfaceGui: pos/size — четвёрки (scale, offset, scale, offset)."""
    parent[3].append(item("TextLabel", [
        p_str("Name", name),
        p_str("Text", text),
        p_token("Font", font),
        p_bool("TextScaled", True),
        p_bool("TextWrapped", wrap),
        p_color3("TextColor3", color),
        p_float("TextStrokeTransparency", stroke),
        p_color3("BackgroundColor3", (10, 12, 20)),
        p_float("BackgroundTransparency", transparency),
        p_token("TextXAlignment", xalign),
        p_token("TextYAlignment", 1),
        p_udim2("Position", pos[0], pos[1], pos[2], pos[3]),
        p_udim2("Size", size[0], size[1], size[2], size[3]),
    ]))


# ---------------------------------------------------------------------------
# ОСВЕЩЕНИЕ: обычный солнечный день
# ---------------------------------------------------------------------------

def build_lighting(root_children):
    lighting = item("Lighting", [
        p_str("Name", "Lighting"),
        p_color3("Ambient", (88, 92, 98)),
        p_color3("OutdoorAmbient", (130, 134, 130)),
        p_float("Brightness", 2.6),
        p_float("ClockTime", 14.5),
        p_float("GeographicLatitude", 24),
        p_float("ExposureCompensation", 0.05),
        p_float("EnvironmentDiffuseScale", 0.4),
        p_float("EnvironmentSpecularScale", 0.6),
        p_color3("FogColor", (182, 198, 212)),
        p_float("FogStart", 340),
        p_float("FogEnd", 1800),
        p_bool("GlobalShadows", True),
        p_float("ShadowSoftness", 0.35),
    ])
    lighting[3].append(item("Atmosphere", [
        p_str("Name", "Atmosphere"),
        p_color3("Color", (198, 210, 220)),
        p_color3("Decay", (150, 165, 180)),
        p_float("Density", 0.22),
        p_float("Glare", 0.12),
        p_float("Haze", 0.6),
        p_float("Offset", 0.0),
    ]))
    root_children.append(lighting)


# ---------------------------------------------------------------------------
# КАРТА: зелёная локация — плац, дороги, дома, заборы, деревья
# ---------------------------------------------------------------------------
WORLD = 420.0     # размер карты
PLAZA = 52.0      # половина стороны бетонного плаца
GATE = 16.0       # ширина прохода в заборе


def l2w(cx, cz, rot, lx, lz):
    """локальные координаты относительно центра здания → мировые"""
    c, sn = math.cos(rot), math.sin(rot)
    return (cx + lx * c + lz * sn, cz - lx * sn + lz * c)


def cyl(parent, name, height, dia, pos, rgb, mat=M_WOOD, **kw):
    """вертикальный цилиндр"""
    add_part_rot(parent, name, (height, dia, dia), pos, rgb, mat_rotz(math.pi / 2),
                 mat=mat, shape=SHAPE_CYLINDER, **kw)


def disc(parent, name, thick, dia, pos, rgb, mat=M_CONCRETE, **kw):
    """плоский диск, лежит на земле"""
    add_part_rot(parent, name, (thick, dia, dia), pos, rgb, mat_rotz(math.pi / 2),
                 mat=mat, shape=SHAPE_CYLINDER, **kw)


def fence_line(parent, name, x1, z1, x2, z2, h=3.4, seg=8.0, rgb=C_WOOD, mat=M_WOOD):
    dx, dz = x2 - x1, z2 - z1
    length = math.hypot(dx, dz)
    if length < 1.0:
        return
    n = max(1, int(round(length / seg)))
    ang = math.atan2(dx, dz)
    for i in range(n + 1):
        t = i / n
        add_part(parent, "%s_P%d" % (name, i), (0.8, h, 0.8),
                 (x1 + dx * t, FLOOR_TOP + h / 2, z1 + dz * t), C_WOOD2, mat=M_WOOD)
    for k, frac in enumerate((0.52, 0.86)):
        add_part_rot(parent, "%s_R%d" % (name, k), (0.5, 0.6, length),
                     ((x1 + x2) / 2, FLOOR_TOP + h * frac, (z1 + z2) / 2), rgb, mat_roty(ang), mat=mat)


def tree(parent, idx, x, z, h=16.0, spread=5.6):
    trunk_h = h * 0.46
    cyl(parent, "Tree%d_Trunk" % idx, trunk_h, 1.8, (x, FLOOR_TOP + trunk_h / 2, z), C_TRUNK, mat=M_WOOD)
    top = FLOOR_TOP + trunk_h
    blobs = (
        (0.0, 0.0, h * 0.28, spread),
        (-spread * 0.5, spread * 0.28, h * 0.16, spread * 0.78),
        (spread * 0.55, -spread * 0.3, h * 0.2, spread * 0.72),
        (spread * 0.1, spread * 0.55, h * 0.36, spread * 0.6),
    )
    for i, (ox, oz, oy, r) in enumerate(blobs):
        col = C_LEAF if i % 2 == 0 else C_LEAF2
        add_part_shape(parent, "Tree%d_Leaf%d" % (idx, i), (r * 2, r * 1.7, r * 2),
                       (x + ox, top + oy, z + oz), col, SHAPE_BALL, mat=M_LEAFY)


def rock(parent, idx, x, z, size=7.0, rot=0.0):
    add_part_rot(parent, "Rock%d_A" % idx, (size, size * 0.7, size * 0.85),
                 (x, FLOOR_TOP + size * 0.28, z), C_ROCK, mat_roty(rot), mat=M_ROCK)
    add_part_rot(parent, "Rock%d_B" % idx, (size * 0.6, size * 0.45, size * 0.55),
                 (x + size * 0.5, FLOOR_TOP + size * 0.18, z + size * 0.42), C_ROCK,
                 mat_roty(rot + 0.8), mat=M_SLATE)


def house(parent, name, cx, cz, w, d, h, rot=0.0, wall=C_WALL, wall_mat=M_BRICK,
          roof=C_ROOF, roof_mat=M_SLATE, door_side=1, windows=2, chimney=False):
    add_part_rot(parent, name + "_Plinth", (w + 1.4, 1.6, d + 1.4), (cx, FLOOR_TOP + 0.8, cz),
                 C_CONCRETE2, mat_roty(rot), mat=M_CONCRETE)
    add_part_rot(parent, name + "_Walls", (w, h, d), (cx, FLOOR_TOP + h / 2, cz),
                 wall, mat_roty(rot), mat=wall_mat)
    add_part_rot(parent, name + "_Roof", (w + 2.6, 1.5, d + 2.6), (cx, FLOOR_TOP + h + 0.75, cz),
                 roof, mat_roty(rot), mat=roof_mat)
    add_part_rot(parent, name + "_RoofTrim", (w + 3.2, 0.5, d + 3.2), (cx, FLOOR_TOP + h + 1.6, cz),
                 C_ROOF2, mat_roty(rot), mat=M_SLATE)
    if chimney:
        x, z = l2w(cx, cz, rot, w * 0.32, -d * 0.3)
        add_part_rot(parent, name + "_Chimney", (2.4, h * 0.55, 2.4),
                     (x, FLOOR_TOP + h + h * 0.22, z), C_BRICK2, mat_roty(rot), mat=M_BRICK)
    # окна на длинных стенах
    count = max(2, int((w - 4) // 5.0))
    for r in range(max(1, windows)):
        wy = FLOOR_TOP + 3.6 + r * 4.8
        if wy > h - 1.8:
            break
        for i in range(count):
            lx = -w / 2 + 3.0 + i * ((w - 6.0) / max(1, count - 1))
            for sgn in (-1, 1):
                x, z = l2w(cx, cz, rot, lx, sgn * (d / 2 + 0.1))
                add_part_rot(parent, "%s_Win%d_%d_%d" % (name, r, i, sgn), (2.9, 3.1, 0.35),
                             (x, wy, z), C_GLASS, mat_roty(rot), mat=M_GLASS,
                             transparency=0.42, cancollide=False, castshadow=False)
    # дверь на торце
    x, z = l2w(cx, cz, rot, door_side * (w / 2 + 0.08), 0)
    add_part_rot(parent, name + "_DoorFrame", (0.3, 7.6, 5.4), (x, FLOOR_TOP + 3.8, z),
                 C_CONCRETE2, mat_roty(rot), mat=M_CONCRETE)
    x, z = l2w(cx, cz, rot, door_side * (w / 2 + 0.22), 0)
    add_part_rot(parent, name + "_Door", (0.35, 6.6, 4.2), (x, FLOOR_TOP + 3.3, z),
                 C_WOOD, mat_roty(rot), mat=M_WOOD, cancollide=False)


def crate(parent, name, x, z, y=0.0, size=4.0, rot=0.0):
    add_part_rot(parent, name, (size, size, size), (x, FLOOR_TOP + y + size / 2, z),
                 C_WOOD, mat_roty(rot), mat=M_WOOD)
    for sgn in (-1, 1):
        add_part_rot(parent, name + "_Band%d" % sgn, (size * 1.02, size * 0.16, size * 0.16),
                     (x, FLOOR_TOP + y + size * (0.5 + sgn * 0.22), z),
                     C_WOOD2, mat_roty(rot), mat=M_WOOD, cancollide=False, castshadow=False)


def container(parent, name, x, z, rot=0.0, rgb=C_RED):
    add_part_rot(parent, name, (24, 9.4, 9.6), (x, FLOOR_TOP + 4.7, z), rgb, mat_roty(rot), mat=M_METAL)
    for i in range(1, 8):
        add_part_rot(parent, "%s_Rib%d" % (name, i), (24.2, 0.4, 9.8),
                     l2w(x, z, rot, 0, 0)[0:1] and (l2w(x, z, rot, (i - 4) * 3.0, 0)[0], FLOOR_TOP + 4.7,
                                                   l2w(x, z, rot, (i - 4) * 3.0, 0)[1]),
                     rgb, mat_roty(rot), mat=M_METAL, transparency=0.25,
                     cancollide=False, castshadow=False)


def barrel(parent, name, x, z, tipped=False):
    if tipped:
        add_part_rot(parent, name, (3.6, 3.0, 3.0), (x, FLOOR_TOP + 1.5, z),
                     C_BLUE, mat_rotz(math.pi / 2), mat=M_METAL, shape=SHAPE_CYLINDER)
    else:
        cyl(parent, name, 3.8, 3.0, (x, FLOOR_TOP + 1.9, z), C_BLUE, mat=M_METAL)


def lamp(parent, name, x, z):
    cyl(parent, name + "_Pole", 14.0, 0.7, (x, FLOOR_TOP + 7.0, z), C_METAL2, mat=M_METAL)
    add_part(parent, name + "_Head", (3.4, 0.8, 1.6), (x, FLOOR_TOP + 13.6, z), C_METAL, mat=M_METAL,
             cancollide=False)
    bulb = item("Part", part_props(name + "_Bulb", (3.0, 0.35, 1.3), (x, FLOOR_TOP + 13.15, z),
                                   C_WHITE, mat=M_GLASS, transparency=0.25,
                                   cancollide=False, castshadow=False))
    bulb[3].append(item("PointLight", [
        p_str("Name", "LampLight"), p_float("Brightness", 1.6),
        p_color3("Color", (255, 244, 214)), p_bool("Enabled", True),
        p_float("Range", 34), p_bool("Shadows", False)]))
    parent[3].append(bulb)


def tyre_stack(parent, name, x, z, n=5):
    for i in range(n):
        disc(parent, "%s_%d" % (name, i), 1.1, 4.2, (x, FLOOR_TOP + 0.55 + i * 1.1, z),
             (28, 28, 30), mat=M_SMOOTH, transparency=0.05)


# ---------------------------------------------------------------------------
# СБОРКА КАРТЫ
# ---------------------------------------------------------------------------

def build_arena(ws):
    mapm = item("Model", [p_str("Name", "Arena")])
    rnd = random.Random(20260930)

    # --- земля -------------------------------------------------------------
    add_part(mapm, "Ground", (WORLD, 60, WORLD), (0, FLOOR_TOP - 30, 0), C_GRASS, mat=M_GRASS)
    # холмы по краям — просто широкие приподнятые плиты травы
    for i, (x, z, w, d, h) in enumerate((
        (-170, -150, 80, 90, 5.0), (150, 160, 96, 70, 4.2),
        (175, -120, 70, 80, 3.6), (-150, 165, 84, 66, 4.6),
    )):
        add_part(mapm, "Hill%d" % i, (w, h * 2, d), (x, FLOOR_TOP + h / 2 - h, z),
                 C_GRASS2, mat=M_GRASS)

    # --- дороги от плаца к краям карты -------------------------------------
    road_len = WORLD / 2 - PLAZA
    for i, (dx, dz) in enumerate(((0, -1), (0, 1), (-1, 0), (1, 0))):
        rot = 0.0 if dx == 0 else math.pi / 2
        cx = dx * (PLAZA + road_len / 2)
        cz = dz * (PLAZA + road_len / 2)
        add_part_rot(mapm, "Road%d" % i, (24, 0.5, road_len), (cx, FLOOR_TOP - 0.2, cz),
                     C_ASPHALT, mat_roty(rot), mat=M_ASPHALT)
        # разметка по центру
        add_part_rot(mapm, "RoadLine%d" % i, (0.7, 0.2, road_len - 8), (cx, FLOOR_TOP + 0.06, cz),
                     C_WHITE, mat_roty(rot), mat=M_SMOOTH, cancollide=False, castshadow=False,
                     transparency=0.25)
        # бордюры
        for sgn in (-1, 1):
            ox, oz = l2w(cx, cz, rot, sgn * 13.4, 0)
            add_part_rot(mapm, "Curb%d_%d" % (i, sgn), (1.6, 0.9, road_len),
                         (ox, FLOOR_TOP + 0.1, oz), C_CONCRETE, mat_roty(rot), mat=M_CONCRETE)

    # --- бетонный плац -----------------------------------------------------
    add_part(mapm, "Plaza", (PLAZA * 2, 0.6, PLAZA * 2), (0, FLOOR_TOP - 0.3, 0),
             C_CONCRETE, mat=M_CONCRETE)
    disc(mapm, "PlazaCircle", 0.12, 92.0, (0, FLOOR_TOP + 0.07, 0), C_ASPHALT2,
         mat=M_ASPHALT, cancollide=False, castshadow=False)
    disc(mapm, "PlazaRing", 0.16, 96.0, (0, FLOOR_TOP + 0.04, 0), C_CONCRETE2,
         mat=M_CONCRETE, cancollide=False, castshadow=False)

    # --- спавн -------------------------------------------------------------
    spawn = item("SpawnLocation", part_props("ArenaSpawn", (18, 0.6, 18), (0, FLOOR_TOP + 0.3, 0),
                                             C_CONCRETE2, mat=M_CONCRETE, cancollide=True))
    spawn[3].append(item("Part", part_props("SpawnRing", (0.16, 22, 22), (0, FLOOR_TOP + 0.62, 0),
                                            C_YELLOW, mat=M_SMOOTH, cancollide=False,
                                            castshadow=False, transparency=0.35,
                                            shape=SHAPE_CYLINDER)))
    mapm[3].append(spawn)

    # --- забор вокруг плаца с четырьмя проходами ---------------------------
    sides = (
        (-PLAZA, -PLAZA, PLAZA, -PLAZA),
        (PLAZA, -PLAZA, PLAZA, PLAZA),
        (PLAZA, PLAZA, -PLAZA, PLAZA),
        (-PLAZA, PLAZA, -PLAZA, -PLAZA),
    )
    for i, (x1, z1, x2, z2) in enumerate(sides):
        mx, mz = (x1 + x2) / 2, (z1 + z2) / 2
        # две половины стороны, посередине — проход
        hx = (GATE / 2) * (1 if abs(x2 - x1) > 0.1 else 0)
        hz = (GATE / 2) * (1 if abs(z2 - z1) > 0.1 else 0)
        fence_line(mapm, "Fence%d_A" % i, x1, z1, mx - hx, mz - hz)
        fence_line(mapm, "Fence%d_B" % i, mx + hx, mz + hz, x2, z2)
        # столбы у прохода
        for sgn in (-1, 1):
            add_part(mapm, "GatePost%d_%d" % (i, sgn), (1.6, 6.4, 1.6),
                     (mx + hx * sgn, FLOOR_TOP + 3.2, mz + hz * sgn), C_CONCRETE2, mat=M_CONCRETE)

    # --- подиумы белых манекенов (совпадают с Config.Dummy) ----------------
    pads = item("Folder", [p_str("Name", "DummyPads")])
    dummy_count = 8
    for i in range(dummy_count):
        a = i / dummy_count * math.pi * 2
        x, z = math.sin(a) * ConfigDummyRadius(), math.cos(a) * ConfigDummyRadius()
        disc(pads, "DummyPad%d" % (i + 1), 0.18, 7.8, (x, FLOOR_TOP + 0.1, z),
             C_ASPHALT2, mat=M_ASPHALT, cancollide=False, castshadow=False)
        disc(pads, "DummyRing%d" % (i + 1), 0.2, 8.8, (x, FLOOR_TOP + 0.03, z),
             C_CONCRETE2, mat=M_CONCRETE, cancollide=False, castshadow=False)
    mapm[3].append(pads)

    # ---тренировочные щиты и столб ----------------------------------------
    for i, ang in enumerate((-0.6, 0.4, 2.4)):
        x = math.sin(ang) * 30.0
        z = math.cos(ang) * 30.0
        rot = ang
        add_part_rot(mapm, "ShieldWall%d" % i, (10, 8, 1.0), (x, FLOOR_TOP + 4, z),
                     C_WOOD, mat_roty(rot), mat=M_WOOD)
        for k in (-1, 1):
            px, pz = l2w(x, z, rot, k * 4.2, 0.9)
            add_part_rot(mapm, "ShieldPost%d_%d" % (i, k), (1.0, 9.0, 1.0),
                         (px, FLOOR_TOP + 4.5, pz), C_WOOD2, mat_roty(rot), mat=M_WOOD)
        disc(mapm, "ShieldPad%d" % i, 0.16, 12.0, (x, FLOOR_TOP + 0.08, z), C_SAND,
             mat=M_SAND, cancollide=False, castshadow=False)
    # столб для отработки ударов
    cyl(mapm, "TrainPole", 12.0, 1.6, (26, FLOOR_TOP + 6, -26), C_METAL, mat=M_METAL)
    disc(mapm, "TrainPolePad", 0.16, 9.0, (26, FLOOR_TOP + 0.08, -26), C_SAND, mat=M_SAND,
         cancollide=False, castshadow=False)
    tyre_stack(mapm, "TyreStack", -24, -28, 5)
    tyre_stack(mapm, "TyreStack2", -27, -31, 3)

    # --- здания в четырёх квадрантах ---------------------------------------
    houses = (
        # (x, z, w, d, h, rot, стена, крыша, окна, труба)
        (-96, -96, 46, 32, 17, math.pi / 4, C_BRICK, C_ROOF, 2, True),
        (96, -96, 40, 30, 14, -math.pi / 4, C_WALL, C_ROOF2, 2, False),
        (96, 96, 46, 32, 17, math.pi * 0.75, C_BRICK2, C_ROOF, 2, True),
        (-96, 96, 40, 30, 14, -math.pi * 0.75, C_WALL, C_ROOF2, 2, False),
        (-150, -52, 22, 18, 11, 0.35, C_WALL, C_ROOF, 1, True),
        (150, 54, 22, 18, 11, -0.3, C_BRICK, C_ROOF2, 1, False),
        (-52, 150, 24, 18, 12, math.pi / 2 + 0.25, C_BRICK2, C_ROOF, 1, True),
        (54, -150, 24, 18, 12, -math.pi / 2 - 0.2, C_WALL, C_ROOF2, 1, False),
    )
    for i, (x, z, w, d, h, rot, wall, roof, wins, chim) in enumerate(houses):
        house(mapm, "House%d" % i, x, z, w, d, h, rot=rot, wall=wall, roof=roof,
              windows=wins, chimney=chim)

    # --- складские контейнеры, ящики, бочки --------------------------------
    for i, (x, z, rot, rgb) in enumerate((
        (-120, -66, 0.3, C_RED), (-120, -78, 0.3, C_BLUE), (-108, -72, 0.3, C_YELLOW),
        (120, 66, -0.4, C_BLUE), (120, 78, -0.4, C_RED),
        (72, -122, 0.1, C_YELLOW), (-72, 122, 0.05, C_BLUE),
    )):
        container(mapm, "Container%d" % i, x, z, rot=rot, rgb=rgb)
    for i, (x, z) in enumerate(((-70, -40), (-64, -44), (-70, -44), (64, 42), (70, 46))):
        crate(mapm, "Crate%d" % i, x, z, y=0.0, size=4.2, rot=rnd.uniform(0, 1.5))
    for i, (x, z, tip) in enumerate(((-58, -34, False), (-55, -37, True), (58, 36, False),
                                     (61, 40, True), (-34, 58, False), (36, -58, True))):
        barrel(mapm, "Barrel%d" % i, x, z, tipped=tip)

    # --- фонари вдоль дорог ------------------------------------------------
    for i, (x, z) in enumerate(((30, -70), (30, -120), (-30, -70), (-30, -120),
                                (70, 30), (120, 30), (70, -30), (120, -30))):
        lamp(mapm, "Lamp%d" % i, x, z)

    # --- деревья и камни по всей карте -------------------------------------
    keep = [(-96, -96, 34), (96, -96, 32), (96, 96, 34), (-96, 96, 32),
            (-150, -52, 20), (150, 54, 20), (-52, 150, 20), (54, -150, 20)]
    placed = 0
    tries = 0
    while placed < 30 and tries < 600:
        tries += 1
        x = rnd.uniform(-WORLD / 2 + 16, WORLD / 2 - 16)
        z = rnd.uniform(-WORLD / 2 + 16, WORLD / 2 - 16)
        if max(abs(x), abs(z)) < PLAZA + 12:
            continue
        if abs(x) < 20 or abs(z) < 20:      # не сажаем на дороги
            continue
        if any((x - hx) ** 2 + (z - hz) ** 2 < (hr + 16) ** 2 for hx, hz, hr in keep):
            continue
        tree(mapm, placed, x, z, h=rnd.uniform(13.0, 19.0), spread=rnd.uniform(4.6, 6.4))
        placed += 1
    for i in range(16):
        x = rnd.uniform(-WORLD / 2 + 14, WORLD / 2 - 14)
        z = rnd.uniform(-WORLD / 2 + 14, WORLD / 2 - 14)
        if max(abs(x), abs(z)) < PLAZA + 8 or abs(x) < 18 or abs(z) < 18:
            continue
        rock(mapm, i, x, z, size=rnd.uniform(4.5, 9.5), rot=rnd.uniform(0, 3.0))

    # --- наблюдательная вышка ----------------------------------------------
    tw = item("Model", [p_str("Name", "Watchtower")])
    tx, tz = -66, -118
    for sx in (-4, 4):
        for sz in (-4, 4):
            add_part(tw, "Leg%d_%d" % (sx, sz), (1.2, 22, 1.2), (tx + sx, FLOOR_TOP + 11, tz + sz),
                     C_WOOD2, mat=M_WOOD)
    add_part(tw, "Deck", (13, 1.0, 13), (tx, FLOOR_TOP + 22.5, tz), C_WOOD, mat=M_WOOD)
    for sx in (-6.6, 6.6):
        add_part(tw, "RailingX%s" % sx, (0.6, 3.2, 14), (tx + sx, FLOOR_TOP + 24.6, tz),
                 C_WOOD, mat=M_WOOD, cancollide=False)
    for sz in (-6.6, 6.6):
        add_part(tw, "RailingZ%s" % sz, (14, 3.2, 0.6), (tx, FLOOR_TOP + 24.6, tz + sz),
                 C_WOOD, mat=M_WOOD, cancollide=False)
    add_part(tw, "Roof", (14, 0.8, 14), (tx, FLOOR_TOP + 29.5, tz), C_ROOF2, mat=M_SLATE)
    for sx in (-6, 6):
        for sz in (-6, 6):
            add_part(tw, "RoofPost%d_%d" % (sx, sz), (0.7, 5.4, 0.7),
                     (tx + sx, FLOOR_TOP + 26.8, tz + sz), C_WOOD2, mat=M_WOOD)
    mapm[3].append(tw)

    # --- табло -------------------------------------------------------------
    sb = item("Model", [p_str("Name", "Scoreboard")])
    sbx, sbz = 0.0, PLAZA + 12.0
    for sgn in (-1, 1):
        add_part(sb, "Post%d" % sgn, (2.2, 26, 2.2), (sbx + sgn * 13, FLOOR_TOP + 13, sbz),
                 C_WOOD2, mat=M_WOOD)
    add_part(sb, "Backboard", (32, 22, 1.2), (sbx, FLOOR_TOP + 24, sbz), C_ROOF2, mat=M_WOOD)
    board = item("Part", part_props("Scoreboard", (0.6, 17, 30), (sbx, FLOOR_TOP + 24, sbz - 0.9),
                                    (28, 30, 36), mat=M_SMOOTH, rotation=mat_look((0, 0, -1))))
    gui = item("SurfaceGui", [
        p_str("Name", "BoardGui"),
        p_token("Face", 5),
        p_bool("AlwaysOnTop", True),
        p_bool("LightInfluence", False),
        p_v2("CanvasSize", 400, 240),
    ])
    add_label(gui, "Title", "ЛУЧШИЕ БОЙЦЫ ПОЛИГОНА", 19,
              (0.0, 0, 0.0, 0), (1.0, 0, 0.12, 0), C_YELLOW, xalign=1)
    for i in range(8):
        add_label(gui, "Row%d" % (i + 1), "%d. —" % (i + 1), 18,
                  (0.05, 0, 0.14 + i * 0.098, 0), (0.9, 0, 0.085, 0),
                  C_WHITE, xalign=0)
    add_label(gui, "Foot", "ЛКМ — комбо · F — пинок · R — лазер · X — ульта · V — полёт", 16,
              (0.0, 0, 0.92, 0), (1.0, 0, 0.07, 0), C_WHITE, xalign=1)
    board[3].append(gui)
    sb[3].append(board)
    mapm[3].append(sb)

    # --- декор: облака и ветряк (их оживляет клиент) -----------------------
    decor = item("Folder", [p_str("Name", "Decor")])
    for i, (x, y, z, s) in enumerate(((-120, 96, -80, 26), (140, 108, 40, 34),
                                      (-40, 118, 150, 30), (60, 102, -160, 24))):
        add_part(decor, "Bob_Cloud%d" % i, (s, s * 0.4, s * 0.7), (x, y, z), C_WHITE,
                 mat=M_FABRIC, transparency=0.35, cancollide=False, castshadow=False)
        add_part(decor, "Bob_Cloud%d_puff" % i, (s * 0.6, s * 0.35, s * 0.5),
                 (x + s * 0.35, y + s * 0.1, z - s * 0.2), C_WHITE,
                 mat=M_FABRIC, transparency=0.4, cancollide=False, castshadow=False)
    # радиолокатор на вышке: одна длинная деталь, вращается вокруг оси Y —
    # как раз то, что умеет оживлять клиент
    wx, wz = 150.0, -150.0
    cyl(decor, "RadarTower", 24.0, 2.4, (wx, FLOOR_TOP + 12, wz), C_METAL2, mat=M_METAL)
    add_part(decor, "RadarDeck", (10, 0.8, 10), (wx, FLOOR_TOP + 24.4, wz), C_METAL, mat=M_METAL)
    add_part(decor, "Spin_RadarHub", (2.2, 2.2, 2.2), (wx, FLOOR_TOP + 27.6, wz), C_METAL,
             mat=M_METAL, shape=SHAPE_BALL, cancollide=False, castshadow=False)
    add_part(decor, "Spin_RadarBar", (18, 0.5, 2.6), (wx, FLOOR_TOP + 27.6, wz), C_WHITE,
             mat=M_SMOOTH, cancollide=False, castshadow=False)
    add_part(decor, "RadarBlip", (3.0, 0.6, 2.2), (wx + 7.4, FLOOR_TOP + 27.9, wz), C_RED,
             mat=M_SMOOTH, cancollide=False, castshadow=False)
    ws[3].append(mapm)


# ---------------------------------------------------------------------------
# СКРИПТЫ
# ---------------------------------------------------------------------------

def build_scripts(root_children, ws):
    # ReplicatedStorage: общие модули + клиентские модули + ремоуты
    rs = item("ReplicatedStorage", [p_str("Name", "ReplicatedStorage")])
    modules = [
        ("CombatConfig", "config.lua"),
        ("CombatPose", "pose.lua"),
        ("CombatActions", "actions.lua"),
        ("CombatAnimator", "animator.lua"),
        ("CombatHud", "hud.lua"),
        ("CombatCamera", "camera.lua"),
        ("CombatFloat", "floatnumbers.lua"),
        ("CombatInput", "input.lua"),
    ]
    for name, path in modules:
        rs[3].append(item("ModuleScript", [
            p_str("Name", name),
            p_protected("Source", read_lua(path)),
        ]))

    remotes = item("Folder", [p_str("Name", "CombatRemotes")])
    for rname in ("Attack", "Action", "Feedback", "Hurt", "Ult", "Sfx", "Ack"):
        remotes[3].append(item("RemoteEvent", [p_str("Name", rname)]))
    rs[3].append(remotes)

    # ServerScriptService: серверные скрипты
    sss = item("ServerScriptService", [p_str("Name", "ServerScriptService")])
    sss[3].append(item("ModuleScript", [
        p_str("Name", "CombatVfx"),
        p_protected("Source", read_lua("vfx.lua")),
    ]))
    sss[3].append(item("ModuleScript", [
        p_str("Name", "CombatDummies"),
        p_protected("Source", read_lua("dummies.lua")),
    ]))
    sss[3].append(item("Script", [
        p_str("Name", "CombatServer"),
        p_protected("Source", read_lua("servermain.lua")),
    ]))

    # StarterPlayer / StarterPlayerScripts: клиент
    sp = item("StarterPlayer", [
        p_str("Name", "StarterPlayer"),
        p_bool("EnableMouseLockOption", True),
        p_bool("LoadCharacterAppearance", True),
        p_float("CameraMaxZoomDistance", 120),
        p_float("CameraMinZoomDistance", 6),
        p_token("CameraMode", 0),
    ])
    sps = item("StarterPlayerScripts", [p_str("Name", "StarterPlayerScripts")])
    sps[3].append(item("LocalScript", [
        p_str("Name", "CombatClient"),
        p_protected("Source", read_lua("clientmain.lua")),
    ]))
    sp[3].append(sps)

    root_children.append(rs)
    root_children.append(sss)
    root_children.append(sp)

    stg = item("StarterGui", [p_str("Name", "StarterGui")])
    stg[3].append(item("ScreenGui", [
        p_str("Name", "GuiRoot"),
        p_bool("ResetOnSpawn", False),
        p_bool("Enabled", False),
    ]))
    root_children.append(stg)


# ---------------------------------------------------------------------------
# СБОРКА
# ---------------------------------------------------------------------------

def main():
    ws = item("Workspace", [
        p_str("Name", "Workspace"),
        p_bool("StreamingEnabled", False),
        p_float("Gravity", 196.2),
        p_float("FallenPartsDestroyHeight", -300),
    ])

    build_arena(ws)

    root_children = [ws]
    build_lighting(root_children)
    build_scripts(root_children, ws)

    lines = [
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime"'
        ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
        ' xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd"'
        ' version="4">',
        '\t<External>null</External>',
        '\t<External>nil</External>',
    ]
    for ch in root_children:
        lines.extend(emit(ch, 1))
    lines.append('</roblox>')
    xml = "\n".join(lines) + "\n"

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        f.write(xml)

    print("Готово:", OUT_PATH)
    print("Инстансов: %d, размер: %.1f КБ" % (xml.count("<Item "), len(xml) / 1024))


if __name__ == "__main__":
    main()
