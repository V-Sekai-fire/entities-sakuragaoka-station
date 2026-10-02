# SPDX-License-Identifier: Apache-2.0 OR MIT
"""A release contact sheet: one row per case, one column per Hammersley view, failures first.

    python3 contact_sheet.py sheet.json out.png [--views 8] [--size 320] [--spp 32]

sheet.json lists the cases, each {"name", "verdict", "metric", "meshes": [{"obj", "color"}]}.
Every cell is a CPU Mitsuba render (llvm_ad_rgb, one thread, seed 0) from
`sphere_hammersley_sequence`, ported in anny-render-corpus/render_view.py, with a 24-patch
reference colour chart billboarded into the lower right of the frame under the same lights. Each
cell is labelled with its view, its skirt coverage and the chart's neutral-patch drift, the
number that says whether the light or the film moved between releases. The numbers are also
written beside the sheet as <out>.json.
"""
import argparse
import json
import os
import math
import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from render_view import camera  # noqa: E402  (the sequence, ported exactly)

# The 24 reference patches, sRGB 8-bit, row-major, the last six a neutral ramp from white to black.
# lookdev-24, the station's own 24-patch chart (entities-sakuragaoka-station tools/calib/chart24.json:
# published averaged values, sRGB 8-bit, row-major), so sheets here and there read the same patches.
CHART = [tuple(p["srgb8"]) for p in sorted(json.load(open(pathlib.Path(__file__).resolve().parent.parent / "calib" / "chart24.json"))["patches"],
                                           key=lambda p: p["no"])]
NEUTRALS = range(18, 24)
FOV = 40.0


def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def load_obj(path):
    v, f = [], []
    for line in open(path):
        if line.startswith("v "):
            x, y, z = map(float, line.split()[1:4])
            v.append((x, -z, y))  # Godot Y-up to the sequence's Z-up
        elif line.startswith("f "):
            f.append([int(t.split("/")[0]) - 1 for t in line.split()[1:4]])
    return np.array(v), np.array(f, dtype=np.int64)


def basis(eye):
    fwd = -eye / np.linalg.norm(eye)
    right = np.cross(fwd, [0, 0, 1.0])
    if np.linalg.norm(right) < 1e-6:  # straight up or down: the sequence's first view
        right = np.array([0.0, -1.0, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    return fwd, right, up


def project(p, eye, size):
    fwd, right, up = basis(eye)
    d = p - eye
    z = d @ fwd
    t = math.tan(math.radians(FOV) / 2)
    x, y = (d @ right) / (z * t), (d @ up) / (z * t)
    return int((x * 0.5 + 0.5) * size), int((0.5 - y * 0.5) * size)


def chart_patches(eye):
    """Patch centres and size, a 6x4 card facing the camera in the lower right of the frame."""
    fwd, right, up = basis(eye)
    dist = np.linalg.norm(eye)
    t = math.tan(math.radians(FOV) / 2) * dist * 0.55  # the card sits nearer than the object
    centre = eye + fwd * dist * 0.55 + right * t * 0.62 - up * t * 0.72
    w = t * 0.06
    out = []
    for i in range(24):
        r, c = divmod(i, 6)
        out.append((centre + right * (c - 2.5) * w * 1.1 - up * (r - 1.5) * w * 1.1, w, right, up))
    return out


def normalised_obj(path, centre, scale):
    """The mesh in the sheet's shared unit cube, Z-up, written once beside the original."""
    out = pathlib.Path(path).with_suffix(f".unit{abs(hash((round(scale, 6),) + tuple(np.round(centre, 6)))) % 10**8}.obj")
    if not out.exists():
        v, _ = load_obj(path)
        v = (v - centre) * scale
        tmp = out.with_suffix(f".{os.getpid()}.tmp")  # workers run in parallel: write, then rename
        with open(tmp, "w") as o:
            o.writelines(f"v {x:.6f} {y:.6f} {z:.6f}\n" for x, y, z in v)
            o.writelines(l for l in open(path) if l.startswith(("vt ", "f ")))
        os.replace(tmp, out)
    return str(out)


def render_cell(mi, case, eye, size, spp, norm):
    centre, scale = norm
    scene = {
        "type": "scene",
        # Every see-through layer costs a bounce, so x-ray cells get room for all of them.
        "integrator": {"type": "path", "max_depth": 4 if all(m.get("opacity", 1.0) >= 1.0 for m in case["meshes"]) else 24,
                       "rr_depth": 32},
        "sensor": {"type": "perspective", "fov": FOV, "fov_axis": "y",
                   "to_world": mi.ScalarTransform4f().look_at(origin=[float(x) for x in eye],
                                                              target=[0, 0, 0], up=[float(x) for x in basis(eye)[2]]),
                   "film": {"type": "hdrfilm", "width": size, "height": size, "pixel_format": "rgb"},
                   "sampler": {"type": "independent", "sample_count": spp}},
        "world": {"type": "constant", "radiance": {"type": "rgb", "value": 0.6}},
        "key": {"type": "directional", "direction": [-0.3, 0.4, -1.0],
                "irradiance": {"type": "rgb", "value": 1.5}},
    }
    for k, m in enumerate(case["meshes"]):
        refl = ({"type": "bitmap", "filename": m["texture"]} if m.get("texture")
                else {"type": "rgb", "value": [srgb_to_linear(c) for c in m["color"]]})
        bsdf = {"type": "twosided", "bsdf": {"type": "diffuse", "reflectance": refl}}
        # Order-independent transparency, CAD-style: a mask BSDF lets each ray through with
        # probability 1 - opacity at every layer, so the path tracer composites all layers
        # without sorting them (stochastic transparency; it converges as spp rises).
        if m.get("opacity", 1.0) < 1.0:
            bsdf = {"type": "mask", "opacity": {"type": "rgb", "value": float(m["opacity"])}, "bsdf": bsdf}
        scene[f"m{k}"] = {"type": "obj", "filename": normalised_obj(m["obj"], centre, scale),
                          "face_normals": True, "bsdf": bsdf}
    for i, (pc, w, right, up) in enumerate(chart_patches(eye)):
        n = np.cross(right, up)
        scene[f"chart{i}"] = {
            "type": "rectangle",
            "to_world": mi.ScalarTransform4f().look_at(origin=[float(x) for x in pc],
                                                       target=[float(x) for x in pc + n], up=[float(x) for x in up])
            @ mi.ScalarTransform4f().scale([w / 2, w / 2, 1]),
            "bsdf": {"type": "twosided", "bsdf": {"type": "diffuse", "reflectance": {
                "type": "rgb", "value": [srgb_to_linear(c) for c in CHART[i]]}}},
        }
    return mi.render(mi.load_dict(scene), spp=spp, seed=0)


def from_usda(case):
    """A case given as the pen's scene.usda: its meshes, colours and the gate's verdict."""
    from pxr import Usd, UsdGeom
    path = pathlib.Path(case["usda"])
    stage = Usd.Stage.Open(str(path))
    info = stage.GetRootLayer().customLayerData
    case.setdefault("verdict", "PASS" if info.get("state") == "DONE" else "FAIL")
    case.setdefault("metric", str(info.get("status", ""))[:60])
    case["meshes"] = []
    z_up = UsdGeom.GetStageUpAxis(stage) == "Z"
    cache = UsdGeom.XformCache()
    palette = [(200, 170, 150), (70, 110, 190), (190, 120, 80), (120, 160, 110), (170, 120, 170), (90, 90, 90)]
    from pxr import UsdShade

    def texture_of(mat):
        """The file feeding the UsdPreviewSurface's diffuseColor, or its constant colour."""
        if not mat:
            return None, None
        for p in Usd.PrimRange(mat.GetPrim()):
            sh = UsdShade.Shader(p)
            if sh and sh.GetIdAttr().Get() == "UsdPreviewSurface":
                inp = sh.GetInput("diffuseColor")
                src = inp.GetConnectedSources()[0] if inp and inp.HasConnectedSource() else []
                for s_ in src:
                    f = UsdShade.Shader(s_.source).GetInput("file")
                    if f and f.Get():
                        return f.Get().resolvedPath, None
                if inp and inp.Get() is not None:
                    return None, [round(x * 255) for x in inp.Get()]
        return None, None

    for prim in stage.Traverse():
        if not prim.IsA(UsdGeom.Mesh) or not UsdGeom.Imageable(prim).ComputeVisibility() == "inherited":
            continue
        g = UsdGeom.Mesh(prim)
        pts, idx, cnt = g.GetPointsAttr().Get(), g.GetFaceVertexIndicesAttr().Get(), g.GetFaceVertexCountsAttr().Get()
        if not pts or not idx:
            continue
        m = cache.GetLocalToWorldTransform(prim)
        world = [m.Transform(p) for p in pts]
        if z_up:  # into the Y-up frame load_obj expects
            world = [(p[0], p[2], -p[1]) for p in world]
        st = UsdGeom.PrimvarsAPI(prim).GetPrimvar("st")
        uv = st.ComputeFlattened() if st and st.GetInterpolation() == "faceVarying" else None
        starts, k = [], 0
        for n in cnt:
            starts.append(k)
            k += n
        # One part per material: the mesh's own binding, then each GeomSubset's.
        parts = {}
        own = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0]
        claimed = set()
        for sub in UsdGeom.Subset.GetAllGeomSubsets(UsdGeom.Imageable(prim)):
            faces = list(sub.GetIndicesAttr().Get() or [])
            claimed.update(faces)
            parts[sub.GetPrim().GetName()] = (UsdShade.MaterialBindingAPI(sub.GetPrim()).ComputeBoundMaterial()[0], faces)
        rest = [f for f in range(len(cnt)) if f not in claimed]
        if rest:
            parts[""] = (own, rest)
        for pname, (mat, faces) in parts.items():
            tex, const = texture_of(mat)
            obj = path.with_name(f"{prim.GetName().lower()}{'.' + pname.lower() if pname else ''}.from_usd.obj")
            with open(obj, "w") as o:
                o.writelines(f"v {p[0]:.6f} {p[1]:.6f} {p[2]:.6f}\n" for p in world)
                if uv is not None:
                    o.writelines(f"vt {t[0]:.6f} {t[1]:.6f}\n" for t in uv)
                for fi in faces:  # fan-triangulate quads and n-gons
                    s0, n = starts[fi], cnt[fi]
                    for j in range(1, n - 1):
                        c = (s0, s0 + j, s0 + j + 1)
                        if uv is not None:
                            o.write("f " + " ".join(f"{idx[q] + 1}/{q + 1}" for q in c) + "\n")
                        else:
                            o.write("f " + " ".join(f"{idx[q] + 1}" for q in c) + "\n")
            dc = g.GetDisplayColorAttr().Get()
            rgb = const or ([round(x * 255) for x in dc[0]] if dc else list(palette[len(case["meshes"]) % len(palette)]))
            op = case.get("opacity", {}).get(prim.GetName().lower(), case.get("opacity", {}).get("*", 1.0))
            case["meshes"].append({"obj": str(obj), "color": rgb, "texture": tex, "opacity": op})
    return case


def worker(argv):
    """Render one case for contact_sheet.exs: <case.json> <outdir> views size spp distance.

    Writes <outdir>/view_<i>.rgb (raw 8-bit RGB, size x size), and prints one tab-separated
    line per view: view yaw_deg pitch_deg coverage grey_drift. The case's resolved verdict and
    metric go to <outdir>/case.tsv. All layout, labels and PNG encoding are the Elixir side's.
    """
    case_path, outdir, views, size, spp, distance = argv
    views, size, spp, distance = int(views), int(size), int(spp), float(distance)
    import drjit as dr
    import mitsuba as mi
    mi.set_variant("llvm_ad_rgb")
    dr.set_thread_count(1)
    case = json.load(open(case_path))
    if "usda" in case:
        case = from_usda(case)
    v = np.concatenate([load_obj(m["obj"])[0] for m in case["meshes"]])
    lo, hi = v.min(0), v.max(0)
    norm = ((lo + hi) / 2, 1.0 / float((hi - lo).max()))
    if "frame" in case:  # a shared frame handed in by the composer
        norm = (np.array(case["frame"]["centre"]), case["frame"]["scale"])
    out = pathlib.Path(outdir)
    out.mkdir(parents=True, exist_ok=True)
    (out / "case.tsv").write_text(f"{case.get('verdict', '')}\t{case.get('metric', '')}\n")
    for i in range(views):
        eye, yaw, pitch, _ = camera(i, views, FOV, (0.0, 0.0), distance)
        img = np.clip(np.array(mi.util.convert_to_bitmap(render_cell(mi, case, eye, size, spp, norm))), 0, 255).astype(np.uint8)
        drift = []
        for k in NEUTRALS:
            px, py = project(chart_patches(eye)[k][0], eye, size)
            rgb = img[max(py - 1, 0):py + 2, max(px - 1, 0):px + 2].reshape(-1, 3).astype(float).mean(0)
            ref = CHART[k]  # the patch's own tint is not drift: lookdev-24's white is (245, 245, 240)
            drift.append(float(max(abs((rgb[0] - rgb[1]) - (ref[0] - ref[1])), abs((rgb[2] - rgb[1]) - (ref[2] - ref[1])))))
        fg = float((np.abs(img.astype(int) - img[0, 0].astype(int)).sum(-1) > 12).mean())
        (out / f"view_{i}.rgb").write_bytes(img.tobytes())
        print(f"{i}\t{math.degrees(yaw):.1f}\t{math.degrees(pitch):.1f}\t{fg:.4f}\t{max(drift):.2f}", flush=True)


def bounds(argv):
    """Print the shared unit-cube frame of several cases: centre x y z, then scale."""
    allv = []
    for p in argv:
        c = json.load(open(p))
        c = from_usda(c) if "usda" in c else c
        allv += [load_obj(m["obj"])[0] for m in c["meshes"]]
    v = np.concatenate(allv)
    lo, hi = v.min(0), v.max(0)
    c = (lo + hi) / 2
    print(f"{c[0]}\t{c[1]}\t{c[2]}\t{1.0 / float((hi - lo).max())}")


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet")
    ap.add_argument("out")
    ap.add_argument("--views", type=int, default=8)
    ap.add_argument("--size", type=int, default=320)
    ap.add_argument("--spp", type=int, default=32)
    ap.add_argument("--distance", type=float, default=0.6, help="render_view's close-up is 0.6")
    a = ap.parse_args(argv)
    import drjit as dr
    import mitsuba as mi
    mi.set_variant("llvm_ad_rgb")
    dr.set_thread_count(1)

    spec = json.load(open(a.sheet))
    spec["cases"] = [from_usda(c) if "usda" in c else c for c in spec["cases"]]
    cases = sorted(spec["cases"], key=lambda c: c["verdict"] != "FAIL")  # failures first
    def norm_of(case):
        v = np.concatenate([load_obj(m["obj"])[0] for m in case["meshes"]])
        lo, hi = v.min(0), v.max(0)
        return (lo + hi) / 2, 1.0 / float((hi - lo).max())
    shared = spec.get("shared_frame", True)
    if shared:
        allc = {"meshes": [m for c in cases for m in c["meshes"]]}
        norms = {c["name"]: norm_of(allc) for c in cases}
    else:
        norms = {c["name"]: norm_of(c) for c in cases}

    S, label_h, head_w = a.size, 44, 220
    sheet = Image.new("RGB", (head_w + S * a.views, 30 + (S + label_h) * len(cases)), (24, 24, 24))
    d = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    d.text((8, 8), spec.get("title", "contact sheet"), fill=(240, 240, 240), font=font)
    numbers = []
    for r, case in enumerate(cases):
        y0 = 30 + r * (S + label_h)
        col = {"FAIL": (230, 80, 80), "PASS": (120, 210, 120)}.get(case["verdict"], (200, 200, 120))
        d.text((8, y0 + 8), case["name"], fill=(240, 240, 240), font=font)
        d.text((8, y0 + 24), case["verdict"], fill=col, font=font)
        d.text((8, y0 + 40), case.get("metric", ""), fill=(200, 200, 200), font=font)
        for i in range(a.views):
            eye, yaw, pitch, _ = camera(i, a.views, FOV, (0.0, 0.0), a.distance)
            img = np.clip(np.array(mi.util.convert_to_bitmap(render_cell(mi, case, eye, S, a.spp, norms[case['name']]))), 0, 255)
            drift = []
            for k in NEUTRALS:
                px, py = project(chart_patches(eye)[k][0], eye, S)
                rgb = img[max(py - 1, 0):py + 2, max(px - 1, 0):px + 2].reshape(-1, 3).mean(0)
                ref = CHART[k]  # the patch's own tint is not drift: lookdev-24's white is (245, 245, 240)
            drift.append(float(max(abs((rgb[0] - rgb[1]) - (ref[0] - ref[1])), abs((rgb[2] - rgb[1]) - (ref[2] - ref[1])))))
            fg = float((np.abs(img.astype(int) - img[0, 0].astype(int)).sum(-1) > 12).mean())
            x0 = head_w + i * S
            sheet.paste(Image.fromarray(img.astype(np.uint8)), (x0, y0))
            d.text((x0 + 4, y0 + S + 4), f"view {i}  yaw {math.degrees(yaw):.0f}  pitch {math.degrees(pitch):.0f}",
                   fill=(220, 220, 220), font=font)
            d.text((x0 + 4, y0 + S + 20), f"cover {fg:.1%}  grey drift {max(drift):.1f}/255",
                   fill=(220, 220, 220), font=font)
            numbers.append({"case": case["name"], "verdict": case["verdict"], "view": i,
                            "yaw_deg": math.degrees(yaw), "pitch_deg": math.degrees(pitch),
                            "coverage": fg, "grey_drift": max(drift)})
            print(case["name"], i, f"cover {fg:.3f} drift {max(drift):.1f}", flush=True)
    sheet.save(a.out)
    json.dump({"generator": "sphere_hammersley_sequence (anny-render-corpus/render_view.py)",
               "variant": "llvm_ad_rgb", "views": a.views, "cells": numbers},
              open(pathlib.Path(a.out).with_suffix(".json"), "w"), indent=1)


if __name__ == "__main__":
    if sys.argv[1:2] == ["--worker"]:
        worker(sys.argv[2:])
    elif sys.argv[1:2] == ["--bounds"]:
        bounds(sys.argv[2:])
    else:
        main(sys.argv[1:])
