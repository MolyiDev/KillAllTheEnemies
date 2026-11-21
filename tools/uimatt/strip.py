# Rewrites a binary rbxl with all chunks uncompressed, dropping PROP chunks by (class, prop) or prop name.
import sys, struct
from compression import zstd

def lz4_block(src, out_len):
    dst = bytearray(); i = 0; n = len(src)
    while i < n:
        tok = src[i]; i += 1
        lit = tok >> 4
        if lit == 15:
            while True:
                b = src[i]; i += 1; lit += b
                if b != 255: break
        dst += src[i:i+lit]; i += lit
        if i >= n: break
        off = src[i] | (src[i+1] << 8); i += 2
        ml = tok & 15
        if ml == 15:
            while True:
                b = src[i]; i += 1; ml += b
                if b != 255: break
        ml += 4
        start = len(dst) - off
        for k in range(ml): dst.append(dst[start + k])
    assert len(dst) == out_len, (len(dst), out_len)
    return bytes(dst)

src_path, dst_path, *drops = sys.argv[1:]
data = open(src_path, 'rb').read()
hdr = data[:32]; p = 32
out = bytearray(hdr)
classes = {}
dropped = []
while p < len(data):
    name = data[p:p+4]; clen, ulen, res = struct.unpack('<III', data[p+4:p+16]); p += 16
    if clen == 0:
        body = data[p:p+ulen]; p += ulen
    else:
        raw = data[p:p+clen]; p += clen
        body = zstd.decompress(raw) if raw[:4] == b'\x28\xb5\x2f\xfd' else lz4_block(raw, ulen)
    keep = True
    if name == b'INST':
        cid = struct.unpack('<i', body[:4])[0]; L = struct.unpack('<I', body[4:8])[0]
        classes[cid] = body[8:8+L].decode()
    elif name == b'PROP':
        cid = struct.unpack('<i', body[:4])[0]; L = struct.unpack('<I', body[4:8])[0]
        pname = body[8:8+L].decode(); ptype = body[8+L]
        cls = classes.get(cid, '?')
        if pname in drops or f'{cls}.{pname}' in drops:
            keep = False; dropped.append(f'{cls}.{pname}(type {ptype})')
    if keep:
        out += name + struct.pack('<III', 0, len(body), 0) + body
    if name == b'END\x00': break
open(dst_path, 'wb').write(out)
print('dropped', len(dropped), dropped[:20])
