#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Генератор места bridge_world.rbxlx для Roblox Studio.

Создаёт однострочный XML-файл места (формат RBXLX v4), который открывается
в Roblox Studio через File -> Open from File. Внутри:

  * бухта с водой, берегами, холмами, скалами, островами и дальними хребтами;
  * гигантский вантовый мост (в духе моста Мапуто-Катембе): две H-образные
    башни, веерные ванты, полотно из 128 блоков-сегментов;
  * скрипт BridgeAssembler: при запуске (Play) мост собирается по блокам —
    башни растут снизу вверх, полотно наращивается консолью от каждой башни
    вместе с вантами, потом зажигаются фонари. У западного входа стоит пульт
    «Пересобрать мост» (клавиша E);
  * скрипт Ambience: лодки плывут под мостом, блики на воде мерцают,
    маяк пульсирует;
  * освещение закатного золотого часа (Atmosphere, Bloom, SunRays).

Запуск:  python3 tools/generate_bridge_world.py
"""

import math
import os
import random

RNG = random.Random(20260928)

OUT_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        "bridge_world.rbxlx")

# ---------------------------------------------------------------------------
# Геометрия мира
# ---------------------------------------------------------------------------
WATER_Y = 0.0
DECK_Y = 120.0               # центр плиты полотна
DECK_TOP = DECK_Y + 2.5      # верх плиты
SEG_LEN = 30.0
SEG_N = 128                  # сегментов полотна
DECK_HALF_W = 50.0
X0 = -1920.0                 # начало полотна (конец: -X0)
TOWERS = (-720.0, 720.0)     # пилоны по X
TOWER_TOP = 470.0
LEG_Z = 70.0                 # центр ног пилона по Z
LEG_W = 34.0
CABLE_Z_DECK = 46.0
CABLE_Z_TOWER = 55.0

# Материалы (значения Enum.Material)
M_PLASTIC = 256
M_SMOOTH = 272
M_NEON = 288
M_WOOD = 512
M_SLATE = 800
M_CONCRETE = 816
M_GRANITE = 832
M_BRICK = 848
M_PEBBLE = 864
M_METAL = 1088
M_GRASS = 1280
M_LEAFY = 1284
M_SAND = 1296
M_GLASS = 1568
M_ASPHALT = 1376
M_SANDSTONE = 912

# ---------------------------------------------------------------------------
# Низкоуровневый RBXLX-билдер
# ---------------------------------------------------------------------------

def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if v == int(v) and abs(v) < 1e15:
        return str(int(v))
    return repr(round(float(v), 6))


class Builder:
    def __init__(self):
        self.counter = 0

    def referent(self):
        self.counter += 1
        return "RBX%032X" % self.counter


B = Builder()

# --- эмиттеры свойств -------------------------------------------------------

def p_str(name, v):
    return '<string name="%s">%s</string>' % (name, esc(v))


def p_bool(name, v):
    return '<bool name="%s">%s</bool>' % (name, "true" if v else "false")


def p_float(name, v):
    return '<float name="%s">%s</float>' % (name, fmt(v))


def p_int(name, v):
    return '<int name="%s">%d</int>' % (name, int(v))


def p_token(name, v):
    return '<token name="%s">%d</token>' % (name, int(v))


def p_color3(name, rgb):
    r, g, b = (c / 255.0 for c in rgb)
    return ('<Color3 name="%s"><R>%s</R><G>%s</G><B>%s</B></Color3>'
            % (name, fmt(r), fmt(g), fmt(b)))


def p_color3uint8(name, rgb):
    r, g, b = rgb
    val = 0xFF000000 | (r << 16) | (g << 8) | b
    return '<Color3uint8 name="%s">%d</Color3uint8>' % (name, val)


def p_v3(name, x, y, z):
    return ('<Vector3 name="%s"><X>%s</X><Y>%s</Y><Z>%s</Z></Vector3>'
            % (name, fmt(x), fmt(y), fmt(z)))


def p_v2(name, x, y):
    return ('<Vector2 name="%s"><X>%s</X><Y>%s</Y></Vector2>'
            % (name, fmt(x), fmt(y)))


def p_udim2(name, xs, xo, ys, yo):
    return ('<UDim2 name="%s"><XS>%s</XS><XO>%d</XO><YS>%s</YS><YO>%d</YO></UDim2>'
            % (name, fmt(xs), int(xo), fmt(ys), int(yo)))


def p_ref(name, referent):
    return '<Ref name="%s">%s</Ref>' % (name, referent)


def p_cframe(name, pos, mat):
    (x, y, z) = pos
    r00, r01, r02, r10, r11, r12, r20, r21, r22 = mat
    return ('<CoordinateFrame name="%s">'
            '<X>%s</X><Y>%s</Y><Z>%s</Z>'
            '<R00>%s</R00><R01>%s</R01><R02>%s</R02>'
            '<R10>%s</R10><R11>%s</R11><R12>%s</R12>'
            '<R20>%s</R20><R21>%s</R21><R22>%s</R22>'
            '</CoordinateFrame>'
            % (name, fmt(x), fmt(y), fmt(z),
               fmt(r00), fmt(r01), fmt(r02),
               fmt(r10), fmt(r11), fmt(r12),
               fmt(r20), fmt(r21), fmt(r22)))


def p_protected(name, source):
    assert "]]>" not in source, "CDATA не может содержать ]]>"
    return '<ProtectedString name="%s"><![CDATA[%s]]></ProtectedString>' % (name, source)


def p_contentid(name, url):
    return '<ContentId name="%s"><url>%s</url></ContentId>' % (name, esc(url))


# --- CFrame-помощники ------------------------------------------------------

def mat_id():
    return (1, 0, 0, 0, 1, 0, 0, 0, 1)


def mat_from_ru(right, up):
    """Матрица поворота по осям Right/Up локальных осей (столбцы = оси)."""
    rx, ry, rz = right
    ux, uy, uz = up
    # back = right x up
    bx = ry * uz - rz * uy
    by = rz * ux - rx * uz
    bz = rx * uy - ry * ux
    return (rx, ux, bx, ry, uy, by, rz, uz, bz)


def mat_rotz(a):
    c, s = math.cos(a), math.sin(a)
    return mat_from_ru((c, s, 0.0), (-s, c, 0.0))


def mat_rotx(a):
    c, s = math.cos(a), math.sin(a)
    return mat_from_ru((1.0, 0.0, 0.0), (0.0, c, s))


def mat_roty(a):
    c, s = math.cos(a), math.sin(a)
    return mat_from_ru((c, 0.0, -s), (0.0, 1.0, 0.0))


def _norm(v):
    l = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) or 1.0
    return (v[0] / l, v[1] / l, v[2] / l)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def mat_look(look):
    """Матрица, у которой LookVector смотрит вдоль look."""
    look = _norm(look)
    back = (-look[0], -look[1], -look[2])
    up_hint = (0.0, 1.0, 0.0)
    if abs(look[0]) < 1e-6 and abs(look[1]) > 0.99:
        up_hint = (1.0, 0.0, 0.0)
    right = _norm(_cross(up_hint, back))
    up = _cross(back, right)
    return mat_from_ru(right, up)


# --- эмиттеры инстансов ----------------------------------------------------

def item(class_name, props, children=()):
    return (class_name, B.referent(), list(props), list(children))


def emit(it, indent=0):
    class_name, referent, props, children = it
    pad = "\t" * indent
    out = [pad + '<Item class="%s" referent="%s">' % (class_name, referent),
           pad + "\t<Properties>"]
    for p in props:
        out.append(pad + "\t\t" + p)
    out.append(pad + "\t</Properties>")
    for ch in children:
        out.extend(emit(ch, indent + 1))
    out.append(pad + "</Item>")
    return out


def part_props(name, size, pos, rgb, mat=M_SMOOTH, transparency=0.0,
               reflectance=0.0, rotation=None, shape=None, cancollide=True,
               castshadow=True, anchored=True):
    props = [
        p_str("Name", name),
        p_bool("Anchored", anchored),
        p_bool("CanCollide", cancollide),
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


def add_part(parent, name, size, pos, rgb, **kw):
    parent[3].append(item("Part", part_props(name, size, pos, rgb, **kw)))


def add_part_rot(parent, name, size, pos, rgb, rotation, **kw):
    kw["rotation"] = rotation
    parent[3].append(item("Part", part_props(name, size, pos, rgb, **kw)))


def add_part_shape(parent, name, size, pos, rgb, shape, **kw):
    kw["shape"] = shape
    parent[3].append(item("Part", part_props(name, size, pos, rgb, **kw)))


def add_light(parent, name, rgb, brightness, rng, shadows=False, enabled=True):
    parent[3].append(item("PointLight", [
        p_str("Name", name),
        p_float("Brightness", brightness),
        p_color3("Color", rgb),
        p_bool("Enabled", enabled),
        p_float("Range", rng),
        p_bool("Shadows", shadows),
    ]))


# ---------------------------------------------------------------------------
# Мост
# ---------------------------------------------------------------------------

def seg_x(i):
    return X0 + SEG_LEN * (i + 0.5)


def build_step_for_x(x):
    t = TOWERS[0] if x < 0 else TOWERS[1]
    d = abs(x - t)
    return int(round((d - 15.0) / 30.0))


def build_bridge(root):
    bridge = item("Model", [p_str("Name", "Bridge")])

    pylons = item("Folder", [p_str("Name", "Pylons")])
    deck = item("Folder", [p_str("Name", "Deck")])
    cables = item("Folder", [p_str("Name", "Cables")])
    lamps = item("Folder", [p_str("Name", "Lamps")])
    bridge[3].extend([pylons, deck, cables, lamps])

    concrete = (188, 186, 180)
    concrete_dark = (150, 148, 142)

    # ---------------- Пилоны ----------------
    leg_h = 42.5
    n_leg = 12
    for ti, tx in enumerate(TOWERS):
        tname = "W" if tx < 0 else "E"
        for zi, z in enumerate((-LEG_Z, LEG_Z)):
            side = "a" if zi == 0 else "b"
            for k in range(n_leg):
                y = -40.0 + leg_h * (k + 0.5)
                w = LEG_W if k < 9 else LEG_W - 6
                add_part(pylons, "Pyl_s%02d_leg%s_%s" % (k, side, tname),
                         (w, leg_h - 0.4, w), (tx, y, z), concrete,
                         mat=M_CONCRETE)
        # ростверк под водой
        add_part(pylons, "Pyl_s12_cap_" + tname,
                 (120, 26, 210), (tx, -46, 0), concrete_dark, mat=M_CONCRETE)
        # перекладины (буква H)
        for bi, by in enumerate((95.0, 250.0, 440.0)):
            add_part(pylons, "Pyl_s12_beam%d_%s" % (bi, tname),
                     (26, 30, 2 * LEG_Z + LEG_W), (tx, by, 0), concrete,
                     mat=M_CONCRETE)
        # верхний оголовок
        add_part(pylons, "Pyl_s12_head_" + tname,
                 (LEG_W - 6, 14, 2 * LEG_Z + LEG_W), (tx, TOWER_TOP + 6, 0),
                 concrete, mat=M_CONCRETE)
        # маяки на вершинах
        add_part_shape(pylons, "Pyl_s12_beacon_" + tname,
                       (10, 10, 10), (tx, TOWER_TOP + 19, 0),
                       (255, 210, 130), 0, mat=M_NEON, cancollide=False,
                       castshadow=False, transparency=0.25)
        bridge_beacon = pylons[3][-1]
        add_light(bridge_beacon, "TowerBeacon", (255, 205, 130), 1.4, 90)

    # ---------------- Полотно ----------------
    asphalt = (54, 56, 60)
    barrier_rgb = (168, 168, 164)
    mark_rgb = (222, 222, 214)
    divider_rgb = (150, 150, 146)

    for i in range(SEG_N):
        x = seg_x(i)
        step = build_step_for_x(x)
        seg = item("Model", [p_str("Name", "Seg_s%02d_i%03d" % (step, i))])
        add_part(seg, "slab", (SEG_LEN - 0.6, 5, 2 * DECK_HALF_W),
                 (x, DECK_Y, 0), asphalt, mat=M_ASPHALT)
        add_part(seg, "barrierA", (SEG_LEN - 0.6, 11, 2.6),
                 (x, DECK_Y + 7, DECK_HALF_W - 1.6), barrier_rgb, mat=M_CONCRETE)
        add_part(seg, "barrierB", (SEG_LEN - 0.6, 11, 2.6),
                 (x, DECK_Y + 7, -(DECK_HALF_W - 1.6)), barrier_rgb, mat=M_CONCRETE)
        add_part(seg, "divider", (SEG_LEN - 0.6, 4.2, 2.2),
                 (x, DECK_Y + 4.6, 0), divider_rgb, mat=M_CONCRETE)
        add_part(seg, "markA", (SEG_LEN - 0.6, 0.35, 1.8),
                 (x, DECK_Y + 2.7, 26), mark_rgb, mat=M_SMOOTH,
                 cancollide=False, castshadow=False)
        add_part(seg, "markB", (SEG_LEN - 0.6, 0.35, 1.8),
                 (x, DECK_Y + 2.7, -26), mark_rgb, mat=M_SMOOTH,
                 cancollide=False, castshadow=False)
        deck[3].append(seg)

    # ---------------- Ванты ----------------
    cable_rgb = (228, 230, 234)
    thick = 1.7

    def cable(a, b, name, step):
        ax, ay, az = a
        bx, by, bz = b
        dx, dy, dz = bx - ax, by - ay, bz - az
        ln = math.sqrt(dx * dx + dy * dy + dz * dz)
        cx, cy, cz = (ax + bx) / 2, (ay + by) / 2, (az + bz) / 2
        add_part_rot(cables, name, (thick, thick, ln), (cx, cy, cz),
                     cable_rgb, mat_look((dx, dy, dz)),
                     mat=M_METAL, reflectance=0.25, cancollide=False,
                     castshadow=False)

    ci = 0
    for tx in TOWERS:
        tname = "W" if tx < 0 else "E"
        dir_x = 1.0 if tx < 0 else -1.0        # в сторону середины пролёта
        # главный пролёт: 12 вант в каждую сторону по каждой плоскости
        for k in range(12):
            d = 45.0 + 60.0 * k
            ax = tx + dir_x * d
            step = build_step_for_x(ax)
            ty = 215.0 + (d - 45.0) / (1125.0 - 45.0) * 220.0
            for zsgn in (-1, 1):
                cable((tx, ty, zsgn * CABLE_Z_TOWER),
                      (ax, DECK_TOP + 1.5, zsgn * CABLE_Z_DECK),
                      "Cable_s%02d_%sM%02d%d" % (step, tname, k, zsgn), step)
                ci += 1
        # боковые пролёты к берегам
        for k in range(12):
            d = 75.0 + 90.0 * k
            ax = tx - dir_x * d
            step = build_step_for_x(ax)
            ty = 215.0 + (d - 45.0) / (1125.0 - 45.0) * 220.0
            for zsgn in (-1, 1):
                cable((tx, ty, zsgn * CABLE_Z_TOWER),
                      (ax, DECK_TOP + 1.5, zsgn * CABLE_Z_DECK),
                      "Cable_s%02d_%sS%02d%d" % (step, tname, k, zsgn), step)
                ci += 1

    # ---------------- Опоры боковых пролётов и подходы ----------------
    for tx in (1.0, -1.0):
        for px in (1560.0, 1800.0):
            add_part(pylons, "Pier_%d" % int(px * tx),
                     (34, 130, 60), (tx * px, 40, 0), concrete_dark,
                     mat=M_CONCRETE)
            add_part(pylons, "PierCap_%d" % int(px * tx),
                     (48, 8, 74), (tx * px, 106, 0), concrete_dark,
                     mat=M_CONCRETE)

    # устои
    for sx in (-1.0, 1.0):
        add_part(pylons, "Abutment_%s" % ("W" if sx < 0 else "E"),
                 (70, 120, 150), (sx * 1955, 35, 0), concrete_dark,
                 mat=M_CONCRETE)

    # ---------------- Фонари ----------------
    pole_rgb = (60, 62, 66)
    glow_rgb = (255, 214, 150)
    for side in (-1, 1):
        z = side * 47.0
        for i in range(32):
            x = -1860.0 + i * 120.0
            step = i
            name = "Lamp_s%02d_%s%d" % (step, "A" if side > 0 else "B", i)
            add_part_shape(lamps, name + "_pole",
                           (21, 2.2, 2.2), (x, DECK_TOP + 10.5, z),
                           pole_rgb, 2, rotation=mat_rotz(math.pi / 2),
                           mat=M_METAL, cancollide=False, castshadow=False)
            head = item("Part", part_props(name + "_head", (3.2, 1.3, 5.2),
                                          (x, DECK_TOP + 21.2, z - side * 1.2),
                                          glow_rgb, mat=M_NEON,
                                          transparency=0.35, cancollide=False,
                                          castshadow=False))
            add_light(head, "LampLight", glow_rgb, 0.85, 42)
            lamps[3].append(head)

    # ---------------- Пульт пересборки и табличка ----------------
    console = item("Part", part_props("Console", (7, 2.4, 5),
                                      (-1835, DECK_TOP + 1.4, 40),
                                      (40, 90, 160), mat=M_NEON,
                                      transparency=0.1))
    console[3].append(item("ProximityPrompt", [
        p_str("Name", "RebuildPrompt"),
        p_str("ActionText", "Пересобрать мост"),
        p_str("ObjectText", "Пульт строителей"),
        p_float("HoldDuration", 0.4),
        p_float("MaxActivationDistance", 18),
        p_bool("RequiresLineOfSight", False),
        p_token("KeyboardKeyCode", 101),  # E
    ]))
    bridge[3].append(console)

    sign = item("Part", part_props("Sign", (26, 13, 1.2),
                                   (-1862, DECK_TOP + 8.5, 48.4),
                                   (48, 52, 62), mat=M_SMOOTH,
                                   rotation=mat_look((-1, 0, 0))))
    gui = item("SurfaceGui", [
        p_str("Name", "SignGui"),
        p_token("Face", 5),  # Front
        p_bool("AlwaysOnTop", True),
        p_v2("CanvasSize", 520, 260),
    ])
    gui[3].append(item("TextLabel", [
        p_str("Name", "Title"),
        p_str("Text", "ВЕЛИКИЙ МОСТ ЗАЛИВА"),
        p_token("Font", 19),  # GothamBold
        p_bool("TextScaled", True),
        p_color3("TextColor3", (255, 236, 200)),
        p_color3("BackgroundColor3", (30, 36, 48)),
        p_float("BackgroundTransparency", 1),
        p_udim2("Position", 0.02, 0, 0.04, 0),
        p_udim2("Size", 0.96, 0, 0.42, 0),
    ]))
    gui[3].append(item("TextLabel", [
        p_str("Name", "Sub"),
        p_str("Text", "вантовый мост · собирается по блокам"),
        p_token("Font", 4),  # SourceSansBold
        p_bool("TextScaled", True),
        p_color3("TextColor3", (214, 226, 240)),
        p_float("BackgroundTransparency", 1),
        p_udim2("Position", 0.02, 0, 0.50, 0),
        p_udim2("Size", 0.96, 0, 0.20, 0),
    ]))
    gui[3].append(item("TextLabel", [
        p_str("Name", "Hint"),
        p_str("Text", "Нажмите Play — мост соберётся сам.  E у пульта — пересобрать."),
        p_token("Font", 3),
        p_bool("TextScaled", True),
        p_color3("TextColor3", (186, 200, 216)),
        p_float("BackgroundTransparency", 1),
        p_udim2("Position", 0.02, 0, 0.74, 0),
        p_udim2("Size", 0.96, 0, 0.18, 0),
    ]))
    sign[3].append(gui)
    bridge[3].append(sign)

    root[3].append(bridge)
    return bridge


# ---------------------------------------------------------------------------
# Вода
# ---------------------------------------------------------------------------

def build_water(root):
    water = item("Model", [p_str("Name", "Water")])

    add_part(water, "DeepWater", (8000, 3, 8000), (0, -2.6, 0),
             (17, 52, 96), mat=M_GLASS, transparency=0.12, reflectance=0.22,
             cancollide=True, castshadow=False)
    add_part(water, "SurfaceWater", (8000, 0.8, 8000), (0, -0.5, 0),
             (46, 118, 168), mat=M_GLASS, transparency=0.5, reflectance=0.5,
             cancollide=False, castshadow=False)

    glints = item("Folder", [p_str("Name", "WaterGlints")])
    for i in range(26):
        x = RNG.uniform(-2600, 2600)
        z = RNG.uniform(-2200, 2200)
        if abs(x) < 400 and abs(z) < 200:
            z += 600
        w = RNG.uniform(300, 900)
        add_part(glints, "Glint%02d" % i, (w, 0.3, RNG.uniform(6, 16)),
                 (x, -0.15, z), (170, 215, 235), mat=M_NEON,
                 transparency=0.82, cancollide=False, castshadow=False)
    water[3].append(glints)

    # пена у берегов
    for sx in (-1, 1):
        add_part(water, "Foam_%s" % ("W" if sx < 0 else "E"),
                 (26, 0.5, 2700), (sx * 2655, 0.1, 0),
                 (235, 242, 245), mat=M_SMOOTH, transparency=0.55,
                 cancollide=False, castshadow=False)
    for sz in (-1, 1):
        add_part(water, "FoamIsland_%d" % sz,
                 (420, 0.5, 26), (300, 0.1, sz * 1105),
                 (235, 242, 245), mat=M_SMOOTH, transparency=0.55,
                 cancollide=False, castshadow=False)

    root[3].append(water)


# ---------------------------------------------------------------------------
# Ландшафт
# ---------------------------------------------------------------------------

def add_tree(parent, name, x, y, z, scale=1.0):
    trunk_h = 15 * scale
    add_part_shape(parent, name + "_trunk", (trunk_h, 3.0 * scale, 3.0 * scale),
                   (x, y + trunk_h / 2, z), (116, 84, 56), 2,
                   rotation=mat_rotz(math.pi / 2), mat=M_WOOD)
    leaf = (58, 118, 52) if RNG.random() < 0.5 else (76, 138, 62)
    add_part_shape(parent, name + "_leaf1", (17 * scale,) * 3,
                   (x, y + trunk_h + 4 * scale, z), leaf, 0, mat=M_LEAFY,
                   cancollide=False)
    add_part_shape(parent, name + "_leaf2", (12 * scale,) * 3,
                   (x + 5 * scale, y + trunk_h + 1 * scale, z + 3 * scale),
                   leaf, 0, mat=M_LEAFY, cancollide=False)
    add_part_shape(parent, name + "_leaf3", (11 * scale,) * 3,
                   (x - 5 * scale, y + trunk_h + 1.5 * scale, z - 3 * scale),
                   leaf, 0, mat=M_LEAFY, cancollide=False)


def add_rock(parent, name, x, y, z, s):
    add_part(parent, name, (s * 1.6, s, s * 1.3), (x, y + s * 0.4, z),
             (110, 112, 118), mat=M_SLATE,
             rotation=mat_rotz(RNG.uniform(-0.5, 0.5)))


def add_house(parent, name, x, y, z, yaw=0.0):
    wall = (214, 202, 182) if RNG.random() < 0.5 else (196, 172, 148)
    roof = (146, 74, 58) if RNG.random() < 0.5 else (96, 82, 92)
    w, h, d = 36, 22, 28
    rot = mat_roty(yaw)

    def rp(n, size, off, rgb, mat=M_SMOOTH, rotation=None, **kw):
        ox, oy, oz = off
        c, s = math.cos(yaw), math.sin(yaw)
        px = x + ox * c + oz * s
        pz = z - ox * s + oz * c
        add_part_rot(parent, name + n, size, (px, y + oy, pz), rgb,
                     rotation if rotation is not None else rot, mat=mat, **kw)

    rp("_walls", (w, h, d), (0, h / 2, 0), wall, mat=M_SANDSTONE)
    rp("_roofA", (w + 6, 2.6, 20), (0, h + 4.2, -6.2), roof,
       rotation=mat_from_ru((1, 0, 0), (0, math.cos(-0.7), math.sin(-0.7))))
    rp("_roofB", (w + 6, 2.6, 20), (0, h + 4.2, 6.2), roof,
       rotation=mat_from_ru((1, 0, 0), (0, math.cos(0.7), math.sin(0.7))))
    rp("_door", (8, 12, 1), (0, 6, d / 2 + 0.6), (96, 70, 50), mat=M_WOOD)
    for wx in (-11, 11):
        rp("_win%d" % wx, (7, 6, 0.8), (wx, 12, d / 2 + 0.6),
           (255, 224, 160), mat=M_NEON, transparency=0.35, cancollide=False,
           castshadow=False)


def build_scenery(root):
    scen = item("Model", [p_str("Name", "Scenery")])

    grass = (86, 128, 66)
    grass2 = (104, 146, 76)
    sand = (222, 202, 158)

    # ---- берега ----
    for sx, tag in ((-1, "W"), (1, "E")):
        add_part(scen, "Land_" + tag,
                 (1500, 80, 2900), (sx * 3560, -18, 0), grass, mat=M_LEAFY)
        add_part(scen, "Beach_" + tag,
                 (430, 40, 2900), (sx * 2875, -2, 0), sand, mat=M_SAND)
        # холмы
        for hi in range(7):
            hx = sx * RNG.uniform(2950, 4150)
            hz = RNG.uniform(-1250, 1250)
            hs = RNG.uniform(120, 320)
            hh = RNG.uniform(35, 95)
            add_part(scen, "Hill_%s%d" % (tag, hi),
                     (hs, hh, hs * 0.8), (hx, 22 + hh / 2 - 12, hz),
                     grass2, mat=M_LEAFY,
                     rotation=mat_rotz(RNG.uniform(-0.18, 0.18)))
        # скалы у берега
        for ri in range(9):
            rx = sx * RNG.uniform(2620, 2820)
            rz = RNG.uniform(-1300, 1300)
            add_rock(scen, "Rock_%s%d" % (tag, ri), rx, 12, rz,
                     RNG.uniform(18, 46))
        # дорога на берегу
        add_part(scen, "Road_" + tag, (620, 8, 100), (sx * 3020, 22, 0),
                 (54, 56, 60), mat=M_ASPHALT)

        # подход эстакады (наклонная плита)
        ang = math.atan2(96.5, 790.0)
        add_part_rot(scen, "Approach_" + tag, (800, 8, 100),
                     (sx * 2315, 74, 0), (54, 56, 60),
                     mat_rotz(-sx * ang), mat=M_ASPHALT)
        add_part(scen, "ApproachRailA_" + tag, (800, 6, 2),
                 (sx * 2315, 80, 48), (168, 168, 164), mat=M_CONCRETE,
                 rotation=mat_rotz(-sx * ang))
        add_part(scen, "ApproachRailB_" + tag, (800, 6, 2),
                 (sx * 2315, 80, -48), (168, 168, 164), mat=M_CONCRETE,
                 rotation=mat_rotz(-sx * ang))

    # ---- горы на востоке повыше ----
    for mi in range(5):
        mx = 3250 + RNG.uniform(0, 900)
        mz = RNG.uniform(-1200, 1200)
        ms = RNG.uniform(340, 620)
        mh = RNG.uniform(120, 210)
        add_part(scen, "Mountain_%d" % mi, (ms, mh, ms * 0.7),
                 (mx, 22 + mh / 2 - 20, mz), (96, 110, 92), mat=M_SLATE,
                 rotation=mat_rotz(RNG.uniform(-0.12, 0.12)))

    # ---- дальние хребты (силуэты на горизонте) ----
    add_part(scen, "Ridge_N", (5200, 300, 520), (0, 40, -3050),
             (92, 104, 118), mat=M_SLATE, castshadow=False)
    add_part(scen, "Ridge_N2", (3600, 220, 420), (-800, 20, -2650),
             (100, 112, 124), mat=M_SLATE, castshadow=False)
    add_part(scen, "Ridge_S", (4800, 220, 480), (500, 15, 3050),
             (96, 108, 120), mat=M_SLATE, castshadow=False)

    # ---- острова ----
    for ix, iz, isl in ((320, -1180, "A"), (-860, 1140, "B")):
        add_part(scen, "Island_" + isl, (360, 26, 300), (ix, -4, iz),
                 grass, mat=M_LEAFY)
        add_part(scen, "IslandSand_" + isl, (420, 20, 360), (ix, -8, iz),
                 sand, mat=M_SAND)
        add_tree(scen, "Palm_%s1" % isl, ix - 60, 9, iz - 30, 1.1)
        add_tree(scen, "Palm_%s2" % isl, ix + 70, 9, iz + 40, 0.9)
        add_rock(scen, "IslRock_" + isl, ix + 120, 8, iz - 80, 16)

    # ---- деревья на берегах ----
    for sx, tag in ((-1, "W"), (1, "E")):
        for i in range(16):
            tx = sx * RNG.uniform(2950, 4150)
            tz = RNG.uniform(-1300, 1300)
            add_tree(scen, "Tree_%s%d" % (tag, i), tx, 22, tz,
                     RNG.uniform(0.8, 1.4))

    # ---- дома ----
    add_house(scen, "House_W1", -3150, 22, 320, 0.15)
    add_house(scen, "House_W2", -3380, 22, -180, -0.2)
    add_house(scen, "House_W3", -3080, 22, -520, 0.45)
    add_house(scen, "House_E1", 3180, 22, -260, 2.9)
    add_house(scen, "House_E2", 3420, 22, 380, 3.3)

    # ---- маяк ----
    lh = item("Model", [p_str("Name", "Lighthouse")])
    lh_x, lh_z = -2950.0, -980.0
    base_y = 18.0
    stripes = [(238, 236, 230), (196, 62, 52)]
    for i in range(5):
        add_part_shape(lh, "LhStripe%d" % i, (12, 12, 12),
                       (lh_x, base_y + 8 + i * 12, lh_z), stripes[i % 2], 2,
                       rotation=mat_rotz(math.pi / 2), mat=M_SANDSTONE)
    add_part_shape(lh, "LhLantern", (10, 12, 12),
                   (lh_x, base_y + 8 + 5 * 12, lh_z), (255, 220, 150), 2,
                   rotation=mat_rotz(math.pi / 2), mat=M_NEON,
                   transparency=0.35, cancollide=False, castshadow=False)
    add_light(lh[3][-1], "Beacon", (255, 215, 150), 2.2, 140)
    add_part_shape(lh, "LhTop", (7, 14, 14),
                   (lh_x, base_y + 8 + 5 * 12 + 9, lh_z), (60, 62, 66), 2,
                   rotation=mat_rotz(math.pi / 2), mat=M_METAL)
    scen[3].append(lh)

    root[3].append(scen)


# ---------------------------------------------------------------------------
# Лодки
# ---------------------------------------------------------------------------

def add_boat(boats, name, x, z, yaw, hull_rgb):
    boat = item("Model", [p_str("Name", name)])
    rot = mat_roty(yaw)

    def bp(n, size, off, rgb, mat=M_SMOOTH, rotation=None, **kw):
        ox, oy, oz = off
        c, s = math.cos(yaw), math.sin(yaw)
        px = x + ox * c + oz * s
        pz = z - ox * s + oz * c
        add_part_rot(boat, name + n, size, (px, oy, pz), rgb,
                     rotation if rotation is not None else rot,
                     mat=mat, cancollide=False, castshadow=True, **kw)

    bp("_hull", (46, 8, 16), (0, 3, 0), hull_rgb, mat=M_WOOD)
    bp("_cabin", (16, 8, 11), (-8, 11, 0), (222, 214, 198))
    bp("_mast", (32, 1.8, 1.8), (4, 20, 0), (116, 84, 56), mat=M_WOOD,
       rotation=mat_rotz(math.pi / 2))
    bp("_sail", (1.2, 24, 15), (4, 22, 4.2), (240, 238, 228),
       rotation=mat_roty(0.0),
       transparency=0.06)
    boats[3].append(boat)


def build_boats(root):
    boats = item("Model", [p_str("Name", "Boats")])
    add_boat(boats, "Boat1", 820, -720, 0.25, (88, 62, 48))
    add_boat(boats, "Boat2", -420, 860, 3.4, (52, 58, 74))
    add_boat(boats, "Boat3", 1550, 1280, 1.8, (110, 70, 52))
    root[3].append(boats)


# ---------------------------------------------------------------------------
# Освещение / камера / спавн
# ---------------------------------------------------------------------------

def build_lighting(root_children):
    lighting = item("Lighting", [
        p_str("Name", "Lighting"),
        p_color3("Ambient", (52, 48, 46)),
        p_color3("OutdoorAmbient", (70, 64, 58)),
        p_float("Brightness", 2.6),
        p_float("ClockTime", 16.4),
        p_float("ExposureCompensation", 0.12),
        p_float("EnvironmentDiffuseScale", 1),
        p_float("EnvironmentSpecularScale", 1),
        p_color3("FogColor", (178, 168, 152)),
        p_float("FogStart", 1200),
        p_float("FogEnd", 7000),
        p_float("GeographicLatitude", 12),
        p_bool("GlobalShadows", True),
        p_float("ShadowSoftness", 0.35),
    ])
    lighting[3].append(item("Atmosphere", [
        p_str("Name", "Atmosphere"),
        p_color3("Color", (199, 184, 158)),
        p_color3("Decay", (92, 100, 116)),
        p_float("Density", 0.36),
        p_float("Glare", 0.32),
        p_float("Haze", 1.9),
        p_float("Offset", 0.25),
    ]))
    lighting[3].append(item("BloomEffect", [
        p_str("Name", "Bloom"),
        p_float("Intensity", 0.65),
        p_float("Size", 32),
        p_float("Threshold", 1.05),
    ]))
    lighting[3].append(item("SunRaysEffect", [
        p_str("Name", "SunRays"),
        p_float("Intensity", 0.14),
        p_float("Spread", 0.85),
    ]))
    lighting[3].append(item("ColorCorrectionEffect", [
        p_str("Name", "WarmTone"),
        p_float("Brightness", 0.02),
        p_float("Contrast", 0.08),
        p_float("Saturation", 0.12),
        p_color3("TintColor", (255, 236, 214)),
    ]))
    root_children.append(lighting)


def build_workspace_kids(ws):
    # камера
    cam_pos = (-2350.0, 285.0, 820.0)
    target = (300.0, 165.0, -80.0)
    look = (target[0] - cam_pos[0], target[1] - cam_pos[1], target[2] - cam_pos[2])
    cam = item("Camera", [
        p_str("Name", "CurrentCamera"),
        p_cframe("CFrame", cam_pos, mat_look(look)),
        p_float("FieldOfView", 70),
        p_token("CameraType", 5),
    ])
    ws[3].append(cam)
    ws[2].append(p_ref("CurrentCamera", cam[1]))

    # спавн на западной части моста
    spawn = item("SpawnLocation", [
        p_str("Name", "Spawn"),
        p_bool("Anchored", True),
        p_bool("CanCollide", True),
        p_color3uint8("Color3uint8", (120, 130, 140)),
        p_cframe("CFrame", (-1835.0, DECK_TOP + 0.5, 0), mat_id()),
        p_int("Duration", 0),
        p_bool("Enabled", True),
        p_token("Material", M_CONCRETE),
        p_bool("Neutral", True),
        p_token("TopSurface", 0),
        p_token("BottomSurface", 0),
        p_float("Transparency", 0),
        p_v3("size", 26, 1, 26),
    ])
    ws[3].append(spawn)


# ---------------------------------------------------------------------------
# Скрипты
# ---------------------------------------------------------------------------

LUA_ASSEMBLER = r'''--[[
	МОСТ ЗАЛИВА — сборка по блокам.

	Как только вы нажимаете Play:
	  1) башни-пилоны вырастают снизу вверх блок за блоком;
	  2) полотно наращивается консолью от каждой башни в обе стороны —
	     в точности как строят настоящие вантовые мосты (Мапуто-Катембе,
	     мосты через Неву);
	  3) вслед за каждым блоком полотна на место «выстреливают» ванты;
	  4) последними зажигаются фонари.

	У западного входа на мост стоит пульт: нажмите E, чтобы пересобрать мост.
]]

local TweenService = game:GetService("TweenService")

local bridge = script.Parent
local pylons = bridge:WaitForChild("Pylons")
local deck = bridge:WaitForChild("Deck")
local cables = bridge:WaitForChild("Cables")
local lamps = bridge:WaitForChild("Lamps")
local console = bridge:WaitForChild("Console")
local prompt = console:WaitForChild("RebuildPrompt")

local STAGE_LIFT = 260
local entries = {}
local building = false

local function stepOf(name)
	local s = string.match(name, "s(%d+)")
	return (s and tonumber(s)) or 0
end

local function register(part, kind, step)
	part.Anchored = true
	local e = {
		part = part,
		cf = part.CFrame,
		size = part.Size,
		transparency = part.Transparency,
		collide = part.CanCollide,
		kind = kind,
		step = step,
	}
	if kind == "cable" then
		local len = e.size.Z
		local look = e.cf.LookVector
		local towerEnd = e.cf.Position - look * (len * 0.5)
		e.startCF = CFrame.lookAt(towerEnd + look * 0.5, towerEnd + look * 8)
		e.startSize = Vector3.new(e.size.X, e.size.Y, 1)
	end
	table.insert(entries, e)
end

for _, m in ipairs(deck:GetChildren()) do
	local step = stepOf(m.Name)
	for _, p in ipairs(m:GetChildren()) do
		if p:IsA("BasePart") then
			register(p, "deck", step)
		end
	end
end

for _, p in ipairs(cables:GetChildren()) do
	if p:IsA("BasePart") then
		register(p, "cable", stepOf(p.Name))
	end
end

for _, p in ipairs(lamps:GetChildren()) do
	if p:IsA("BasePart") then
		register(p, "lamp", stepOf(p.Name))
	end
end

for _, p in ipairs(pylons:GetChildren()) do
	if p:IsA("BasePart") then
		register(p, "pylon", stepOf(p.Name))
	end
end

local function stage(e, i)
	e.part.CanCollide = false
	if e.kind == "cable" then
		e.part.CFrame = e.startCF
		e.part.Size = e.startSize
		e.part.Transparency = 1
		return
	end
	local angle = ((e.step * 47 + i * 29) % 180) - 90
	local lift = (e.kind == "pylon") and -STAGE_LIFT or STAGE_LIFT
	e.part.CFrame = e.cf * CFrame.new(0, lift, 0) * CFrame.Angles(0, math.rad(angle), 0)
	e.part.Transparency = 1
end

local function play(e, duration)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local goal = {CFrame = e.cf, Size = e.size, Transparency = e.transparency}
	TweenService:Create(e.part, info, goal):Play()
	e.part.CanCollide = e.collide
end

local function maxStepOf(kind)
	local m = 0
	for _, e in ipairs(entries) do
		if e.kind == kind and e.step > m then
			m = e.step
		end
	end
	return m
end

local function build()
	if building then
		return
	end
	building = true
	prompt.Enabled = false

	for i, e in ipairs(entries) do
		stage(e, i)
	end
	task.wait(0.5)

	-- Фаза 1: пилоны растут снизу вверх
	local sMax = maxStepOf("pylon")
	for s = 0, sMax do
		for _, e in ipairs(entries) do
			if e.kind == "pylon" and e.step == s then
				play(e, 0.32)
			end
		end
		task.wait(0.22)
	end

	-- Фаза 2: полотно консолью + ванты
	sMax = maxStepOf("deck")
	for s = 0, sMax do
		for _, e in ipairs(entries) do
			if e.kind == "deck" and e.step == s then
				play(e, 0.6)
			elseif e.kind == "cable" and e.step == s then
				play(e, 0.5)
			end
		end
		task.wait(0.15)
	end

	-- Фаза 3: фонари
	sMax = maxStepOf("lamp")
	for s = 0, sMax do
		for _, e in ipairs(entries) do
			if e.kind == "lamp" and e.step == s then
				play(e, 0.35)
			end
		end
		task.wait(0.08)
	end

	building = false
	prompt.Enabled = true
end

prompt.Triggered:Connect(function()
	task.spawn(build)
end)

task.wait(1.2)
build()
'''

LUA_AMBIENCE = r'''--[[
	Атмосфера бухты: лодки плывут под мостом, блики на воде мерцают,
	маяк и оголощки башен мягко пульсируют.
]]

local RunService = game:GetService("RunService")

local boats = workspace:WaitForChild("Boats")
local water = workspace:WaitForChild("Water")
local glints = water:WaitForChild("WaterGlints")
local scenery = workspace:WaitForChild("Scenery")
local lighthouse = scenery:WaitForChild("Lighthouse")

local boatData = {}
for i, boat in ipairs(boats:GetChildren()) do
	boatData[i] = {
		model = boat,
		base = boat:GetPivot(),
		phase = i * 2.1,
		range = 160 + i * 70,
		speed = 0.028 / (1 + i * 0.35),
	}
end

local glintParts = {}
for _, g in ipairs(glints:GetChildren()) do
	if g:IsA("BasePart") then
		table.insert(glintParts, g)
	end
end

local beacon = lighthouse:FindFirstChild("Beacon", true)

RunService.Heartbeat:Connect(function()
	local t = os.clock()

	for _, b in ipairs(boatData) do
		local off = math.sin(t * b.speed + b.phase) * b.range
		local bob = math.sin(t * 0.9 + b.phase) * 1.3
		b.model:PivotTo(b.base * CFrame.new(off, bob, 0))
	end

	for _, g in ipairs(glintParts) do
		g.Transparency = 0.8 + 0.17 * math.sin(t * 0.8 + g.Position.X * 0.011)
	end

	if beacon then
		beacon.Brightness = 1.6 + 1.4 * (0.5 + 0.5 * math.sin(t * 1.3))
	end
end)
'''


def build_scripts(root_children, ws):
    assembler = item("Script", [
        p_str("Name", "BridgeAssembler"),
        p_protected("Source", LUA_ASSEMBLER),
    ])
    # скрипт живёт внутри модели Bridge
    for ch in ws[3]:
        if ch[0] == "Model" and any(p.startswith('<string name="Name">Bridge')
                                    for p in ch[2]):
            ch[3].append(assembler)
            break

    sss = item("ServerScriptService", [p_str("Name", "ServerScriptService")])
    sss[3].append(item("Script", [
        p_str("Name", "Ambience"),
        p_protected("Source", LUA_AMBIENCE),
    ]))
    root_children.append(sss)


# ---------------------------------------------------------------------------
# Сборка файла
# ---------------------------------------------------------------------------

def main():
    ws = item("Workspace", [
        p_str("Name", "Workspace"),
        p_bool("StreamingEnabled", False),
        p_float("Gravity", 196.2),
        p_float("FallenPartsDestroyHeight", -250),
    ])
    build_workspace_kids(ws)
    bridge = build_bridge(ws)
    build_water(ws)
    build_scenery(ws)
    build_boats(ws)

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

    n_items = xml.count("<Item ")
    print("Готово: %s" % OUT_PATH)
    print("Инстансов: %d, размер: %.1f КБ" % (n_items, len(xml) / 1024))


if __name__ == "__main__":
    main()
