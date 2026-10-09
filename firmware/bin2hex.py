import sys
d = open(sys.argv[1], 'rb').read()
d += b'\0' * ((-len(d)) % 4)
for i in range(0, len(d), 4):
    print('%08x' % int.from_bytes(d[i:i+4], 'little'))
