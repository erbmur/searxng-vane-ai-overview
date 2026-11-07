# SearXNG + Vane AI Overview

Add a Google-style AI Overview and conversational follow-up chat to the SearXNG `simple` results page, powered by a self-hosted [Vane](https://github.com/ItzCrazyKns/Vane) instance.

The integration adds:

- An AI-generated summary above SearXNG search results.
- Clickable source links returned by Vane.
- A Hide/Show control for the entire AI panel.
- Follow-up questions using Vane's `/api/search` `history` parameter.
- Per-answer source links in the conversation.
- A reset-conversation control.
- A configurable Vane API URL, provider IDs, model IDs, sources and optimization mode.

This project targets **native/systemd SearXNG installations** using the `simple` theme. It does not currently patch Docker-based SearXNG containers.

## Requirements

- A working SearXNG installation with the `simple` theme.
- A reachable Vane instance.
- A chat model and embedding model configured in Vane.
- The SearXNG Python environment has `requests` and `flask` installed.
- Root access to the SearXNG host.
- `curl`, `python3`, and `systemd`.

The SearXNG host must be able to reach Vane's `/api/providers` and `/api/search` endpoints.

## Before installing: find your Vane provider IDs

Vane requires provider UUIDs and model keys. These are installation-specific; do not copy the IDs from somebody else's setup.

Open:

```text
http://YOUR-VANE-HOST:PORT/api/providers
```

Find the provider ID (`id`) for your chat model and the provider ID for your embedding model. Use the model `key`, not its display name.

Vane API documentation:
https://github.com/ItzCrazyKns/Vane/blob/master/docs/API/SEARCH.md

## Installation

Download or clone this repository on the SearXNG host:

```bash
git clone https://github.com/YOUR-USERNAME/searxng-vane-ai-overview.git
cd searxng-vane-ai-overview
chmod +x install.sh uninstall.sh
sudo ./install.sh
```

The installer prompts for:

| Setting | Example | Meaning |
|---|---|---|
| Vane API URL | `http://10.0.0.20:3000/api/search` | Full Vane search endpoint |
| Chat provider UUID | UUID from `/api/providers` | Provider hosting the chat model |
| Chat model key | `gemma4:12b` | Exact model key in Vane |
| Embedding provider UUID | UUID from `/api/providers` | Provider hosting embeddings |
| Embedding model key | `nomic-embed-text` | Exact embedding model key |
| Optimization mode | `speed` | `speed`, `balanced`, or `quality` |
| Sources | `web` | Comma-separated: `web`, `academic`, `discussions` |
| Timeout | `180` | Request timeout in seconds |

The installer tests Vane connectivity before changing SearXNG.

### Non-interactive installation

You can set environment variables instead of answering prompts:

```bash
sudo env \
  VANE_API_URL="http://10.0.0.20:3000/api/search" \
  VANE_CHAT_PROVIDER_ID="YOUR-CHAT-PROVIDER-UUID" \
  VANE_CHAT_MODEL="gemma4:12b" \
  VANE_EMBED_PROVIDER_ID="YOUR-EMBEDDING-PROVIDER-UUID" \
  VANE_EMBED_MODEL="nomic-embed-text" \
  VANE_OPTIMIZATION_MODE="speed" \
  VANE_SOURCES="web" \
  VANE_TIMEOUT_SECONDS="180" \
  ./install.sh
```

The installer auto-detects common native SearXNG paths. For a non-standard installation, override them:

```bash
sudo env \
  SEARXNG_WEBAPP="/path/to/searx/webapp.py" \
  SEARXNG_TEMPLATE="/path/to/searx/templates/simple/results.html" \
  SEARXNG_PYTHON="/path/to/venv/bin/python" \
  SEARXNG_SERVICE="searxng" \
  ./install.sh
```

## After installation

Open SearXNG, run a search, and wait for the AI Overview to load.

- Use the Hide/Show button to collapse or expand the complete panel.
- Ask a follow-up question in the chat field.
- Ask additional questions; previous exchanges are sent to Vane as conversation history.
- Select **Reset conversation** to clear the follow-up chat and return to the initial search context.

The conversation is held in the browser page. It is not persisted after navigating away or refreshing the page.

## Configuration

The installer writes configuration to:

```text
/etc/searxng/vane-ai-overview.json
```

The file contains the Vane API URL and model/provider configuration. It is created with restricted permissions.

To change a model or provider later, edit this JSON file and restart SearXNG:

```bash
sudo nano /etc/searxng/vane-ai-overview.json
sudo systemctl restart searxng
```

## Uninstall

Run:

```bash
sudo ./uninstall.sh
```

The uninstaller removes the marked integration blocks from `webapp.py` and `results.html`, then restarts SearXNG. It deliberately leaves the configuration file in place; remove it manually if desired:

```bash
sudo rm /etc/searxng/vane-ai-overview.json
```

## Troubleshooting

Check the service:

```bash
sudo systemctl status searxng --no-pager
sudo journalctl -u searxng -n 100 --no-pager
```

Test Vane reachability from the SearXNG host:

```bash
curl -i http://YOUR-VANE-HOST:PORT/api/providers
```

Check the installed route markers:

```bash
grep -n "VANE_AI_OVERVIEW_ROUTE" /path/to/searx/webapp.py
grep -n "VANE_AI_OVERVIEW_UI" /path/to/searx/templates/simple/results.html
```

After changing templates, force-refresh the browser (`Ctrl+F5`).

## Notes and security

- The integration exposes two same-origin SearXNG routes: `GET /ai-overview` and `POST /ai-overview-followup`. They are intended to be used through the SearXNG UI.
- If SearXNG is exposed publicly, protect it with your existing authentication/reverse-proxy controls. The integration does not add authentication of its own.
- Do not expose Vane's API publicly unless you have secured it appropriately.
- The follow-up endpoint validates message roles and lengths, but this is not a substitute for access control.
- The browser uses `textContent` for generated text and creates source links only for HTTP(S) URLs.
- Vane answers and search sources can be wrong or incomplete. Verify important claims against the linked sources.
- This project modifies SearXNG's Python application and template files. Keep a Proxmox/LXC or filesystem backup before installing and re-test after SearXNG upgrades. An upstream update may replace or conflict with these changes.

## License

MIT. See [LICENSE](LICENSE).
