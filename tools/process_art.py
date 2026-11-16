"""Magenta arka planı şeffaflaştırır, turnaround sayfalarını front/side/back olarak böler.
Kullanım: uv run --with pillow --with numpy --with scipy python tools/process_art.py"""
import numpy as np
from PIL import Image
from pathlib import Path

RAW = Path("assets/art/raw")

def key_magenta(path):
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    # magentalık: R ve B yüksek, G düşük
    mag = np.clip((np.minimum(r, b) - g) / 255.0, 0, 1)
    alpha = np.clip(1.0 - (mag - 0.35) / 0.35, 0, 1)  # mag>=0.7 tamamen şeffaf
    # kenar renk taşmasını temizle: magenta karışımını G'ye doğru çek
    spill = np.clip(np.minimum(r, b) - g, 0, None) * (1 - alpha)
    rgb = a.copy()
    rgb[..., 0] -= spill * 0.8; rgb[..., 2] -= spill * 0.8
    out = np.dstack([np.clip(rgb, 0, 255), alpha * 255]).astype(np.uint8)
    # küçük gürültüleri sil
    out[..., 3][out[..., 3] < 20] = 0
    return out

def bbox(alpha):
    ys, xs = np.where(alpha > 0)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1

def save_crop(arr, path, pad=8):
    x0, y0, x1, y1 = bbox(arr[..., 3])
    im = Image.fromarray(arr[max(0,y0-pad):y1+pad, max(0,x0-pad):x1+pad])
    im.save(path); print(path, im.size)

def split_sheet(arr, n=3):
    col = (arr[..., 3] > 0).sum(axis=0)
    filled = col > 2
    runs, start = [], None
    for x, f in enumerate(filled):
        if f and start is None: start = x
        if not f and start is not None: runs.append((start, x)); start = None
    if start is not None: runs.append((start, len(filled)))
    # küçük parçaları komşuya kat, en geniş n grubu al
    runs = [r for r in runs if r[1] - r[0] > 15]
    while len(runs) > n:  # en küçük boşluğu birleştir
        gaps = [runs[i+1][0] - runs[i][1] for i in range(len(runs)-1)]
        i = int(np.argmin(gaps)); runs[i:i+2] = [(runs[i][0], runs[i+1][1])]
    assert len(runs) == n, f"{len(runs)} parça bulundu"
    return [arr[:, s:e] for s, e in runs]

def uniform(parts, names, outdir, prefix, pad=8):
    # her parçayı kırp, ortak yükseklik + ayak hizası (alt) + ortak genişlik
    crops = []
    for p in parts:
        x0, y0, x1, y1 = bbox(p[..., 3]); crops.append(p[y0:y1, x0:x1])
    H = max(c.shape[0] for c in crops) + 2*pad
    W = max(c.shape[1] for c in crops) + 2*pad
    for c, nm in zip(crops, names):
        canvas = np.zeros((H, W, 4), np.uint8)
        h, w = c.shape[:2]
        y = H - pad - h; x = (W - w)//2
        canvas[y:y+h, x:x+w] = c
        fp = outdir / f"{prefix}_{nm}.png"; Image.fromarray(canvas).save(fp); print(fp, (W, H))

for f in ("cutlass_idle", "cutlass_swing"):
    save_crop(key_magenta(RAW / f"{f}.png"), Path("assets/art/weapons") / f"{f}.png")
for who in ("bosun", "gunner", "deckhand"):
    arr = key_magenta(RAW / f"crew_{who}_sheet.png")
    uniform(split_sheet(arr), ["front", "side", "back"], Path("assets/art/crew"), who)

# Papağan: 5 poz (sağa bakan profil), ayrı ayrı kırpılır (uçuş pozları ortak tuvale hizalanmaz)
if (RAW / "parrot_sheet.png").exists():
    arr = key_magenta(RAW / "parrot_sheet.png")
    names = ["fly_up", "fly_mid", "fly_down", "glide", "perch"]
    from scipy import ndimage
    lab, n = ndimage.label(ndimage.binary_dilation(arr[..., 3] > 0, iterations=3))
    sizes = ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))
    keep = sorted(np.argsort(sizes)[-5:] + 1, key=lambda k: np.where(lab == k)[1].mean())
    parts = []
    for k in keep:
        m = arr.copy(); m[..., 3][lab != k] = 0; parts.append(m)
    uniform(parts, names, Path("assets/art/animals"), "parrot")

# Uçuş karelerini gaga ucuna (en sağdaki opak piksel) göre aynı tuvalde hizala: kanat çırparken kafa sabit kalsın
def align_by_beak(names, d):
    ims = [np.asarray(Image.open(d / f"parrot_{n}.png")) for n in names]
    crops, beaks = [], []
    for a in ims:
        x0, y0, x1, y1 = bbox(a[..., 3]); c = a[y0:y1, x0:x1]
        cols = np.where(c[..., 3].any(axis=0))[0]; bx = cols.max()
        by = int(np.where(c[:, bx, 3] > 0)[0].mean())
        crops.append(c); beaks.append((bx, by))
    L = max(bx for bx, _ in beaks); R = max(c.shape[1] - bx for c, (bx, _) in zip(crops, beaks))
    T = max(by for _, by in beaks); B = max(c.shape[0] - by for c, (_, by) in zip(crops, beaks))
    for c, (bx, by), n in zip(crops, beaks, names):
        cv = np.zeros((T + B + 16, L + R + 16, 4), np.uint8)
        y, x = 8 + T - by, 8 + L - bx
        cv[y:y + c.shape[0], x:x + c.shape[1]] = c
        Image.fromarray(cv).save(d / f"parrot_{n}.png"); print("beak-aligned", n, cv.shape[1::-1], "beak at", (8 + L, 8 + T))
if (RAW / "parrot_sheet.png").exists():
    align_by_beak(["fly_up", "fly_mid", "fly_down", "glide"], Path("assets/art/animals"))
