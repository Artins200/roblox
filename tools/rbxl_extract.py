#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Парсер бинарного формата Roblox (.rbxl/.rbxlx-binary) -> дерево инстансов.

Использование:
  python3 tools/rbxl_extract.py bomb.rbxl            # краткая сводка
  python3 tools/rbxl_extract.py bomb.rbxl --scripts  # выгрузить все скрипты в .work/scripts/
  python3 tools/rbxl_extract.py bomb.rbxl --tree     # печать дерева
  python3 tools/rbxl_extract.py bomb.rbxl --xml out.xml  # конверт в XML
"""
import struct, sys, os, re

try:
    import zstandard
    _dctx = zstandard.ZstdDecompressor()
except Exception:
    _dctx = None


def read_chunks(data):
    assert data[:8] == b'<roblox!', 'not a binary rbxl'
    # сигнатура: <roblox! + 6 байт + uint32(0)? фактически чанки начинаются с 14,
    # но между 14 и 32 идёт meta-заголовок: 00 00 | 6b 00 00 00 | 77 12 00 00 | 8 нулей
    pos = 32  # SSTR
    chunks = []
    while pos < len(data):
        name = data[pos:pos + 4]
        if name == b'END\x00':
            clen = struct.unpack('<I', data[pos + 4:pos + 8])[0]
            raw = data[pos + 12:pos + 12 + clen]
            chunks.append(('END', raw))
            break
        clen, ulen, comp = struct.unpack('<III', data[pos + 4:pos + 16])
        raw = data[pos + 16:pos + 16 + clen]
        if comp in (0, 1, 2) and _dctx is not None:
            try:
                out = _dctx.decompressobj().decompress(raw)
            except Exception:
                out = raw
        else:
            out = raw
        chunks.append((name.decode('latin1'), out))
        pos += 16 + clen
    return chunks


# ---- типы данных ----
def read_string(buf, pos):
    n = struct.unpack('<I', buf[pos:pos + 4])[0]
    s = buf[pos + 4:pos + 4 + n]
    return s.decode('utf-8', 'replace'), pos + 4 + n


def read_string_backup(buf, pos):
    """некоторые чанки используют 2-байтную длину? — вернём None"""
    return None, pos


def parse_sstr(buf):
    count = struct.unpack('<I', buf[:4])[0]
    pos = 4
    out = []
    for _ in range(count):
        s, pos = read_string(buf, pos)
        out.append(s)
    return out


def parse_inst(buf, strings):
    """INST: int32 classId | uint16 classTag? | см. rbxfile"""
    # Формат (rbxfile): int32 class_id; uint16 is_ref? -> на самом деле:
    # int32 class_id; uint16 reserved=0? ; uint8? Далее: int32 instance_count; referent[]
    # Проверим empirically: INST_001 = 30 байт
    # 'AssetService' строка внутри -> значит здесь имя класса хранится как int32-индекс в SSTR?
    # Посмотрим hex.
    return None, None, None


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else 'bomb.rbxl'
    data = open(path, 'rb').read()
    chunks = read_chunks(data)
    from collections import Counter
    print(Counter(c[0] for c in chunks))
    strings = None
    insts = []
    for name, buf in chunks:
        if name == 'SSTR':
            strings = parse_sstr(buf)
            print('strings:', len(strings))
            open('.work/strings.txt', 'w', encoding='utf-8').write('\n'.join(strings))
        elif name == 'INST':
            insts.append(buf)
        elif name == 'PRNT':
            open('.work/prnt.bin', 'wb').write(buf)
        elif name == 'PROP':
            pass
    # первый INST hex
    print('INST0 hex:', insts[0].hex())
    print('INST0 repr:', insts[0])
    big = max(insts, key=len)
    print('big INST hex head:', big[:80].hex())


if __name__ == '__main__':
    main()
