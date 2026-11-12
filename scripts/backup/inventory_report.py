#!/usr/bin/env python3
"""Read-only aggregate backup inventory report. Never prints keys or run IDs."""
import re
import subprocess
import sys

import publish

COMPLETE = 'complete.json'
METADATA = ('manifest.json', 'manifest.sig')
PART = re.compile(r'[0-9]{4}\.gpgpart\Z')


def summarize(objects):
    """Return aggregate counts and flag any unknown or incomplete objects."""
    runs, unknown = {}, False
    for key in objects:
        if not key.startswith(publish.PREFIX):
            unknown = True
            continue
        segments = key[len(publish.PREFIX):].split('/')
        if len(segments) != 2 or not publish.RUN.fullmatch(segments[0]):
            unknown = True
            continue
        run, name = segments
        if name not in METADATA + (COMPLETE,) and not PART.fullmatch(name):
            unknown = True
            continue
        runs.setdefault(run, set()).add(name)
    incomplete = any(
        COMPLETE not in names or not set(METADATA) <= names
        or not any(PART.fullmatch(name) for name in names)
        for names in runs.values())
    return {
        'runs': len(runs),
        'complete_markers': sum(COMPLETE in names for names in runs.values()),
        'total_bytes': sum(objects.values()),
        'unknown_or_incomplete': unknown or incomplete,
    }


def main():
    try:
        summary = summarize(publish.inventory())
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError):
        print('Backup inventory listing failed.', file=sys.stderr)
        return 1
    summary['unknown_or_incomplete'] = str(summary['unknown_or_incomplete']).lower()
    print('Backup inventory: runs={runs} complete_markers={complete_markers} '
          'total_bytes={total_bytes} unknown_or_incomplete={unknown_or_incomplete}'.format(**summary))
    return 0


if __name__ == '__main__':
    sys.exit(main())
