#!/usr/bin/env python3
"""
build_rbxmx.py — генерирует plugin/ArenaAgent.rbxmx из plugin/ArenaAgent.lua.

.rbxmx — это XML-модель Roblox. Положите её в папку плагинов Studio — так же,
как .lua: Studio загрузит скрипт внутри модели как плагин. Удобно как запасной
вариант: не зависит от кодировки/расширения текстового файла.

Запуск:  python3 tools/build_rbxmx.py
"""

import pathlib
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
LUA = ROOT / "plugin" / "ArenaAgent.lua"
OUT = ROOT / "plugin" / "ArenaAgent.rbxmx"


def main() -> int:
    src = LUA.read_text(encoding="utf-8")

    # CDATA не может содержать "]]>" — режем по стандарту XML
    cdata = src.replace("]]>", "]]]]><![CDATA[>")

    xml = f"""<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">
  <Item class="Script" referent="RBX0">
    <Properties>
      <string name="Name">ArenaAgent</string>
      <bool name="Disabled">false</bool>
      <ProtectedString name="Source"><![CDATA[{cdata}]]></ProtectedString>
    </Properties>
  </Item>
</roblox>
"""
    OUT.write_text(xml, encoding="utf-8")

    # проверка: валидный XML и исходник читается обратно без изменений
    tree = ET.parse(OUT)
    item = tree.getroot().find("Item")
    assert item is not None and item.get("class") == "Script"
    source = item.find("./Properties/ProtectedString").text
    assert source == src, "исходник в rbxmx не совпал с lua"

    print(f"OK: {OUT.name} ({OUT.stat().st_size} байт), исходник совпадает байт-в-байт")
    return 0


if __name__ == "__main__":
    sys.exit(main())
