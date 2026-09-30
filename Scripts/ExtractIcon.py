"""Decode the original 32-bit ICO representations without resampling any pixel."""
from pathlib import Path
import struct, zlib, hashlib, json
assets = Path(__file__).resolve().parent.parent / 'Assets'
source = assets / 'TaskManager-Windows.ico'
data = source.read_bytes()
manifest = []
def chunk(kind, body):
    return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body) & 0xffffffff)
for index in range(struct.unpack_from('<H', data, 4)[0]):
    w,h,_,_,_,bits,length,offset = struct.unpack_from('<BBBBHHII', data, 6+16*index)
    w,h = w or 256,h or 256
    payload = data[offset:offset+length]
    if payload.startswith(b'\x89PNG'):
        png = payload
    else:
        assert bits == 32
        header = struct.unpack_from('<I',payload)[0]
        rows=[]
        for y in range(h-1,-1,-1):
            row=bytearray([0])
            for x in range(w):
                b,g,r,a=payload[header+(y*w+x)*4:header+(y*w+x+1)*4]
                row.extend((r,g,b,a))
            rows.append(row)
        png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(rows)))+chunk(b'IEND',b'')
    filename=f'TaskManager-{w}.png'
    (assets / filename).write_bytes(png)
    manifest.append({'file':filename,'size':w,'source':'TaskManager-Windows.ico','sha256':hashlib.sha256(png).hexdigest()})
(assets / 'icon-sources.json').write_text(json.dumps({'source':'https://github.com/HaydenReeve/WindowsIcons/blob/main/Icons/applications/taskmanager.ico','ico_sha256':hashlib.sha256(data).hexdigest(),'representations':manifest},indent=2)+'\n')
