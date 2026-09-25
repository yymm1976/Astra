"""Shared local Minecraft paths. Explicit arguments always take precedence."""
from pathlib import Path
import os
import sys


def default_minecraft_root() -> Path:
    configured = os.environ.get("ASTRA_MC_ROOT")
    if configured:
        return Path(configured).expanduser()
    home = Path.home()
    if sys.platform == "win32":
        candidates = [Path(os.environ.get("APPDATA", home / "AppData/Roaming")) / ".minecraft"]
    elif sys.platform == "darwin":
        candidates = [home / "Library/Application Support/minecraft"]
    else:
        candidates = [home / ".minecraft"]
    return next((p for p in candidates if (p / "libraries").is_dir()), candidates[0])


def minecraft_root(path=None) -> Path:
    root = Path(path).expanduser() if path is not None else default_minecraft_root()
    root = root.resolve()
    if not (root / "libraries").is_dir():
        raise FileNotFoundError(f"Minecraft libraries not found under {root}. "
                                "Use --minecraft-root or set ASTRA_MC_ROOT.")
    return root


def minecraft_instance(root: Path, path=None) -> Path:
    configured = path if path is not None else os.environ.get("ASTRA_MC_INSTANCE")
    if configured is not None:
        instance = Path(configured).expanduser().resolve()
        if not instance.is_dir():
            raise FileNotFoundError(f"Minecraft instance not found: {instance}")
        return instance
    candidates = [p.resolve() for p in [root, *sorted((root / "versions").glob("*"))]
                  if (p / "config/iris.properties").is_file()]
    if len(candidates) != 1:
        raise ValueError(f"Found {len(candidates)} Iris instances under {root}; "
                         "use --instance or set ASTRA_MC_INSTANCE to select one explicitly.")
    return candidates[0]


def iris_jar(instance: Path) -> Path:
    candidates = sorted((instance / "mods").glob("iris*.jar"))
    if len(candidates) != 1:
        raise ValueError(f"Found {len(candidates)} Iris jars in {instance / 'mods'}; "
                         "use --iris-jar to select the installed version explicitly.")
    return candidates[0]
