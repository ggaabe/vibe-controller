"""Translate the reviewed semantic edit plan into frame-exact Resolve requests."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
plan = json.loads((ROOT / 'review/editorial-plan.json').read_text())
fps = plan['source_fps']


def frames(tc):
    h, m, s, f = map(int, tc.split(':'))
    return ((h * 60 + m) * 60 + s) * fps + f


ranges = []
duration = 0
for segment in plan['segments']:
    start, end = frames(segment['in']), frames(segment['out'])
    assert end > start
    duration += (end - start) / fps
    for kind in ('video', 'audio'):
        ranges.append({'clip_id': plan['source_clip_id'], 'start_frame': start,
                       'end_frame': end - 1, 'track_type': kind, 'track_index': 1})

requests = [
    {'tool': 'timeline', 'arguments': {'action': 'create_variant_from_ranges',
      'params': {'name': plan['timeline_name'], 'ranges': ranges, 'pack': True,
                 'start_timecode': '01:00:00:00', 'dry_run': False}}},
    {'tool': 'timeline', 'arguments': {'action': 'probe_timeline_structure',
                                     'params': {'track_types': ['video', 'audio']}}},
    {'tool': 'project_manager', 'arguments': {'action': 'save'}},
    {'tool': 'render', 'arguments': {'action': 'get_codecs', 'params': {'format': 'mp4'}}},
]
(ROOT / 'review/create-cut-requests.json').write_text(json.dumps(requests, indent=2))
print(f'Planned speech cut: {duration:.3f} seconds across {len(plan["segments"])} semantic sections.')
