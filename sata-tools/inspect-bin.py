#!/usr/bin/python3
"""CLI wrapper: inspect an official UDMPRO-*.bin on a Mac/PC (no UDM needed)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ubnt_bin import main

if __name__ == "__main__":
    main()
