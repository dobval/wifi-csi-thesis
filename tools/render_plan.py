#!/usr/bin/env python3
"""Render a spaceplanner-plan JSON export as a to-scale ASCII floor plan.

    python3 tools/render_plan.py docs/layout-source.json [--width 76]

Units: the export labels itself "m" but stores centimetres (a 98 cm door, a 270 cm
wall). Values are auto-detected: if the room span is under 20 units it is assumed
to be metres and scaled to cm.

Terminal cells are about twice as tall as they are wide, so the vertical scale is
2x the horizontal one; the plan is therefore roughly square on screen.
"""
from __future__ import annotations

import argparse
import json
import math
import sys

SYMBOLS = [
    ("ESP", "E"),
    ("AP", "A"),
    ("out of zone", "3"),
    ("in zone", "1"),
]


def marker(text: str) -> str:
    for key, ch in SYMBOLS:
        if key.lower() in text.lower():
            return ch
    return "?"


def seg_dist(px, py, x1, y1, x2, y2):
    dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0:
        return math.hypot(px - x1, py - y1)
    t = ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    return math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))


def opening_span(plan, op):
    wall = next(w for w in plan["walls"] if w["id"] == op["wall_id"])
    x1, y1, x2, y2 = wall["x1"], wall["y1"], wall["x2"], wall["y2"]
    L = math.hypot(x2 - x1, y2 - y1)
    ux, uy = (x2 - x1) / L, (y2 - y1) / L
    cx = x1 + op["position"] * (x2 - x1)
    cy = y1 + op["position"] * (y2 - y1)
    half = op["width"] / 2
    return (cx - ux * half, cy - uy * half, cx + ux * half, cy + uy * half)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("json")
    ap.add_argument("--width", type=int, default=76)
    args = ap.parse_args()

    plan = json.load(open(args.json))["floors"][0]["plan"]
    walls = plan["walls"]

    xs = [c for w in walls for c in (w["x1"], w["x2"])]
    ys = [c for w in walls for c in (w["y1"], w["y2"])]
    k = 1 if (max(xs) - min(xs)) > 20 else 100     # metres -> cm
    xmin, xmax = min(xs) * k, max(xs) * k
    ymin, ymax = min(ys) * k, max(ys) * k

    W = args.width
    sx = (xmax - xmin) / W
    sy = sx * 2
    H = int(round((ymax - ymin) / sy))

    def cell_of(x, y):
        c = int((x - xmin) / sx)
        r = int((y - ymin) / sy)
        return max(0, min(W - 1, c)), max(0, min(H - 1, r))

    grid = [[" "] * W for _ in range(H)]

    # walls
    for w in walls:
        th = w["thickness"] * k
        for r in range(H):
            for c in range(W):
                cx = xmin + (c + 0.5) * sx
                cy = ymin + (r + 0.5) * sy
                if seg_dist(cx, cy, w["x1"] * k, w["y1"] * k, w["x2"] * k, w["y2"] * k) <= th / 2 + sx * 0.5:
                    grid[r][c] = "#"

    # openings overwrite the wall
    for op in plan["openings"]:
        ox1, oy1, ox2, oy2 = opening_span(plan, op)
        ch = "=" if op["type"] == "window" else "."
        for r in range(H):
            for c in range(W):
                cx = xmin + (c + 0.5) * sx
                cy = ymin + (r + 0.5) * sy
                if seg_dist(cx, cy, ox1 * k, oy1 * k, ox2 * k, oy2 * k) <= sx * 1.2:
                    grid[r][c] = ch

    # line of sight + annotations
    pts = {a["text"]: (a["x"] * k, a["y"] * k) for a in plan["annotations"]}
    los = None
    for t in pts:
        if "ESP" in t.upper():
            for u in pts:
                if u.upper().startswith("AP"):
                    los = (pts[t], pts[u])
    if los:
        (x1, y1), (x2, y2) = los
        (c1, r1), (c2, r2) = cell_of(x1, y1), cell_of(x2, y2)
        steps = max(abs(c2 - c1), abs(r2 - r1), 1)
        for i in range(steps + 1):
            c = round(c1 + (c2 - c1) * i / steps)
            r = round(r1 + (r2 - r1) * i / steps)
            if grid[r][c] == " ":
                grid[r][c] = ":"

    for a in plan["annotations"]:
        c, r = cell_of(a["x"] * k, a["y"] * k)
        grid[r][c] = marker(a["text"])

    print(f"+{'-' * W}+")
    for r in grid:
        print("|" + "".join(r) + "|")
    print(f"+{'-' * W}+")
    print(f"  room {xmax-xmin:.0f} x {ymax-ymin:.0f} plan units — "
          f"proportional, NOT to scale")
    print(f"  1 char = {sx:.1f} units across, {sy:.1f} down")
    print("  # wall   = window   . door   : line of sight")
    for a in plan["annotations"]:
        print(f"  {marker(a['text'])}  {a['text']}  x={a['x']*k:.0f}  y={a['y']*k:.0f} units")
    print()
    for op in plan["openings"]:
        ox1, oy1, ox2, oy2 = opening_span(plan, op)
        extra = f", sill {op['sill_height']*k:.0f}" if op.get("sill_height") else ""
        print(f"  {op['type']:7s} {op['width']*k:4.0f} units wide, "
              f"centre ({((ox1+ox2)/2)*k:.0f}, {((oy1+oy2)/2)*k:.0f}){extra}")

    if los:
        (ax, ay), (bx, by) = los
        d = math.hypot(ax - bx, ay - by)
        ux, uy = (bx - ax) / d, (by - ay) / d
        print()
        print(f"  AP label <-> node label    {d:.0f} units")
        print(f"  mid-point of those labels  x={(ax+bx)/2:.0f}  y={(ay+by)/2:.0f} units")
        for a in plan["annotations"]:
            t = a["text"]
            if "zone" not in t.lower():
                continue
            vx, vy = a["x"] * k - ax, a["y"] * k - ay
            perp = abs(vx * uy - vy * ux)
            along = vx * ux + vy * uy
            print(f"  {t:18s} {perp:5.0f} units off the label line, "
                  f"{along:5.0f} along it")
        print()
        print("  These are LABEL positions, not object positions: annotations are")
        print("  offset so the text does not overlap the drawing. The plan is for")
        print("  topology only - take every distance from a tape measure.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
