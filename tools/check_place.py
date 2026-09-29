# -*- coding: utf-8 -*-
"""Проверка собранного epic_combat.rbxlx.

Ловит класс ошибок, из-за которых игра молча не работает: скрипт ждёт
`script.Parent:WaitForChild("X")`, а такого соседа в его сервисе нет —
WaitForChild висит вечно и весь код после него не выполняется.

Запуск:  python3 tools/check_place.py
"""

import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLACE = os.path.join(ROOT, "epic_combat.rbxlx")

SCRIPT_CLASSES = ("ModuleScript", "Script", "LocalScript")


def props(it):
    d = {}
    p = it.find("Properties")
    if p is not None:
        for c in p:
            d[c.get("name")] = c.text or ""
    return d


def build(it):
    pr = props(it)
    return {
        "class": it.get("class"),
        "name": pr.get("Name", "?"),
        "props": pr,
        "children": [build(c) for c in it.findall("Item")],
    }


def main():
    if not os.path.exists(PLACE):
        print("нет файла %s — сначала запусти generate_epic_combat.py" % PLACE)
        return 1

    roots = [build(it) for it in ET.parse(PLACE).getroot().findall("Item")]
    services = {}
    for r in roots:
        services[r["class"]] = r

    problems = 0
    checked = 0

    def names(node):
        return set(c["name"] for c in node["children"])

    def walk(node):
        nonlocal problems, checked
        # «соседи» скрипта — это дети его родителя, т.е. узла, в котором мы сейчас
        sibling_names = names(node)
        for child in node["children"]:
            if child["class"] in SCRIPT_CLASSES:
                checked += 1
                problems += check_script(child, sibling_names)
            walk(child)

    def check_script(script, parent_names):
        src = script["props"].get("Source", "")
        bad = 0
        # синонимы: local RS = script.Parent  /  local RS = game:GetService("X")
        parent_aliases = set(re.findall(r"local (\w+)\s*=\s*script\.Parent", src))
        service_aliases = dict(re.findall(r'local (\w+)\s*=\s*game:GetService\("(\w+)"\)', src))

        def report(name, where):
            nonlocal bad
            bad += 1
            print("  %s: ждёт \"%s\", которого нет (%s)" % (script["name"], name, where))

        for m in re.finditer(r'script\.Parent:WaitForChild\("([^"]+)"', src):
            want = m.group(1)
            if want not in parent_names:
                report(want, "у родителя скрипта")
        for m in re.finditer(r'(\w+):WaitForChild\("([^"]+)"', src):
            var, want = m.group(1), m.group(2)
            if var == "script" or var == "Parent":
                continue
            if var in parent_aliases:
                if want not in parent_names:
                    report(want, "рядом со скриптом")
            elif var in service_aliases:
                svc = services.get(service_aliases[var])
                if svc is None:
                    bad += 1
                    print("  %s: сервис %s не найден" % (script["name"], service_aliases[var]))
                elif want not in names(svc):
                    report(want, "в сервисе %s" % service_aliases[var])
        return bad

    for r in roots:
        walk(r)

    print("скриптов проверено: %d, проблем: %d" % (checked, problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
