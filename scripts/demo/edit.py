#!/usr/bin/env python3
"""Smooth, fixed-keyframe zoom/pan using ffmpeg. Never captures a screen."""
import argparse
import json
import math
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent


def load_timeline(path):
    data = json.loads(Path(path).read_text())
    if data.get('status') in ('needs_footage', 'needs_review_inputs'):
        raise ValueError('main A/B timeline awaits reviewed source timecodes and measured focus framing; editorial plan cannot render')
    if data.get('status') == 'needs_framing_review':
        raise ValueError('timeline framing awaits review; calibrate its keyframes before rendering')
    frames = data['keyframes']
    if len(frames) < 2 or frames[0]['at'] != 0:
        raise ValueError('timeline needs at least two keyframes, starting at 0')
    previous = -1
    for frame in frames:
        if any(not isinstance(frame[k], (int, float)) or not math.isfinite(frame[k]) for k in ('at', 'zoom', 'x', 'y')):
            raise ValueError('keyframe numbers must be finite')
        if frame['at'] <= previous or frame['at'] < 0:
            raise ValueError('keyframe times must strictly increase')
        if not 1 <= frame['zoom'] <= 3 or not 0 <= frame['x'] <= 1 or not 0 <= frame['y'] <= 1:
            raise ValueError('zoom range 1..3; normalized x/y range 0..1')
        previous = frame['at']
    return frames


def expression(frames, key):
    # Smoothstep has zero velocity at each endpoint; holds use equal values.
    result = str(frames[-1][key])
    for left, right in reversed(list(zip(frames, frames[1:]))):
        u = f'((on/30-{left["at"]})/{right["at"] - left["at"]})'
        eased = f'({u}*{u}*(3-2*{u}))'
        value = f'({left[key]}+({right[key]}-{left[key]})*{eased})'
        result = f'if(lt(on/30,{right["at"]}),{value},{result})'
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--timeline', type=Path, default=ROOT / 'timeline.json')
    parser.add_argument('--start', type=float, default=0, help='Trim lead-in seconds so scenario T=0 aligns')
    parser.add_argument('--dry-run', action='store_true', help='Validate and print filter; no encoding')
    args = parser.parse_args()
    if not math.isfinite(args.start) or args.start < 0:
        raise ValueError('start must be finite and nonnegative')
    frames = load_timeline(args.timeline)
    if args.input.resolve() == args.output.resolve() or args.output.exists():
        raise ValueError('output must be new and different from input')
    info = json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(args.input.resolve()),
    ], text=True))
    video = next(stream for stream in info['streams'] if stream['codec_type'] == 'video')
    # Capture dimensions must be even for yuv420p. Keep the original aspect and size.
    width, height = int(video['width']) // 2 * 2, int(video['height']) // 2 * 2
    duration = float(info['format']['duration']) - args.start
    if duration <= frames[-1]['at']:
        raise ValueError('clip after lead-in must extend beyond the final keyframe')
    z, cx, cy = (expression(frames, key) for key in ('zoom', 'x', 'y'))
    filter_text = (
        f"fps=30,scale=iw*2:ih*2,zoompan=z='{z}':"
        f"x='max(0,min(iw-iw/zoom,iw*({cx})-iw/zoom/2))':"
        f"y='max(0,min(ih-ih/zoom,ih*({cy})-ih/zoom/2))':"
        f'd=1:s={width}x{height}:fps=30,setsar=1'
    )
    if args.dry_run:
        print(filter_text)
        return
    subprocess.run([
        'ffmpeg', '-hide_banner', '-loglevel', 'error', '-nostdin', '-n',
        '-ss', str(args.start), '-noautorotate', '-i', str(args.input.resolve()),
        '-map', '0:v:0', '-map', '0:a:0?', '-vf', filter_text,
        '-c:v', 'libx264', '-preset', 'fast', '-crf', '18', '-pix_fmt', 'yuv420p',
        '-c:a', 'aac', '-movflags', '+faststart', str(args.output.resolve()),
    ], check=True)
    print(f'Created {args.output}')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, StopIteration, OSError, subprocess.SubprocessError) as error:
        print(f'Edit failed: {error}', file=sys.stderr)
        sys.exit(1)
