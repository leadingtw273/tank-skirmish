#!/usr/bin/env python3
"""作者覆蓋回歸：由獨立道路拓樸重算間隙，不讀生成器coverage結論。"""
import argparse
import json
import math
from pathlib import Path


def check(plan, graph):
    points = [(row['id'], (row['position'][0], row['position'][2])) for row in plan['lamps']]
    failures = []
    minimum = min(math.dist(a[1], b[1]) for i, a in enumerate(points) for b in points[i + 1:])
    if minimum < 12 - 1e-5: failures.append('柱距不足12m')
    missing = [node for node, center in graph['nodes'].items() if not any(math.dist(center, p) <= 16.5 for _, p in points)]
    if missing: failures.append('路口無近燈:' + ','.join(missing))
    lines = {}
    edge_rows = []
    for edge in graph['connections']:
        a, b = graph['nodes'][edge['from']], graph['nodes'][edge['to']]
        length = math.dist(a, b)
        direction = ((b[0] - a[0]) / length, (b[1] - a[1]) / length)
        if direction[0] < -1e-5 or (abs(direction[0]) < 1e-5 and direction[1] < 0): direction = (-direction[0], -direction[1])
        normal = (-direction[1], direction[0])
        dot = lambda p, v: p[0] * v[0] + p[1] * v[1]
        low, high = sorted([dot(a, direction), dot(b, direction)])
        offset = dot(a, normal)
        key = (round(math.atan2(direction[1], direction[0]), 4), round(offset, 2))
        row = {'id': edge['from'] + '_to_' + edge['to'], 'low': low, 'high': high, 'direction': direction, 'normal': normal, 'offset': offset}
        edge_rows.append(row)
        lines.setdefault(key, []).append(row)
    corridors = []
    for key, rows in sorted(lines.items()):
        for row in sorted(rows, key=lambda r: r['low']):
            if corridors and corridors[-1]['key'] == key and row['low'] <= corridors[-1]['high'] + .1:
                corridors[-1]['high'] = max(corridors[-1]['high'], row['high'])
            else: corridors.append(dict(row, key=key))
    measurements = []
    for route in edge_rows + corridors:
        d, n = route['direction'], route['normal']
        stations = sorted((p[0] * d[0] + p[1] * d[1], name) for name, p in points
                          if abs(p[0] * n[0] + p[1] * n[1] - route['offset']) <= 7.75
                          and route['low'] - 1e-5 <= p[0] * d[0] + p[1] * d[1] <= route['high'] + 1e-5)
        positions = [route['low']] + [s[0] for s in stations] + [route['high']]
        gaps = [b - a for a, b in zip(positions, positions[1:])]
        maximum = max(gaps, default=0)
        measurements.append({'id': route['id'], 'length_m': route['high'] - route['low'], 'stations': stations, 'maximum_gap_m': maximum})
        if maximum > 36 + 1e-4: failures.append(route['id'] + ':沿路空隙%.4fm' % maximum)
    return {'lamps': len(points), 'nodes': len(graph['nodes']), 'edges': len(edge_rows), 'corridors': len(corridors),
            'minimum_pole_distance_m': minimum, 'missing_junctions': missing,
            'maximum_along_road_gap_m': max(r['maximum_gap_m'] for r in measurements), 'measurements': measurements, 'failures': failures}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('plan', type=Path)
    parser.add_argument('graph', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = check(json.loads(args.plan.read_text()), json.loads(args.graph.read_text()))
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    print(json.dumps({k: v for k, v in result.items() if k != 'measurements'}, ensure_ascii=False))
    raise SystemExit(bool(result['failures']))


if __name__ == '__main__': main()
