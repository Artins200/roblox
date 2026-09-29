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
  * готовый боец (StarterCharacter) классического R6-рига с энергоядром;
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


def read_lua(name):
    with open(os.path.join(LUA_DIR, name), "r", encoding="utf-8") as f:
        return f.read()


# ---------------------------------------------------------------------------
# ГЕОМЕТРИЯ АРЕНЫ
# ---------------------------------------------------------------------------
HALF = 130.0          # половина арены (260×260 стадов)
FLOOR_TOP = 0.0       # верх пола
DECK_Y = 16.0         # высота боковых платформ
SPAWN_PAD_R = 17.0    # радиус центрального круга

# Материалы (Enum.Material)
M_PLASTIC = 256
M_SMOOTH = 272
M_NEON = 288
M_METAL = 1088
M_SLATE = 800
M_CONCRETE = 816
M_GRANITE = 832
M_GLASS = 1568
M_FORCEFIELD = 1600
M_DIAMOND = 1552
M_MARBLE = 784

SHAPE_BALL = 0
SHAPE_BLOCK = 1
SHAPE_CYLINDER = 2

# Цвета
C_DARK = (14, 15, 22)
C_FLOOR = (26, 28, 38)
C_TRIM = (90, 220, 255)
C_TRIM_HOT = (235, 255, 255)
C_ULT = (255, 70, 200)
C_GOLD = (255, 210, 90)
C_VIOLET = (150, 90, 255)
C_WHITE = (240, 244, 252)
C_RED = (255, 80, 70)

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
# ОСВЕЩЕНИЕ
# ---------------------------------------------------------------------------

def build_lighting(root_children):
    lighting = item("Lighting", [
        p_str("Name", "Lighting"),
        p_color3("Ambient", (58, 62, 82)),
        p_color3("OutdoorAmbient", (70, 76, 98)),
        p_float("Brightness", 2.1),
        p_float("ClockTime", 0.0),
        p_float("GeographicLatitude", 20),
        p_float("ExposureCompensation", 0.15),
        p_float("EnvironmentDiffuseScale", 0.55),
        p_float("EnvironmentSpecularScale", 0.9),
        p_color3("FogColor", (18, 20, 34)),
        p_float("FogStart", 260),
        p_float("FogEnd", 900),
        p_bool("GlobalShadows", True),
        p_float("ShadowSoftness", 0.25),
    ])
    lighting[3].append(item("Atmosphere", [
        p_str("Name", "Atmosphere"),
        p_color3("Color", (60, 70, 105)),
        p_color3("Decay", (40, 45, 70)),
        p_float("Density", 0.34),
        p_float("Glare", 0.35),
        p_float("Haze", 0.9),
        p_float("Offset", 0.05),
    ]))
    lighting[3].append(item("BloomEffect", [
        p_str("Name", "Bloom"), p_float("Intensity", 1.5),
        p_float("Size", 32), p_float("Threshold", 0.85)]))
    lighting[3].append(item("ColorCorrectionEffect", [
        p_str("Name", "ColorGrade"), p_float("Brightness", 0.02),
        p_float("Contrast", 0.16), p_float("Saturation", 0.12),
        p_color3("TintColor", (235, 240, 255))]))
    lighting[3].append(item("SunRaysEffect", [
        p_str("Name", "Rays"), p_float("Intensity", 0.05), p_float("Spread", 1)]))
    root_children.append(lighting)


# ---------------------------------------------------------------------------
# АРЕНА
# ---------------------------------------------------------------------------

def add_neon_ring(parent, name, x, y, z, radius, thickness, rgb, transparency=0.15):
    add_part_shape(parent, name, (thickness, radius * 2, radius * 2), (x, y, z), rgb,
                   SHAPE_CYLINDER, mat=M_NEON, transparency=transparency,
                   cancollide=False, castshadow=False, rotation=mat_rotz(math.pi / 2))


def build_arena(ws):
    arena = item("Model", [p_str("Name", "Arena")])

    # --- пол ---------------------------------------------------------------
    add_part(arena, "Floor", (HALF * 2, 8, HALF * 2), (0, FLOOR_TOP - 4, 0),
             C_FLOOR, mat=M_CONCRETE)
    add_part(arena, "FloorPlate", (HALF * 2 - 12, 0.4, HALF * 2 - 12), (0, FLOOR_TOP + 0.2, 0),
             (32, 35, 48), mat=M_METAL, cancollide=False, castshadow=False)

    # светящийся контур по краям
    for i, (sx, sz) in enumerate([(HALF * 2, 1.6), (1.6, HALF * 2)]):
        off = HALF - 0.8
        if sx > sz:
            for sgn in (-1, 1):
                add_part(arena, "EdgeTrim%d_%d" % (i, sgn), (sx, 0.7, sz),
                         (0, FLOOR_TOP + 0.4, sgn * off), C_TRIM, mat=M_NEON,
                         cancollide=False, castshadow=False, transparency=0.1)
        else:
            for sgn in (-1, 1):
                add_part(arena, "EdgeTrim%d_%d" % (i, sgn), (sx, 0.7, sz),
                         (sgn * off, FLOOR_TOP + 0.4, 0), C_TRIM, mat=M_NEON,
                         cancollide=False, castshadow=False, transparency=0.1)

    # «бездна» под ареной (декорация) + разрушенные края
    add_part(arena, "Void", (900, 40, 900), (0, FLOOR_TOP - 60, 0), (8, 9, 14),
             mat=M_SLATE, cancollide=False, castshadow=False)
    for i in range(14):
        a = RNG.uniform(0, math.pi * 2)
        r = RNG.uniform(HALF - 6, HALF + 2)
        add_part_rot(arena, "EdgeRock%d" % i,
                     (RNG.uniform(6, 16), RNG.uniform(3, 8), RNG.uniform(6, 14)),
                     (math.cos(a) * r, FLOOR_TOP - RNG.uniform(0.5, 2.5), math.sin(a) * r),
                     (24, 26, 36), mat=M_SLATE,
                     rot=mat_roty(a) if i % 2 else mat_rotx(RNG.uniform(-0.2, 0.2)))

    # --- центральный круг и пилон ------------------------------------------
    core = item("Model", [p_str("Name", "BattleCore")])
    add_part_shape(core, "CorePad", (0.6, SPAWN_PAD_R * 2, SPAWN_PAD_R * 2),
                   (0, FLOOR_TOP + 0.3, 0), (40, 44, 60), SHAPE_CYLINDER,
                   mat=M_METAL)
    add_neon_ring(core, "CoreRing1", 0, FLOOR_TOP + 0.62, 0, SPAWN_PAD_R, 0.5, C_TRIM, 0.05)
    add_neon_ring(core, "CoreRing2", 0, FLOOR_TOP + 0.62, 0, SPAWN_PAD_R - 4, 0.35, C_TRIM_HOT, 0.25)
    add_neon_ring(core, "CoreRing3", 0, FLOOR_TOP + 0.62, 0, 4.5, 0.6, C_ULT, 0.1)

    # спицы от центра к краям
    for i in range(8):
        a = i * math.pi / 4
        add_part_rot(core, "Spoke%d" % i, (0.55, 0.25, HALF - 22),
                     (math.cos(a) * (HALF - 11), FLOOR_TOP + 0.45, math.sin(a) * (HALF - 11)),
                     (60, 200, 235), mat=M_NEON, rot=mat_roty(-a),
                     cancollide=False, castshadow=False, transparency=0.35)

    # вертикальный пилон над центром (чисто декор)
    add_part_shape(core, "Pylon", (0.8, 9, 9), (0, FLOOR_TOP + 46, 0), (30, 34, 48),
                   SHAPE_CYLINDER, mat=M_GLASS, transparency=0.55,
                   cancollide=False, castshadow=False)
    add_part_shape(core, "PylonCore", (0.6, 4, 4), (0, FLOOR_TOP + 46, 0), C_TRIM,
                   SHAPE_CYLINDER, mat=M_NEON, transparency=0.15,
                   cancollide=False, castshadow=False)
    orb = item("Part", part_props("CoreOrb", (7, 7, 7), (0, FLOOR_TOP + 46, 0), C_TRIM_HOT,
                                  mat=M_NEON, shape=SHAPE_BALL, transparency=0.25,
                                  cancollide=False, castshadow=False))
    add_light(orb, "CoreLight", (120, 220, 255), 4, 70)
    core[3].append(orb)
    arena[3].append(core)

    # --- спавн -------------------------------------------------------------
    spawn = item("SpawnLocation", [
        p_str("Name", "ArenaSpawn"),
        p_bool("Anchored", True),
        p_bool("CanCollide", False),
        p_bool("Neutral", True),
        p_int("Duration", 0),
        p_bool("Enabled", True),
        p_bool("AllowTeamChangeOnTouch", False),
        p_color3uint8("Color3uint8", C_TRIM),
        p_cframe("CFrame", (0, FLOOR_TOP + 1.2, 0), mat_id()),
        p_token("Material", M_FORCEFIELD),
        p_token("TopSurface", 0),
        p_token("BottomSurface", 0),
        p_float("Transparency", 0.55),
        p_v3("size", 14, 1, 14),
    ])

    # --- боковые платформы с рампами ---------------------------------------
    for side in (-1, 1):
        px = side * (HALF - 34)
        add_part(arena, "Deck%d" % side, (54, 2.5, 78), (px, DECK_Y - 1.25, 0),
                 (34, 38, 52), mat=M_METAL)
        add_part(arena, "DeckTrim%d" % side, (54, 0.5, 1.2), (px, DECK_Y + 0.25, -38),
                 C_VIOLET, mat=M_NEON, cancollide=False, castshadow=False, transparency=0.15)
        add_part(arena, "DeckTrimB%d" % side, (54, 0.5, 1.2), (px, DECK_Y + 0.25, 38),
                 C_VIOLET, mat=M_NEON, cancollide=False, castshadow=False, transparency=0.15)
        # ограда сзади
        add_part(arena, "DeckFence%d" % side, (1.2, 7, 78), (px + side * 26.4, DECK_Y + 3, 0),
                 (60, 66, 84), mat=M_METAL)
        # рампы к полу
        ramp_len = 34.0
        ang = math.atan(DECK_Y / ramp_len)
        for sgn in (-1, 1):
            add_part_rot(arena, "Ramp%d_%d" % (side, sgn),
                         (14, 1.0, math.hypot(ramp_len, DECK_Y)),
                         (px, DECK_Y / 2 - 0.5, sgn * (39 + ramp_len / 2)),
                         (40, 44, 60), mat=M_METAL,
                         rot=mat_rotx(-ang * sgn))

    # --- колонны по периметру + кольца (их крутит клиент) ------------------
    decor = item("Folder", [p_str("Name", "Decor")])
    for i in range(12):
        a = i * math.pi / 6 + 0.12
        x, z = math.cos(a) * (HALF - 12), math.sin(a) * (HALF - 12)
        h = RNG.uniform(34, 54)
        add_part_rot(decor, "Pillar%d" % i, (7, h, 7), (x, FLOOR_TOP + h / 2, z),
                     (30, 33, 46), mat=M_GRANITE, rot=mat_roty(a))
        add_part_rot(decor, "Cap%d" % i, (9.5, 1.6, 9.5), (x, FLOOR_TOP + h + 0.8, z),
                     (48, 52, 70), mat=M_METAL, rot=mat_roty(a))
        add_part_rot(decor, "Spin_Ring%d" % i, (0.5, 13, 13), (x, FLOOR_TOP + h * 0.55, z),
                     C_TRIM, mat=M_NEON, rot=mat_rotz(math.pi / 2),
                     cancollide=False, castshadow=False, transparency=0.2)
        if i % 2 == 0:
            lamp = item("Part", part_props("Lamp%d" % i, (3, 3, 3),
                                           (x, FLOOR_TOP + h + 2.6, z), C_TRIM,
                                           mat=M_NEON, shape=SHAPE_BALL,
                                           cancollide=False, castshadow=False))
            add_light(lamp, "Glow", (110, 200, 255), 3, 46)
            decor[3].append(lamp)

    # парящие сферы (клиент качает их вверх-вниз)
    for i in range(10):
        a = RNG.uniform(0, math.pi * 2)
        r = RNG.uniform(30, 95)
        y = FLOOR_TOP + RNG.uniform(18, 44)
        color = (C_ULT if i % 3 == 0 else (C_VIOLET if i % 3 == 1 else C_TRIM))
        s = RNG.uniform(2.2, 4.6)
        add_part_shape(decor, "Bob_Orb%d" % i, (s, s, s),
                       (math.cos(a) * r, y, math.sin(a) * r), color, SHAPE_BALL,
                       mat=M_NEON, transparency=0.25, cancollide=False, castshadow=False)

    # арки-ворота
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        x, z = math.cos(a) * (HALF - 20), math.sin(a) * (HALF - 20)
        for sgn in (-1, 1):
            ox = -math.sin(a) * 11 * sgn
            oz = math.cos(a) * 11 * sgn
            add_part_rot(decor, "Arch%d_%d" % (i, sgn), (3, 26, 3), (x + ox, FLOOR_TOP + 13, z + oz),
                         (44, 48, 66), mat=M_METAL, rot=mat_roty(a))
        add_part_rot(decor, "ArchTop%d" % i, (3, 2.4, 23.5), (x, FLOOR_TOP + 26.6, z),
                     C_TRIM, mat=M_NEON, rot=mat_roty(a + math.pi / 2),
                     cancollide=False, castshadow=False, transparency=0.2)

    # укрытия на полу
    cover_spots = [(-58, -58), (-58, 58), (58, -58), (58, 58), (0, -84), (0, 84), (-84, 0), (84, 0)]
    for i, (x, z) in enumerate(cover_spots):
        add_part(decor, "Cover%d" % i, (12, 9, 5), (x, FLOOR_TOP + 4.5, z),
                 (36, 40, 54), mat=M_CONCRETE, transparency=0.05)
        add_part(decor, "CoverTrim%d" % i, (12.4, 0.5, 5.4), (x, FLOOR_TOP + 9.2, z),
                 C_TRIM, mat=M_NEON, cancollide=False, castshadow=False, transparency=0.3)
    arena[3].append(decor)

    # --- посты для манекенов (белые тренировочные бойцы) -------------------
    posts = item("Folder", [p_str("Name", "DummyPosts")])

    def add_post(idx, kind, radius, angle, ring_color):
        x, z = math.cos(angle) * radius, math.sin(angle) * radius
        facing = mat_look((-math.cos(angle), 0, -math.sin(angle)))  # лицом к центру
        pad = item("Part", part_props("Post_%s_%d" % (kind, idx), (0.6, 6.8, 6.8),
                                      (x, FLOOR_TOP + 0.3, z), (52, 56, 72),
                                      mat=M_METAL, shape=SHAPE_CYLINDER, rotation=facing))
        pad[3].append(item("Part", part_props("PostRing_%s_%d" % (kind, idx),
                                              (0.28, 8.4, 8.4), (x, FLOOR_TOP + 0.6, z),
                                              ring_color, mat=M_NEON, shape=SHAPE_CYLINDER,
                                              transparency=0.15, cancollide=False,
                                              castshadow=False, rotation=mat_rotz(math.pi / 2))))
        posts[3].append(pad)

    angle0 = 0.39
    for i in range(4):
        add_post(i, "normal", 22.0, angle0 + i * math.pi / 2, C_TRIM)
    add_post(10, "heavy", 34.0, angle0 + math.pi / 4, C_VIOLET)
    add_post(11, "heavy", 34.0, angle0 + math.pi + math.pi / 4, C_VIOLET)
    add_post(20, "titan", 46.0, angle0 + math.pi / 2 + 0.2, C_ULT)
    add_post(21, "titan", 46.0, angle0 - math.pi / 2 - 0.2, C_ULT)
    arena[3].append(posts)

    # --- табло -------------------------------------------------------------
    sb = item("Model", [p_str("Name", "Scoreboard")])
    add_part(sb, "Base", (34, 4, 8), (0, FLOOR_TOP + 2, -HALF - 8), (40, 44, 58), mat=M_CONCRETE)
    for sgn in (-1, 1):
        add_part(sb, "LegLead%d" % sgn, (2.4, 20, 2.4), (sgn * 10, FLOOR_TOP + 12, -HALF - 8),
                 (52, 56, 74), mat=M_METAL)
    board = item("Part", part_props("Scoreboard", (1.4, 30, 46), (0, FLOOR_TOP + 26, -HALF - 8),
                                    (18, 20, 30), mat=M_SMOOTH, rotation=mat_look((0, 0, 1))))
    gui = item("SurfaceGui", [
        p_str("Name", "BoardGui"),
        p_token("Face", 5),
        p_bool("AlwaysOnTop", True),
        p_bool("LightInfluence", False),
        p_v2("CanvasSize", 400, 280),
    ])
    add_label(gui, "Title", "ЛУЧШИЕ БОЙЦЫ АРЕНЫ", 19,
              (0.0, 0, 0.0, 0), (1.0, 0, 0.12, 0), C_GOLD, xalign=1)
    for i in range(8):
        add_label(gui, "Row%d" % (i + 1), "%d. —" % (i + 1), 18,
                  (0.05, 0, 0.14 + i * 0.098, 0), (0.9, 0, 0.085, 0),
                  (235, 240, 255), xalign=0)
    add_label(gui, "Foot", "V — полёт · F — лазер · X — УЛЬТА · T — манекены", 16,
              (0.0, 0, 0.92, 0), (1.0, 0, 0.07, 0), C_TRIM, xalign=1)
    board[3].append(gui)
    sb[3].append(board)
    arena[3].append(sb)

    ws[3].append(arena)
    ws[3].append(spawn)
    return arena


# ---------------------------------------------------------------------------
# СТАРТОВЫЙ ПЕРСОНАЖ (классический R6 + энергоядро)
# ---------------------------------------------------------------------------

def build_starter_character(sp):
    ch = item("Model", [p_str("Name", "StarterCharacter")])
    parts = {}

    def mkpart(name, size, pos, rgb, cancollide=True, transparency=0.0, mat=M_SMOOTH):
        it = item("Part", [
            p_str("Name", name),
            p_bool("Anchored", False),
            p_bool("CanCollide", cancollide),
            p_color3uint8("Color3uint8", rgb),
            p_cframe("CFrame", pos, mat_id()),
            p_token("Material", mat),
            p_float("Reflectance", 0.0),
            p_token("TopSurface", 0),
            p_token("BottomSurface", 0),
            p_float("Transparency", transparency),
            p_v3("size", *size),
        ])
        ch[3].append(it)
        parts[name] = it
        return it

    body = (238, 242, 250)
    mkpart("HumanoidRootPart", (2, 2, 1), (0, 3, 0), body, False, 1.0)
    mkpart("Torso", (2, 2, 1), (0, 3, 0), body)
    head = mkpart("Head", (2, 1, 1), (0, 4.5, 0), body)
    head[3].append(item("SpecialMesh", [
        p_str("Name", "Mesh"), p_token("MeshType", 5),
        p_v3("Scale", 1.25, 1.25, 1.25)]))
    mkpart("Left Arm", (1, 2, 1), (-1.5, 3, 0), body)
    mkpart("Right Arm", (1, 2, 1), (1.5, 3, 0), body)
    mkpart("Left Leg", (1, 2, 1), (-0.5, 1, 0), body)
    mkpart("Right Leg", (1, 2, 1), (0.5, 1, 0), body)

    # энергоядро в груди (клиент красит его по заряду ульты)
    core = mkpart("Core", (0.6, 0.6, 0.6), (0, 3.1, -0.7), (60, 220, 255), False, 0.4, M_NEON)
    core[3].append(item("PointLight", [
        p_str("Name", "CoreLight"), p_float("Brightness", 1.4),
        p_color3("Color", (120, 220, 255)), p_bool("Enabled", True),
        p_float("Range", 12), p_bool("Shadows", False)]))
    ch[3].append(item("WeldConstraint", [
        p_str("Name", "CoreWeld"),
        p_ref("Part0", parts["Torso"][1]),
        p_ref("Part1", core[1]),
    ]))

    # Humanoid + Animator
    hum = item("Humanoid", [
        p_str("Name", "Humanoid"),
        p_bool("AutoRotate", True),
        p_bool("BreakJointsOnDeath", False),
        p_float("Health", 2500),
        p_float("MaxHealth", 2500),
        p_float("JumpPower", 55),
        p_bool("UseJumpPower", True),
        p_float("WalkSpeed", 20),
        p_token("DisplayDistanceType", 2),
        p_float("HealthDisplayDistance", 0),
        p_float("NameDisplayDistance", 0),
        p_token("RigType", 0),
    ])
    hum[3].append(item("Animator", [p_str("Name", "Animator")]))
    ch[3].append(hum)

    # шарниры R6. Точки вращения — в плечах/бёдрах/шее (см. CombatPose).
    joints = [
        ("RootJoint", "HumanoidRootPart", "Torso", (0, 0, 0), (0, 0, 0)),
        ("Neck", "Torso", "Head", (0, 1, 0), (0, -0.5, 0)),
        ("Left Shoulder", "Torso", "Left Arm", (-1, 0.5, 0), (0.5, 0.5, 0)),
        ("Right Shoulder", "Torso", "Right Arm", (1, 0.5, 0), (-0.5, 0.5, 0)),
        ("Left Hip", "Torso", "Left Leg", (-0.5, -1, 0), (0, 1, 0)),
        ("Right Hip", "Torso", "Right Leg", (0.5, -1, 0), (0, 1, 0)),
    ]
    for name, p0, p1, c0, c1 in joints:
        ch[3].append(item("Motor6D", [
            p_str("Name", name),
            p_ref("Part0", parts[p0][1]),
            p_ref("Part1", parts[p1][1]),
            p_cframe("C0", c0, mat_id()),
            p_cframe("C1", c1, mat_id()),
        ]))

    sp[3].append(ch)
    return ch


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
    for rname in ("Attack", "Action", "Feedback", "Hurt", "Knock", "Ult", "Sfx", "Ack"):
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
        p_bool("LoadCharacterAppearance", False),
        p_float("CameraMaxZoomDistance", 120),
        p_float("CameraMinZoomDistance", 6),
        p_token("CameraMode", 0),
    ])
    build_starter_character(sp)
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
