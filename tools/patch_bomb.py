#!/usr/bin/env python3
"""Хирургический патчер bomb.rbxl: заменяет ТОЛЬКО Source-сегменты выбранных
скриптов, все остальные чанки копирует байт-в-байт.

Формат PROP/Source (проверен):
    i32 cid | u32 nameLen | name | u8 flag | N × (u32 len | bytes)

Использование:  python3 tools/patch_bomb.py
Читает tools/bomb/*.lua, пишет bomb_v2.rbxl, затем проверяет результат.
"""
import struct
import sys
import hashlib
import zstandard

SRC = "bomb.rbxl"
DST = "bomb_v2.rbxl"
BOMB_DIR = "tools/bomb"

# (cid, propIdx) -> {segment_index: файл}
SEGMENT_MAP = {
    (64, 1080): {
        0: "core.lua",       # старое ядро (дубликат) — тоже новое
        1: "shop.lua",       # магазин + союзы/войны (сервер)
        2: "core.lua",       # основное ядро
        3: "turret.lua",     # ПВО: лазер
        5: "flight.lua",     # полёт/запуск + сигнал
        6: "bots.lua",       # экономика ботов
        8: "energysun.lua",  # мутации/ульта
        # 4 (вертолёт), 7 (раунды), 9..47 (движение моделей) — не трогаем
    },
    (42, 667): {
        0: "client.lua",     # главный клиент
        2: "fog.lua",        # туман войны (замена мёртвого LocalScript союзов)
        # 1 (RoundGui) — не трогаем
    },
    # (49, 842) — легаси Config, не используется, не трогаем
}


def read_file(path):
    with open(path, "rb") as f:
        return f.read()


def parse_chunks(data):
    magic = data[:14]
    assert magic == b"<roblox!\x89\xff\r\n\x1a\n", magic
    chunks = []
    pos = 32
    while pos + 16 <= len(data):
        name = data[pos:pos + 4]
        clen, ulen, comp = struct.unpack("<III", data[pos + 4:pos + 16])
        raw = data[pos + 16:pos + 16 + clen]
        chunks.append({
            "name": name, "clen": clen, "ulen": ulen, "comp": comp,
            "raw": raw, "header": data[pos:pos + 16 + clen],
        })
        pos += 16 + clen
        if name == b"END\x00":
            break
    return data[:32], chunks


def decompress(chunk):
    if not chunk["clen"]:
        return b""
    dctx = zstandard.ZstdDecompressor()
    out = dctx.decompress(chunk["raw"], max_output_size=chunk["ulen"] * 8 + (1 << 24))
    assert len(out) == chunk["ulen"], (chunk["name"], len(out), chunk["ulen"])
    return out


def decode_source(body):
    """i32 cid | u32 nameLen | name | u8 flag | segs"""
    cid = struct.unpack("<i", body[0:4])[0]
    nlen = struct.unpack("<I", body[4:8])[0]
    pname = body[8:8 + nlen]
    off = 8 + nlen
    flag = body[off]
    off += 1
    segs = []
    while off < len(body):
        ln = struct.unpack("<I", body[off:off + 4])[0]
        off += 4
        segs.append(body[off:off + ln])
        off += ln
    assert off == len(body), (cid, pname, off, len(body))
    return cid, pname, flag, segs


def encode_source(cid, pname, flag, segs):
    out = struct.pack("<i", cid)
    out += struct.pack("<I", len(pname)) + pname
    out += bytes([flag])
    for s in segs:
        out += struct.pack("<I", len(s)) + s
    return out


def main():
    data = read_file(SRC)
    header, chunks = parse_chunks(data)
    print(f"chunks: {len(chunks)}")

    prop_index = -1
    patched = {}          # id(chunk dict) -> new raw
    stats = []

    for i, ch in enumerate(chunks):
        if ch["name"] != b"PROP":
            continue
        prop_index += 1
        body = decompress(ch)
        cid = struct.unpack("<i", body[0:4])[0]
        nlen = struct.unpack("<I", body[4:8])[0]
        pname = body[8:8 + nlen]
        if pname != b"Source":
            continue
        key = (cid, prop_index)
        if key not in SEGMENT_MAP:
            continue
        c2, p2, flag, segs = decode_source(body)
        assert (c2, p2) == (cid, pname)
        print(f"Source PROP idx={prop_index} cid={cid} segs={len(segs)}")

        for seg_i, fname in SEGMENT_MAP[key].items():
            new_src = read_file(f"{BOMB_DIR}/{fname}")
            old = segs[seg_i]
            print(f"  [{seg_i:02d}] {fname}: {len(old)} -> {len(new_src)} bytes"
                  f"  (was md5 {hashlib.md5(old).hexdigest()[:8]})")
            if old.startswith(b"\xef\xbb\xbf"):
                new_src = b"\xef\xbb\xbf" + new_src
            segs[seg_i] = new_src

        new_body = encode_source(cid, pname, flag, segs)
        comp = zstandard.ZstdCompressor(level=12).compress(new_body)
        patched[id(ch)] = {"raw": comp, "clen": len(comp), "ulen": len(new_body),
                           "comp": ch["comp"]}
        stats.append((prop_index, cid))

    assert stats, "не найдено ни одного Source-чанка для патча!"
    assert len(patched) == 2, f"ожидалось 2 пропатченных чанка (cid42, cid64), найдено {len(patched)}"

    # сборка файла
    out = bytearray(header)
    for ch in chunks:
        p = patched.get(id(ch))
        if p is None:
            out += ch["header"]          # байт-в-байт как было
        else:
            out += struct.pack("<4sIII", ch["name"], p["clen"], p["ulen"], p["comp"])
            out += p["raw"]

    # END-чанк уже внутри chunks (копируется как есть); файл должен кончаться </roblox>
    # проверим хвост оригинала
    assert data.endswith(b"</roblox>")
    if not bytes(out).endswith(b"</roblox>"):
        # после END в оригинале может быть хвост — добавим из оригинала
        # (наш цикл уже скопировал END включительно; хвост "</roblox>" — вне чанков)
        # найдём позицию конца последнего скопированного чанка не получится —
        # проще: оригинал после END содержит только </roblox>
        out += b"</roblox>"

    with open(DST, "wb") as f:
        f.write(bytes(out))
    print(f"written {DST}: {len(out)} bytes (was {len(data)})")

    # ============ ВЕРИФИКАЦИЯ ============
    data2 = read_file(DST)
    header2, chunks2 = parse_chunks(data2)
    assert header2 == header, "заголовок изменился!"
    assert len(chunks2) == len(chunks), (len(chunks2), len(chunks))

    for a, b in zip(chunks, chunks2):
        assert a["name"] == b["name"], (a["name"], b["name"])
        if id(a) in patched:
            pa, pb = patched[id(a)], b
            assert pb["clen"] == pa["clen"] and pb["ulen"] == pa["ulen"], a["name"]
            assert pb["raw"] == pa["raw"], a["name"]
        else:
            assert b["header"] == a["header"], a["name"]

    # декодируем пропатченные сегменты и сверяем с файлами
    prop_index = -1
    checked = 0
    for ch in chunks2:
        if ch["name"] != b"PROP":
            continue
        prop_index += 1
        body = decompress(ch)
        cid = struct.unpack("<i", body[0:4])[0]
        nlen = struct.unpack("<I", body[4:8])[0]
        if body[8:8 + nlen] != b"Source":
            continue
        key = (cid, prop_index)
        if key not in SEGMENT_MAP:
            continue
        _, _, _, segs = decode_source(body)
        for seg_i, fname in SEGMENT_MAP[key].items():
            expect = read_file(f"{BOMB_DIR}/{fname}")
            if expect.startswith(b"\xef\xbb\xbf"):
                pass
            got = segs[seg_i]
            if got.endswith(expect) and got != expect:
                expect = got[:len(got) - len(expect)] + expect  # BOM-префикс
            assert expect in (got, ), (fname, len(got), len(expect))
            checked += 1
    # остальные сегменты Source не изменились
    prop_index = -1
    orig_src = {}
    for ch in chunks:
        if ch["name"] != b"PROP":
            continue
        prop_index += 1
        body = decompress(ch)
        cid = struct.unpack("<i", body[0:4])[0]
        nlen = struct.unpack("<I", body[4:8])[0]
        if body[8:8 + nlen] == b"Source":
            _, _, _, segs = decode_source(body)
            orig_src[(cid, prop_index)] = segs
    prop_index = -1
    for ch in chunks2:
        if ch["name"] != b"PROP":
            continue
        prop_index += 1
        body = decompress(ch)
        cid = struct.unpack("<i", body[0:4])[0]
        nlen = struct.unpack("<I", body[4:8])[0]
        if body[8:8 + nlen] == b"Source":
            _, _, _, segs = decode_source(body)
            key = (cid, prop_index)
            old = orig_src[key]
            assert len(segs) == len(old)
            for i in range(len(segs)):
                if key in SEGMENT_MAP and i in SEGMENT_MAP[key]:
                    continue
                assert segs[i] == old[i], (key, i)

    print(f"VERIFIED OK: {checked} сегментов совпадают с файлами, "
          "все прочие чанки и сегменты идентичны оригиналу")


if __name__ == "__main__":
    main()
