"""Package original Windows PNG resources in an ICNS container without resampling."""
from pathlib import Path
import struct
import sys
assets = Path(__file__).resolve().parent.parent / 'Assets'
chunks = []
for kind, size in [('icp4',16), ('icp5',32), ('icp6',64), ('ic08',256), ('ic11',32), ('ic12',64), ('ic13',256)]:
    png = (assets / f'TaskManager-{size}.png').read_bytes()
    chunks.append(kind.encode('ascii') + struct.pack('>I', 8 + len(png)) + png)
body = b''.join(chunks)
Path(sys.argv[1]).write_bytes(b'icns' + struct.pack('>I', 8 + len(body)) + body)
