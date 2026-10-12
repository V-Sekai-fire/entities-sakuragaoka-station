#!/usr/bin/env python3
# Airborne-petal energy per view: sum over pixels of |with petals - without| (RGB, 0..255), for the
# original (lying petals hidden) and the port, plus pixel counts and petal colour means.
import sys
from PIL import Image
import numpy as np
D = '/Users/ernest.lee/.hermes/cache/scratch/petals-ref/shots/'
L = lambda p: np.asarray(Image.open(D + p).convert('RGB')).astype(int)
port = sys.argv[1] if len(sys.argv) > 1 else 'port'
for i in range(4):
    row = []
    for a, b, tag in [('origair_%d.png', 'orignp_%d.png', 'orig'), (port + '/port-view_%d.png', 'portnp/port-view_%d.png', 'port')]:
        A = L(a % i); B = L(b % i)
        e = np.abs(A - B)
        d = e.max(-1) > 8
        w = e.sum(-1)
        # colour the petals add, weighted by how much they change the pixel
        col = (A * w[..., None]).sum((0, 1)) / max(w.sum(), 1)
        row.append('%s energy %8.0fk px %6d colour %s' % (tag, e.sum() / 1000, d.sum(), col.round()))
    print(i, ' | '.join(row))
