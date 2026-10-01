#!/usr/bin/env bash
# Run with APPIMAGE_DEBUG_EXEC inside the unmodified Nix appimage-run FHS.
set -euo pipefail
export LD_LIBRARY_PATH="$APPDIR/usr/lib/deltiecord/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$SVG_TEST_PYTHON" "$SVG_TEST_SCRIPT"
