#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Генератор build_a_boat.rbxlx — полная копия Build A Boat For Treasure.

Мир:
  * Зона строительства (зелёная платформа-причал) со стартовым спавном;
  * Магазин блоков у причала (дерево, металл, камень, неон, стекло, золото,
    мрамор, обсидиан, моторы, пропеллеры, пушки, TNT, пружины, лёд, стулья,
    штурвал и т.д.);
  * Рычаг ЗАПУСК — поднимает воду, открывает шлюз и толкает лодку по реке;
  * Длинная река с препятствиями: камни → пилы → водопад → лава → узкие
    ворота → молоты → вращающиеся столбы → финальная рампа;
  * Сундуки с золотом по маршруту и гигантский сундук-сокровище в конце;
  * Система золота, таблицы лидеров, GUI магазина/инвентаря, киянка для
    постройки, физика непритопляемых лодок.

Запуск: python3 tools/generate_build_a_boat.py
Открыть в Roblox Studio: File → Open from File… → build_a_boat.rbxlx
"""

import math
import os
import random

RNG = random.Random(20260929)

OUT_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        "build_a_boat.rbxlx")

# ---------------------------------------------------------------------------
# Материалы / цвета / размеры мира
# ---------------------------------------------------------------------------
WATER_Y = 0.0                # уровень спокойной воды (до запуска чуть ниже)
BUILD_PLATFORM_Y = 4.2       # верх платформы строительства
BUILD_MIN_X, BUILD_MAX_X = -110, 20
BUILD_MIN_Z, BUILD_MAX_Z = -55, 55
BUILD_CX = (BUILD_MIN_X + BUILD_MAX_X) / 2
BUILD_CZ = (BUILD_MIN_Z + BUILD_MAX_Z) / 2

RIVER_START_X = BUILD_MAX_X + 10
RIVER_END_X = 4800.0
RIVER_MIN_Z, RIVER_MAX_Z = -38, 38
RIVER_HALF_W = (RIVER_MAX_Z - RIVER_MIN_Z) / 2  # 38
RIVER_W = RIVER_MAX_Z - RIVER_MIN_Z             # 76

# Материалы (Enum.Material)
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
M_ICE = 1328
M_FABRIC = 1344
M_FORCEFIELD = 1600

# Нормализованный Id формы (enum PartType): Ball=0, Block=1, Cylinder=2
SHAPE_BALL = 0
SHAPE_BLOCK = 1
SHAPE_CYLINDER = 2

# KeyboardKeyCode.E = 101

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
    r, g, b = (c/255.0 for c in rgb)
    return ('<Color3 name="%s"><R>%s</R><G>%s</G><B>%s</B></Color3>' % (n, fmt(r), fmt(g), fmt(b)))
def p_color3uint8(n, rgb):
    r, g, b = rgb
    val = 0xFF000000 | (r<<16) | (g<<8) | b
    return '<Color3uint8 name="%s">%d</Color3uint8>' % (n, val)
def p_v3(n, x, y, z):
    return '<Vector3 name="%s"><X>%s</X><Y>%s</Y><Z>%s</Z></Vector3>' % (n, fmt(x), fmt(y), fmt(z))
def p_v2(n, x, y):
    return '<Vector2 name="%s"><X>%s</X><Y>%s</Y></Vector2>' % (n, fmt(x), fmt(y))
def p_udim(n, s, o):
    return '<UDim name="%s"><S>%s</S><O>%d</O></UDim>' % (n, fmt(s), int(o))
def p_udim2(n, xs, xo, ys, yo):
    return '<UDim2 name="%s"><XS>%s</XS><XO>%d</XO><YS>%s</YS><YO>%d</YO></UDim2>' % (n, fmt(xs), int(xo), fmt(ys), int(yo))
def p_ref(n, r):
    return '<Ref name="%s">%s</Ref>' % (n, r)
def p_cframe(n, pos, mat):
    x, y, z = pos
    r00,r01,r02,r10,r11,r12,r20,r21,r22 = mat
    return ('<CoordinateFrame name="%s">'
            '<X>%s</X><Y>%s</Y><Z>%s</Z>'
            '<R00>%s</R00><R01>%s</R01><R02>%s</R02>'
            '<R10>%s</R10><R11>%s</R11><R12>%s</R12>'
            '<R20>%s</R20><R21>%s</R21><R22>%s</R22>'
            '</CoordinateFrame>' % (n, fmt(x), fmt(y), fmt(z),
                fmt(r00),fmt(r01),fmt(r02),fmt(r10),fmt(r11),fmt(r12),fmt(r20),fmt(r21),fmt(r22)))
def p_protected(n, source):
    assert "]]>" not in source
    return '<ProtectedString name="%s"><![CDATA[%s]]></ProtectedString>' % (n, source)
def p_contentid(n, url):
    return '<ContentId name="%s"><url>%s</url></ContentId>' % (n, esc(url))

def mat_id():
    return (1,0,0, 0,1,0, 0,0,1)
def mat_from_ru(right, up):
    rx,ry,rz = right; ux,uy,uz = up
    bx = ry*uz - rz*uy; by = rz*ux - rx*uz; bz = rx*uy - ry*ux
    return (rx,ux,bx, ry,uy,by, rz,uz,bz)
def mat_rotx(a):
    c,s = math.cos(a),math.sin(a)
    return mat_from_ru((1,0,0),(0,c,s))
def mat_roty(a):
    c,s = math.cos(a),math.sin(a)
    return mat_from_ru((c,0,-s),(0,1,0))
def mat_rotz(a):
    c,s = math.cos(a),math.sin(a)
    return mat_from_ru((c,s,0),(-s,c,0))
def _norm(v):
    l = math.sqrt(v[0]*v[0]+v[1]*v[1]+v[2]*v[2]) or 1.0
    return (v[0]/l, v[1]/l, v[2]/l)
def _cross(a,b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def mat_look(look):
    look = _norm(look); back = (-look[0],-look[1],-look[2])
    up = (0,1,0)
    if abs(look[0])<1e-6 and abs(look[1])>0.99: up = (1,0,0)
    right = _norm(_cross(up, back))
    up = _cross(back, right)
    return mat_from_ru(right, up)

def item(class_name, props, children=()):
    return (class_name, B.referent(), list(props), list(children))

def emit(it, indent=0):
    cls, ref, props, children = it
    pad = "\t"*indent
    out = [pad + '<Item class="%s" referent="%s">' % (cls, ref),
           pad + "\t<Properties>"]
    for p in props:
        out.append(pad + "\t\t" + p)
    out.append(pad + "\t</Properties>")
    for ch in children:
        out.extend(emit(ch, indent+1))
    out.append(pad + "</Item>")
    return out

def part_props(name, size, pos, rgb, mat=M_SMOOTH, transparency=0.0, reflectance=0.0,
               rotation=None, shape=None, cancollide=True, castshadow=True, anchored=True):
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

# ---------------------------------------------------------------------------
# ЗОНА СТРОИТЕЛЬСТВА
# ---------------------------------------------------------------------------

def build_build_area(root):
    ba = item("Model", [p_str("Name", "BuildArea")])

    # Пирс / платформа под строительство
    add_part(ba, "Platform", (BUILD_MAX_X - BUILD_MIN_X + 8, 4, BUILD_MAX_Z - BUILD_MIN_Z + 20),
             ((BUILD_MIN_X+BUILD_MAX_X)/2, BUILD_PLATFORM_Y-2, 0),
             (96, 104, 108), mat=M_CONCRETE)
    # Разметка зоны строительства (зелёная плитка)
    add_part(ba, "BuildMat", (BUILD_MAX_X - BUILD_MIN_X - 4, 0.4, BUILD_MAX_Z - BUILD_MIN_Z - 4),
             ((BUILD_MIN_X+BUILD_MAX_X)/2, BUILD_PLATFORM_Y+0.2, 0),
             (60, 170, 70), mat=M_PLASTIC, cancollide=False)
    # Сетка
    for i in range(int((BUILD_MAX_X-BUILD_MIN_X)/4)):
        x = BUILD_MIN_X + 2 + i*4
        add_part(ba, "GridL_x%d" % i, (0.12, 0.06, BUILD_MAX_Z-BUILD_MIN_Z-4),
                 (x, BUILD_PLATFORM_Y+0.45, 0), (255,255,255), mat=M_SMOOTH,
                 cancollide=False, castshadow=False, transparency=0.5)
    for j in range(int((BUILD_MAX_Z-BUILD_MIN_Z)/4)):
        z = BUILD_MIN_Z + 2 + j*4
        add_part(ba, "GridL_z%d" % j, (BUILD_MAX_X-BUILD_MIN_X-4, 0.06, 0.12),
                 ((BUILD_MIN_X+BUILD_MAX_X)/2, BUILD_PLATFORM_Y+0.45, z), (255,255,255),
                 mat=M_SMOOTH, cancollide=False, castshadow=False, transparency=0.5)

    # Ограждение по краям платформы (кроме реки)
    add_part(ba, "FenceBack", (2, 6, BUILD_MAX_Z-BUILD_MIN_Z+20),
             (BUILD_MIN_X-3, BUILD_PLATFORM_Y+3, 0), (160,160,164), mat=M_METAL)
    add_part(ba, "FenceSideA", (BUILD_MAX_X-BUILD_MIN_X+8, 6, 2),
             ((BUILD_MIN_X+BUILD_MAX_X)/2, BUILD_PLATFORM_Y+3, BUILD_MAX_Z+9),
             (160,160,164), mat=M_METAL)
    add_part(ba, "FenceSideB", (BUILD_MAX_X-BUILD_MIN_X+8, 6, 2),
             ((BUILD_MIN_X+BUILD_MAX_X)/2, BUILD_PLATFORM_Y+3, BUILD_MIN_Z-9),
             (160,160,164), mat=M_METAL)

    # Шлюзовые ворота (закрывают реку до запуска)
    gate = item("Model", [p_str("Name", "StartGate")])
    add_part(gate, "GateLeft", (2, 14, RIVER_HALF_W),
             (RIVER_START_X-1, BUILD_PLATFORM_Y+3, -RIVER_HALF_W/2),
             (220, 60, 50), mat=M_METAL)
    add_part(gate, "GateRight", (2, 14, RIVER_HALF_W),
             (RIVER_START_X-1, BUILD_PLATFORM_Y+3, RIVER_HALF_W/2),
             (220, 60, 50), mat=M_METAL)
    ba[3].append(gate)

    # Рычаг запуска
    lever = item("Model", [p_str("Name", "LaunchLever")])
    base = item("Part", part_props("LeverBase", (10, 3, 10),
                (BUILD_MIN_X+15, BUILD_PLATFORM_Y+1.5, BUILD_MAX_Z+18),
                (60,66,72), mat=M_METAL))
    base[3].append(item("ProximityPrompt", [
        p_str("Name", "LaunchPrompt"),
        p_str("ActionText", "ЗАПУСТИТЬ ЛОДКУ"),
        p_str("ObjectText", "Рычаг запуска"),
        p_float("HoldDuration", 0.5),
        p_float("MaxActivationDistance", 14),
        p_bool("RequiresLineOfSight", False),
        p_token("KeyboardKeyCode", 101),
        p_color3("ObjectColor", (220,60,50)),
    ]))
    lever[3].append(base)
    arm = item("Part", part_props("LeverArm", (2, 12, 2),
              (BUILD_MIN_X+15, BUILD_PLATFORM_Y+9, BUILD_MAX_Z+18),
              (210,50,45), mat=M_METAL, shape=SHAPE_CYLINDER,
              rotation=mat_rotz(math.pi/2)))
    lever[3].append(arm)
    knob = item("Part", part_props("Knob", (4,4,4),
              (BUILD_MIN_X+15, BUILD_PLATFORM_Y+15, BUILD_MAX_Z+18),
              (230,200,60), mat=M_NEON, shape=SHAPE_BALL,
              transparency=0.2))
    add_light(knob, "Glow", (255,210,80), 1.2, 20)
    lever[3].append(knob)
    sign = item("Part", part_props("Sign", (14,8,0.6),
              (BUILD_MIN_X+15, BUILD_PLATFORM_Y+6, BUILD_MAX_Z+24),
              (180,40,40), mat=M_SMOOTH, rotation=mat_look((0,0,1))))
    gui = item("SurfaceGui", [
        p_str("Name","SignGui"), p_token("Face",5), p_bool("AlwaysOnTop",True),
        p_v2("CanvasSize",280,160)])
    gui[3].append(item("TextLabel",[
        p_str("Name","T"), p_str("Text","ЗАПУСК"), p_token("Font",19),
        p_bool("TextScaled",True), p_color3("TextColor3",(255,230,180)),
        p_color3("BackgroundColor3",(120,30,30)), p_float("BackgroundTransparency",1),
        p_udim2("Position",0,0,0.1,0), p_udim2("Size",1,0,0.8,0)]))
    sign[3].append(gui)
    lever[3].append(sign)
    ba[3].append(lever)

    # Спавн игроков
    spawn = item("SpawnLocation", [
        p_str("Name", "PlayerSpawn"),
        p_bool("Anchored", True), p_bool("CanCollide", True),
        p_color3uint8("Color3uint8", (80, 180, 255)),
        p_cframe("CFrame", (BUILD_MIN_X+8, BUILD_PLATFORM_Y+0.5, 0), mat_id()),
        p_int("Duration", 0), p_bool("Enabled", True),
        p_token("Material", M_NEON), p_bool("Neutral", True),
        p_token("TopSurface",0), p_token("BottomSurface",0),
        p_float("Transparency", 0.3), p_v3("size", 12,1,12),
        p_bool("AllowTeamChangeOnTouch", False),
    ])
    ba[3].append(spawn)

    # Несколько декоративных стартовых блоков (показать, как строить)
    demo = item("Model", [p_str("Name", "DemoBlocks")])
    for i in range(3):
        add_part(demo, "DemoW%d" % i, (4,2,4),
                 (BUILD_MIN_X+30+i*4, BUILD_PLATFORM_Y+2, 0),
                 (180,140,90), mat=M_WOOD)
    ba[3].append(demo)

    root[3].append(ba)
    return ba

# ---------------------------------------------------------------------------
# МАГАЗИН
# ---------------------------------------------------------------------------

SHOP_BLOCKS = [
    # name,           color,        material,    cost, shape,     size
    ("WoodBlock",     (180,140,90), M_WOOD,        5,  SHAPE_BLOCK, (4,2,4)),
    ("Plank",         (200,160,100),M_WOOD,        8,  SHAPE_BLOCK, (8,1,4)),
    ("StoneBlock",    (140,140,145),M_CONCRETE,   15,  SHAPE_BLOCK, (4,4,4)),
    ("MetalBlock",    (170,175,180),M_METAL,      25,  SHAPE_BLOCK, (4,2,4)),
    ("GlassBlock",    (190,220,240),M_GLASS,      20,  SHAPE_BLOCK, (4,2,4)),
    ("NeonBlock",     (255,80,200), M_NEON,       60,  SHAPE_BLOCK, (4,2,4)),
    ("GoldBlock",     (255,210,60), M_METAL,     150,  SHAPE_BLOCK, (4,2,4)),
    ("Marble",        (240,238,232),M_SMOOTH,    100,  SHAPE_BLOCK, (4,2,4)),
    ("Obsidian",      (40,25,55),   M_SLATE,     200,  SHAPE_BLOCK, (4,2,4)),
    ("Ice",           (180,230,255),M_ICE,        80,  SHAPE_BLOCK, (4,2,4)),
    ("Titanium",      (120,130,150),M_METAL,     350,  SHAPE_BLOCK, (4,2,4)),
    ("Concrete",      (120,125,128),M_CONCRETE,   40,  SHAPE_BLOCK, (4,2,4)),
    ("WoodPole",      (120,80,50),  M_WOOD,       12,  SHAPE_CYLINDER, (2,8,2)),
    ("Chair",         (90,60,40),   M_WOOD,       35,  SHAPE_BLOCK, (4,4,4)),
    ("Wheel",         (120,80,40),  M_WOOD,       75,  SHAPE_CYLINDER, (6,2,6)),
    ("Engine",        (80,85,95),   M_METAL,     400,  SHAPE_BLOCK, (6,4,6)),
    ("Propeller",     (160,160,170),M_METAL,     200,  SHAPE_CYLINDER, (8,1,2)),
    ("Cannon",        (70,75,80),   M_METAL,     800,  SHAPE_CYLINDER, (8,4,4)),
    ("TNT",           (200,50,40),  M_PLASTIC,   150,  SHAPE_BLOCK, (4,4,4)),
    ("Spring",        (200,200,60), M_METAL,     250,  SHAPE_CYLINDER, (3,4,3)),
    ("Magnet",        (200,40,40),  M_METAL,     600,  SHAPE_BLOCK, (5,3,5)),
    ("JetTurbine",    (90,100,110), M_METAL,    1200,  SHAPE_CYLINDER, (5,6,8)),
]

def build_shop(root):
    shop = item("Model", [p_str("Name", "Shop")])
    sx, sz, sy = BUILD_MIN_X - 20, BUILD_MAX_Z + 35, BUILD_PLATFORM_Y
    # пол
    add_part(shop, "Floor", (34, 1, 34), (sx, sy, sz), (100, 90, 80), mat=M_WOOD)
    # стены
    add_part(shop, "WallBack", (34, 16, 1), (sx, sy+8, sz-16), (200,170,130), mat=M_WOOD)
    add_part(shop, "WallL", (1, 16, 34), (sx-16, sy+8, sz), (200,170,130), mat=M_WOOD)
    add_part(shop, "WallR", (1, 16, 34), (sx+16, sy+8, sz), (200,170,130), mat=M_WOOD)
    # крыша
    add_part(shop, "Roof", (40, 1, 40), (sx, sy+16, sz), (160,50,40), mat=M_BRICK)
    # вывеска "SHOP"
    sign = item("Part", part_props("ShopSign", (26, 10, 0.6),
              (sx, sy+12, sz+15), (180,40,40), mat=M_SMOOTH,
              rotation=mat_look((0,0,-1))))
    sg = item("SurfaceGui", [p_str("Name","T"), p_token("Face",5),
        p_bool("AlwaysOnTop",True), p_v2("CanvasSize",520,200)])
    sg[3].append(item("TextLabel",[
        p_str("Name","T"), p_str("Text","МАГАЗИН БЛОКОВ"),
        p_token("Font",19), p_bool("TextScaled",True),
        p_color3("TextColor3",(255,240,180)),
        p_color3("BackgroundColor3",(120,30,30)), p_float("BackgroundTransparency",1),
        p_udim2("Position",0,0,0.1,0), p_udim2("Size",1,0,0.8,0)]))
    sign[3].append(sg)
    shop[3].append(sign)

    # Витрина блоков внутри (демонстрация)
    for i,(name,rgb,m,cost,shape,size) in enumerate(SHOP_BLOCKS[:18]):
        bx = sx - 13 + (i%6)*5
        bz = sz - 13 + (i//6)*8
        sh = item("Model", [p_str("Name", "Show_"+name)])
        add_part_shape(sh, "ShowBase", (5,1,5), (bx, sy+0.6, bz),
                       (80,70,60), SHAPE_BLOCK, mat=M_WOOD)
        add_part_shape(sh, "ShowBlock", size, (bx, sy+1.6+size[1]/2, bz),
                       rgb, shape, mat=m, cancollide=False)
        # бирка с ценой
        tag = item("Part", part_props("PriceTag", (4,2,0.2),
                  (bx, sy+0.5, bz+2.6), (255,255,255), mat=M_SMOOTH,
                  cancollide=False, rotation=mat_look((0,0,-1))))
        tg = item("SurfaceGui", [p_str("Name","PG"), p_token("Face",5),
            p_bool("AlwaysOnTop",True), p_v2("CanvasSize",120,60)])
        tg[3].append(item("TextLabel",[
            p_str("Name","P"), p_str("Text","%dG" % cost),
            p_token("Font",19), p_bool("TextScaled",True),
            p_color3("TextColor3",(255,210,60)), p_float("BackgroundTransparency",1),
            p_udim2("Size",1,0,1,0)]))
        tag[3].append(tg)
        sh[3].append(tag)
        shop[3].append(sh)

    # Прилавок с NPC (простой блок как "продавец")
    add_part(shop, "Counter", (20, 5, 8), (sx, sy+2.5, sz-10), (120,80,50), mat=M_WOOD)
    npc = item("Part", part_props("ShopKeeper", (6, 8, 4),
              (sx, sy+9, sz-10), (230,200,170), mat=M_SMOOTH, shape=SHAPE_BLOCK))
    add_part_shape(npc, "Head", (5,5,5), (sx, sy+15, sz-10),
                   (240,210,170), SHAPE_BALL, mat=M_SMOOTH)
    add_part_shape(npc, "Hat", (7,2,7), (sx, sy+18.5, sz-10),
                   (40,40,40), SHAPE_BLOCK, mat=M_SMOOTH)
    npc[3].append(item("ProximityPrompt", [
        p_str("Name","ShopPrompt"),
        p_str("ActionText","ОТКРЫТЬ МАГАЗИН"),
        p_str("ObjectText","Продавец"),
        p_float("HoldDuration",0.2),
        p_float("MaxActivationDistance",12),
        p_bool("RequiresLineOfSight",False),
        p_token("KeyboardKeyCode",101),
    ]))
    shop[3].append(npc)

    # Невидимый сенсор-кирпич, который открывает магазин при входе
    sensor = item("Part", part_props("ShopSensor", (32,6,32),
                 (sx, sy+3, sz), (255,0,255), mat=M_NEON,
                 transparency=1.0, cancollide=False, anchored=True))
    shop[3].append(sensor)

    root[3].append(shop)
    return shop

# ---------------------------------------------------------------------------
# ТАБЛИЦЫ ЛИДЕРОВ
# ---------------------------------------------------------------------------

def build_leaderboards(root):
    lb = item("Model", [p_str("Name", "Leaderboards")])
    lx = BUILD_MIN_X - 60
    lz = 0
    # подставка
    add_part(lb, "Base", (16, 6, 10), (lx, 3, lz), (100,100,105), mat=M_CONCRETE)
    # доска золота
    board1 = item("Part", part_props("GoldBoard", (1, 22, 28),
                (lx+2, 17, lz-10), (40, 90, 160), mat=M_SMOOTH,
                rotation=mat_roty(math.pi/2)))
    sg = item("SurfaceGui", [p_str("Name","BoardGui"), p_token("Face",4),
        p_bool("AlwaysOnTop",True), p_v2("CanvasSize",260,560)])
    sg[3].append(item("TextLabel",[
        p_str("Name","Title"), p_str("Text","ТОЛЬКО ЗОЛОТА"),
        p_token("Font",19), p_bool("TextScaled",True),
        p_color3("TextColor3",(255,220,100)),
        p_color3("BackgroundColor3",(20,40,80)), p_float("BackgroundTransparency",0),
        p_udim2("Position",0,0,0,0), p_udim2("Size",1,0,0.18,0)]))
    for k in range(8):
        sg[3].append(item("TextLabel",[
            p_str("Name","L%d"%k), p_str("Text","---"),
            p_token("Font",3), p_bool("TextScaled",True),
            p_color3("TextColor3",(255,255,255)), p_float("BackgroundTransparency",1),
            p_udim2("Position",0.05,0,0.2+k*0.095,0), p_udim2("Size",0.9,0,0.085,0)]))
    board1[3].append(sg)
    lb[3].append(board1)

    # доска дистанции
    board2 = item("Part", part_props("DistBoard", (1, 22, 28),
                (lx+2, 17, lz+10), (40, 120, 90), mat=M_SMOOTH,
                rotation=mat_roty(math.pi/2)))
    sg2 = item("SurfaceGui", [p_str("Name","BoardGui"), p_token("Face",4),
        p_bool("AlwaysOnTop",True), p_v2("CanvasSize",260,560)])
    sg2[3].append(item("TextLabel",[
        p_str("Name","Title"), p_str("Text","ДАЛЬНОСТЬ"),
        p_token("Font",19), p_bool("TextScaled",True),
        p_color3("TextColor3",(180,255,200)),
        p_color3("BackgroundColor3",(30,60,30)), p_float("BackgroundTransparency",0),
        p_udim2("Position",0,0,0,0), p_udim2("Size",1,0,0.18,0)]))
    for k in range(8):
        sg2[3].append(item("TextLabel",[
            p_str("Name","L%d"%k), p_str("Text","---"),
            p_token("Font",3), p_bool("TextScaled",True),
            p_color3("TextColor3",(255,255,255)), p_float("BackgroundTransparency",1),
            p_udim2("Position",0.05,0,0.2+k*0.095,0), p_udim2("Size",0.9,0,0.085,0)]))
    board2[3].append(sg2)
    lb[3].append(board2)

    root[3].append(lb)

# ---------------------------------------------------------------------------
# РЕКА + БЕРЕГА
# ---------------------------------------------------------------------------

def add_rock(parent, name, x, y, z, s, rgb=(100,98,102)):
    add_part(parent, name, (s*1.6, s, s*1.2), (x, y+s*0.4, z),
             rgb, mat=M_SLATE,
             rotation=mat_rotz(RNG.uniform(-0.3,0.3)))

def build_river(root):
    river = item("Model", [p_str("Name", "River")])

    # Дно реки (камень/песок)
    add_part(river, "RiverFloor", (RIVER_END_X - RIVER_START_X + 40, 6, RIVER_W+6),
             ((RIVER_START_X+RIVER_END_X)/2, -5, 0),
             (70,72,80), mat=M_SLATE)

    # Вода (изначально немного ниже платформы, при запуске поднимается)
    add_part(river, "Water", (RIVER_END_X - RIVER_START_X + 60, 4, RIVER_W+20),
             ((RIVER_START_X+RIVER_END_X)/2, WATER_Y - 2, 0),
             (40,110,170), mat=M_GLASS, transparency=0.3, reflectance=0.4,
             cancollide=False, castshadow=False)
    # Маркер воды для физики плавучести (невидимый, но CanCollide=false,
    # а скрипт сам будет толкать лодки — для визуала достаточно)
    water_top = add_part(river, "WaterTop", (RIVER_END_X-RIVER_START_X+70, 0.2, RIVER_W+30),
             ((RIVER_START_X+RIVER_END_X)/2, WATER_Y+0.1, 0),
             (120,200,240), mat=M_GLASS, transparency=0.7,
             cancollide=False, castshadow=False)

    # Берега реки (стены канала)
    add_part(river, "BankL", (RIVER_END_X - RIVER_START_X + 60, 20, 6),
             ((RIVER_START_X+RIVER_END_X)/2, 8, -RIVER_HALF_W - 4),
             (100,110,80), mat=M_GRASS)
    add_part(river, "BankR", (RIVER_END_X - RIVER_START_X + 60, 20, 6),
             ((RIVER_START_X+RIVER_END_X)/2, 8, RIVER_HALF_W + 4),
             (100,110,80), mat=M_GRASS)
    # Тропинки/полоса земли по краям
    add_part(river, "LandL", (RIVER_END_X - RIVER_START_X + 200, 10, 200),
             ((RIVER_START_X+RIVER_END_X)/2, -2, -RIVER_HALF_W - 110),
             (90,120,70), mat=M_GRASS)
    add_part(river, "LandR", (RIVER_END_X - RIVER_START_X + 200, 10, 200),
             ((RIVER_START_X+RIVER_END_X)/2, -2, RIVER_HALF_W + 110),
             (90,120,70), mat=M_GRASS)

    # ---- СЕКЦИИ ПРЕПЯТСТВИЙ ----
    obstacles = item("Folder", [p_str("Name", "Obstacles")])

    # 1) СЕКЦИЯ КАМНЕЙ (x 200-600)
    rocks_sec = item("Folder", [p_str("Name", "Sec1_Rocks")])
    for i in range(30):
        x = RNG.uniform(220, 600)
        z = RNG.uniform(-RIVER_HALF_W+6, RIVER_HALF_W-6)
        s = RNG.uniform(6, 18)
        add_rock(rocks_sec, "Rock%d"%i, x, -1, z, s)
    obstacles[3].append(rocks_sec)

    # 2) ПИЛЫ / ВРАЩАЮЩИЕСЯ ДИСКИ (x 650-1300)
    saws_sec = item("Folder", [p_str("Name", "Sec2_Saws")])
    saw_positions = []
    for i in range(12):
        x = 700 + i*55
        side = -1 if i%2==0 else 1
        z = side * RNG.uniform(8, 28)
        saw_positions.append((x, z, side))
    for idx,(x,z,side) in enumerate(saw_positions):
        saw = item("Model", [p_str("Name","Saw%d"%idx)])
        # опора
        add_part_shape(saw, "Pole", (3, 18, 3), (x, 9, z), (80,80,85),
                       SHAPE_CYLINDER, mat=M_METAL, rotation=mat_rotx(math.pi/2))
        # лезвие пилы (диск)
        blade = item("Part", part_props("Blade", (22, 1, 22),
                    (x, 6, z), (180,185,190), mat=M_METAL, shape=SHAPE_CYLINDER,
                    rotation=mat_rotx(math.pi/2), anchored=True, cancollide=True))
        saw[3].append(blade)
        # зубья (небольшие кубики по периметру)
        for t in range(12):
            a = t*math.pi*2/12
            tx = x + math.cos(a)*12
            tz = z + math.sin(a)*12
            add_part(saw, "Tooth%d"%t, (2,2,2), (tx,6,tz),
                     (120,120,130), mat=M_METAL)
        saws_sec[3].append(saw)
    obstacles[3].append(saws_sec)

    # 3) ВОДОПАД (провал) x 1350-1500
    waterfall = item("Folder", [p_str("Name", "Sec3_Waterfall")])
    # обрыв (дно ниже)
    add_part(waterfall, "Cliff", (160, 20, RIVER_W+10), (1420, -20, 0),
             (60,70,90), mat=M_SLATE)
    # каскад
    add_part(waterfall, "WaterSheet", (20, 30, RIVER_W+4), (1340, -5, 0),
             (100,180,230), mat=M_GLASS, transparency=0.35, cancollide=False)
    # бассейн внизу (ниже уровнем)
    add_part(waterfall, "PoolFloor", (240, 4, RIVER_W+10), (1540, -35, 0),
             (70,75,85), mat=M_SLATE)
    add_part(waterfall, "PoolWater", (240, 8, RIVER_W+10), (1540, -30, 0),
             (40,110,170), mat=M_GLASS, transparency=0.3, reflectance=0.3, cancollide=False)
    # Скалы-пороги
    for i in range(6):
        add_rock(waterfall, "FallRock%d"%i, 1340+i*8, -1, RNG.uniform(-25,25), RNG.uniform(8,14))
    obstacles[3].append(waterfall)

    # 4) ЛАВА x 1700-2200
    lava_sec = item("Folder", [p_str("Name", "Sec4_Lava")])
    add_part(lava_sec, "LavaPool", (500, 1, RIVER_W), (1950, WATER_Y+0.05, 0),
             (220,80,20), mat=M_NEON, transparency=0.2, cancollide=False,
             castshadow=False)
    # Островки-каменюги, торчащие из лавы, чтоб перепрыгивать (препятствия и опоры)
    for i in range(18):
        x = 1720 + i*28
        z = RNG.uniform(-28,28)
        add_part(lava_sec, "LavaRock%d"%i, (14, 8, 14), (x, WATER_Y+3, z),
                 (60,40,30), mat=M_SLATE)
    # огоньки (неоновые точки)
    for i in range(25):
        x = RNG.uniform(1720,2200); z = RNG.uniform(-RIVER_HALF_W, RIVER_HALF_W)
        add_part_shape(lava_sec, "Spark%d"%i, (3,8+RNG.random()*6,3), (x, WATER_Y+2, z),
                       (255,160,40), SHAPE_BALL, mat=M_NEON, cancollide=False,
                       transparency=0.5, castshadow=False)
    obstacles[3].append(lava_sec)

    # 5) УЗКИЕ ВОРОТА x 2250-2750
    gates_sec = item("Folder", [p_str("Name", "Sec5_NarrowGates")])
    for i in range(8):
        x = 2300 + i*60
        gap = 18 + (i%3)*4
        # столбы слева и справа, сжимающие проход
        add_part(gates_sec, "GateL_%d"%i, (8,20,RIVER_HALF_W - gap),
                 (x, 8, -(gap + (RIVER_HALF_W-gap)/2)), (120,60,60), mat=M_METAL)
        add_part(gates_sec, "GateR_%d"%i, (8,20,RIVER_HALF_W - gap),
                 (x, 8, (gap + (RIVER_HALF_W-gap)/2)), (120,60,60), mat=M_METAL)
    obstacles[3].append(gates_sec)

    # 6) МОЛОТЫ / КАЧАЮЩИЕСЯ ПРЕГРАДЫ x 2800-3400
    hammers_sec = item("Folder", [p_str("Name", "Sec6_Hammers")])
    for i in range(10):
        x = 2850 + i*55
        z = RNG.uniform(-15,15)
        hammer = item("Model", [p_str("Name","Hammer%d"%i)])
        # верхняя балка
        add_part(hammer, "Axle", (12,3,12), (x, 22, z), (80,80,90), mat=M_METAL)
        # стержень
        add_part_shape(hammer, "Rod", (2,20,2), (x, 11, z), (100,100,110),
                       SHAPE_CYLINDER, mat=M_METAL, rotation=mat_rotx(math.pi/2))
        # навершие молота (тяжёлый блок)
        add_part(hammer, "Head", (12,8,12), (x, -1, z), (60,60,70), mat=M_METAL)
        hammers_sec[3].append(hammer)
    obstacles[3].append(hammers_sec)

    # 7) ВРАЩАЮЩИЕСЯ СТОЛБЫ x 3450-4000
    spinners = item("Folder", [p_str("Name", "Sec7_Spinners")])
    for i in range(7):
        x = 3500 + i*80
        z = 0
        spin = item("Model", [p_str("Name","Spinner%d"%i)])
        add_part_shape(spin, "Axis", (3, 24, 3), (x, 10, z), (70,70,80),
                       SHAPE_CYLINDER, mat=M_METAL, rotation=mat_rotx(math.pi/2))
        # перекладина со столбами/брусками
        for side in (-1, 1):
            add_part(spin, "Arm%d"%side, (38,2,3), (x,10,z), (120,120,130), mat=M_METAL,
                     rotation=mat_roty(0))
            add_part(spin, "Weight%d"%side, (6,6,6), (x+side*19, 10, z),
                     (60,60,70), mat=M_METAL)
        spinners[3].append(spin)
    obstacles[3].append(spinners)

    # 8) ФИНАЛЬНАЯ РАМПА x 4100-4600
    ramp = item("Folder", [p_str("Name", "Sec8_Ramp")])
    ang = math.atan2(30, 500.0)  # подъём вверх
    add_part_rot(ramp, "Ramp", (500, 3, RIVER_W-6), (4350, -2, 0),
                 (80,85,90), mat_rotz(ang), mat=M_CONCRETE)
    add_part_rot(ramp, "RampSideL", (500, 12, 2), (4350, 5, -RIVER_HALF_W+3),
                 (160,160,160), mat_rotz(ang), mat=M_METAL)
    add_part_rot(ramp, "RampSideR", (500, 12, 2), (4350, 5, RIVER_HALF_W-3),
                 (160,160,160), mat_rotz(ang), mat=M_METAL)
    obstacles[3].append(ramp)

    river[3].append(obstacles)

    # ---- СУНДУКИ С ЗОЛОТОМ по маршруту ----
    chests = item("Folder", [p_str("Name","TreasureChests")])
    CHESTS = [
        (300,  -25,  50,   "Chest_50"),
        (550,   20, 150,   "Chest_150"),
        (850,  -10, 250,   "Chest_250"),
        (1250,  15, 400,   "Chest_400"),
        (1600, -20, 600,   "Chest_600"),
        (2100,  18, 800,   "Chest_800"),
        (2650, -12, 1200,  "Chest_1200"),
        (3200,  10, 1500,  "Chest_1500"),
        (3800,   0, 2000,  "Chest_2000"),
    ]
    for (x,z,reward,name) in CHESTS:
        chest = item("Part", part_props(name, (6,5,4),
                    (x, WATER_Y+2.5, z), (140,90,30), mat=M_WOOD, shape=SHAPE_BLOCK))
        add_part_shape(chest, "Lid", (6.2, 1.5, 4.2), (x, WATER_Y+5.5, z),
                       (180,130,40), SHAPE_BLOCK, mat=M_WOOD)
        add_part_shape(chest, "Lock", (1.2,1.2,0.6), (x, WATER_Y+4.5, z+2.2),
                       (255,215,80), SHAPE_BALL, mat=M_NEON, transparency=0.3)
        chest[2].append(p_int("GoldReward", reward))
        chest[2].append(p_str("TreasureType", "SmallChest"))
        chests[3].append(chest)

    # Главный сундук-сокровище в конце
    end = item("Part", part_props("EndTreasure", (22, 16, 16),
                (4700, WATER_Y+8, 0), (255,210,60), mat=M_NEON,
                shape=SHAPE_BLOCK, transparency=0.15))
    add_part_shape(end, "Lid", (22.2,5,16.2), (4700, WATER_Y+18, 0),
                   (255,230,100), SHAPE_BLOCK, mat=M_NEON, transparency=0.2)
    add_part_shape(end, "Glow", (30,30,30), (4700, WATER_Y+20, 0),
                   (255,220,120), SHAPE_BALL, mat=M_NEON, transparency=0.75,
                   cancollide=False, castshadow=False)
    add_light(end, "TreasureLight", (255,210,80), 5, 80)
    end[2].append(p_int("GoldReward", 10000))
    end[2].append(p_str("TreasureType", "EndChest"))
    chests[3].append(end)

    # Надпись "THE END" на финише
    endsign = item("Part", part_props("EndSign", (20, 10, 0.6),
                (4700, WATER_Y+28, 0), (180,40,40), mat=M_SMOOTH,
                rotation=mat_look((-1,0,0))))
    eg = item("SurfaceGui", [p_str("Name","T"), p_token("Face",5),
        p_bool("AlwaysOnTop",True), p_v2("CanvasSize",600,300)])
    eg[3].append(item("TextLabel",[
        p_str("Name","T"), p_str("Text","СОКРОВИЩЕ!"),
        p_token("Font",19), p_bool("TextScaled",True),
        p_color3("TextColor3",(255,220,80)),
        p_color3("BackgroundColor3",(60,30,20)), p_float("BackgroundTransparency",0),
        p_udim2("Position",0,0,0,0), p_udim2("Size",1,0,1,0)]))
    endsign[3].append(eg)
    chests[3].append(endsign)

    river[3].append(chests)
    root[3].append(river)

# ---------------------------------------------------------------------------
# ФОН / ДЕКОР
# ---------------------------------------------------------------------------

def build_decor(root):
    decor = item("Model", [p_str("Name", "Decor")])
    # Дальние скалы/холмы по бокам
    for i in range(20):
        x = 500 + i*230
        s = RNG.uniform(100, 220)
        h = RNG.uniform(60, 140)
        add_part(decor, "HillL%d"%i, (s, h, s*0.7),
                 (x, 40, -RIVER_HALF_W-230), (80,100,70), mat=M_GRASS,
                 rotation=mat_rotz(RNG.uniform(-0.2,0.2)))
        add_part(decor, "HillR%d"%i, (s, h, s*0.7),
                 (x, 40, RIVER_HALF_W+230), (75,95,65), mat=M_GRASS,
                 rotation=mat_rotz(RNG.uniform(-0.2,0.2)))

    # Небо — дальний туман и горы силуэт
    add_part(decor, "SkylineL", (6000, 250, 400), (2000, -20, -1200),
             (60,80,100), mat=M_SLATE, castshadow=False)
    add_part(decor, "SkylineR", (6000, 280, 400), (2000, -5, 1200),
             (55,75,95), mat=M_SLATE, castshadow=False)
    root[3].append(decor)

# ---------------------------------------------------------------------------
# ОСВЕЩЕНИЕ / КАМЕРА / spawn
# ---------------------------------------------------------------------------

def build_lighting(root_children):
    lighting = item("Lighting", [
        p_str("Name","Lighting"),
        p_color3("Ambient", (80,82,90)),
        p_color3("OutdoorAmbient", (110,115,125)),
        p_float("Brightness", 2.4),
        p_float("ClockTime", 10.0),
        p_float("ExposureCompensation", 0.0),
        p_float("EnvironmentDiffuseScale", 1),
        p_float("EnvironmentSpecularScale", 1),
        p_color3("FogColor", (180,205,230)),
        p_float("FogStart", 600),
        p_float("FogEnd", 4200),
        p_float("GeographicLatitude", 35),
        p_bool("GlobalShadows", True),
        p_float("ShadowSoftness", 0.3),
    ])
    lighting[3].append(item("Atmosphere", [
        p_str("Name","Atmosphere"),
        p_color3("Color", (190,205,225)),
        p_color3("Decay", (120,120,130)),
        p_float("Density", 0.28),
        p_float("Glare", 0.2),
        p_float("Haze", 1.2),
        p_float("Offset", 0.1),
    ]))
    lighting[3].append(item("BloomEffect", [
        p_str("Name","Bloom"), p_float("Intensity",0.4),
        p_float("Size",24), p_float("Threshold",1.1)]))
    lighting[3].append(item("ColorCorrectionEffect", [
        p_str("Name","CC"), p_float("Brightness",0.0),
        p_float("Contrast",0.1), p_float("Saturation",0.05),
        p_color3("TintColor",(255,255,255))]))
    root_children.append(lighting)

def build_workspace_camera(ws):
    cam_pos = (BUILD_MIN_X - 30, 70, -80)
    target = ((BUILD_MIN_X+BUILD_MAX_X)/2, BUILD_PLATFORM_Y, 0)
    look = (target[0]-cam_pos[0], target[1]-cam_pos[1], target[2]-cam_pos[2])
    cam = item("Camera", [
        p_str("Name","CurrentCamera"),
        p_cframe("CFrame", cam_pos, mat_look(look)),
        p_float("FieldOfView", 70),
        p_token("CameraType", 5),
    ])
    ws[3].append(cam)
    ws[2].append(p_ref("CurrentCamera", cam[1]))

# ---------------------------------------------------------------------------
# СКРИПТЫ
# ---------------------------------------------------------------------------

# Серверный скрипт: валюта, запуск, сундуки, лидерстаты
LUA_SERVER = r'''-- Build A Boat For Treasure — Server Script
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Leaderstats + первое золото
Players.PlayerAdded:Connect(function(plr)
    local ls = Instance.new("Folder")
    ls.Name = "leaderstats"
    ls.Parent = plr
    local gold = Instance.new("IntValue")
    gold.Name = "Gold"; gold.Value = 50
    gold.Parent = ls
    local dist = Instance.new("IntValue")
    dist.Name = "Distance"; dist.Value = 0
    dist.Parent = ls

    -- Инвентарь (StringValue с JSON'ом купленных блоков)
    local inv = Instance.new("StringValue")
    inv.Name = "Inventory"
    inv.Value = "{}"
    inv.Parent = plr

    -- Стартовый набор
    local starter = Instance.new("Folder")
    starter.Name = "StarterItems"
    starter.Parent = plr
    -- Даём немного бесплатных деревянных блоков
    local function give(name, n)
        local v = Instance.new("IntValue")
        v.Name = name; v.Value = n; v.Parent = starter
    end
    give("WoodBlock", 30)
    give("Plank", 10)
    give("Chair", 2)
end)

-- Запуск лодки
local workspace = game.Workspace
local river = workspace:WaitForChild("River")
local water = river:WaitForChild("Water")
local startGate = workspace.BuildArea:WaitForChild("StartGate")
local lever = workspace.BuildArea:WaitForChild("LaunchLever")
local prompt = lever:WaitForChild("LeverBase"):WaitForChild("LaunchPrompt")

-- Запоминаем изначальные CFrame ворот для возврата
local gateClosedCF = {}
for _,g in ipairs(startGate:GetChildren()) do
    if g:IsA("BasePart") then gateClosedCF[g] = g.CFrame end
end
local waterClosedPos = water.Position

local launched = {}
local RIVER_FLOW = Vector3.new(18, 0, 0)  -- постоянный "течение" толчок

local function launchForPlayer(plr)
    if launched[plr] then return end
    launched[plr] = true
    -- Поднять воду в зоне строительства до уровня причала
    local targetWaterPos = waterClosedPos + Vector3.new(0, 5.5, 0)
    local t1 = TweenService:Create(water, TweenInfo.new(1.8), {Position = targetWaterPos})
    t1:Play()
    -- Открыть ворота: левая половина в минус Z, правая в плюс Z
    for _, g in ipairs(startGate:GetChildren()) do
        if g:IsA("BasePart") then
            local side = (g.Position.Z < 0) and -55 or 55
            local tg = TweenService:Create(g, TweenInfo.new(1.5),
                {CFrame = g.CFrame * CFrame.new(0, 0, side)})
            tg:Play()
        end
    end
    -- Открепить лодку и дать ей плавучесть + стартовый толчок
    local boat = workspace:FindFirstChild("Boat_"..plr.UserId)
    if boat then
        for _,d in ipairs(boat:GetDescendants()) do
            if d:IsA("BasePart") then
                d.Anchored = false
                d.CustomPhysicalProperties = PhysicalProperties.new(0.55, 0.3, 0.5)
                local b = Instance.new("BodyForce")
                b.Name = "RiverFlow"
                b.Force = Vector3.new(0, d:GetMass() * workspace.Gravity, 0)  -- поддерживаем на плаву (антивес)
                b.Parent = d
                d:ApplyImpulse(Vector3.new(d:GetMass() * 16, 0, 0))
            end
        end
    end
    -- Постоянное течение в реке: тикать каждую 0.1с и толкать все лодки вперёд
    local flowConn
    flowConn = game:GetService("RunService").Heartbeat:Connect(function(dt)
        for _, boat in ipairs(workspace:GetChildren()) do
            if boat:IsA("Model") and boat.Name:sub(1,5)=="Boat_" then
                local pri = boat.PrimaryPart
                if not pri then
                    for _,d in ipairs(boat:GetChildren()) do
                        if d:IsA("BasePart") then pri = d; break end
                    end
                    boat.PrimaryPart = pri
                end
                if pri and pri.Position.Y < 8 and pri.Position.Y > -50 then
                    for _,d in ipairs(boat:GetDescendants()) do
                        if d:IsA("BasePart") and d:FindFirstChild("RiverFlow") then
                            -- небольшой импульс вперёд
                            d:ApplyImpulse(Vector3.new(d:GetMass() * 0.6, 0, 0))
                        end
                    end
                end
            end
        end
    end)
    -- Через время вернуть воду и ворота, очистить поток
    task.delay(15, function()
        local t2 = TweenService:Create(water, TweenInfo.new(2.5), {Position = waterClosedPos})
        t2:Play()
        for g, cf in pairs(gateClosedCF) do
            if g and g.Parent then
                TweenService:Create(g, TweenInfo.new(2.2), {CFrame = cf}):Play()
            end
        end
        launched[plr] = false
    end)
end

prompt.Triggered:Connect(function(plr)
    launchForPlayer(plr)
end)

-- Сундуки — награда при касании
for _,chest in ipairs(river.TreasureChests:GetChildren()) do
    if chest:IsA("BasePart") then
        chest.Touched:Connect(function(hit)
            local p = Players:GetPlayerFromCharacter(hit.Parent)
            if not p then return end
            local reward = chest:GetAttribute("GoldReward") or 50
            p.leaderstats.Gold.Value += reward
            -- визуально — спрятать сундук для этого игрока
            chest:Destroy()
        end)
    end
end

-- Постоянный учёт дистанции (по позиции главного блока лодки)
game:GetService("RunService").Heartbeat:Connect(function()
    for _, plr in ipairs(Players:GetPlayers()) do
        local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
        if root and root.Position.X > plr.leaderstats.Distance.Value then
            plr.leaderstats.Distance.Value = math.floor(root.Position.X)
            -- скромная награда за расстояние
            if plr.leaderstats.Distance.Value % 100 == 0 then
                -- тихо - не спамим
            end
        end
    end
end)
'''

# Серверный скрипт магазина
LUA_SHOP_SERVER = r'''-- Сервер магазина: открыть гуи, покупка блоков
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local openRE = Instance.new("RemoteEvent")
openRE.Name = "OpenShop"; openRE.Parent = RS
local buyRE = Instance.new("RemoteEvent")
buyRE.Name = "BuyBlock"; buyRE.Parent = RS
local closeRE = Instance.new("RemoteEvent")
closeRE.Name = "CloseShop"; closeRE.Parent = RS
local placeRE = Instance.new("RemoteEvent")
placeRE.Name = "PlaceBlock"; placeRE.Parent = RS
local equipRE = Instance.new("RemoteEvent")
equipRE.Name = "EquipBlock"; equipRE.Parent = RS

-- Цены/блоки определены в общем модуле на клиенте; здесь же простая проверка
local PRICES = {
    WoodBlock=5; Plank=8; StoneBlock=15; MetalBlock=25; GlassBlock=20;
    NeonBlock=60; GoldBlock=150; Marble=100; Obsidian=200; Ice=80;
    Titanium=350; Concrete=40; WoodPole=12; Chair=35; Wheel=75;
    Engine=400; Propeller=200; Cannon=800; TNT=150; Spring=250;
    Magnet=600; JetTurbine=1200;
}

-- Открытие магазина по промпту
local npcPrompt;
do
    local ws = game.Workspace
    local shop = ws:WaitForChild("Shop")
    local sk = shop:WaitForChild("ShopKeeper", 5)
    if sk then
        npcPrompt = sk:WaitForChild("ShopPrompt")
    end
end
if npcPrompt then
    npcPrompt.Triggered:Connect(function(plr)
        openRE:FireClient(plr)
    end)
end

-- Покупка
buyRE.OnServerEvent:Connect(function(plr, blockName)
    local price = PRICES[blockName]
    if not price then return end
    if plr.leaderstats.Gold.Value < price then return end
    plr.leaderstats.Gold.Value -= price
    -- добавить в инвентарь
    local invName = "Inv_"..blockName
    local v = plr:FindFirstChild(invName)
    if not v then
        v = Instance.new("IntValue"); v.Name = invName; v.Value = 0; v.Parent = plr
    end
    v.Value += 1
end)

-- Установка блока в мире (просто создаём Part и крепим к "причалу")
placeRE.OnServerEvent:Connect(function(plr, cf, blockName)
    -- Проверка: строить можно только в зоне строительства
    local pos = cf.Position
    if pos.X < -110 or pos.X > 20 or pos.Z < -60 or pos.Z > 60 then return end
    if pos.Y < 4 or pos.Y > 20 then return end
    local invName = "Inv_"..blockName
    local v = plr:FindFirstChild(invName)
    if not v or v.Value <= 0 then return end
    v.Value -= 1

    local boat = workspace:FindFirstChild("Boat_"..plr.UserId)
    if not boat then
        boat = Instance.new("Model")
        boat.Name = "Boat_"..plr.UserId
        boat.Parent = workspace
    end

    -- Цвета и материалы берём по имени (упрощённо)
    local col = Color3.fromRGB(180,140,90); local mat = Enum.Material.Wood
    local size = Vector3.new(4,2,4); local shape = Enum.PartType.Block
    local map = {
        WoodBlock={Color3.fromRGB(180,140,90),Enum.Material.Wood,Vector3.new(4,2,4),Enum.PartType.Block};
        Plank={Color3.fromRGB(200,160,100),Enum.Material.Wood,Vector3.new(8,1,4),Enum.PartType.Block};
        StoneBlock={Color3.fromRGB(140,140,145),Enum.Material.Concrete,Vector3.new(4,4,4),Enum.PartType.Block};
        MetalBlock={Color3.fromRGB(170,175,180),Enum.Material.Metal,Vector3.new(4,2,4),Enum.PartType.Block};
        GlassBlock={Color3.fromRGB(190,220,240),Enum.Material.Glass,Vector3.new(4,2,4),Enum.PartType.Block};
        NeonBlock={Color3.fromRGB(255,80,200),Enum.Material.Neon,Vector3.new(4,2,4),Enum.PartType.Block};
        GoldBlock={Color3.fromRGB(255,210,60),Enum.Material.Metal,Vector3.new(4,2,4),Enum.PartType.Block};
        Marble={Color3.fromRGB(240,238,232),Enum.Material.SmoothPlastic,Vector3.new(4,2,4),Enum.PartType.Block};
        Obsidian={Color3.fromRGB(40,25,55),Enum.Material.Slate,Vector3.new(4,2,4),Enum.PartType.Block};
        Ice={Color3.fromRGB(180,230,255),Enum.Material.Ice,Vector3.new(4,2,4),Enum.PartType.Block};
        Titanium={Color3.fromRGB(120,130,150),Enum.Material.Metal,Vector3.new(4,2,4),Enum.PartType.Block};
        Concrete={Color3.fromRGB(120,125,128),Enum.Material.Concrete,Vector3.new(4,2,4),Enum.PartType.Block};
        WoodPole={Color3.fromRGB(120,80,50),Enum.Material.Wood,Vector3.new(2,8,2),Enum.PartType.Cylinder};
        Chair={Color3.fromRGB(90,60,40),Enum.Material.Wood,Vector3.new(4,4,4),Enum.PartType.Block};
        Wheel={Color3.fromRGB(120,80,40),Enum.Material.Wood,Vector3.new(6,2,6),Enum.PartType.Cylinder};
        Engine={Color3.fromRGB(80,85,95),Enum.Material.Metal,Vector3.new(6,4,6),Enum.PartType.Block};
        Propeller={Color3.fromRGB(160,160,170),Enum.Material.Metal,Vector3.new(8,1,2),Enum.PartType.Cylinder};
        Cannon={Color3.fromRGB(70,75,80),Enum.Material.Metal,Vector3.new(8,4,4),Enum.PartType.Cylinder};
        TNT={Color3.fromRGB(200,50,40),Enum.Material.Plastic,Vector3.new(4,4,4),Enum.PartType.Block};
        Spring={Color3.fromRGB(200,200,60),Enum.Material.Metal,Vector3.new(3,4,3),Enum.PartType.Cylinder};
        Magnet={Color3.fromRGB(200,40,40),Enum.Material.Metal,Vector3.new(5,3,5),Enum.PartType.Block};
        JetTurbine={Color3.fromRGB(90,100,110),Enum.Material.Metal,Vector3.new(5,6,8),Enum.PartType.Cylinder};
    }
    local def = map[blockName]
    if def then col,mat,size,shape = def[1],def[2],def[3],def[4] end

    local p = Instance.new("Part")
    p.Name = blockName
    p.Size = size
    p.CFrame = cf
    p.Color = col
    p.Material = mat
    p.Shape = shape
    p.Anchored = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.Parent = boat
    -- snap к сетке 4
    local gx = math.floor((p.Position.X+2)/4)*4
    local gz = math.floor((p.Position.Z+2)/4)*4
    p.Position = Vector3.new(gx, p.Position.Y, gz)

    -- Приварить к соседним блокам в той же лодке (WeldConstraint)
    for _, other in ipairs(boat:GetChildren()) do
        if other:IsA("BasePart") and other ~= p then
            local d = (other.Position - p.Position).Magnitude
            if d < math.max(size.Magnitude, other.Size.Magnitude) + 0.6 then
                local w = Instance.new("WeldConstraint")
                w.Part0 = p; w.Part1 = other
                w.Parent = p
                break
            end
        end
    end
    -- Первый блок лодки — PrimaryPart
    if not boat.PrimaryPart then boat.PrimaryPart = p end
end)
'''

# Клиентский скрипт: GUI магазина, инвентарь, отображение золота, киянка
LUA_CLIENT = r'''-- Build A Boat — Client Script (StarterPlayerScripts)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local plr = Players.LocalPlayer
local pg = plr:WaitForChild("PlayerGui")

-- Список блоков для магазина
local BLOCKS = {
    {n="WoodBlock",  d="Дерево",       c=Color3.fromRGB(180,140,90), p=5};
    {n="Plank",      d="Доска",        c=Color3.fromRGB(200,160,100),p=8};
    {n="StoneBlock", d="Камень",       c=Color3.fromRGB(140,140,145),p=15};
    {n="Concrete",   d="Бетон",        c=Color3.fromRGB(120,125,128),p=40};
    {n="MetalBlock", d="Металл",       c=Color3.fromRGB(170,175,180),p=25};
    {n="GlassBlock", d="Стекло",       c=Color3.fromRGB(190,220,240),p=20};
    {n="WoodPole",   d="Шест",         c=Color3.fromRGB(120,80,50),  p=12};
    {n="Ice",        d="Лёд",          c=Color3.fromRGB(180,230,255),p=80};
    {n="NeonBlock",  d="Неон",         c=Color3.fromRGB(255,80,200), p=60};
    {n="GoldBlock",  d="Золото",       c=Color3.fromRGB(255,210,60), p=150};
    {n="Marble",     d="Мрамор",       c=Color3.fromRGB(240,238,232),p=100};
    {n="Obsidian",   d="Обсидиан",     c=Color3.fromRGB(40,25,55),  p=200};
    {n="Titanium",   d="Титан",        c=Color3.fromRGB(120,130,150),p=350};
    {n="Chair",      d="Стул",         c=Color3.fromRGB(90,60,40),  p=35};
    {n="Wheel",      d="Штурвал",      c=Color3.fromRGB(120,80,40), p=75};
    {n="Spring",     d="Пружина",      c=Color3.fromRGB(200,200,60),p=250};
    {n="TNT",        d="TNT",          c=Color3.fromRGB(200,50,40), p=150};
    {n="Magnet",     d="Магнит",       c=Color3.fromRGB(200,40,40), p=600};
    {n="Engine",     d="Мотор",        c=Color3.fromRGB(80,85,95),  p=400};
    {n="Propeller",  d="Пропеллер",    c=Color3.fromRGB(160,160,170),p=200};
    {n="JetTurbine", d="Турбина",      c=Color3.fromRGB(90,100,110),p=1200};
    {n="Cannon",     d="Пушка",        c=Color3.fromRGB(70,75,80),  p=800};
}

-- HUD: отображение золота и подсказки
local hud = Instance.new("ScreenGui")
hud.Name = "BABHud"; hud.ResetOnSpawn = false; hud.Parent = pg

local goldLabel = Instance.new("TextLabel")
goldLabel.Size = UDim2.fromOffset(220,46)
goldLabel.Position = UDim2.new(0,16,0,16)
goldLabel.BackgroundColor3 = Color3.fromRGB(20,20,28)
goldLabel.BackgroundTransparency = 0.2
goldLabel.TextColor3 = Color3.fromRGB(255,220,100)
goldLabel.Font = Enum.Font.GothamBold
goldLabel.TextScaled = true
goldLabel.Text = "💰 50"
goldLabel.BorderSizePixel = 0
goldLabel.Parent = hud
local gCorn = Instance.new("UICorner"); gCorn.CornerRadius = UDim.new(0,8); gCorn.Parent = goldLabel

local distLabel = Instance.new("TextLabel")
distLabel.Size = UDim2.fromOffset(220,30)
distLabel.Position = UDim2.new(0,16,0,68)
distLabel.BackgroundColor3 = Color3.fromRGB(20,20,28)
distLabel.BackgroundTransparency = 0.3
distLabel.TextColor3 = Color3.fromRGB(200,240,255)
distLabel.Font = Enum.Font.Gotham
distLabel.TextScaled = true
distLabel.Text = "Дистанция: 0"
distLabel.BorderSizePixel = 0
distLabel.Parent = hud
local dCorn = Instance.new("UICorner"); dCorn.CornerRadius = UDim.new(0,8); dCorn.Parent = distLabel

-- Обновлять HUD
plr:WaitForChild("leaderstats")
local function updHud()
    goldLabel.Text = "💰 "..tostring(plr.leaderstats.Gold.Value)
    distLabel.Text = "Дистанция: "..tostring(plr.leaderstats.Distance.Value)
end
plr.leaderstats.Gold.Changed:Connect(updHud)
plr.leaderstats.Distance.Changed:Connect(updHud)
updHud()

-- Кнопка открытия магазина
local shopBtn = Instance.new("TextButton")
shopBtn.Size = UDim2.fromOffset(160,46)
shopBtn.Position = UDim2.new(1,-176,0,16)
shopBtn.BackgroundColor3 = Color3.fromRGB(180,40,40)
shopBtn.TextColor3 = Color3.fromRGB(255,240,200)
shopBtn.Font = Enum.Font.GothamBold
shopBtn.TextScaled = true
shopBtn.Text = "🏪 МАГАЗИН (B)"
shopBtn.BorderSizePixel = 0
shopBtn.Parent = hud
local sCorn = Instance.new("UICorner"); sCorn.CornerRadius = UDim.new(0,8); sCorn.Parent = shopBtn

-- Кнопка инвентаря / киянки
local hammerBtn = Instance.new("TextButton")
hammerBtn.Size = UDim2.fromOffset(160,46)
hammerBtn.Position = UDim2.new(1,-176,0,68)
hammerBtn.BackgroundColor3 = Color3.fromRGB(50,120,60)
hammerBtn.TextColor3 = Color3.fromRGB(255,255,255)
hammerBtn.Font = Enum.Font.GothamBold
hammerBtn.TextScaled = true
hammerBtn.Text = "🔨 КИЯНКА (H)"
hammerBtn.BorderSizePixel = 0
hammerBtn.Parent = hud
local hCorn = Instance.new("UICorner"); hCorn.CornerRadius = UDim.new(0,8); hCorn.Parent = hammerBtn

-- Подсказка
local hint = Instance.new("TextLabel")
hint.Size = UDim2.fromOffset(520,50)
hint.Position = UDim2.new(0.5,-260,1,-60)
hint.BackgroundTransparency = 1
hint.TextColor3 = Color3.fromRGB(255,255,255)
hint.Font = Enum.Font.Gotham
hint.TextScaled = true
hint.Text = "Построй лодку из блоков и жми рычаг ЗАПУСК у воды!  E чтобы плыть."
hint.Parent = hud

-- GUI магазина
local shopGui = Instance.new("ScreenGui")
shopGui.Name = "ShopGui"; shopGui.ResetOnSpawn = false; shopGui.Enabled = false; shopGui.Parent = pg

local bg = Instance.new("Frame")
bg.Size = UDim2.fromOffset(640,500)
bg.Position = UDim2.fromScale(0.5,0.5); bg.AnchorPoint = Vector2.new(0.5,0.5)
bg.BackgroundColor3 = Color3.fromRGB(30,34,42)
bg.Parent = shopGui
local bgC = Instance.new("UICorner"); bgC.CornerRadius = UDim.new(0,12); bgC.Parent = bg

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,0,0,48)
title.BackgroundColor3 = Color3.fromRGB(180,40,40)
title.TextColor3 = Color3.fromRGB(255,240,200)
title.Font = Enum.Font.GothamBold; title.TextScaled = true
title.Text = "🏪 МАГАЗИН БЛОКОВ"; title.Parent = bg
local tC = Instance.new("UICorner"); tC.CornerRadius = UDim.new(0,12); tC.Parent = title

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(40,40); close.Position = UDim2.new(1,-46,0,4)
close.BackgroundColor3 = Color3.fromRGB(40,40,50); close.Text = "✕"; close.TextColor3 = Color3.fromRGB(255,255,255)
close.TextScaled = true; close.Font = Enum.Font.GothamBold; close.Parent = bg
local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0,20); cc.Parent = close

local grid = Instance.new("ScrollingFrame")
grid.Size = UDim2.new(1,-20,1,-60)
grid.Position = UDim2.fromOffset(10,54)
grid.BackgroundTransparency = 1
grid.CanvasSize = UDim2.new(0,0,0,0)
grid.ScrollBarThickness = 8
grid.Parent = bg
local glay = Instance.new("UIGridLayout")
glay.CellSize = UDim2.fromOffset(140,130)
glay.CellPadding = UDim2.fromOffset(10,10)
glay.Parent = grid
local uiap = Instance.new("UIAspectRatioConstraint") -- noop but ok

for _,b in ipairs(BLOCKS) do
    local card = Instance.new("Frame")
    card.Size = UDim2.fromOffset(140,130)
    card.BackgroundColor3 = Color3.fromRGB(50,54,64)
    card.Parent = grid
    local cc2 = Instance.new("UICorner"); cc2.CornerRadius = UDim.new(0,8); cc2.Parent = card
    local swatch = Instance.new("Frame")
    swatch.Size = UDim2.fromOffset(64,40); swatch.Position = UDim2.new(0.5,-32,0,10)
    swatch.BackgroundColor3 = b.c; swatch.BorderSizePixel = 0; swatch.Parent = card
    local nameL = Instance.new("TextLabel")
    nameL.Size = UDim2.new(1,-8,0,24); nameL.Position = UDim2.fromOffset(4,56)
    nameL.BackgroundTransparency = 1; nameL.TextColor3 = Color3.fromRGB(255,255,255)
    nameL.Font = Enum.Font.GothamBold; nameL.TextScaled = true; nameL.Text = b.d; nameL.Parent = card
    local priceL = Instance.new("TextLabel")
    priceL.Size = UDim2.new(1,-8,0,20); priceL.Position = UDim2.fromOffset(4,82)
    priceL.BackgroundTransparency = 1; priceL.TextColor3 = Color3.fromRGB(255,220,100)
    priceL.Font = Enum.Font.Gotham; priceL.TextScaled = true; priceL.Text = "💰 "..b.p; priceL.Parent = card
    local buy = Instance.new("TextButton")
    buy.Size = UDim2.new(1,-16,0,24); buy.Position = UDim2.new(0,8,1,-28)
    buy.BackgroundColor3 = Color3.fromRGB(40,120,60); buy.TextColor3 = Color3.fromRGB(255,255,255)
    buy.Font = Enum.Font.GothamBold; buy.TextScaled = true; buy.Text = "КУПИТЬ"
    buy.Parent = card
    local bC = Instance.new("UICorner"); bC.CornerRadius = UDim.new(0,6); bC.Parent = buy
    buy.MouseButton1Click:Connect(function()
        RS.BuyBlock:FireServer(b.n)
    end)
end
grid.CanvasSize = UDim2.new(0,0,0, math.ceil(#BLOCKS/4)*140)

local function openShop() shopGui.Enabled = true end
local function closeShop() shopGui.Enabled = false end
close.MouseButton1Click:Connect(closeShop)
RS.OpenShop.OnClientEvent:Connect(openShop)
shopBtn.MouseButton1Click:Connect(openShop)
UIS.InputBegan:Connect(function(inp, gpe)
    if gpe then return end
    if inp.KeyCode == Enum.KeyCode.B then openShop() end
    if inp.KeyCode == Enum.KeyCode.Escape or inp.KeyCode == Enum.KeyCode.X then
        shopGui.Enabled = false
    end
end)

-- Инструмент «Киянка» — размещение блоков
local equipped = false
local mouse = plr:GetMouse()
local currentBlock = "WoodBlock"

-- Выбор блока: упрощённый селектор внизу экрана
local invBar = Instance.new("ScreenGui")
invBar.Name = "InvBar"; invBar.ResetOnSpawn = false; invBar.Parent = pg
local bar = Instance.new("Frame")
bar.Size = UDim2.fromOffset(680,70); bar.Position = UDim2.new(0.5,-340,1,-86)
bar.BackgroundColor3 = Color3.fromRGB(25,28,36); bar.BackgroundTransparency = 0.2
bar.Parent = invBar
local barC = Instance.new("UICorner"); barC.CornerRadius = UDim.new(0,10); barC.Parent = bar
local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Horizontal
list.Padding = UDim.new(0,6)
list.VerticalAlignment = Enum.VerticalAlignment.Center
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.Parent = bar

local function rebuildBar()
    for _,ch in ipairs(bar:GetChildren()) do if ch:IsA("TextButton") then ch:Destroy() end end
    for _,b in ipairs(BLOCKS) do
        local cnt = plr:FindFirstChild("Inv_"..b.n)
        local n = cnt and cnt.Value or 0
        if n>0 then
            local slot = Instance.new("TextButton")
            slot.Size = UDim2.fromOffset(58,58)
            slot.BackgroundColor3 = b.c
            slot.TextColor3 = Color3.fromRGB(255,255,255)
            slot.TextScaled = true; slot.Font = Enum.Font.GothamBold
            slot.Text = tostring(n)
            slot.Name = b.n
            slot.Parent = bar
            local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,8); c.Parent = slot
            slot.MouseButton1Click:Connect(function() currentBlock = b.n end)
        end
    end
end
plr.ChildAdded:Connect(function(c) if c.Name:sub(1,4)=="Inv_" then task.defer(rebuildBar) end end)
plr.ChildRemoved:Connect(function(c) if c.Name:sub(1,4)=="Inv_" then task.defer(rebuildBar) end end)
for _,c in ipairs(plr:GetChildren()) do if c.Name:sub(1,4)=="Inv_" then c.Changed:Connect(rebuildBar) end end
task.defer(rebuildBar)

hammerBtn.MouseButton1Click:Connect(function() equipped = not equipped end)
UIS.InputBegan:Connect(function(inp, gpe)
    if gpe then return end
    if inp.KeyCode == Enum.KeyCode.H then equipped = not equipped end
end)

-- Курсор: подсветка блока при строительстве
local ghost = Instance.new("Part")
ghost.Name = "BuildGhost"; ghost.Size = Vector3.new(4,2,4); ghost.Transparency = 1
ghost.Color = Color3.fromRGB(120,220,120); ghost.Anchored = true; ghost.CanCollide = false
ghost.Material = Enum.Material.Neon; ghost.Parent = workspace
local lastPlace = 0
game:GetService("RunService").RenderStepped:Connect(function()
    if not equipped then ghost.Transparency = 1 return end
    ghost.Transparency = 0.45
    local t = mouse.Target
    local p = mouse.Hit and mouse.Hit.Position or Vector3.new(0,6,0)
    local gx = math.floor((p.X+2)/4)*4
    local gy = math.floor((p.Y+1)/2)*2
    local gz = math.floor((p.Z+2)/4)*4
    if t and t:IsA("BasePart") then
        local normal = mouse.Hit.LookVector
        gy = t.Position.Y + t.Size.Y/2 + ghost.Size.Y/2
    end
    ghost.Position = Vector3.new(gx,gy,gz)
    if UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) and tick()-lastPlace > 0.2 then
        lastPlace = tick()
        RS.PlaceBlock:FireServer(CFrame.new(gx,gy,gz), currentBlock)
    end
end)

-- Напоминалка о плавании
UIS.InputBegan:Connect(function(inp, gpe)
    if gpe then return end
    if inp.KeyCode == Enum.KeyCode.E then
        -- Толкать лодку, если игрок сидит в лодке и есть моторы — упрощённо
    end
end)
'''

def build_scripts(root_children, ws):
    # Основной серверный скрипт
    sss = item("ServerScriptService", [p_str("Name","ServerScriptService")])
    sss[3].append(item("Script", [
        p_str("Name","GameServer"),
        p_protected("Source", LUA_SERVER),
    ]))
    sss[3].append(item("Script", [
        p_str("Name","ShopServer"),
        p_protected("Source", LUA_SHOP_SERVER),
    ]))
    root_children.append(sss)

    # Клиентский скрипт в StarterPlayerScripts
    sp = item("StarterPlayer", [p_str("Name","StarterPlayer")])
    sps = item("StarterPlayerScripts", [p_str("Name","StarterPlayerScripts")])
    sps[3].append(item("LocalScript", [
        p_str("Name","ClientMain"),
        p_protected("Source", LUA_CLIENT),
    ]))
    sp[3].append(sps)
    # StarterCharacterScripts пустой по умолчанию
    root_children.append(sp)

    # ReplicatedStorage
    rs = item("ReplicatedStorage", [p_str("Name","ReplicatedStorage")])
    root_children.append(rs)

    # StarterGui (пустой — клиентский скрипт создаёт сам)
    sg = item("StarterGui", [p_str("Name","StarterGui")])
    root_children.append(sg)

# ---------------------------------------------------------------------------
# СБОРКА
# ---------------------------------------------------------------------------

def main():
    ws = item("Workspace", [
        p_str("Name","Workspace"),
        p_bool("StreamingEnabled", False),
        p_float("Gravity", 196.2),
        p_float("FallenPartsDestroyHeight", -200),
    ])
    build_workspace_camera(ws)
    build_build_area(ws)
    build_shop(ws)
    build_leaderboards(ws)
    build_river(ws)
    build_decor(ws)

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

    n = xml.count("<Item ")
    print("Готово:", OUT_PATH)
    print("Инстансов: %d, размер: %.1f КБ" % (n, len(xml)/1024))

if __name__ == "__main__":
    main()
