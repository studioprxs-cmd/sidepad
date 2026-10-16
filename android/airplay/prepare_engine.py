#!/usr/bin/env python3
"""Import only allowlisted native libraries from a pinned, hash-verified official release.

The upstream APK is never installed. Java/Kotlin UI and unrelated native code are not imported.
Use --apk for an already downloaded artifact or --download to fetch it explicitly.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent
LOCK = json.loads((ROOT / 'engine.lock.json').read_text())


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def verify():
    for name, expected in LOCK['libraries'].items():
        path = ROOT / 'jniLibs' / name.removeprefix('lib/')
        if not path.is_file() or digest(path) != expected:
            raise ValueError(f'Missing or modified AirPlay library: {path}. Run: python3 android/airplay/prepare_engine.py --download')
    print('AirPlay engine: all pinned libraries verified (' + LOCK['tag'] + ')')


def prepare(apk):
    if digest(apk) != LOCK['apk_sha256']:
        raise ValueError('AirPlay engine APK SHA-256 mismatch; no libraries were imported')
    with zipfile.ZipFile(apk) as archive:
        # Validate the entire allowlist before writing anything.
        blobs = {name: archive.read(name) for name in LOCK['libraries']}
        for name, blob in blobs.items():
            if hashlib.sha256(blob).hexdigest() != LOCK['libraries'][name]:
                raise ValueError('Native library hash mismatch: ' + name)
        for name, blob in blobs.items():
            destination = ROOT / 'jniLibs' / name.removeprefix('lib/')
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(blob)
    verify()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--verify', action='store_true')
    group.add_argument('--download', action='store_true')
    group.add_argument('--apk', type=Path)
    args = parser.parse_args()
    try:
        if args.verify:
            verify()
        else:
            apk = args.apk or ROOT / 'downloads' / ('engine-' + LOCK['tag'] + '.apk')
            if args.download and (not apk.is_file() or digest(apk) != LOCK['apk_sha256']):
                apk.parent.mkdir(parents=True, exist_ok=True)
                temporary = apk.with_suffix('.download')
                with urllib.request.urlopen(LOCK['apk_url'], timeout=60) as source, temporary.open('wb') as target:
                    while chunk := source.read(1024 * 1024):
                        target.write(chunk)
                if digest(temporary) != LOCK['apk_sha256']:
                    temporary.unlink()
                    raise ValueError('Downloaded APK SHA-256 mismatch')
                temporary.replace(apk)
            prepare(apk)
    except (OSError, ValueError, zipfile.BadZipFile, KeyError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
