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
    # 6m空間索引只加速真實三角形查詢，不用AABB代替人行道／建築幾何。
    cells = collections.defaultdict(list)
    for road in roads:
        for tri in triangles(road):
            if max(v[1] for v in tri) < 0.06: continue
            xs, zs = [v[0] for v in tri], [v[2] for v in tri]
            for x in range(math.floor(min(xs) / 6), math.floor(max(xs) / 6) + 1):
                for z in range(math.floor(min(zs) / 6), math.floor(max(zs) / 6) + 1):
                    cells[x, z].append(tri)
    buildings = []
    for building in data['buildings']:
        ts = triangles(building)
        pts = [xz(v) for t in ts for v in t]
        if pts:
            buildings.append((building['name'], ts, (min(p[0] for p in pts), min(p[1] for p in pts), max(p[0] for p in pts), max(p[1] for p in pts))))
    accepted, skipped, adjustments = [], [], []
    geometry_cache = {}

    def geometry(p):
        key = tuple(round(v, 6) for v in p)
        if key in geometry_cache: return geometry_cache[key]
        support = []
        for tri in cells[math.floor(p[0] / 6), math.floor(p[1] / 6)]:
            w = barycentric(p, tri)
            if w: support.append(sum(w[i] * tri[i][1] for i in range(3)))
        height = max(support, default=0)
        reason = None if height >= 0.06 else '不是實際人行道頂面'
        if reason is None:
            for name, ts, bounds in buildings:
                if not (bounds[0] - CLEARANCE <= p[0] <= bounds[2] + CLEARANCE and bounds[1] - CLEARANCE <= p[1] <= bounds[3] + CLEARANCE): continue
                if any(barycentric(p, t) is not None or min(segment_distance(p, xz(t[i]), xz(t[(i + 1) % 3])) for i in range(3)) < CLEARANCE for t in ts):
                    reason = '建築外緣不足0.5m:' + name
                    break
        geometry_cache[key] = (height, reason)
        return height, reason

    def place(options, source, kind, station):
        identity = f'{source}:{kind}:{station}'
        if any(row['id'] == identity for row in accepted): return True
        reasons = collections.Counter()
        for p, toward in options:
            height, reason = geometry(p)
            if reason is None and any(length(sub(p, xz(old['position']))) < MIN_DISTANCE - 1e-6 for old in accepted):
                reason = '與已排燈位過近（12m）'
            if reason:
                reasons[reason] += 1
                continue
            row = {'id': identity, 'source': source, 'kind': kind, 'position': [p[0], math.ceil(height * 100000) / 100000, p[1]],
                   'surface_height': height, 'arm': list(unit(toward)), 'yaw': math.atan2(-toward[1], toward[0])}
            accepted.append(row)
            movement = length(sub(p, options[0][0]))
            if movement > 0.01:
                adjustments.append({'id': identity, 'original_xz': options[0][0], 'moved_m': movement, 'position': row['position']})
            return True
        skipped.append({'id': identity, 'source': source, 'kind': kind,
                        'position': [options[0][0][0], 0, options[0][0][1]], 'reason': '有限替代位置皆不可用', 'attempt_reasons': dict(reasons)})
        return False

    junctions = {}
    for road in sorted(roads, key=lambda r: r['name']):
        if road['group'] != 'Junctions': continue
        pivot, local_dirs = local_ports(road, catalog)
        center = xz(transform(road, pivot))
        dirs = [unit((road['basis'][0][0] * d[0] + road['basis'][2][0] * d[1], road['basis'][0][2] * d[0] + road['basis'][2][2] * d[1])) for d in local_dirs]
        angles = sorted(math.atan2(d[1], d[0]) for d in dirs)
        groups = []
        if len(dirs) == 2 and dot(dirs[0], dirs[1]) < -0.999:
            n = (-dirs[0][1], dirs[0][0])
            groups.append(('through', 0, [(add(center, mul(n, OFFSET)), mul(n, -1))]))
        else:
            for index, angle in enumerate(angles):
                gap = (angles[(index + 1) % len(angles)] - angle) % math.tau
                if gap >= math.pi - 0.01: continue
                bisector = (math.cos(angle + gap / 2), math.sin(angle + gap / 2))
                p = add(center, mul(bisector, OFFSET / math.sin(gap / 2)))
                options = [(p, sub(center, p))]
                # 11m寬道路兩側內角會衝突；沿相鄰支路錯開約5m，而非刪掉整個角。
                for shift in range(1, 9):
                    for direction in [(math.cos(angle), math.sin(angle)), (math.cos(angle + gap), math.sin(angle + gap))]:
                        q = add(p, mul(direction, shift))
                        if length(sub(q, center)) <= 16:
                            options.append((q, sub(add(center, mul(direction, dot(sub(q, center), direction))), q)))
                groups.append(('corner', index, options))
        fallback = []
        for distance in [6, 8, 4, 10, 12]:
            for direction in dirs:
                normal = (-direction[1], direction[0])
                for side in [-1, 1]:
                    p = add(add(center, mul(direction, distance)), mul(normal, side * OFFSET))
                    fallback.append((p, mul(normal, -side)))
        junctions[road['name'].split('__')[0]] = {'name': road['name'], 'center': center, 'groups': groups, 'fallback': fallback}
    # 先完成每節點一盞，包括原先漏掉的四個45度彎，再配置其餘內角。
    for junction in junctions.values():
        covered = any(place(options, junction['name'], kind, index) for kind, index, options in junction['groups'])
        if not covered:
            assert place(junction['fallback'], junction['name'], 'junction', 0), junction['name'] + ': 無合法路口保底燈位'
    for junction in junctions.values():
        for kind, index, options in junction['groups']:
            place(options, junction['name'], kind, index)

    edges = collections.defaultdict(list)
    for road in roads:
        if road['group'] == 'Connections':
            match = re.fullmatch(r'(.+)_to_(.+)_\d+', road['name'])
            assert match, road['name']
            edges[f'{match[1]}_to_{match[2]}'].append(road)
    edge_rows, lines = [], collections.defaultdict(list)
    for name, modules in sorted(edges.items()):
        origin = xz(modules[0]['origin'])
        direction = unit(xz(modules[0]['basis'][2]))
        if direction[0] < -1e-5 or (abs(direction[0]) < 1e-5 and direction[1] < 0): direction = mul(direction, -1)
        normal = (-direction[1], direction[0])
        angle = math.atan2(direction[1], direction[0])
        offset = dot(origin, normal)
        endpoints = [junctions[node]['center'] for node in name.split('_to_')]
        projections = [dot(xz(v), direction) for module in modules for tri in triangles(module) for v in tri] + [dot(p, direction) for p in endpoints]
        row = {'id': name, 'direction': direction, 'normal': normal, 'offset': offset, 'low': min(projections), 'high': max(projections)}
        edge_rows.append(row)
        lines[round(angle, 5), round(offset, 3)].append(row)
    # 合併穿過路口的共線道路，避免在每條edge的虛擬端點把實際長空隙藏起來。
    corridors = []
    for key, segments in sorted(lines.items()):
        for segment in sorted(segments, key=lambda r: r['low']):
            if corridors and corridors[-1]['line'] == key and segment['low'] <= corridors[-1]['high'] + 0.1:
                corridors[-1]['high'] = max(corridors[-1]['high'], segment['high'])
                corridors[-1]['edges'].append(segment['id'])
            else:
                corridors.append(dict(segment, id='corridor-%d' % len(corridors), line=key, edges=[segment['id']]))

    def coverage(route):
        stations = sorted((dot(xz(row['position']), route['direction']), row['id']) for row in accepted
                          if abs(dot(xz(row['position']), route['normal']) - route['offset']) <= 7.75
                          and route['low'] - 1e-5 <= dot(xz(row['position']), route['direction']) <= route['high'] + 1e-5)
        points = [(route['low'], 'START')] + stations + [(route['high'], 'END')]
        gaps = [{'from': a[1], 'to': b[1], 'start_m': a[0], 'end_m': b[0], 'gap_m': b[0] - a[0]} for a, b in zip(points, points[1:])]
        return {'id': route['id'], 'length_m': route['high'] - route['low'], 'stations': stations, 'gaps': gaps,
                'maximum_gap_m': max((g['gap_m'] for g in gaps), default=0),
                'maximum_lamp_pair_gap_m': max((b[0] - a[0] for a, b in zip(stations, stations[1:])), default=0)}

    failed_gaps = set()
    for iteration in range(300):
        work = sorted(((gap['gap_m'], route, gap) for route in corridors for gap in coverage(route)['gaps']
                       if gap['gap_m'] > SPACING + 1e-4 and (route['id'], gap['from'], gap['to']) not in failed_gaps), key=lambda item: (-item[0], item[1]['id']))
        if not work: break
        _, route, gap = work[0]
        midpoint = (gap['start_m'] + gap['end_m']) / 2
        options = []
        preferred_side = -1 if sum(route['id'].encode()) % 2 else 1
        previous = next((r for r in accepted if r['id'] == gap['from']), None)
        if previous:
            preferred_side = -1 if dot(xz(previous['position']), route['normal']) - route['offset'] > 0 else 1
        for shift in [0] + [value for step in range(1, 13) for value in [-step, step]]:
            station = midpoint + shift
            if not (max(route['low'], gap['start_m'] + 1) <= station <= min(route['high'], gap['end_m'] - 1)): continue
            for side in [preferred_side, -preferred_side]:
                p = add(mul(route['direction'], station), mul(route['normal'], route['offset'] + side * OFFSET))
                options.append((p, mul(route['normal'], -side)))
        if not options or not place(options, route['id'], 'straight', iteration):
            failed_gaps.add((route['id'], gap['from'], gap['to']))
    corridor_coverage = [coverage(route) for route in corridors]
    edge_coverage = [coverage(route) for route in edge_rows]
    maximum_gap = max(row['maximum_gap_m'] for row in corridor_coverage + edge_coverage)
    assert maximum_gap <= 36.0001, '沿路空隙超標: ' + str([(row['id'], row['maximum_gap_m']) for row in corridor_coverage + edge_coverage if row['maximum_gap_m'] > 36.0001])
    junction_coverage = [{'node': node, 'lamps': [r['id'] for r in accepted if r['source'] == junction['name']]} for node, junction in junctions.items()]
    assert all(row['lamps'] for row in junction_coverage)
    minimum = min(length(sub(xz(a['position']), xz(b['position']))) for i, a in enumerate(accepted) for b in accepted[i + 1:])
    old_mapping = []
    for i, old in enumerate(data['existing_lamps']):
        nearest = min(accepted, key=lambda row: length(sub(xz(row['position']), xz(old['position']))))
        old_mapping.append({'old': i + 1, 'old_position': old['position'], 'proposal': nearest['id'], 'distance_m': length(sub(xz(nearest['position']), xz(old['position'])))})
    return {'phase': 'R3-B 覆蓋修正', 'minimum_distance_m': MIN_DISTANCE, 'actual_minimum_distance_m': minimum,
            'spacing_m': SPACING, 'maximum_allowed_gap_m': 36, 'maximum_along_road_gap_m': maximum_gap,
            'offset_m': OFFSET, 'pole_radius_m': 0.18, 'building_edge_clearance_m': 0.5,
            'statistics': {'road_modules': len(roads), 'junctions': len(junctions), 'connection_edges': len(edges), 'buildings': len(buildings), 'lamps': len(accepted), 'skipped': len(skipped),
                           'by_kind': dict(collections.Counter(row['kind'] for row in accepted)), 'skip_reasons': dict(collections.Counter(row['reason'] for row in skipped)), 'covered_junctions': sum(bool(row['lamps']) for row in junction_coverage),
                           'maximum_along_road_gap_m': maximum_gap, 'corridors': len(corridors)},
            'lamps': accepted, 'skipped': skipped, 'adjustments': adjustments, 'existing_six': old_mapping,
            'junction_coverage': junction_coverage, 'edge_coverage': edge_coverage, 'corridor_coverage': corridor_coverage}


def svg(data, plan):
    all_points = [xz(v) for r in data['roads'] for t in triangles(r) for v in t]
    lo_x, lo_z = min(p[0] for p in all_points) - 12, min(p[1] for p in all_points) - 12
    hi_x, hi_z = max(p[0] for p in all_points) + 12, max(p[1] for p in all_points) + 12
    scale = min(1480 / (hi_x - lo_x), 1480 / (hi_z - lo_z))
    def point(p): return ((p[0] - lo_x) * scale + 60, (p[1] - lo_z) * scale + 100)
    def pts(values): return ' '.join(f'{x:.2f},{y:.2f}' for x, y in map(point, values))
    elements = ['<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1700" viewBox="0 0 1600 1700">', '<rect width="1600" height="1700" fill="#14202b"/>', '<g font-family="Microsoft JhengHei,Noto Sans CJK TC,sans-serif" fill="#e2e9ed">', '<text x="60" y="42" font-size="27">LEA-212 R3-B 全圖路燈配置（12m淨距／沿路空隙≤36m）</text>', f'<text x="60" y="76" font-size="18">黃點／箭頭：燈柱／燈臂　紅叉：略過　青點：出生　預計 {len(plan["lamps"])} 盞，略過 {len(plan["skipped"])} 處</text>', '</g>']
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
