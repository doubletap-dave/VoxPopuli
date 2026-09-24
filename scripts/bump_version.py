"""Bump VoxPopuli.toc and prepend a CHANGELOG.md section.

CurseForge packages a tag as a release. The tag name is the version with no
"v" prefix, so the site version matches the .toc. Put "alpha" or "beta" in
the tag (for example 1.2.0-beta) to mark that channel.
"""

from __future__ import annotations

import argparse
import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "VoxPopuli.toc"
CHANGELOG = ROOT / "CHANGELOG.md"
VERSION_RE = re.compile(r"^(## Version:\s*)(\d+)\.(\d+)\.(\d+)\s*$", re.MULTILINE)


def read_version(text: str) -> tuple[int, int, int]:
    match = VERSION_RE.search(text)
    if not match:
        raise SystemExit("VoxPopuli.toc has no '## Version: MAJOR.MINOR.PATCH' line")
    return int(match.group(2)), int(match.group(3)), int(match.group(4))


def bump(major: int, minor: int, patch: int, kind: str) -> tuple[int, int, int]:
    if kind == "major":
        return major + 1, 0, 0
    if kind == "minor":
        return major, minor + 1, 0
    if kind == "patch":
        return major, minor, patch + 1
    raise SystemExit(f"unknown bump {kind}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Bump the VoxPopuli version")
    parser.add_argument("--bump", choices=("patch", "minor", "major"), required=True)
    parser.add_argument("--notes", default="", help="Changelog body. Blank becomes a single release line.")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    toc_text = TOC.read_text(encoding="utf-8")
    current = read_version(toc_text)
    major, minor, patch = bump(*current, args.bump)
    version = f"{major}.{minor}.{patch}"
    today = date.today().isoformat()
    notes = args.notes.strip() or "Release."
    section = f"## {version} - {today}\n\n{notes.rstrip()}\n\n"

    print(f"{current[0]}.{current[1]}.{current[2]} -> {version}")
    if args.dry_run:
        print(section)
        return 0

    TOC.write_text(VERSION_RE.sub(rf"\g<1>{version}", toc_text, count=1), encoding="utf-8", newline="\n")

    existing = CHANGELOG.read_text(encoding="utf-8") if CHANGELOG.exists() else "# Changelog\n\n"
    if not existing.startswith("# Changelog"):
        existing = "# Changelog\n\n" + existing
    marker = existing.find("\n## ")
    if marker == -1:
        updated = existing.rstrip() + "\n\n" + section
    else:
        updated = existing[: marker + 1] + section + existing[marker + 1 :]
    CHANGELOG.write_text(updated, encoding="utf-8", newline="\n")
    print(f"updated {TOC.name} and {CHANGELOG.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
