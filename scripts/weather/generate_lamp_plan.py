#!/usr/bin/env python3
"""R3-B：由真實道路／碰撞幾何產生12m淨距燈位，輸出 JSON／SVG／執行期配置。"""
import argparse
import collections
import html
import json
import math
import re
from pathlib import Path

SPACING = 30.0
MIN_DISTANCE = 12.0
OFFSET = 5.5
CLEARANCE = 0.5 + 0.18  # 建築到燈柱外緣至少 0.5m。


def add(a, b): return (a[0] + b[0], a[1] + b[1])
def sub(a, b): return (a[0] - b[0], a[1] - b[1])
def mul(a, s): return (a[0] * s, a[1] * s)
def dot(a, b): return a[0] * b[0] + a[1] * b[1]
def cross(a, b): return a[0] * b[1] - a[1] * b[0]
def length(a): return math.hypot(*a)
def unit(a): return mul(a, 1.0 / length(a))
def xz(p): return (p[0], p[2])


def triangles(row):
    return [pts[i:i + 3] for face in row['faces']
            for pts in [face['points']] for i in range(0, len(pts), 3)]


def barycentric(p, tri):
    a, b, c = [xz(v) for v in tri]
    area = cross(sub(b, a), sub(c, a))
    if abs(area) < 1e-7: return None
    u = cross(sub(p, a), sub(c, a)) / area
    v = cross(sub(b, a), sub(p, a)) / area
    return (1 - u - v, u, v) if min(u, v, 1 - u - v) >= -1e-6 else None


def segment_distance(p, a, b):
    d = sub(b, a)
    t = max(0, min(1, dot(sub(p, a), d) / max(dot(d, d), 1e-12)))
    return length(sub(p, add(a, mul(d, t))))


def transform(row, p):
    return tuple(row['origin'][i] + sum(row['basis'][j][i] * p[j] for j in range(3)) for i in range(3))


def local_ports(row, catalog):
    kind = row['name'].rsplit('__', 1)[-1]
    basics = {'Cross': [(0, -1), (1, 0), (0, 1), (-1, 0)],
              'T': [(0, -1), (-1, 0), (1, 0)],
              'Corner90': [(0, -1), (1, 0)],
              'Curve45': [(0, -1), unit((1, 1))], 'Road1': [(0, -1), (0, 1)]}
    pivot = (0, 0, 0.48528 if kind == 'Curve45' else 0)
    if kind in basics: return pivot, basics[kind]
    model = next(m for m in catalog['models'] if m['id'] == row['road_id'])
    names = ['SouthOuter', 'LeftOuter', 'RightOuter'] if kind == 'Y' else ['SouthOuter', 'NorthOuter', 'DiagonalOuter']
    ports = [next(p for p in model['snap_points'] if p['name'] == name) for name in names]
    pivot = (0, 0, 9) if kind == 'Y' else (0, 0, ports[2]['position'][2] - ports[2]['position'][0] * ports[2]['outward'][2] / ports[2]['outward'][0])
    return pivot, [unit(xz(p['outward'])) for p in ports]


def generate(data, catalog):
    roads = data['roads']
    road_tris = [t for r in roads for t in triangles(r)]
    buildings = []
    for b in data['buildings']:
        ts = triangles(b)
        pts = [xz(v) for t in ts for v in t]
        if pts:
            buildings.append((b['name'], ts, (min(p[0] for p in pts), min(p[1] for p in pts), max(p[0] for p in pts), max(p[1] for p in pts))))
    accepted, skipped = [], []

    def consider(p, toward, source, kind, station):
        candidate_id = f'{source}:{kind}:{station}'
        row = {'id': candidate_id, 'source': source, 'kind': kind, 'position': [p[0], 0, p[1]],
               'arm': list(unit(toward)), 'yaw': math.atan2(-toward[1], toward[0])}
        reason = None
        support = []
        for t in road_tris:
            weights = barycentric(p, t)
            if weights: support.append(sum(weights[i] * t[i][1] for i in range(3)))
        if not support or max(support) < 0.06: reason = reason or '不是實際人行道頂面'
        else:
            row['surface_height'] = max(support)
            # 單精度 physics 的同平面取樣可相差約1e-7m；向上量化到10µm。
            row['position'][1] = math.ceil(max(support) * 100000) / 100000
        for name, ts, bounds in buildings:
            if not (bounds[0] - CLEARANCE <= p[0] <= bounds[2] + CLEARANCE and bounds[1] - CLEARANCE <= p[1] <= bounds[3] + CLEARANCE): continue
            if any(barycentric(p, t) is not None or min(segment_distance(p, xz(t[i]), xz(t[(i + 1) % 3])) for i in range(3)) < CLEARANCE for t in ts):
                reason = reason or '建築外緣不足0.5m:' + name
                break
        if any(length(sub(p, xz(old['position']))) < MIN_DISTANCE - 1e-6 for old in accepted): reason = reason or '與已排燈位過近（12m）'
        if reason:
            row['reason'] = reason
            skipped.append(row)
        else: accepted.append(row)

    for row in sorted(roads, key=lambda r: (r["name"].endswith("__Road1"), r["name"])):
        if row['group'] != 'Junctions': continue
        pivot, local_dirs = local_ports(row, catalog)
        center = xz(transform(row, pivot))
        dirs = [unit((row['basis'][0][0] * d[0] + row['basis'][2][0] * d[1], row['basis'][0][2] * d[0] + row['basis'][2][2] * d[1])) for d in local_dirs]
        angles = sorted(math.atan2(d[1], d[0]) for d in dirs)
        if len(dirs) == 2 and dot(dirs[0], dirs[1]) < -0.999:
            n = (-dirs[0][1], dirs[0][0])
            consider(add(center, mul(n, OFFSET)), mul(n, -1), row['name'], 'through', 0)
            continue
        for index, angle in enumerate(angles):
            gap = (angles[(index + 1) % len(angles)] - angle) % math.tau
            if gap >= math.pi - 0.01: continue  # 外側扇區不是路口內角。
            bisector = (math.cos(angle + gap / 2), math.sin(angle + gap / 2))
            p = add(center, mul(bisector, OFFSET / math.sin(gap / 2)))
            consider(p, sub(center, p), row['name'], 'corner', index)

    edges = collections.defaultdict(list)
    for row in roads:
        if row['group'] == 'Connections':
            match = re.fullmatch(r'(.+)_to_(.+)_\d+', row['name'])
            assert match, row['name']
            edges[f'{match[1]}_to_{match[2]}'].append(row)
    edge_anchors = []
    for name, modules in sorted(edges.items()):
        origin = xz(modules[0]['origin'])
        direction = unit(xz(modules[0]['basis'][2]))
        normal = (-direction[1], direction[0])
        projection = [dot(sub(xz(v), origin), direction) for row in modules for t in triangles(row) for v in t]
        low, high = min(projection), max(projection)
        # 優先內角燈已全數排完；直路由固定端的相鄰路口燈起算30m。
        # 用 source 節點關係選相鄰路口，避免隔街燈成為錯誤 anchor。
        endpoint_names = name.split('_to_')
        anchors = [r for r in accepted if r['kind'] in ('corner', 'through')
                   and r['source'].split('__')[0] in endpoint_names
                   and abs(dot(sub(xz(r['position']), origin), normal)) < 8]
        near_start = [r for r in anchors if dot(sub(xz(r['position']), origin), direction) <= low + 12]
        anchor = max(near_start, key=lambda r: (dot(sub(xz(r['position']), origin), direction), r['id']), default=None)
        start = dot(sub(xz(anchor['position']), origin), direction) if anchor else low
        phase = -1 if anchor and dot(sub(xz(anchor['position']), origin), normal) >= 0 else 1
        stations = []
        station = start + SPACING
        while station <= high + 1e-6:
            if station >= low - 1e-6: stations.append(station)
            station += SPACING
        edge_anchors.append({'edge': name, 'anchor': anchor['id'] if anchor else 'connection-start',
                             'origin_station_m': start, 'stations_m': stations})
        for i, station in enumerate(stations):
            side = phase * (-1) ** i
            p = add(add(origin, mul(direction, station)), mul(normal, side * OFFSET))
            consider(p, mul(normal, -side), name, 'straight', i)
    old_mapping = []
    for i, old in enumerate(data['existing_lamps']):
        nearest = min(accepted, key=lambda r: length(sub(xz(r['position']), xz(old['position']))))
        d = length(sub(xz(nearest['position']), xz(old['position'])))
        old_mapping.append({'old': i + 1, 'old_position': old['position'], 'proposal': nearest['id'], 'distance_m': d, 'action': '保留／微調到演算法燈位' if d < 2 else '由鄰近演算法燈位取代'})
    return {'phase': 'R3-B，已核可規則之生成燈位', 'minimum_distance_m': MIN_DISTANCE, 'edge_anchors': edge_anchors, 'actual_minimum_distance_m': min(length(sub(xz(a['position']), xz(b['position']))) for i, a in enumerate(accepted) for b in accepted[i+1:]), 'spacing_m': SPACING, 'offset_m': OFFSET, 'pole_radius_m': 0.18, 'building_edge_clearance_m': 0.5,
            'statistics': {'road_modules': len(roads), 'junctions': sum(r['group'] == 'Junctions' for r in roads), 'connection_edges': len(edges), 'buildings': len(buildings), 'lamps': len(accepted), 'skipped': len(skipped), 'by_kind': dict(collections.Counter(r['kind'] for r in accepted)), 'skip_reasons': dict(collections.Counter(r['reason'].split(':')[0] for r in skipped))},
            'lamps': accepted, 'skipped': skipped, 'existing_six': old_mapping}


def svg(data, plan):
    all_points = [xz(v) for r in data['roads'] for t in triangles(r) for v in t]
    lo_x, lo_z = min(p[0] for p in all_points) - 12, min(p[1] for p in all_points) - 12
    hi_x, hi_z = max(p[0] for p in all_points) + 12, max(p[1] for p in all_points) + 12
    scale = min(1480 / (hi_x - lo_x), 1480 / (hi_z - lo_z))
    def point(p): return ((p[0] - lo_x) * scale + 60, (p[1] - lo_z) * scale + 100)
    def pts(values): return ' '.join(f'{x:.2f},{y:.2f}' for x, y in map(point, values))
    elements = ['<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1700" viewBox="0 0 1600 1700">', '<rect width="1600" height="1700" fill="#14202b"/>', '<g font-family="Microsoft JhengHei,Noto Sans CJK TC,sans-serif" fill="#e2e9ed">', '<text x="60" y="42" font-size="27">LEA-212 R3-B 全圖路燈配置（最小間距12m）</text>', f'<text x="60" y="76" font-size="18">黃點／箭頭：燈柱／燈臂　紅叉：略過　青點：出生　預計 {len(plan["lamps"])} 盞，略過 {len(plan["skipped"])} 處</text>', '</g>']
    for row in data['roads']:
        for tri in triangles(row):
            color = '#829098' if sum(v[1] for v in tri) / 3 > .06 else '#354858'
            elements.append(f'<polygon points="{pts([xz(v) for v in tri])}" fill="{color}"/>')
    for row in data['buildings']:
        for tri in triangles(row): elements.append(f'<polygon points="{pts([xz(v) for v in tri])}" fill="#5a666b"/>')
    for row in plan['skipped']:
        x, y = point(xz(row['position']))
        elements.append(f'<path d="M{x-3},{y-3}l6,6m-6,0l6,-6" stroke="#d96b69"><title>{html.escape(row["id"]+"："+row["reason"])}</title></path>')
    for row in plan['lamps']:
        x, y = point(xz(row['position']))
        a = row['arm']; tip = (x + a[0] * 9, y + a[1] * 9)
        elements.append(f'<g><title>{html.escape(row["id"])}</title><circle cx="{x}" cy="{y}" r="3.4" fill="#ffd36d"/><path d="M{x},{y}L{tip[0]},{tip[1]}" stroke="#ffd36d" stroke-width="2"/><circle cx="{tip[0]}" cy="{tip[1]}" r="1.5" fill="#fff0bd"/></g>')
    x, y = point(xz(data['spawn']))
    elements.append(f'<circle cx="{x}" cy="{y}" r="7" fill="#48e5de" stroke="#ffffff" stroke-width="2"/>')
    elements.append('<text x="60" y="1650" fill="#d6e0e6" font-size="18" font-family="Microsoft JhengHei,sans-serif">北在上（−Z）｜燈柱中心距道路中心線約5.5m｜約30m交錯｜實際碰撞／人行道篩選｜滑鼠指向符號可看來源</text></svg>')
    return '\n'.join(elements)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('geometry', type=Path)
    parser.add_argument('catalog', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    data, catalog = json.loads(args.geometry.read_text()), json.loads(args.catalog.read_text())
    plan = generate(data, catalog)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'lamp-plan.json').write_text(json.dumps(plan, ensure_ascii=False, indent=2))
    (args.output / 'lamp-plan.svg').write_text(svg(data, plan))
    runtime = ["## 自 generate_lamp_plan.py 產生；請修改道路資料／規則後重新生成。", "extends RefCounted", "const LAMPS := ["]
    for lamp in plan['lamps']:
        x, y, z = lamp['position']
        runtime.append(f'\t[Vector3({x:.8f}, {y:.8f}, {z:.8f}), {lamp["yaw"]:.10f}, "{lamp["id"]}"],')
    runtime.append("]\n")
    (args.output / 'lamp_layout.gd').write_text('\n'.join(runtime))
    print(json.dumps(plan['statistics'], ensure_ascii=False))


if __name__ == '__main__': main()
