"""Verify original icon pixels and the lossless ICNS packaging."""
from pathlib import Path
import hashlib, json, struct, sys, zlib
assets = Path(__file__).resolve().parent.parent / 'Assets'
manifest = json.loads((assets / 'icon-sources.json').read_text())
ico = (assets / 'TaskManager-Windows.ico').read_bytes()
assert hashlib.sha256(ico).hexdigest() == manifest['ico_sha256']
for i in range(struct.unpack_from('<H', ico, 4)[0]):
    w,h,_,_,_,bits,n,o = struct.unpack_from('<BBBBHHII', ico, 6+i*16)
    w,h = w or 256,h or 256
    original=ico[o:o+n]
    png=(assets / f'TaskManager-{w}.png').read_bytes()
    if original.startswith(b'\x89PNG'):
        assert original == png
        continue
    chunks=[];offset=8
    while offset < len(png):
        size=struct.unpack_from('>I',png,offset)[0]
        if png[offset+4:offset+8] == b'IDAT':chunks.append(png[offset+8:offset+8+size])
        offset += size+12
    decoded=zlib.decompress(b''.join(chunks))
    header=struct.unpack_from('<I',original)[0]
    for y in range(h):
        row=decoded[y*(w*4+1):(y+1)*(w*4+1)]
        assert row[0] == 0
        for x in range(w):
            b,g,r,a=original[header+((h-y-1)*w+x)*4:header+((h-y-1)*w+x+1)*4]
            assert row[1+x*4:1+(x+1)*4] == bytes((r,g,b,a))
for entry in manifest['representations']:
    assert hashlib.sha256((assets / entry['file']).read_bytes()).hexdigest() == entry['sha256']
icns=Path(sys.argv[1]).read_bytes()
assert icns[:4] == b'icns' and struct.unpack_from('>I',icns,4)[0] == len(icns)
offset=8;count=0
sizes={b'icp4':16,b'icp5':32,b'icp6':64,b'ic08':256,b'ic11':32,b'ic12':64,b'ic13':256}
while offset < len(icns):
    kind=icns[offset:offset+4];size=struct.unpack_from('>I',icns,offset+4)[0]
    assert icns[offset+8:offset+size] == (assets / f'TaskManager-{sizes[kind]}.png').read_bytes()
    count+=1;offset+=size
assert count == len(sizes)
print(f'PASS: 9 original icon representations verified pixel-for-pixel; {count} ICNS chunks preserve PNG bytes.')
