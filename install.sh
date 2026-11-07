#!/usr/bin/env bash
set -Eeuo pipefail

# SearXNG + Vane AI Overview installer
# Supports native SearXNG installations. Docker installations are not modified.

VERSION="1.0.0"
CONFIG_FILE="/etc/searxng/vane-ai-overview.json"
SERVICE="${SEARXNG_SERVICE:-searxng}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_ASSET="${SCRIPT_DIR}/assets/vane_backend.py"
UI_ASSET="${SCRIPT_DIR}/assets/vane_ui.html"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
die() { red "ERROR: $*"; exit 1; }

[[ $EUID -eq 0 ]] || die "Run this installer as root (sudo)."
[[ -f "$BACKEND_ASSET" && -f "$UI_ASSET" ]] || die "The assets directory is missing. Download the complete repository, not just install.sh."
command -v python3 >/dev/null || die "python3 is required."
command -v curl >/dev/null || die "curl is required."

# Find common native-install locations, or allow environment overrides.
WEBAPP="${SEARXNG_WEBAPP:-}"
TEMPLATE="${SEARXNG_TEMPLATE:-}"
PYTHON="${SEARXNG_PYTHON:-}"

if [[ -z "$WEBAPP" ]]; then
  for candidate in \
    /usr/local/searxng/searxng-src/searx/webapp.py \
    /usr/local/searxng/searxng/searx/webapp.py \
    /usr/share/searxng/searx/webapp.py; do
    [[ -f "$candidate" ]] && WEBAPP="$candidate" && break
  done
fi
[[ -n "$WEBAPP" && -f "$WEBAPP" ]] || die "Could not find searx/webapp.py. Set SEARXNG_WEBAPP=/path/to/searx/webapp.py."

if [[ -z "$TEMPLATE" ]]; then
  candidate="$(dirname "$WEBAPP")/templates/simple/results.html"
  [[ -f "$candidate" ]] && TEMPLATE="$candidate"
fi
[[ -n "$TEMPLATE" && -f "$TEMPLATE" ]] || die "Could not find templates/simple/results.html. Set SEARXNG_TEMPLATE=/path/to/results.html."

if [[ -z "$PYTHON" ]]; then
  for candidate in \
    /usr/local/searxng/searx-pyenv/bin/python \
    /usr/local/searxng/searxng-pyenv/bin/python \
    /usr/bin/python3; do
    [[ -x "$candidate" ]] && PYTHON="$candidate" && break
  done
fi
[[ -n "$PYTHON" && -x "$PYTHON" ]] || die "Could not find SearXNG's Python interpreter. Set SEARXNG_PYTHON=/path/to/python."

systemctl list-unit-files "${SERVICE}.service" >/dev/null 2>&1 || die "Systemd service '${SERVICE}' was not found. Set SEARXNG_SERVICE if it has a different name."

echo "SearXNG files:"
echo "  webapp:   $WEBAPP"
echo "  template: $TEMPLATE"
echo "  python:   $PYTHON"
echo "  service:  $SERVICE"
echo

# Existing configuration can be retained; environment variables override it.
old_value() {
  local key="$1"
  if [[ -f "$CONFIG_FILE" ]]; then
    python3 - "$CONFIG_FILE" "$key" <<'PY'
import json, sys
try:
    print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))
except Exception:
    print("")
PY
  fi
}

prompt_value() {
  local var="$1" label="$2" default="$3" secret="${4:-no}" value=""
  if [[ -n "${!var:-}" ]]; then
    printf -v "$var" '%s' "${!var}"
    return
  fi
  if [[ -n "$default" ]]; then
    read -r -p "$label [$default]: " value
    value="${value:-$default}"
  else
    if [[ "$secret" == "yes" ]]; then
      read -r -s -p "$label: " value
      echo
    else
      read -r -p "$label: " value
    fi
  fi
  [[ -n "$value" ]] || die "$label is required."
  printf -v "$var" '%s' "$value"
}

VANE_API_URL="${VANE_API_URL:-$(old_value api_url)}"
VANE_CHAT_PROVIDER_ID="${VANE_CHAT_PROVIDER_ID:-$(old_value chat_provider_id)}"
VANE_CHAT_MODEL="${VANE_CHAT_MODEL:-$(old_value chat_model)}"
VANE_EMBED_PROVIDER_ID="${VANE_EMBED_PROVIDER_ID:-$(old_value embedding_provider_id)}"
VANE_EMBED_MODEL="${VANE_EMBED_MODEL:-$(old_value embedding_model)}"
VANE_OPTIMIZATION_MODE="${VANE_OPTIMIZATION_MODE:-$(old_value optimization_mode)}"
VANE_SOURCES="${VANE_SOURCES:-$(old_value sources_csv)}"
VANE_TIMEOUT_SECONDS="${VANE_TIMEOUT_SECONDS:-$(old_value timeout_seconds)}"

prompt_value VANE_API_URL "Vane API URL (include /api/search)" "http://127.0.0.1:3000/api/search"
prompt_value VANE_CHAT_PROVIDER_ID "Vane chat provider UUID" ""
prompt_value VANE_CHAT_MODEL "Chat model key (as shown by Vane /api/providers)" "gemma4:12b"
prompt_value VANE_EMBED_PROVIDER_ID "Vane embedding provider UUID" ""
prompt_value VANE_EMBED_MODEL "Embedding model key" "Xenova/all-MiniLM-L6-v2"
prompt_value VANE_OPTIMIZATION_MODE "Vane optimization mode (speed/balanced/quality)" "speed"
prompt_value VANE_SOURCES "Vane sources (comma-separated: web,academic,discussions)" "web"
prompt_value VANE_TIMEOUT_SECONDS "Vane request timeout in seconds" "180"

[[ "$VANE_API_URL" == http://* || "$VANE_API_URL" == https://* ]] || die "VANE_API_URL must begin with http:// or https://."
[[ "$VANE_CHAT_PROVIDER_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || die "Chat provider ID does not look like a UUID."
[[ "$VANE_EMBED_PROVIDER_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || die "Embedding provider ID does not look like a UUID."
[[ "$VANE_OPTIMIZATION_MODE" =~ ^(speed|balanced|quality)$ ]] || die "Optimization mode must be speed, balanced or quality."
[[ "$VANE_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || die "Timeout must be an integer."

# Test connectivity before modifying SearXNG.
VANE_BASE="${VANE_API_URL%/api/search}"
echo
echo "Checking Vane API at ${VANE_BASE}/api/providers ..."
HTTP_CODE="$(curl -sS -o /tmp/vane-providers-"$$".json -w '%{http_code}' --connect-timeout 5 --max-time 15 "${VANE_BASE}/api/providers" || true)"
if [[ "$HTTP_CODE" != "200" ]]; then
  rm -f /tmp/vane-providers-"$$".json
  die "Vane /api/providers returned HTTP ${HTTP_CODE:-no response}. Check the URL and network access from this SearXNG host."
fi
rm -f /tmp/vane-providers-"$$".json
green "Vane API is reachable."

# Convert comma-separated source list to JSON and write root-owned configuration.
install -d -m 0755 /etc/searxng
python3 - "$CONFIG_FILE" "$VANE_API_URL" "$VANE_CHAT_PROVIDER_ID" "$VANE_CHAT_MODEL" \
  "$VANE_EMBED_PROVIDER_ID" "$VANE_EMBED_MODEL" "$VANE_OPTIMIZATION_MODE" \
  "$VANE_SOURCES" "$VANE_TIMEOUT_SECONDS" <<'PY'
import json, os, sys
(path, api, chat_id, chat_model, embed_id, embed_model, mode, sources, timeout) = sys.argv[1:]
data = {
    "api_url": api,
    "chat_provider_id": chat_id,
    "chat_model": chat_model,
    "embedding_provider_id": embed_id,
    "embedding_model": embed_model,
    "optimization_mode": mode,
    "sources": [x.strip() for x in sources.split(",") if x.strip()],
    "timeout_seconds": int(timeout)
}
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.chmod(tmp, 0o640)
os.replace(tmp, path)
PY

# Let the SearXNG service account read the configuration.
SERVICE_USER="$(systemctl show -p User --value "${SERVICE}.service" 2>/dev/null || true)"
SERVICE_GROUP="$(systemctl show -p Group --value "${SERVICE}.service" 2>/dev/null || true)"
SERVICE_USER="${SERVICE_USER:-searxng}"
SERVICE_GROUP="${SERVICE_GROUP:-$SERVICE_USER}"
chown root:"$SERVICE_GROUP" "$CONFIG_FILE" 2>/dev/null || chmod 0644 "$CONFIG_FILE"

# Ensure requests is importable by the SearXNG Python environment.
"$PYTHON" -c 'import requests, flask' >/dev/null 2>&1 || die "The SearXNG Python environment needs requests and Flask. Install requests into that environment before continuing."

# Modify the two files with a marker-based, repeatable patch.
python3 - "$WEBAPP" "$TEMPLATE" "$BACKEND_ASSET" "$UI_ASSET" <<'PY'
from pathlib import Path
import sys

webapp_path, template_path, backend_path, ui_path = map(Path, sys.argv[1:])
backend = backend_path.read_text()
ui = ui_path.read_text()

webapp = webapp_path.read_text()
begin = "# VANE_AI_OVERVIEW_ROUTE"
end = "# END VANE_AI_OVERVIEW_ROUTE"

if begin in webapp and end in webapp:
    before, rest = webapp.split(begin, 1)
    _, after = rest.split(end, 1)
    webapp = before + backend + after
else:
    anchor = "app.secret_key = settings['server']['secret_key']"
    if webapp.count(anchor) != 1:
        raise SystemExit("Cannot safely find the Flask app initialization point in webapp.py.")
    webapp = webapp.replace(anchor, anchor + "\n\n" + backend, 1)

webapp_path.write_text(webapp)

template = template_path.read_text()
begin = "<!-- VANE_AI_OVERVIEW_UI -->"
end = "<!-- END VANE_AI_OVERVIEW_UI -->"

if begin in template and end in template:
    before, rest = template.split(begin, 1)
    _, after = rest.split(end, 1)
    template = before + ui + after
else:
    anchor = '<div id="urls" role="main">'
    if template.count(anchor) != 1:
        raise SystemExit("Cannot safely find the results container in results.html.")
    template = template.replace(anchor, ui + "\n\n    " + anchor, 1)

template_path.write_text(template)
PY

echo
echo "Checking Python syntax..."
"$PYTHON" -m py_compile "$WEBAPP"

echo "Restarting ${SERVICE}..."
systemctl restart "$SERVICE"
sleep 2
if ! systemctl is-active --quiet "$SERVICE"; then
  journalctl -u "$SERVICE" -n 60 --no-pager
  die "SearXNG failed to start. Inspect the log above."
fi

green "Installation completed successfully."
echo
echo "AI Overview: GET /ai-overview?q=..."
echo "Follow-ups:  POST /ai-overview-followup"
echo "Config:      $CONFIG_FILE"
echo
echo "Refresh SearXNG with Ctrl+F5 and run a search."
echo "To uninstall, run: ${SCRIPT_DIR}/uninstall.sh"
