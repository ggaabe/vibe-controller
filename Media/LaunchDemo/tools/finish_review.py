"""Level the native Resolve review export without altering its picture or timing.

The original camera file and Resolve export are read-only inputs. This is the
review-delivery audio pass, not a replacement for the editable source timeline.
"""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'review/vibe-controller-speech-review-native.mp4'
OUTPUT = ROOT / 'exports/vibe-controller-speech-review.mp4'
PLACEMENTS = json.loads((ROOT / 'review/cut-placements.json').read_text())
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
SAMPLE_RATE = 48000


def sample_at(frame):
    return round(frame * 1001 * SAMPLE_RATE / 30000)


def audio_graph():
    start = PLACEMENTS[0]['start']
    split_labels = ''.join(f'[a{i}]' for i in range(len(PLACEMENTS)))
    filters = [f'[0:a]aresample={SAMPLE_RATE},asplit={len(PLACEMENTS)}{split_labels}']
    for i, clip in enumerate(PLACEMENTS):
        lo = sample_at(clip['start'] - start)
        hi = sample_at(clip['end'] - start)
        duration = (hi - lo) / SAMPLE_RATE
        # Six-millisecond edge fades suppress cut clicks, with no time overlap,
        # added silence, retiming, or change to the controller response footage.
        filters.append(
            f'[a{i}]atrim=start_sample={lo}:end_sample={hi},asetpts=PTS-STARTPTS,'
            f'afade=t=in:st=0:d=0.006,'
            f'afade=t=out:st={duration - 0.006:.9f}:d=0.006[c{i}]'
        )
    filters.append(''.join(f'[c{i}]' for i in range(len(PLACEMENTS))) +
                   f'concat=n={len(PLACEMENTS)}:v=0:a=1[smooth]')
    return ';'.join(filters)


def run(args, log_name):
    result = subprocess.run(args, capture_output=True, text=True)
    (ROOT / 'review' / log_name).write_text(result.stderr)
    result.check_returncode()
    return result.stderr


graph = audio_graph()
log = run([
    'ffmpeg', '-hide_banner', '-nostats', '-i', str(SOURCE),
    '-filter_complex', graph + ';[smooth]loudnorm=I=-16:TP=-1.5:LRA=7:print_format=json[out]',
    '-map', '[out]', '-f', 'null', '-'
], 'review-loudness-pass1.log')
measurement = json.loads(re.findall(r'\{\s*"input_i".*?\}', log, re.S)[-1])
(ROOT / 'review/review-loudness-measurement.json').write_text(json.dumps(measurement, indent=2))

normalize = (
    'loudnorm=I=-16:TP=-1.5:LRA=7:linear=false:'
    f'measured_I={measurement["input_i"]}:'
    f'measured_TP={measurement["input_tp"]}:'
    f'measured_LRA={measurement["input_lra"]}:'
    f'measured_thresh={measurement["input_thresh"]}:'
    f'offset={measurement["target_offset"]}:print_format=json'
)
run([
    'ffmpeg', '-hide_banner', '-nostats', '-n', '-i', str(SOURCE),
    '-filter_complex', graph + f';[smooth]{normalize},aresample=48000[out]',
    '-map', '0:v:0', '-map', '[out]', '-c:v', 'copy',
    '-c:a', 'aac', '-b:a', '256k', '-ar', '48000',
    '-map_metadata', '-1', '-movflags', '+faststart',
    '-metadata', 'title=Vibe Controller - Speech Review', str(OUTPUT)
], 'review-loudness-pass2.log')
print(json.dumps({'output': str(OUTPUT), 'input_measurement': measurement}, indent=2))
