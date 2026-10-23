#!/usr/bin/env python3
"""Main A/B manual cues; explicit example scenarios remain available for Q&A. Never records."""
import argparse
import json
import math
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent


def load_scenario(path):
    data = json.loads(Path(path).read_text())
    mode = data.get('mode', 'ui')
    if mode not in ('ui', 'manual_cues'):
        raise ValueError('unsupported scenario mode')
    if mode == 'ui' and (not isinstance(data.get('bundle_id'), str) or not data['bundle_id']):
        raise ValueError('bundle_id must be a nonempty string')
    previous = -1
    if not data.get('steps'):
        raise ValueError('steps cannot be empty')
    for step in data['steps']:
        at = step['at']
        if not isinstance(at, (int, float)) or not math.isfinite(at) or at < 0 or at <= previous:
            raise ValueError('step times must be finite, nonnegative, strictly increasing')
        previous = at
        allowed = ('cue',) if mode == 'manual_cues' else ('focus', 'press', 'hold')
        if step['action'] not in allowed:
            raise ValueError('unsupported action')
        if step['action'] == 'press' and not step.get('label'):
            raise ValueError('press requires label')
    return data


def invoke(bundle, action, label=''):
    result = subprocess.run(
        ['osascript', str(ROOT / 'ui.applescript'), bundle, action, label],
        capture_output=True, text=True, timeout=10, check=True,
    )
    return result.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scenario', type=Path, default=ROOT / 'scenario.json')
    parser.add_argument('--run', action='store_true', help='Execute UI actions; may schedule a real alarm')
    parser.add_argument('--inspect', action='store_true', help='Read target AX button labels, no clicks')
    parser.add_argument('--confirmed-target', action='store_true', help='I verified target and prepared permissions')
    args = parser.parse_args()
    if args.run and args.inspect:
        parser.error('choose --run or --inspect')
    scenario = load_scenario(args.scenario)
    if scenario.get('mode') == 'manual_cues':
        if args.run or args.inspect:
            parser.error('main A/B is manual cue-only; no UI execution or permission changes. Use explicit Q&A scenario for example inspection.')
        print('DRY RUN: MANUAL A/B CUES; no Apple Events, clicks, waits, alarms, or recording')
        for step in scenario['steps']:
            print(f"T+{step['at']:6.1f}s {step['note']}")
        for item in scenario.get('required_inputs', []):
            print('INPUT REQUIRED: ' + item)
        return
    if (args.run or args.inspect) and not args.confirmed_target:
        parser.error('first run doctor.sh and verify target; then pass --confirmed-target')
    if args.inspect:
        labels = invoke(scenario['bundle_id'], 'inspect')
        if not labels:
            raise RuntimeError(
                'No labeled AXButtons found. Target window was found, but button inspection is unverified. '
                'Open the example window manually and inspect its accessibility tree; do not run the scenario yet.'
            )
        print(labels)
        return
    if not args.run:
        print('DRY RUN: no Apple Events, clicks, waits, alarms, or recording')
        for step in scenario['steps']:
            print(f"T+{step['at']:6.1f}s {step['action']:5} {step.get('label', '')} | {step.get('note', '')}")
        return
    print('No recorder started. Prepare your own recording, then return here.', flush=True)
    for remaining in range(5, 0, -1):
        print(f'Scenario starts in {remaining}', flush=True)
        time.sleep(1)
    start = time.monotonic()
    print('T=0 (align or trim recording to this point)', flush=True)
    for step in scenario['steps']:
        time.sleep(max(0, start + step['at'] - time.monotonic()))
        drift = time.monotonic() - start - step['at']
        if drift > 2:
            raise RuntimeError(f'UI timing drift {drift:.1f}s; abort and retake')
        print(f"T+{time.monotonic() - start:.2f} {step['action']} {step.get('label', '')}", flush=True)
        if step['action'] != 'hold':
            print(invoke(scenario['bundle_id'], step['action'], step.get('label', '')), flush=True)
    print('Scenario ended. Stop the recording yourself. Verify alarm id 42 was handled.', flush=True)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('\nStopped future UI steps. Recorder and scheduled alarm are NOT stopped.', file=sys.stderr)
        sys.exit(130)
    except (ValueError, KeyError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'Aborted: {error}', file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr, file=sys.stderr)
        print('Stop recording manually; a previously scheduled alarm may still fire.', file=sys.stderr)
        sys.exit(1)
