# -*- coding: utf-8 -*-
"""Статическая проверка перекрёстных ссылок между Lua-модулями бойца.

Ищет обращения Module.field (и Config.a.b) и проверяет, что поле где-то
определено в модуле-источнике. Ловит опечатки, которые в Roblox молча
ломают всю анимацию.
"""
import os, re, sys

LUA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lua")
FILES = {f: open(os.path.join(LUA, f), encoding="utf-8").read()
         for f in sorted(os.listdir(LUA)) if f.endswith(".lua")}

# какой файл определяет какой модуль
OWNER = {
    "Config": "config.lua", "Pose": "pose.lua", "Actions": "actions.lua",
    "Animator": "animator.lua", "Hud": "hud.lua", "Camera": "camera.lua",
    "Float": "floatnumbers.lua", "Vfx": "vfx.lua", "Dummies": "dummies.lua",
    "Input": "input.lua",
}

def strip_comments(src):
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == "-" and src[i:i+2] == "--":
            if src[i:i+4] == "--[[":
                j = src.find("]]", i + 4)
                i = (j + 2) if j != -1 else n
            else:
                j = src.find("\n", i)
                i = (j + 1) if j != -1 else n
        elif c in "\"'":
            q = c; out.append(c); i += 1
            while i < n and src[i] != q:
                if src[i] == "\\": out.append(src[i]); i += 1
                out.append(src[i]); i += 1
            out.append(src[i] if i < n else ""); i += 1
        else:
            out.append(c); i += 1
    return "".join(out)

CODE = {f: strip_comments(s) for f, s in FILES.items()}

def defined_fields(module):
    """Одноуровневые поля модуля + плоские пути Config.a.b"""
    src = CODE[OWNER[module]]
    fields = {}
    for m in re.finditer(r"\b%s\.([A-Za-z_]\w*)" % module, src):
        name = m.group(1)
        after = src[m.end():m.end()+30]
        # определение: = ... (не ==), либо function
        if re.match(r"\s*(=\s*[^=]|\s*\{)", after) or after.lstrip().startswith("="):
            fields[name] = True
        fields.setdefault(name, False)
    # вложенные пути Module.x.y (один уровень) — брутфорсом по блокам
    # определения вида Module.X.Y = ... (вне таблиц)
    for m in re.finditer(r"\b%s\.([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*=" % module, src):
        fields["%s.%s" % (m.group(1), m.group(2))] = True
    # вложенные ключи внутри таблиц
    if True:
        for m in re.finditer(r"\b%s\.([A-Za-z_]\w*)\s*=\s*\{" % module, src):
            top = m.group(1)
            i = m.end() - 1; depth = 0
            while i < len(src):
                if src[i] == "{": depth += 1
                elif src[i] == "}":
                    depth -= 1
                    if depth == 0: break
                i += 1
            body = src[m.end():i]
            for sm in re.finditer(r"([A-Za-z_]\w*)\s*=", body):
                fields["%s.%s" % (top, sm.group(1))] = True
            fields[top] = True
    return fields

DEFS = {m: defined_fields(m) for m in OWNER}

def uses(module):
    """Все обращения module.path, встречающиеся в остальных файлах"""
    found = {}
    for f, src in CODE.items():
        if f == OWNER[module]:
            continue
        for m in re.finditer(r"\b%s\.((?:[A-Za-z_]\w*)(?:\.[A-Za-z_]\w*)?)" % module, src):
            path = m.group(1)
            line = src[:m.start()].count("\n") + 1
            found.setdefault(path, []).append((f, line))
    return found

problems = 0
for module in OWNER:
    for path, locs in sorted(uses(module).items()):
        if path in DEFS[module]:
            continue
        # Animator.list/Anim... — методы экземпляра Anim, таблица Animator не содержит
        if module == "Animator" and path.split(".")[0] in ("list", "timeScale", "hitStopUntil",
                "timeScaleTarget", "get", "forget", "clearFor", "hitStop", "setChargeHold", "update", "playSound"):
            continue
        problems += 1
        print("НЕ НАЙДЕНО: %s.%s  →  %s" % (module, path, ", ".join("%s:%d" % l for l in locs[:3])))

print("проверено модулей: %d, проблем: %d" % (len(OWNER), problems))

# ---------------------------------------------------------------------------
# Дополнительные проверки: анимации, fx-события, remote'ы
# ---------------------------------------------------------------------------
def extra_checks():
    problems = 0
    actions_src = CODE["actions.lua"]
    known = set(re.findall(r'\bact\("([A-Za-z0-9_]+)"', actions_src))
    known |= set(re.findall(r'^\t([A-Za-z0-9_]+)\s*=\s*Pose\.deg', actions_src, re.M))
    known |= {"ko"}   # есть в act()

    # 1) все проигрываемые анимации должны существовать
    played = {}
    for f, src in CODE.items():
        for m in re.finditer(r':play\(\s*"([A-Za-z0-9_]+)"', src):
            played.setdefault(m.group(1), []).append(f)
    for name, files in sorted(played.items()):
        if name not in known:
            problems += 1
            print("АНИМАЦИЯ НЕ НАЙДЕНА: %s (играется в %s)" % (name, ", ".join(sorted(set(files)))))

    # 2) fx-события из действий должны обрабатываться аниматором
    anim_src = CODE["animator.lua"]
    handled = set(re.findall(r'ev == "([A-Za-z0-9_]+)"', anim_src))
    fired = set(re.findall(r'e\s*=\s*"([A-Za-z0-9_]+)"', actions_src))
    for name in sorted(fired - handled):
        problems += 1
        print("fx-СОБЫТИЕ БЕЗ ОБРАБОТЧИКА: %s" % name)

    # 3) remote'ы: список в генераторе == используемые в Lua
    gen = open(os.path.join(os.path.dirname(LUA), "generate_epic_combat.py"), encoding="utf-8").read()
    m = re.search(r'for rname in \(([^)]*)\)', gen)
    gen_names = set(re.findall(r'"(\w+)"', m.group(1))) if m else set()
    used = set()
    for f, src in CODE.items():
        used |= set(re.findall(r'remotes\.(\w+)', src))
        used |= set(re.findall(r'remotes:WaitForChild\("(\w+)"', src))
        used |= set(re.findall(r'local \w+ = remotes:WaitForChild\("(\w+)"', src))
    missing = used - gen_names
    for name in sorted(missing):
        problems += 1
        print("REMOTE НЕ СОЗДАЁТСЯ ГЕНЕРАТОРОМ: %s" % name)
    unused = gen_names - used
    for name in sorted(unused):
        print("(примечание) remote не используется в Lua: %s" % name)
    return problems

extra = extra_checks()
print("дополнительные проверки: проблем %d" % extra)
sys.exit(1 if (problems or extra) else 0)
