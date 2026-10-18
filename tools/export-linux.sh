#!/usr/bin/env bash
# Exportación reproducible: OpenGL software evita errores del renderer dummy.
set -euo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
godot_bin=${GODOT_BIN:-godot}
"$project_root/tools/check-godot.sh" --templates
mkdir -p "$project_root/build"
log_file="$project_root/build/export-linux.log"
status=0
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a "$godot_bin" --path "$project_root" \
  --rendering-method gl_compatibility --export-release 'Linux Desktop' \
  "$project_root/build/pyao-client.x86_64" >"$log_file" 2>&1 || status=$?
cat "$log_file"
if (( status != 0 )); then exit "$status"; fi
if grep -Eq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:)' "$log_file"; then exit 1; fi
test -s "$project_root/build/pyao-client.x86_64"
