#!/usr/bin/env python3
"""彙整 profile_rain_weather 的交錯樣本，不把CPU/GPU時間相加或挑選最快組。"""
import argparse
import json
import statistics
from pathlib import Path


def group_records(records):
    groups = []
    for view in ['f5', 'dense-street']:
        for version in ['A', 'B']:
            rows = [row for row in records if row['view'] == view and row['version'] == version]
            if len(rows) < 3:
                raise ValueError('每版每機位至少三次:' + view + version)
            medians = [row['steady']['interval_ms']['median'] for row in rows]
            groups.append({'view': view, 'version': version, 'trials': len(rows),
                           'labels': [row['label'] for row in rows],
                           'median_of_frame_interval_medians_ms': statistics.median(medians),
                           'frame_interval_median_range_ms': [min(medians), max(medians)],
                           'all_frame_interval_medians_above17_5': all(v > 17.5 for v in medians),
                           'legacy_process_report_medians_ms': [row['steady']['process_ms']['median'] for row in rows],
                           'measured_fps_range': [min(row['measured_fps'] for row in rows), max(row['measured_fps'] for row in rows)],
                           'all_steady_focused': all(row['steady']['focused_frames'] == 240 for row in rows),
                           'median_of_viewport_gpu_medians_ms': statistics.median(row['steady']['viewport_gpu_ms']['median'] for row in rows) if all(row['steady']['viewport_gpu_ms']['n'] > 0 for row in rows) else None,
                           'median_of_viewport_cpu_medians_ms': statistics.median(row['steady']['viewport_cpu_ms']['median'] for row in rows),
                           'median_of_setup_cpu_medians_ms': statistics.median(row['steady']['setup_cpu_ms']['median'] for row in rows)})
    return groups


def summarize(root):
    commands = json.loads((root / 'commands.json').read_text())
    records = []
    for command in commands:
        if command['exit'] != 0:
            raise ValueError('原生執行失敗:' + command['label'])
        profile = json.loads((root / command['label'] / 'profile.json').read_text())
        for view in profile['views']:
            row = {'label': command['label'], 'version': command['version'], 'trial': command['trial'], 'view': view['view'],
                   'transform': view['transform'], 'size': view['size'], 'steady': view['steady'],
                   'enabled_street_lights': sum(lamp['enabled'] for lamp in view['street_lights']),
                   'shadowed_street_lights': sum(lamp['enabled'] and lamp['shadow'] for lamp in view['street_lights']),
                   'budget_dropped': view['budget_dropped'],
                   'process_report_updates_in_240_reads': 1 + sum(a['process_ms'] != b['process_ms'] for a, b in zip(view['steady_samples'], view['steady_samples'][1:])),
                   'measured_fps': 240000.0 / sum(sample['interval_ms'] for sample in view['steady_samples']),
                   'conditions': {key: profile[key] for key in ['adapter', 'renderer', 'viewport', 'vsync', 'max_fps', 'refresh_hz', 'grass_enabled', 'atlas_size', 'atlas_16bits', 'atlas_quadrants']}}
            row['conditions']['engine_hash'] = profile['engine']['hash']
            if len(view['warmup_samples']) != 360 or len(view['steady_samples']) != 240:
                raise ValueError('360/240筆數不正確:' + row['label'])
            records.append(row)
    common_keys = ['engine_hash', 'adapter', 'renderer', 'viewport', 'vsync', 'max_fps', 'refresh_hz', 'grass_enabled']
    for key in common_keys:
        if len({json.dumps(row['conditions'][key]) for row in records}) != 1:
            raise ValueError('比較條件不一致:' + key)
    for view in ['f5', 'dense-street']:
        rows = [row for row in records if row['view'] == view]
        if len({(row['transform'], row['size']) for row in rows}) != 1:
            raise ValueError('機位不一致:' + view)
    candidates = [row for row in records if row['version'] == 'B']
    if any(row['enabled_street_lights'] != row['shadowed_street_lights'] or row['budget_dropped'] != 0 for row in candidates):
        raise ValueError('候選出現關燈或未投影')
    focused_trials = [trial for trial in sorted({row['trial'] for row in records})
                      if len([row for row in records if row['trial'] == trial]) == 4
                      and all(row['steady']['focused_frames'] == 240 for row in records if row['trial'] == trial)]
    controlled = [row for row in records if row['trial'] in focused_trials]
    controlled_groups = group_records(controlled)
    return {'record_count': len(records), 'records': records, 'groups': group_records(records),
            'controlled_focused_pairs': focused_trials, 'controlled_groups': controlled_groups,
            'reference_labels': sorted({row['label'] for row in records if row['trial'] not in focused_trials}),
            'monitor_semantics': 'TIME_PROCESS/PHYSICS/NAVIGATION為約1Hz回報上一區間最大值，240次重讀不代表240筆逐幀量測；原始欄位保留追溯。CPU/GPU各項不相加，GPU timestamp與CPU不宣稱逐幀對齊。',
            'engine_source': 'https://raw.githubusercontent.com/godotengine/godot/a13da4feb8d8aefc283c3763d33a2f170a18d541/main/main.cpp',
            'gate_definition': '至少3組完整前景配對；所有候選dense實際繪製間隔median均>17.5ms，才視為穩定超標；失焦組完整保留為參考，不篩選最快組。',
            'lower_resolution_gate_met': next(group['all_frame_interval_medians_above17_5'] for group in controlled_groups if group['view'] == 'dense-street' and group['version'] == 'B')}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    result = summarize(args.root)
    (args.root / 'summary.json').write_text(json.dumps(result, ensure_ascii=False, indent=2))
    for group in result['controlled_groups']:
        print(json.dumps(group, ensure_ascii=False))
    print('lower_resolution_gate_met=', result['lower_resolution_gate_met'])


if __name__ == '__main__':
    main()
