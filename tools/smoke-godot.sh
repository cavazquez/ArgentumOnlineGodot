#!/usr/bin/env bash
# Verifica versión, importación y escenas. Fallan también los errores que Godot imprime con exit 0.
set -euo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
godot_bin=${GODOT_BIN:-godot}
"$project_root/tools/check-godot.sh"
run_dir=$(mktemp -d)
trap 'rm -rf -- "$run_dir"' EXIT
export XDG_DATA_HOME="$run_dir/data"
export XDG_CONFIG_HOME="$run_dir/config"
export XDG_CACHE_HOME="$run_dir/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
run_checked() {
  local log_file=$1
  shift
  local status=0
  "$@" >"$log_file" 2>&1 || status=$?
  cat "$log_file"
  if (( status != 0 )); then return "$status"; fi
  if grep -Eq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:)' "$log_file"; then return 1; fi
}
run_checked "$run_dir/import.log" "$godot_bin" --headless --path "$project_root" --editor --import
run_checked "$run_dir/smoke.log" "$godot_bin" --headless --path "$project_root" res://tests/engine_smoke.tscn
grep -q 'ENGINE_SMOKE: PASS' "$run_dir/smoke.log"

run_checked "$run_dir/credentials.log" "$godot_bin" --headless --path "$project_root" --quit-after 300 res://tests/credentials_smoke.tscn
grep -q 'CREDENTIALS_SMOKE: PASS' "$run_dir/credentials.log"
python3 - "$run_dir/credentials.log" <<'CHECK_LOG'
import pathlib
import sys

log = pathlib.Path(sys.argv[1]).read_text()
secret = b"SYNTHETIC_CANARY_431"
variants = [secret.decode(), secret.hex(), secret.hex(" ")]
if any(value.lower() in log.lower() for value in variants):
    raise SystemExit("Una contraseña sintética o sus bytes llegaron a los logs")
CHECK_LOG
