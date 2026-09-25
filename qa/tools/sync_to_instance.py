#!/usr/bin/env python3
"""Sync the Astra pack to a Minecraft shaderpacks instance and verify byte equality.

Usage:
    python qa/tools/sync_to_instance.py [--dry-run]

Select the destination with --dest, or an Iris instance with --instance / ASTRA_MC_INSTANCE.
No Minecraft process is started or edited; this only copies files.
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import sys
from pathlib import Path
from minecraft_paths import default_minecraft_root, minecraft_instance

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SRC = REPO_ROOT / "Astra"


def digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def relative_files(root: Path) -> dict[str, Path]:
    return {
        path.relative_to(root).as_posix(): path
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SRC)
    parser.add_argument("--dest", type=Path, help="explicit destination pack directory")
    parser.add_argument("--minecraft-root", type=Path, help="libraries root; or ASTRA_MC_ROOT")
    parser.add_argument("--instance", type=Path, help="game directory; or ASTRA_MC_INSTANCE")
    parser.add_argument("--dry-run", action="store_true", help="report only, copy nothing")
    args = parser.parse_args()

    try:
        if args.dest is None:
            root = (args.minecraft_root or default_minecraft_root()).expanduser().resolve()
            instance = minecraft_instance(root, args.instance)
            if not (instance / "shaderpacks").is_dir():
                raise FileNotFoundError(f"No shaderpacks directory in {instance}; use --dest.")
            args.dest = instance / "shaderpacks/Astra"
        args.source = args.source.expanduser().resolve()
        args.dest = args.dest.expanduser().resolve()
        if args.source == args.dest or args.source in args.dest.parents or args.dest in args.source.parents:
            raise ValueError("source and destination must be separate directory trees")
    except (OSError, ValueError) as error:
        print(f"sync_to_instance.py: {error}", file=sys.stderr)
        return 2

    if not args.source.is_dir():
        print(f"source missing: {args.source}", file=sys.stderr)
        return 2
    if not args.dry_run:
        args.dest.mkdir(parents=True, exist_ok=True)

    source_files = relative_files(args.source)
    dest_files = relative_files(args.dest)

    copied: list[str] = []
    for key, src_path in source_files.items():
        dst_path = args.dest / Path(key)
        needs = (not dst_path.is_file()) or digest(src_path) != digest(dst_path)
        if not needs:
            continue
        copied.append(key)
        if not args.dry_run:
            dst_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src_path, dst_path)

    # Re-verify against disk after the copy (never trust the copy call itself).
    dest_files = relative_files(args.dest)
    missing = [key for key in source_files if key not in dest_files]
    differing = [
        key for key, src_path in source_files.items()
        if key in dest_files and digest(src_path) != digest(dest_files[key])
    ]
    extras = [key for key in dest_files if key not in source_files]

    print(f"SOURCE      {args.source}")
    print(f"DEST        {args.dest}")
    print(f"Files       source={len(source_files)} dest={len(dest_files)}")
    print(f"Copied      {len(copied)}")
    for key in copied:
        print(f"  + {key}")
    print(f"Missing after copy: {len(missing)}")
    for key in missing:
        print(f"  - {key}")
    print(f"Content differences after copy: {len(differing)}")
    for key in differing:
        print(f"  * {key}")
    print(f"Extras in dest (not deleted): {len(extras)}")
    for key in extras:
        print(f"  ? {key}")

    if args.dry_run:
        return 0
    return 1 if (missing or differing) else 0


if __name__ == "__main__":
    raise SystemExit(main())
