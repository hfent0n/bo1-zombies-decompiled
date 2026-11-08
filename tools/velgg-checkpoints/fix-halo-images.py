#!/usr/bin/env python3
"""Repair the image entries of a Halo mod.ff built by OpenAssetTools whose textures live in halo.iwd.

The test build (Nov 2026) wrote every Halo GfxImage with mapType 0, category 0, format 0, no mip count and no card
memory. The engine sizes an image from its loadDef format before it reads the .iwi (gfx_d3d/r_image.cpp Load_Texture
-> Image_GetCardMemoryAmount), and format 0 is "unhandled case: 0": an assert, which kills vel.gg's web engine.

For every image in mod.ff that has an images/<name>.iwi in the .iwd, this sets what a retail entry has:
  mapType 3 (2D), category 3 (IMG_CATEGORY_LOAD_FROM_FILE), a semantic, cardMemory (both platforms) =
  Image_GetCardMemoryAmount, loadDef format = the D3DFMT of the .iwi; and the zone's externalSize = their sum.
Sizes do not change, so the zone's block sizes stay valid. Usage: fix-halo-images.py <mod.ff> <halo.iwd> <out.ff>
"""
import struct
import sys
import zipfile
import zlib

D3D = {11: (0x31545844, 8), 12: (0x33545844, 16), 13: (0x35545844, 16)}  # iwi format -> (D3DFMT_DXTn, block bytes)


def card_memory(flags, block, w, h, d):
    def level(w, h, d):
        return block * d * ((h + 3) >> 2) * ((w + 3) >> 2)
    total, levels = level(w, h, d), 1
    if not flags & 2:  # mipmapped
        while w + h + d > 3:
            w, h, d = max(w >> 1, 1), max(h >> 1, 1), max(d >> 1, 1)
            total += level(w, h, d)
            levels += 1
    return total * (6 if flags & 4 else 1), levels


def main(src, iwd, out):
    raw = open(src, 'rb').read()
    if raw[:8] != b'IWffu100':
        sys.exit('not an unsigned T5 fastfile')
    z = zlib.decompressobj()
    zone = bytearray(z.decompress(raw[12:]))
    if z.unused_data:
        sys.exit(f'{len(z.unused_data)} bytes after the zlib stream: unknown layout, not touching it')

    headers = {}
    with zipfile.ZipFile(iwd) as pack:
        for name in pack.namelist():
            if name.startswith('images/') and name.endswith('.iwi'):
                headers[name[7:-4]] = pack.read(name)[:12]

    fixed = []
    external = 0
    for name, h in headers.items():
        key = name.encode() + b'\0'
        at = zone.find(key)
        while at != -1:
            img = at - 52  # GfxImage (0x34) is written just before its inline name
            tex, namep = struct.unpack_from('<iI', zone, img)[0], struct.unpack_from('<I', zone, img + 44)[0]
            if tex == -2 and namep == 0xFFFFFFFF:
                break
            at = zone.find(key, at + 1)
        if at == -1:
            continue
        if h[:3] != b'IWi' or h[3] != 13 or h[4] not in D3D:
            print(f'skip {name}: iwi version {h[3]} format {h[4]}')
            continue
        fmt, block = D3D[h[4]]
        flags = h[5]
        w, hh, d = struct.unpack_from('<hhh', h, 6)
        mem, levels = card_memory(flags, block, w, hh, d)
        # GfxImageLoadDef (12 bytes, then resourceSize bytes of pixels) right after the name, unpadded: every Halo
        # image in the test build has exactly 12 zero bytes there (levelCount, flags, format, resourceSize all 0)
        load = at + len(key)
        if zone[load:load + 12] != bytes(12):
            print(f'skip {name}: unexpected loadDef {zone[load:load + 12].hex()}')
            continue
        # as retail zones have them (vel.gg's zombie_theater_patch.ff): levelCount 0, loadDef flags 0, a semantic
        zone[img + 4] = 3            # mapType: MAPTYPE_2D
        zone[img + 5] = 5 if name.endswith(('_n', '_normal')) else 8 if name == 'halo_spec' else 2  # normal/spec/colour
        zone[img + 6] = 3            # category: IMG_CATEGORY_LOAD_FROM_FILE
        struct.pack_into('<ii', zone, img + 12, mem, mem)               # cardMemory.platform[0..1]
        struct.pack_into('<HHHB', zone, img + 20, w, hh, d, 0)          # width, height, depth, levelCount
        struct.pack_into('<BBxxi', zone, load, 0, 0, fmt)
        external += mem
        fixed.append(f'{name} {w}x{hh} {"DXT1" if h[4] == 11 else "DXT5"} {levels} mips {mem} bytes')

    # XFile.externalSize: the bytes of every image read from an .iwd (retail: exactly their cardMemory sum)
    struct.pack_into('<I', zone, 4, struct.unpack_from('<I', zone, 4)[0] + external)
    print(f'externalSize += {external}')
    comp = zlib.compressobj(9)
    open(out, 'wb').write(raw[:12] + comp.compress(bytes(zone)) + comp.flush())
    print(f'{len(fixed)} of {len(headers)} images fixed')
    for line in fixed[:5]:
        print('  ' + line)


if __name__ == '__main__':
    main(*sys.argv[1:4])
