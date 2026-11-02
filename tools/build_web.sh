#!/usr/bin/env bash
# Web版を書き出し、スマホで遊べる形(build/artifact/)にまとめる。
# 使い方: GODOT=/path/to/godot tools/build_web.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
rm -rf build/web build/artifact
mkdir -p build/web build/artifact
"$GODOT" --headless --export-release "Web" build/web/index.html
cfg=$(grep -o 'const GODOT_CONFIG = .*;' build/web/index.html)
python3 - "$cfg" <<'PY'
import sys
cfg = sys.argv[1]
src = open('web/shell.html', encoding='utf-8').read()
open('build/artifact/planet-pioneer.html', 'w', encoding='utf-8').write(src.replace('/*__GODOT_CONFIG__*/', cfg))
PY
cp build/web/index.pck build/artifact/index.pck.wasm
cp build/web/index.js build/web/index.audio.worklet.js build/web/index.audio.position.worklet.js build/artifact/
gzip -9 -c build/web/index.wasm > build/artifact/index.wasm-gz.wasm
ls -la build/artifact
