"""Prints one version's section of CHANGELOG.md: the notes of its release.

    python3 script/release/changelog.py 0.3.8 < CHANGELOG.md

A section starts at a level-two heading whose first word is the version —
`## 0.3.8 — 2026-10-01 (build 11)` — and runs to the next level-two heading.
It exits 1 and prints nothing when there is no such section or it is empty, so
a release is never published with notes nobody wrote. The release workflow's
preflight runs it against the tag's commit, before the hour of notarization,
and publish.sh runs it again for the notes it publishes.
"""
import re
import sys


def section(text, version):
    """The body under `## <version> …`, stripped, or '' when there is none."""
    body, inside = [], False
    for line in text.splitlines():
        if line.startswith('## '):
            if inside:
                break
            inside = line[3:].split(maxsplit=1)[:1] == [version]
            continue
        if inside:
            body.append(line)
    return '\n'.join(body).strip()


def main():
    if len(sys.argv) != 2 or not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', sys.argv[1]):
        sys.exit('usage: changelog.py X.Y.Z < CHANGELOG.md')
    notes = section(sys.stdin.read(), sys.argv[1])
    if not notes:
        sys.exit(f'CHANGELOG.md has no notes for {sys.argv[1]}')
    print(notes)


if __name__ == '__main__':
    main()
