#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_tests.py — гоняет ArenaAgent.lua вне Roblox Studio.

Поднимает Lua-VM (lupa), подменяет Roblox API заглушками из fake_roblox.lua
и проверяет ключевую логику плагина: разбор ответов модели (extractJSON),
применение ops к DataModel (execOp/applyOps), преобразование значений
(coerceValue/encodeValue), сборку контекста и полный цикл агента (sendTurn)
с фейковым HTTP-провайдером.

Запуск:  python3 tests/run_tests.py
Зависимости: pip install lupa
"""

import json
import os
import sys

from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.join(HERE, "..", "plugin", "ArenaAgent.lua")
FAKE = os.path.join(HERE, "fake_roblox.lua")

L = lua54.LuaRuntime(unpack_returned_tuples=True)

PASS = 0
FAIL = 0
FAILURES = []


def check(name, cond, extra=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ✔ {name}")
    else:
        FAIL += 1
        FAILURES.append(name)
        print(f"  ✘ {name} {extra}")


# ---------------------------------------------------------------------
# Мост Lua table <-> JSON
# ---------------------------------------------------------------------
def _is_lua_table(x):
    n = type(x).__name__
    return n == "LuaTable" or n.endswith("_LuaTable")


def lua_to_py(x):
    if _is_lua_table(x):
        try:
            n = len(x)
        except Exception:
            n = 0
        if n > 0:
            try:
                vals = []
                ok = True
                for i in range(1, n + 1):
                    v = x[i]
                    if v is None:
                        ok = False
                        break
                    vals.append(lua_to_py(v))
                if ok:
                    return vals
            except Exception:
                pass
        out = {}
        try:
            for k in x:
                out[str(k)] = lua_to_py(x[k])
        except TypeError:
            pass
        return out
    return x


def py_to_lua(x):
    if isinstance(x, dict):
        t = L.table()
        for k, v in x.items():
            t[str(k)] = py_to_lua(v)
        return t
    if isinstance(x, list):
        t = L.table()
        for i, v in enumerate(x, 1):
            t[i] = py_to_lua(v)
        return t
    return x


def json_encode(lua_table):
    return json.dumps(lua_to_py(lua_table), ensure_ascii=False)


def json_decode(s):
    return py_to_lua(json.loads(s))


L.globals()["__py_json_encode"] = json_encode
L.globals()["__py_json_decode"] = json_decode

# ---------------------------------------------------------------------
# Загрузка окружения и плагина
# ---------------------------------------------------------------------
print("== Загрузка окружения ==")
L.execute("unpack = unpack or table.unpack")
with open(FAKE, encoding="utf-8") as f:
    L.execute(f.read())
with open(PLUGIN, encoding="utf-8") as f:
    src = f.read()

L.globals()["ARENA_TEST_HOOK"] = True
L.execute(src)
T = L.globals()["ArenaTest"]
check("плагин загрузился в фейковом окружении", T is not None)

HttpService = L.globals()["HttpService"]

# ---------------------------------------------------------------------
# Утилиты для тестов
# ---------------------------------------------------------------------
def lua(code):
    code = code.strip()
    if code.startswith("return ") and "\n" not in code:
        return L.eval(code[len("return "):])
    return L.eval("(function()\n" + code + "\nend)()")


def lua2d(code):
    """lua2, но всегда возвращает кортеж из >=2 элементов."""
    vals = lua2(code)
    if len(vals) == 0:
        return (None, None)
    if len(vals) == 1:
        return (vals[0], None)
    return vals[:2]


def lua2(code):
    """Для выражений с несколькими возвращаемыми значениями: 'return f(...)' -> python tuple."""
    expr = code.strip()
    if expr.startswith("return "):
        expr = expr[len("return "):]
    t = L.eval("(function() return table.pack(" + expr + ") end)()")
    n = int(t["n"])
    return tuple(t[i] for i in range(1, n + 1))


def set_responder(responses):
    """responses: список Python-функций (opts_table) -> dict"""
    idx = {"i": 0}

    def responder(opts):
        i = idx["i"]
        idx["i"] = i + 1
        fn = responses[min(i, len(responses) - 1)]
        result = fn(opts)
        return py_to_lua(result)

    HttpService["_responder"] = responder


def clear_http():
    HttpService["_requests"] = py_to_lua([])
    HttpService["_responder"] = None


def req_history():
    return lua_to_py(HttpService["_requests"])


def openai_reply(content):
    def fn(opts):
        return {"Success": True, "StatusCode": 200,
                "Body": json.dumps({"choices": [{"message": {"role": "assistant", "content": content}}]})}
    return fn


# =====================================================================
print("== splitPath / resolvePath ==")
check("обычный путь", lua('return #ArenaTest.splitPath("Workspace/A/B")') == 3)
check("game/ префикс", lua('return ArenaTest.splitPath("game/ServerScriptService/X")[1]') == "ServerScriptService")
check("workspace/ в нижнем регистре", lua('return ArenaTest.splitPath("workspace/X")[1]') == "Workspace")
check("пустой путь → nil", lua('return ArenaTest.splitPath("") == nil'))
inst = lua('''
local s = game.ServerScriptService
local f = Instance.new("Folder"); f.Name = "Game"; f.Parent = s
local sc = Instance.new("Script"); sc.Name = "Main"; sc.Parent = f
return sc
''')
check("resolve находит", lua('return ArenaTest.resolvePath("ServerScriptService/Game/Main") ~= nil'))
ok, err = lua2d('return ArenaTest.resolvePath("ServerScriptService/Game/Нет")')
check("resolve ошибку пишет понятно", ok is None and "не найден" in str(err), extra=str(err))

# =====================================================================
print("== coerceValue ==")
part = lua('''
local p = Instance.new("Part")
p.Size = Vector3.new(1, 1, 1)
p.Material = Enum.Material.Plastic
p.Anchored = false
p.CFrame = CFrame.new(0, 0, 0)
return p
''')
L.globals()["_part"] = part

v = lua('return ArenaTest.coerceValue(_part, "Size", {4, 1, 2})')
L.globals()["_v"] = v
check("короткий массив → Vector3", v[0] is True and lua('return typeof(_v[1])') == "Vector3")
check("значение Vector3 верное", lua('return _v[1].X') == 4 and lua('return _v[1].Y') == 1 and lua('return _v[1].Z') == 2, extra=str(v[1]))

v = lua('return ArenaTest.coerceValue(_part, "Size", {__t = "Vector3", v = {10, 20, 30}})')
check("__t Vector3", v[0] is True and v[1].Y == 20)

v = lua('return ArenaTest.coerceValue(_part, "Material", "Material.Neon")')
check("строка-энум по полному имени", v[0] is True and str(v[1]) == "Enum.Material.Neon", extra=str(v[1]))

v = lua('return ArenaTest.coerceValue(_part, "Material", "Enum.Material.Metal")')
check("строка-энум с Enum. префиксом", v[0] is True and str(v[1]) == "Enum.Material.Metal")

v = lua('return ArenaTest.coerceValue(_part, "Anchored", "true")')
check("строка → boolean", v[0] is True and v[1] is True)

v = lua('return ArenaTest.coerceValue(_part, "CFrame", {1, 2, 3})')
check("CFrame из 3 чисел", v[0] is True)

v = lua('return ArenaTest.coerceValue(_part, "Color", {__t = "Color3", hex = "FF8800"})')
check("Color3 из hex", v[0] is True and abs(v[1].R - 1.0) < 0.01 and abs(v[1].G - 0.533) < 0.01, extra=str(v[1]))

v = lua('return ArenaTest.coerceValue(_part, "Color", {__t = "Color3", v = {255, 128, 0}})')
check("Color3 0..255 автоопределение", v[0] is True and abs(v[1].R - 1.0) < 0.01)

v = lua('return ArenaTest.coerceValue(_part, "Size", "не число")')
check("мусор отклонён", v[0] is False)

# =====================================================================
print("== execOp: upsert_script / create_instance ==")
res = lua('return {ok = true, applied = {}, errors = {}, warnings = {}, sources = {}, properties = {}, children = {}}')
L.globals()["_res"] = res

r1, e1 = lua2d('return ArenaTest.execOp({op="upsert_script", path="ServerScriptService/Arena/Game/Round", class="Script", source="print(1)"}, _res, {instances=0})')
sc = lua('return game.ServerScriptService.Arena.Game.Round')
check("upsert_script создал скрипт", r1 is True and sc is not None and sc.Source == "print(1)")
check("создал папки-предки", lua('return game.ServerScriptService.Arena.Game.ClassName') == "Folder")

r2, _ = lua2d('return ArenaTest.execOp({op="upsert_script", path="ServerScriptService/Arena/Game/Round", source="print(2)"}, _res, {instances=0})')
check("upsert_script обновил", r2 is True and sc.Source == "print(2)")

folderOccupy = lua('''
local f = Instance.new("Folder"); f.Name = "Occupied"; f.Parent = game.ServerScriptService
return f
''')
r3, e3 = lua2d('return ArenaTest.execOp({op="upsert_script", path="ServerScriptService/Occupied", source="x"}, _res, {instances=0})')
check("upsert_script на занятом пути → ошибка", r3 is False and "занят" in str(e3), extra=str(e3))

r4 = lua2d('return ArenaTest.execOp({op="create_instance", path="Workspace/ArenaBuilds/Tower", class="Model", properties={Name2="ok"}, children={{name="Roof", class="Part", properties={Anchored=true}}}}, _res, {instances=0})')[0]
tower = lua('return game.Workspace.ArenaBuilds.Tower')
roof = lua('return game.Workspace.ArenaBuilds.Tower.Roof')
check("create_instance + дети", r4 is True and tower is not None and tower.ClassName == "Model" and roof is not None)

r5, e5 = lua2d('return ArenaTest.execOp({op="create_instance", path="Workspace/ArenaBuilds/Tower", class="Model"}, _res, {instances=0})')
check("create_instance на существующем → ошибка", r5 is False and "существует" in str(e5))
r5b = lua2d('return ArenaTest.execOp({op="create_instance", path="Workspace/ArenaBuilds/Tower", class="Model", replace=true}, _res, {instances=0})')[0]
check("replace=true пересоздаёт", r5b is True)

# пересоздаём Roof (replace снёс старый вместе с детьми)
lua2d('return ArenaTest.execOp({op="create_instance", path="Workspace/ArenaBuilds/Tower/Roof", class="Part"}, _res, {instances=0})')

r6, e6 = lua2d('return ArenaTest.execOp({op="set_properties", path="Workspace/ArenaBuilds/Tower/Roof", properties={Anchored=true, Size={8,1,8}}}, _res, {instances=0})')
roof2 = lua('return game.Workspace.ArenaBuilds.Tower.Roof')
check("set_properties с массивом", r6 is True and roof2 is not None and roof2.Size.Y == 1 and roof2.Size.X == 8, extra=f"r6={r6}")

r7 = lua2d('return ArenaTest.execOp({op="get_source", path="ServerScriptService/Arena/Game/Round"}, _res, {instances=0})')[0]
check("get_source вернул код", r7 is True and lua_to_py(res["sources"]).get("ServerScriptService/Arena/Game/Round") == "print(2)")

r8 = lua2d('return ArenaTest.execOp({op="get_properties", path="Workspace/ArenaBuilds/Tower/Roof", properties={"Size","Anchored"}}, _res, {instances=0})')[0]
props = lua_to_py(res["properties"]).get("Workspace.ArenaBuilds.Tower.Roof") or lua_to_py(res["properties"])
check("get_properties кодирует Vector3", r8 is True and "Size" in str(props), extra=str(props)[:200])

r9 = lua2d('return ArenaTest.execOp({op="list_children", path="Workspace/ArenaBuilds"}, _res, {instances=0})')[0]
kids = list(lua_to_py(res["children"]).values())
check("list_children", r9 is True and any(k.get("name") == "Tower" for kk in kids for k in kk), extra=str(kids)[:200])

r10 = lua2d('return ArenaTest.execOp({op="rename_instance", path="Workspace/ArenaBuilds/Tower/Roof", name="Крыша"}, _res, {instances=0})')[0]
check("rename_instance", r10 is True and lua('return game.Workspace.ArenaBuilds.Tower["Крыша"]') is not None)

r11 = lua2d('return ArenaTest.execOp({op="move_instance", path="Workspace/ArenaBuilds/Tower/Крыша", to="ReplicatedStorage"}, _res, {instances=0})')[0]
check("move_instance", r11 is True and lua('return game.ReplicatedStorage["Крыша"]') is not None)

r12, e12 = lua2d('return ArenaTest.execOp({op="move_instance", path="Workspace/ArenaBuilds/Tower", to="Workspace/ArenaBuilds/Tower/Внутрь"}, _res, {instances=0})')
check("move внутрь себя запрещён", r12 is False)

r13 = lua2d('return ArenaTest.execOp({op="delete_instance", path="Workspace/ArenaBuilds/Tower"}, _res, {instances=0})')[0]
check("delete_instance", r13 is True and lua('return game.Workspace.ArenaBuilds.Tower == nil'))

r14 = lua2d('return ArenaTest.execOp({op="set_attribute", path="Workspace/ArenaBuilds", name="Level", value=3}, _res, {instances=0})')[0]
check("set_attribute", r14 is True and lua('return game.Workspace.ArenaBuilds:GetAttribute("Level")') == 3)

r15, e15 = lua('return ArenaTest.execOp({op="что-то_странное"}, _res, {instances=0})')
check("неизвестная op → ошибка", r15 is False and "неизвестная" in str(e15))

# applyOps поверх execOp: пачка ops
lua('''
local res = _res
local ops = {
	{op = "upsert_script", path = "ServerScriptService/Pack/Mod", class = "ModuleScript", source = "return {}"},
	{op = "set_properties", path = "ServerScriptService/Pack/Mod", properties = {Enabled = true}},
	{op = "нет_такой"},
}
ArenaTest.applyOps(ops, res, {instances = 0})
''')
applied = lua_to_py(res["applied"])
errors = lua_to_py(res["errors"])
check("applyOps: успехи посчитаны", len(applied) >= 2, extra=str(applied))
check("applyOps: ошибка записана", any("неизвестная" in str(e.get("error", "")) for e in errors))

# =====================================================================
print("== extractJSON ==")
cases = [
    ('{"reply":"ок","ops":[],"done":true}', True),
    ('```json\n{"reply":"ок","ops":[],"done":true}\n```', True),
    ('Вот что я сделал:\n{"reply":"ок","ops":[{"op":"delete_instance","path":"Workspace/{x}"}],"done":false}\nСпасибо!', True),
    ('{"reply":"в строке \\" кавычка и } скобка","ops":[],"done":true}', True),
    ('просто текст без json', False),
    ('', False),
]
for i, (text, expect) in enumerate(cases):
    d = lua2(f'return ArenaTest.extractJSON({text!r})')
    d = d[0] if d else None
    check(f"extractJSON #{i+1}", (d is not None) == expect, extra=str(d)[:80])
d = lua2(f'return ArenaTest.extractJSON({cases[2][0]!r})')[0] or None
check("extractJSON разбирает вложенность", d is not None and d["reply"] == "ок" and len(d["ops"]) == 1)
d = lua2(f'return ArenaTest.extractJSON({cases[3][0]!r})')[0] or None
check("extractJSON: скобки в строках не ломают", d is not None and "скобка" in str(d["reply"] or ""))

# =====================================================================
print("== контекст: снимок, выделение, системный промпт ==")
snap = lua('return ArenaTest.buildSnapshot()')
check("снимок места — JSON со службами", isinstance(snap, str) and "Workspace" in snap and "ServerScriptService" in snap)

scr = lua('''
local s = Instance.new("Script"); s.Name = "MyScript"; s.Source = "print('привет')"
s.Parent = game.ServerScriptService
return s
''')
L.globals()["Selection"]["_list"] = py_to_lua([scr])
sel = lua('return ArenaTest.buildSelectionText(true)')
check("выделение с исходником", "SOURCE:" in str(sel) and "привет" in str(sel))

sysp = lua('return ArenaTest.buildSystemPrompt()')
check("промпт агента содержит протокол", "ФОРМАТ ОТВЕТА" in str(sysp) and "upsert_script" in str(sysp))
T["settings"]["mode"] = "chat"
sysp2 = lua('return ArenaTest.buildSystemPrompt()')
check("промпт чата отличается", "Только чат" in str(sysp2))
T["settings"]["mode"] = "agent"

# =====================================================================
print("== callModel: OpenAI-совместимый ==")
clear_http()
T["settings"]["providerIndex"] = 1
T["settings"]["endpoint"] = "https://openrouter.ai/api/v1"
T["settings"]["apiKey"] = "sk-test"
T["settings"]["model"] = "test/model"
set_responder([openai_reply("привет")])
ok, text = lua2d('''return ArenaTest.callModel(
	{{role="system", content="sys"}, {role="user", content="вопрос"}},
	"sys", ArenaTest.settings)
''')
reqs = req_history()
check("openai: успех", ok is True and text == "привет")
check("openai: URL/заголовки", len(reqs) == 1 and reqs[0]["Url"].endswith("/chat/completions") and reqs[0]["Headers"].get("Authorization") == "Bearer sk-test")
body = json.loads(reqs[0]["Body"])
check("openai: тело запроса", body["model"] == "test/model" and body["messages"][0]["role"] == "system")

print("== callModel: Anthropic ==")
clear_http()
T["settings"]["providerIndex"] = 3
T["settings"]["endpoint"] = "https://api.anthropic.com/v1"
set_responder([lambda opts: {"Success": True, "StatusCode": 200,
                             "Body": json.dumps({"content": [{"type": "text", "text": "часть1"}, {"type": "text", "text": "часть2"}]})}])
ok, text = lua2d('''return ArenaTest.callModel(
	{{role="system", content="sys"}, {role="user", content="вопрос"}},
	"sys", ArenaTest.settings)
''')
reqs = req_history()
body = json.loads(reqs[0]["Body"])
check("anthropic: успех и склейка блоков", ok is True and text == "часть1\nчасть2")
check("anthropic: system отдельно, x-api-key",
      body.get("system") == "sys"
      and all(m.get("role") != "system" for m in body["messages"])
      and reqs[0]["Headers"].get("x-api-key") == "sk-test")

print("== callModel: bridge ==")
clear_http()
T["settings"]["providerIndex"] = 6
T["settings"]["endpoint"] = "http://localhost:8787"
set_responder([lambda opts: {"Success": True, "StatusCode": 200, "Body": json.dumps({"ok": True, "text": "из bridge"})}])
ok, text = lua2d('''return ArenaTest.callModel({{role="user", content="q"}}, "sys", ArenaTest.settings)
''')
reqs = req_history()
check("bridge: URL /v1/chat и ответ", ok is True and text == "из bridge" and reqs[0]["Url"].endswith("/v1/chat"))

clear_http()
set_responder([lambda opts: {"Success": False, "StatusCode": 401, "Body": "unauthorized"}])
T["settings"]["providerIndex"] = 1
ok, err = lua2d('return ArenaTest.callModel({{role="user", content="q"}}, "s", ArenaTest.settings)')
check("HTTP 401 → понятная ошибка", ok is False and "401" in str(err))

# =====================================================================
print("== Полный цикл агента (sendTurn) ==")
lua('''
-- чистим состояние
ArenaTest.state.history = {}
game.ServerScriptService.Arena = nil
''')
set_responder([
    # ход 1: агент создаёт скрипт и говорит, что продолжит
    openai_reply(json.dumps({
        "reply": "Создаю менеджер раунда, дальше добавлю карту.",
        "ops": [{"op": "upsert_script", "path": "ServerScriptService/ArenaBuilds/RoundManager",
                 "class": "Script", "source": "-- Код раунда\nprint('round')"}],
        "done": False,
    }, ensure_ascii=False)),
    # ход 2: агент завершает
    openai_reply(json.dumps({"reply": "Готово: менеджер раунда на месте.", "ops": [], "done": True}, ensure_ascii=False)),
])
L.eval('ArenaTest.sendTurn("Сделай менеджер раунда")')

hist = lua_to_py(T["state"]["history"])
# user → assistant(+ops) → RESULT → assistant(готово) → RESULT
check("история: 5 сообщений", len(hist) == 5, extra=f"got {len(hist)}: {[m['role'] for m in hist]}")
check("история: пользователь → ассистент → RESULT → ассистент",
      hist[0]["role"] == "user" and hist[1]["role"] == "assistant"
      and hist[2]["role"] == "user" and hist[2]["content"].startswith("ARENA_RESULT")
      and hist[3]["role"] == "assistant")
check("скрипт реально создан в DataModel",
      lua("return game.ServerScriptService.ArenaBuilds.RoundManager.Source") == "-- Код раунда\nprint('round')")
check("ARENA_RESULT содержит отчёт", "applied" in hist[2]["content"] and "RoundManager" in hist[2]["content"])
check("ChangeHistoryService: waypoint поставлен", len(lua_to_py(L.globals()["ChangeHistoryService"]["waypoints"])) >= 1)
check("состояние: агент не завис в running", lua("return ArenaTest.state.running") is False)

# цикл с ошибкой JSON → ретрай
lua('ArenaTest.state.history = {}')
set_responder([
    openai_reply("Я не JSON, я просто текст"),
    openai_reply(json.dumps({"reply": "всё ок теперь", "ops": [], "done": True}, ensure_ascii=False)),
])
L.eval('ArenaTest.sendTurn("повтор")')
hist = lua_to_py(T["state"]["history"])
check("не-JSON → ретрай и восстановление",
      any("ARENA_RESULT" in m["content"] and "не валидным JSON" in m["content"] for m in hist if m["role"] == "user")
      and any(m["role"] == "assistant" and "всё ок теперь" in m["content"] for m in hist))

# ошибки ops возвращаются модели
lua('ArenaTest.state.history = {}')
set_responder([
    openai_reply(json.dumps({
        "reply": "попробую удалить несуществующее",
        "ops": [{"op": "delete_instance", "path": "Workspace/Нет_Такого_Объекта"}],
        "done": False,
    })),
    openai_reply(json.dumps({"reply": "понял, там пусто", "ops": [], "done": True})),
])
L.eval('ArenaTest.sendTurn("удали объект")')
hist = lua_to_py(T["state"]["history"])
result_msg = hist[2]["content"]
check("ошибка op попала в ARENA_RESULT для модели", '"errors"' in result_msg and "не найден" in result_msg)

# =====================================================================
print()
print(f"Итог: {PASS} прошло, {FAIL} упало")
if FAILURES:
    print("Упавшие тесты:")
    for f in FAILURES:
        print("  -", f)
sys.exit(1 if FAIL else 0)
