#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
for script in install-debian13-gnome-rdp-codex.sh scripts/*.sh tests/*.sh; do
  bash -n "$script"
done
bash install-debian13-gnome-rdp-codex.sh --help >/dev/null
if bash install-debian13-gnome-rdp-codex.sh --username codex --password test --mode invalid >/dev/null 2>&1; then exit 1; fi
if bash install-debian13-gnome-rdp-codex.sh --username codex --password test --sha256 wrong >/dev/null 2>&1; then exit 1; fi
python3 - <<'PY'
import re
from pathlib import Path
for path in [Path('install-debian13-gnome-rdp-codex.sh'), Path('scripts/build-prebuilt.sh')]:
    for index, code in enumerate(re.findall(r"python3 - <<'([A-Z]+)'\n(.*?)\n\1", path.read_text(), re.S)):
        compile(code[1], f'{path}:embedded-{index}', 'exec')
print('Shell, embedded Python and invalid argument checks passed.')
PY
