#!/usr/bin/env python3
"""Build the RDMALink website from site/src into a clean site/dist.

    python3 site/build.py

Everything in src is copied as it is (dotfiles aside), except that
- index.html gets the two Why diagrams from tools/why.py where it says <!-- build:why-bridge --> and
  <!-- build:why-rdmalink -->, and the version of the newest release in CHANGELOG.md where it says
  <!-- build:version -->;
- styles.css gets the diagrams' CSS where it says /* build:why-css */.
Each placeholder must appear exactly once. Standard library only, and the same input always gives
byte-identical output: nothing here reads the clock, the environment or the file order.
"""
import pathlib
import re
import shutil
import sys

SITE = pathlib.Path(__file__).resolve().parent
SRC = SITE / "src"
DIST = SITE / "dist"
CHANGELOG = SITE.parent / "CHANGELOG.md"

sys.dont_write_bytecode = True  # no __pycache__ in the checkout
sys.path.insert(0, str(SITE / "tools"))
import why  # noqa: E402  (site/tools/why.py)

# A released section: `## 0.3.8 — 2026-09-29 (build 11)`. `## Unreleased` has no version, so it never matches.
RELEASE = re.compile(r"^## (\d+\.\d+\.\d+) — \d{4}-\d{2}-\d{2}\b", re.M)
PLACEHOLDER = re.compile(r"<!-- build:([a-z-]+) -->|/\* build:([a-z-]+) \*/")


def fail(message):
    raise SystemExit("build.py: " + message)


def release_version(text):
    """The version of the first released section in CHANGELOG.md, which lists the newest first."""
    match = RELEASE.search(text)
    if not match:
        fail("CHANGELOG.md has no released version: no heading like '## 1.2.3 — 2026-01-31'")
    return match.group(1)


def fill(name, text, values):
    """Replace each placeholder in `text` with its value; each one must be there exactly once."""
    seen = []

    def swap(match):
        key = match.group(1) or match.group(2)
        if key not in values:
            fail(f"{name} has an unknown placeholder '{key}'")
        seen.append(key)
        return values[key]

    out = PLACEHOLDER.sub(swap, text)
    for key in values:
        if seen.count(key) != 1:
            fail(f"{name} should have the placeholder '{key}' once, not {seen.count(key)} times")
    return out


def main():
    if not (SRC / "index.html").is_file():
        fail(f"no {SRC / 'index.html'}")
    version = release_version(CHANGELOG.read_text(encoding="utf-8"))
    figures, why_css = why.render()
    generated = {
        "index.html": {"version": version, **figures},
        "styles.css": {"why-css": why_css},
    }

    missing = [key for key in generated if not (SRC / key).is_file()]
    if missing:
        fail("src has no " + ", ".join(missing))

    if DIST.exists():
        shutil.rmtree(DIST)
    count = 0
    for path in sorted(SRC.rglob("*")):
        rel = path.relative_to(SRC)
        if any(part.startswith(".") for part in rel.parts) or not path.is_file():
            continue
        out = DIST / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        key = rel.as_posix()
        if key in generated:
            text = fill(key, path.read_text(encoding="utf-8"), generated[key])
            out.write_bytes(text.encode("utf-8"))
        else:
            shutil.copyfile(path, out)
        count += 1
    print(f"build.py: wrote {count} files to {DIST.relative_to(SITE.parent)} for version {version}")


if __name__ == "__main__":
    main()
