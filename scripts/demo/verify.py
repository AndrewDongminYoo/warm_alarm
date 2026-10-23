#!/usr/bin/env python3
"""Offline verification only: no screen capture or Apple Events."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent


def run(*args, ok=True, error=None):
    result = subprocess.run(list(map(str, args)), capture_output=True, text=True)
    if (result.returncode == 0) != ok:
        raise RuntimeError(f'Unexpected exit {result.returncode}: {args}\n{result.stdout}\n{result.stderr}')
    if error is not None and error not in result.stderr:
        raise RuntimeError(f'Expected error {error!r}, got: {result.stderr}')
    return result.stdout


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_zoom(differences):
    if differences[1] <= 10 * max(differences[0], differences[2]):
        raise ValueError('zoom phase must differ from overview frames')


def main():
    dest = Path(tempfile.mkdtemp(prefix='warm-alarm-demo-validation-'))
    source, edited = dest / 'synthetic.mp4', dest / 'edited.mp4'
    print(f'Evidence: {dest}', flush=True)
    run(sys.executable, ROOT / 'test_demo.py')
    run('bash', '-n', ROOT / 'doctor.sh')
    run('osacompile', '-o', dest / 'ui.scpt', ROOT / 'ui.applescript')
    for name in ('demo.py', 'edit.py', 'verify.py'):
        compile((ROOT / name).read_text(), str(ROOT / name), 'exec')
    dry = run(sys.executable, ROOT / 'demo.py')
    assert 'MANUAL A/B CUES' in dry and 'unsupportedWakeCheck' in dry and 'INPUT REQUIRED' in dry
    qa = ROOT / 'scenario-example-qa.json'
    qa_timeline = ROOT / 'timeline-example-qa.json'
    # Unmeasured capture templates are not approved media edits. Only temporary
    # copies are used below to exercise their numeric paths on synthetic video.
    for template in (qa_timeline, ROOT / 'timeline-b-macos.json'):
        run(sys.executable, ROOT / 'edit.py', source, dest / 'blocked-template.mp4',
            '--timeline', template, ok=False, error='framing awaits review')
    def synthetic_timeline(template):
        data = json.loads(template.read_text())
        data['status'] = 'synthetic_fixture'
        target = dest / ('synthetic-' + template.name)
        target.write_text(json.dumps(data))
        return target
    qa_timeline = synthetic_timeline(qa_timeline)
    assert 'Schedule 1 minute alarm' in run(sys.executable, ROOT / 'demo.py', '--scenario', qa)
    for flag in ('--run', '--inspect'):
        run(sys.executable, ROOT / 'demo.py', flag, '--confirmed-target', ok=False, error='main A/B is manual cue-only')
    run(sys.executable, ROOT / 'demo.py', '--scenario', qa, '--run', ok=False, error='then pass --confirmed-target')
    run(sys.executable, ROOT / 'demo.py', '--scenario', qa, '--inspect', ok=False, error='then pass --confirmed-target')
    bad_scenario = dest / 'bad-scenario.json'
    bad_scenario.write_text(json.dumps({'bundle_id': 'invalid', 'steps': [
        {'at': 0, 'action': 'focus'}, {'at': 0, 'action': 'focus'},
    ]}))
    run(sys.executable, ROOT / 'demo.py', '--scenario', bad_scenario, ok=False,
        error='step times must be finite, nonnegative, strictly increasing')
    timeline = dest / 'timeline.json'
    timeline.write_text(json.dumps({'keyframes': [
        {'at': 0, 'zoom': 1, 'x': .5, 'y': .5},
        {'at': 1, 'zoom': 1, 'x': .5, 'y': .5},
        {'at': 3, 'zoom': 1.5, 'x': .7, 'y': .4},
        {'at': 5, 'zoom': 1.5, 'x': .7, 'y': .4},
        {'at': 7, 'zoom': 1, 'x': .5, 'y': .5},
        {'at': 8, 'zoom': 1, 'x': .5, 'y': .5},
    ]}))
    run('ffmpeg', '-hide_banner', '-loglevel', 'error', '-nostdin', '-n',
        '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=30:duration=9',
        '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000:duration=9',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', source)
    before = digest(source)
    dry_filter = run(sys.executable, ROOT / 'edit.py', source, edited, '--timeline', timeline, '--dry-run')
    assert 'zoompan=' in dry_filter and not edited.exists(), 'editor dry run wrote output'
    run(sys.executable, ROOT / 'edit.py', source, edited, '--timeline', timeline)
    assert before == digest(source), 'source modified'
    info = json.loads(run('ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', edited))
    video = next(s for s in info['streams'] if s['codec_type'] == 'video')
    assert (video['width'], video['height'], video['r_frame_rate']) == (640, 360, '30/1')
    assert any(s['codec_type'] == 'audio' for s in info['streams'])
    assert abs(float(info['format']['duration']) - 9) < .1
    # Compare exact frame index at hold and zoom phases, rather than claiming visual quality from exit code.
    def pixels(path, index):
        return subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(path), '-vf',
            f'select=eq(n\\,{index})', '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'])
    differences = []
    for index in (0, 120, 240):
        a, b = pixels(source, index), pixels(edited, index)
        assert len(a) == len(b) == 640 * 360 * 3
        differences.append(sum(abs(x - y) for x, y in zip(a, b)) / len(a))
    # Prove this reader rejects a take with no zoom before trusting its pass.
    try:
        check_zoom([differences[0]] * 3)
    except ValueError as error:
        assert str(error) == 'zoom phase must differ from overview frames'
    else:
        raise RuntimeError('zoom check accepted unchanged overview frames')
    check_zoom(differences)
    for index in (0, 120, 240):
        run('ffmpeg', '-v', 'error', '-nostdin', '-n', '-i', edited, '-vf',
            f'select=eq(n\\,{index})', '-frames:v', '1', dest / f'preview-{index}.png')
    protected = digest(edited)
    run(sys.executable, ROOT / 'edit.py', source, edited, '--timeline', timeline, ok=False,
        error='output must be new and different from input')
    assert protected == digest(edited), 'existing output overwritten'
    run(sys.executable, ROOT / 'edit.py', source, source, '--timeline', timeline, ok=False,
        error='output must be new and different from input')
    run(sys.executable, ROOT / 'edit.py', source, dest / 'too-short.mp4', '--timeline', qa_timeline, ok=False,
        error='clip after lead-in must extend beyond the final keyframe')
    assert not (dest / 'too-short.mp4').exists()
    invalid = dest / 'invalid-timeline.json'
    invalid.write_text('{"keyframes":[{"at":0,"zoom":0,"x":0.5,"y":0.5},{"at":1,"zoom":1,"x":0.5,"y":0.5}]}')
    run(sys.executable, ROOT / 'edit.py', source, dest / 'invalid.mp4', '--timeline', invalid, ok=False,
        error='zoom range 1..3; normalized x/y range 0..1')
    # Exercise the actual presentation timeline and optional audio mapping as well.
    full_source, full_edit = dest / 'full-timeline-source.mp4', dest / 'full-timeline-edited.mp4'
    run('ffmpeg', '-hide_banner', '-loglevel', 'error', '-nostdin', '-n',
        '-f', 'lavfi', '-i', 'testsrc2=size=160x90:rate=30:duration=86',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', full_source)
    run(sys.executable, ROOT / 'edit.py', full_source, full_edit, '--timeline', qa_timeline)
    run(sys.executable, ROOT / 'edit.py', source, dest / 'blocked-main.mp4', '--dry-run', ok=False, error='main A/B timeline awaits reviewed source timecodes')
    assert not (dest / 'blocked-main.mp4').exists()
    full_info = json.loads(run('ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', full_edit))
    assert abs(float(full_info['format']['duration']) - 86) < .1
    assert len(full_info['streams']) == 1
    trimmed = dest / 'trimmed.mp4'
    run(sys.executable, ROOT / 'edit.py', source, trimmed, '--timeline', timeline, '--start', '.4')
    trimmed_info = json.loads(run('ffprobe', '-v', 'error', '-show_format', '-of', 'json', trimmed))
    assert abs(float(trimmed_info['format']['duration']) - 8.6) < .1
    b_scenario = ROOT / 'scenario-b-macos.json'
    b_timeline = synthetic_timeline(ROOT / 'timeline-b-macos.json')
    b_dry = run(sys.executable, ROOT / 'demo.py', '--scenario', b_scenario)
    assert 'DRY RUN' in b_dry and 'T+  30.0s hold' in b_dry
    assert b_dry.count('press ') == 2
    b_source, b_edit = dest / 'demo-b-source.mp4', dest / 'demo-b-edited.mp4'
    run('ffmpeg', '-hide_banner', '-loglevel', 'error', '-nostdin', '-n',
        '-f', 'lavfi', '-i', 'testsrc2=size=160x90:rate=30:duration=30',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', b_source)
    run(sys.executable, ROOT / 'edit.py', b_source, b_edit, '--timeline', b_timeline)
    b_info = json.loads(run('ffprobe', '-v', 'error', '-show_format', '-of', 'json', b_edit))
    assert abs(float(b_info['format']['duration']) - 30) < .1
    a, b = pixels(b_source, 450), pixels(b_edit, 450)
    assert len(a) == len(b) == 160 * 90 * 3
    assert sum(abs(x - y) for x, y in zip(a, b)) / len(a) > 10
    print('PASS: archived macOS Q&A 30s scenario dry run and synthetic timeline zoom')
    print('PASS: archived 86s Q&A timeline, video without audio, lead-in trim; main A/B manual-only guards')
    print(f'PASS: syntax, dry run, explicit UI guard, invalid scenario/timeline rejection, 9s synthetic zoom/pan, audio present, 640x360/30fps, source/output protection, short clip rejection. Pixel MAE overview/zoom/overview: {differences}')
    (dest / 'result.txt').write_text(f'PASS\nPixel MAE: {differences}\n' + json.dumps(info, indent=2))


if __name__ == '__main__':
    main()
