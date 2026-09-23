#!/usr/bin/env python3
"""Run the current GPU beam checks; shares the live implementation with the water probe."""
from underwater_light_probe import main
if __name__ == '__main__':
    raise SystemExit(main(shafts_only=True))
