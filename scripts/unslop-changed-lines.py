#!/usr/bin/env python3
"""Run unslop and report violations only on lines changed in this PR diff.

Usage:
  unslop-changed-lines.py --base <SHA> [--head <ref>] [--unslop <path>] \\
                          [--config <path>] <file>...

Exit code:
  0  no remaining violations
  1  one or more violations remain
  2  usage error (missing binary, git diff failure, etc.)
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

COORD_LINE_RE = re.compile(r"^((?:\d+:\d+)(?:,\d+:\d+)*)\s+(\S+)\s+(.*)$")
HUNK_HEADER_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")


def changed_line_ranges(base: str, head: str, file: str) -> list[tuple[int, int]] | None:
    """Return new-side (start, end) ranges for ``file``.

    None  -> file is newly added; treat every line as in-range.
    []    -> file has no new-side hunks (e.g., pure deletion).
    """
    status_proc = subprocess.run(
        ["git", "diff", "--name-status", f"{base}...{head}", "--", file],
        capture_output=True, text=True,
    )
    if status_proc.returncode != 0:
        print(
            f"[unslop-changed-lines] git diff --name-status failed for {file}: "
            f"{status_proc.stderr.strip()}",
            file=sys.stderr,
        )
        sys.exit(2)
    status_line = status_proc.stdout.strip().splitlines()
    if status_line and status_line[0].startswith("A\t"):
        return None

    diff_proc = subprocess.run(
        ["git", "diff", "--unified=0", f"{base}...{head}", "--", file],
        capture_output=True, text=True,
    )
    if diff_proc.returncode != 0:
        print(
            f"[unslop-changed-lines] git diff --unified=0 failed for {file}: "
            f"{diff_proc.stderr.strip()}",
            file=sys.stderr,
        )
        sys.exit(2)

    ranges: list[tuple[int, int]] = []
    for line in diff_proc.stdout.splitlines():
        m = HUNK_HEADER_RE.match(line)
        if not m:
            continue
        new_start = int(m.group(1))
        new_count = int(m.group(2)) if m.group(2) is not None else 1
        if new_count == 0:
            continue
        ranges.append((new_start, new_start + new_count - 1))
    return ranges


def in_any_range(line: int, ranges: list[tuple[int, int]]) -> bool:
    return any(s <= line <= e for (s, e) in ranges)


def filter_unslop_output(
    output: str, ranges: list[tuple[int, int]] | None
) -> list[str]:
    """Return the lines that should be reported.

    ``ranges`` is None when every line should pass (newly added file).
    """
    if not output.strip():
        return []
    file_header: str | None = None
    kept: list[str] = []
    for line in output.splitlines():
        m = COORD_LINE_RE.match(line)
        if m:
            coords_str, rule, msg = m.group(1), m.group(2), m.group(3)
            coords = []
            for token in coords_str.split(","):
                l_s, c_s = token.split(":")
                coords.append((int(l_s), int(c_s)))
            if ranges is None:
                kept_coords = coords
            else:
                kept_coords = [(l, c) for (l, c) in coords if in_any_range(l, ranges)]
            if kept_coords:
                kept_str = ",".join(f"{l}:{c}" for (l, c) in kept_coords)
                kept.append(f"{kept_str} {rule} {msg}")
            continue
        if file_header is None and line.strip():
            file_header = line
    if not kept:
        return []
    return ([file_header] if file_header else []) + kept


def run_unslop(unslop_bin: str, config: str, file: str) -> tuple[int, str]:
    proc = subprocess.run(
        [unslop_bin, "-c", config, "--no-color", file],
        capture_output=True, text=True,
    )
    return proc.returncode, proc.stdout + proc.stderr


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True, help="Base SHA for git diff")
    parser.add_argument("--head", default="HEAD", help="Head ref for git diff")
    parser.add_argument("--unslop", default="unslop", help="unslop binary path")
    parser.add_argument(
        "--config", default=".textlintrc.json", help="unslop config path"
    )
    parser.add_argument("files", nargs="+", help="Markdown files to lint")
    args = parser.parse_args(argv)

    if not Path(args.config).is_file():
        print(
            f"[unslop-changed-lines] config not found: {args.config}", file=sys.stderr
        )
        return 2

    any_violation = False
    for f in args.files:
        if not Path(f).is_file():
            continue
        ranges = changed_line_ranges(args.base, args.head, f)
        if ranges is not None and not ranges:
            continue
        rc, out = run_unslop(args.unslop, args.config, f)
        if rc == 0:
            continue
        filtered = filter_unslop_output(out, ranges)
        if filtered:
            print("\n".join(filtered))
            any_violation = True
    return 1 if any_violation else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
