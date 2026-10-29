"""Verify this plugin's privacy declarations and their built resource bundle."""

import argparse
import json
import plistlib
from pathlib import Path

EXPECTED_APIS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
    "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
}
BUNDLE_NAMES = {
    "swiftpm": "warm_alarm_ios_warm_alarm_ios.bundle",
    "cocoapods": "warm_alarm_ios_privacy.bundle",
}
SOURCE = (
    Path(__file__).resolve().parents[1]
    / "ios/warm_alarm_ios/Sources/warm_alarm_ios/PrivacyInfo.xcprivacy"
)


def read_manifest(path):
    if not path.is_file():
        raise ValueError(f"Missing privacy manifest: {path}")
    with path.open("rb") as source:
        manifest = plistlib.load(source)
    entries = manifest.get("NSPrivacyAccessedAPITypes", [])
    apis = {
        entry["NSPrivacyAccessedAPIType"]: entry["NSPrivacyAccessedAPITypeReasons"]
        for entry in entries
    }
    if len(entries) != len(EXPECTED_APIS) or apis != EXPECTED_APIS:
        raise ValueError(f"Unexpected required-reason declarations: {path}: {apis}")
    if manifest.get("NSPrivacyTracking") is not False:
        raise ValueError(f"Expected tracking to be false: {path}")
    for key in ("NSPrivacyTrackingDomains", "NSPrivacyCollectedDataTypes"):
        if manifest.get(key) != []:
            raise ValueError(f"Expected an empty {key}: {path}")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=SOURCE)
    parser.add_argument("--app-bundle", type=Path)
    parser.add_argument("--packaging", choices=BUNDLE_NAMES)
    args = parser.parse_args()
    if bool(args.app_bundle) != bool(args.packaging):
        parser.error("--app-bundle and --packaging must be supplied together")

    expected = read_manifest(args.manifest)
    checked = [str(args.manifest)]
    if args.app_bundle:
        if not args.app_bundle.is_dir() or args.app_bundle.suffix != ".app":
            raise ValueError(f"Missing app bundle: {args.app_bundle}")
        candidates = list(
            args.app_bundle.rglob(
                f"{BUNDLE_NAMES[args.packaging]}/PrivacyInfo.xcprivacy"
            )
        )
        if len(candidates) != 1:
            raise ValueError(
                f"Expected one {args.packaging} plugin manifest in {args.app_bundle}; found {len(candidates)}"
            )
        if read_manifest(candidates[0]) != expected:
            raise ValueError(
                f"Bundled manifest differs from the source: {candidates[0]}"
            )
        checked.append(str(candidates[0]))
    print(
        json.dumps(
            {"verified": checked, "required_reason_apis": EXPECTED_APIS}, indent=2
        )
    )


if __name__ == "__main__":
    try:
        main()
    except (
        ValueError,
        KeyError,
        TypeError,
        OSError,
        plistlib.InvalidFileException,
    ) as error:
        raise SystemExit(str(error)) from error
