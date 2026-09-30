#!/usr/bin/env python3
"""Статическая проверка новых скриптов бомба-игры.

1) Все RS.* вызовы определены в каком-то из серверных скриптов.
2) Ремоуты, которых ждёт клиент, создаются ядром; обработчики есть для новых.
3) Атрибуты, которые читает клиент, устанавливаются сервером.
4) Источники внутри bomb_v2.rbxl совпадают с tools/bomb/*.lua.
"""
import re
import struct
import sys
import zstandard

FILES = {
    "core": "tools/bomb/core.lua",
    "shop": "tools/bomb/shop.lua",
    "turret": "tools/bomb/turret.lua",
    "flight": "tools/bomb/flight.lua",
    "bots": "tools/bomb/bots.lua",
    "energysun": "tools/bomb/energysun.lua",
    "client": "tools/bomb/client.lua",
    "fog": "tools/bomb/fog.lua",
}
SERVER = ["core", "shop", "turret", "flight", "bots", "energysun"]
CLIENT = ["client", "fog"]
# нетронутые серверные скрипты (определения API вертолёта, раундов)
UNTOUCHED_SERVER = [".work/scripts/c64_1080_04.lua", ".work/scripts/c64_1080_07.lua"]

errors = []
text = {}
for k, path in FILES.items():
    text[k] = open(path, encoding="utf-8").read()

# ---------- 1) RS.* API ----------
defs = set()
for k in SERVER:
    defs |= set(re.findall(r"function\s+RS\.([A-Za-z_]\w*)", text[k]))
    defs |= set(re.findall(r"RS\.([A-Za-z_]\w*)\s*=", text[k]))
for path_u in UNTOUCHED_SERVER:
    try:
        body_u = open(path_u, encoding="utf-8").read()
    except FileNotFoundError:
        continue
    defs |= set(re.findall(r"function\s+RS\.([A-Za-z_]\w*)", body_u))
    defs |= set(re.findall(r"RS\.([A-Za-z_]\w*)\s*=", body_u))

calls = {}
for k in FILES:
    calls[k] = set(re.findall(r"RS\.([A-Za-z_]\w*)", text[k]))

# поля-данные (не функции): объявлены в таблице RS { ... }
core_rs_table = re.search(r"local RS = \{(.*?)\n\}", text["core"], re.S)
data_fields = set()
if core_rs_table:
    data_fields = set(re.findall(r"([A-Za-z_]\w*)\s*=", core_rs_table.group(1)))
data_fields |= {"Config", "remotes", "players", "flying", "billboards", "Ready",
                "services", "roundResetHooks", "repairCooldowns", "territories",
                "alliances", "wars", "spawnLocations", "occupied", "round"}

for k, cs in calls.items():
    for name in sorted(cs):
        if name in defs or name in data_fields:
            continue
        # присваивания в других скриптах уже учтены в defs
        errors.append(f"[RS API] {k}: RS.{name} нигде не определён")

# ---------- 2) Ремоуты ----------
core_remote_block = re.search(r"local remoteNames = \{(.*?)\}", text["core"], re.S)
core_remotes = set(re.findall(r'"(\w+)"', core_remote_block.group(1))) if core_remote_block else set()
# RemoteFunction создаётся по подстроке Config
core_remotes |= {"GetConfig", "GetHeliConfig"}

client_wait = set(re.findall(r'"(\w+)",\s*$', text["client"], re.M))
client_wait |= set(re.findall(r'^\s*"(\w+)",', text["client"], re.M))
client_wait |= set(re.findall(r'"(\w+)"\s*\}\)\s+do', text["client"]))
# точнее: список внутри ipairs({...}) для WaitForChild
m = re.search(r"for _, n in ipairs\(\{(.*?)\}\) do\s*\n\s*R\[n\] = remotes:WaitForChild", text["client"], re.S)
if m:
    client_wait = set(re.findall(r'"(\w+)"', m.group(1)))
else:
    errors.append("[remotes] не найден список WaitForChild в клиенте")

for r in sorted(client_wait - core_remotes):
    errors.append(f"[remotes] клиент ждёт '{r}', но ядро его не создаёт")

# обработчики на сервере для покупок
for r in ["BuyPowerPlant", "BuyFactory", "BuySatellite", "BuyRocket",
          "UpgradeRocket", "UpgradeFactory", "BuyTurret", "BuyEnergySun",
          "DeclareWar", "CreateAlliance", "BetrayAlliance", "GetPlayersList",
          "RequestLaunch", "SetTarget"]:
    if not any(re.search(rf"remotes\.{r}\.(OnServer|OnServerInvoke)", text[k]) for k in SERVER):
        errors.append(f"[remotes] нет серверного обработчика для '{r}'")

# клиентские FireServer для существующих ремоутов
for r in set(re.findall(r"R\.(\w+):FireServer", text["client"])):
    if r not in core_remotes:
        errors.append(f"[remotes] клиент шлёт '{r}', которого нет в ядре")

# ---------- 3) Атрибуты ----------
server_attrs = set()
for k in SERVER:
    server_attrs |= set(re.findall(r'SetAttribute\(\s*"(\w+)"', text[k]))
for path_u in UNTOUCHED_SERVER:
    try:
        server_attrs |= set(re.findall(r'SetAttribute\(\s*"(\w+)"', open(path_u, encoding="utf-8").read()))
    except FileNotFoundError:
        pass
# клиент тоже выставляет атрибуты (локальные, для тумана)
for k in CLIENT:
    server_attrs |= set(re.findall(r'SetAttribute\(\s*"(\w+)"', text[k]))
client_attrs = set()
for k in CLIENT:
    client_attrs |= set(re.findall(r'attr\("(\w+)"', text[k]))
    client_attrs |= set(re.findall(r'GetAttribute\("(\w+)"', text[k]))
    client_attrs |= set(re.findall(r'GetAttributeChangedSignal\("(\w+)"', text[k]))

for a in sorted(client_attrs - server_attrs):
    errors.append(f"[attrs] клиент читает '{a}', но сервер никогда не выставляет")

# ---------- 4) содержимое bomb_v2.rbxl ----------
def segments(path):
    data = open(path, "rb").read()
    pos = 32
    out = {}
    prop_i = -1
    while pos + 16 <= len(data):
        name = data[pos:pos + 4].decode("latin1")
        clen, ulen, comp = struct.unpack("<III", data[pos + 4:pos + 16])
        raw = data[pos + 16:pos + 16 + clen]
        if name == "PROP":
            prop_i += 1
        if name == "PROP" and clen:
            body = zstandard.ZstdDecompressor().decompress(raw, max_output_size=ulen * 8 + (1 << 24))
            cid = struct.unpack("<i", body[0:4])[0]
            nlen = struct.unpack("<I", body[4:8])[0]
            pname = body[8:8 + nlen]
            if pname == b"Source":
                off = 8 + nlen + 1
                segs = []
                while off < len(body):
                    ln = struct.unpack("<I", body[off:off + 4])[0]
                    off += 4
                    segs.append(body[off:off + ln])
                    off += ln
                out[(cid, prop_i)] = segs
        pos += 16 + clen
        if name == "END\x00":
            break
    return out

try:
    segs = segments("bomb_v2.rbxl")
    expect = {
        (64, 1080): {0: "core", 1: "shop", 2: "core", 3: "turret",
                     5: "flight", 6: "bots", 8: "energysun"},
        (42, 667): {0: "client", 2: "fog"},
    }
    for key, mp in expect.items():
        for i, fname in mp.items():
            got = segs[key][i].decode("utf-8")
            if got != text[fname]:
                errors.append(f"[file] bomb_v2.rbxl сегмент {key}[{i}] != tools/bomb/{fname}.lua")
except FileNotFoundError:
    errors.append("[file] bomb_v2.rbxl не найден — запустите patch_bomb.py")

# ---------- отчёт ----------
if errors:
    print(f"НАЙДЕНО ПРОБЛЕМ: {len(errors)}")
    for e in errors:
        print(" -", e)
    sys.exit(1)
print("CHECK OK: RS-API, ремоуты, атрибуты и содержимое bomb_v2.rbxl согласованы")
