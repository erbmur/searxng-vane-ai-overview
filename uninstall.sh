#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }

WEBAPP="${SEARXNG_WEBAPP:-}"
TEMPLATE="${SEARXNG_TEMPLATE:-}"
SERVICE="${SEARXNG_SERVICE:-searxng}"

if [[ -z "$WEBAPP" ]]; then
  for candidate in /usr/local/searxng/searxng-src/searx/webapp.py /usr/local/searxng/searxng/searx/webapp.py /usr/share/searxng/searx/webapp.py; do
    [[ -f "$candidate" ]] && WEBAPP="$candidate" && break
  done
fi
[[ -n "$WEBAPP" && -f "$WEBAPP" ]] || { echo "Cannot locate webapp.py"; exit 1; }

if [[ -z "$TEMPLATE" ]]; then
  candidate="$(dirname "$WEBAPP")/templates/simple/results.html"
  [[ -f "$candidate" ]] && TEMPLATE="$candidate"
fi
[[ -n "$TEMPLATE" && -f "$TEMPLATE" ]] || { echo "Cannot locate results.html"; exit 1; }

python3 - "$WEBAPP" "$TEMPLATE" <<'PY'
from pathlib import Path
import sys

webapp_path, template_path = map(Path, sys.argv[1:])
webapp = webapp_path.read_text()
begin, end = "# VANE_AI_OVERVIEW_ROUTE", "# END VANE_AI_OVERVIEW_ROUTE"
if begin in webapp and end in webapp:
    before, rest = webapp.split(begin, 1)
    _, after = rest.split(end, 1)
    webapp_path.write_text(before + after)
    print("Removed Vane routes from webapp.py.")
else:
    print("No Vane route block found.")

template = template_path.read_text()
begin, end = "<!-- VANE_AI_OVERVIEW_UI -->", "<!-- END VANE_AI_OVERVIEW_UI -->"
if begin in template and end in template:
    before, rest = template.split(begin, 1)
    _, after = rest.split(end, 1)
    template_path.write_text(before + after)
    print("Removed Vane UI from results.html.")
else:
    print("No Vane UI block found.")
PY

systemctl restart "$SERVICE"
echo
echo "Integration code removed. Configuration retained at /etc/searxng/vane-ai-overview.json."
echo "Remove that file manually if you no longer need it."
