# VANE_AI_OVERVIEW_ROUTE
# SearXNG integration for Vane AI Overview and conversational follow-ups.

import json as _vane_json
import time as _vane_time
import threading as _vane_threading
import requests as _vane_requests
from pathlib import Path as _vane_Path
from flask import jsonify as _vane_jsonify, request as _vane_request

_VANE_CONFIG_PATH = _vane_Path("/etc/searxng/vane-ai-overview.json")
_VANE_CACHE = {}
_VANE_CACHE_LOCK = _vane_threading.Lock()
_VANE_CACHE_TTL = 600
_VANE_CACHE_MAX = 128


def _vane_config():
    try:
        with _VANE_CONFIG_PATH.open("r", encoding="utf-8") as _file:
            _config = _vane_json.load(_file)
        required = (
            "api_url", "chat_provider_id", "chat_model",
            "embedding_provider_id", "embedding_model"
        )
        if any(not isinstance(_config.get(key), str) or not _config[key].strip()
               for key in required):
            raise ValueError("One or more required Vane settings are missing.")
        return _config
    except Exception as _exc:
        logger.error("Could not load Vane integration configuration: %s", _exc)
        raise


def _vane_payload(query, history=None):
    _config = _vane_config()
    return {
        "chatModel": {
            "providerId": _config["chat_provider_id"],
            "key": _config["chat_model"]
        },
        "embeddingModel": {
            "providerId": _config["embedding_provider_id"],
            "key": _config["embedding_model"]
        },
        "optimizationMode": _config.get("optimization_mode", "speed"),
        "sources": _config.get("sources", ["web"]),
        "query": query,
        "history": history or [],
        "stream": False
    }


def _vane_extract_result(result):
    _message = result.get("message")
    if not isinstance(_message, str) or not _message.strip():
        raise ValueError("Vane returned an empty answer.")

    _sources = []
    for _item in result.get("sources", []):
        if not isinstance(_item, dict):
            continue
        _metadata = _item.get("metadata") or {}
        if not isinstance(_metadata, dict):
            _metadata = {}
        _url = _metadata.get("url")
        _title = _metadata.get("title") or _url
        if not isinstance(_url, str) or not _url.startswith(("https://", "http://")):
            continue
        _sources.append({
            "title": str(_title)[:300],
            "url": _url,
            "snippet": str(_item.get("content") or "")[:500]
        })
    return {"message": _message, "sources": _sources}


def _vane_call(query, history=None):
    _config = _vane_config()
    _response = _vane_requests.post(
        _config["api_url"],
        json=_vane_payload(query, history),
        timeout=(10, int(_config.get("timeout_seconds", 180)))
    )
    _response.raise_for_status()
    return _vane_extract_result(_response.json())


@app.route("/ai-overview", methods=["GET"])
def vane_ai_overview():
    _query = _vane_request.args.get("q", "").strip()
    if not _query:
        return _vane_jsonify({"error": "Missing search query"}), 400
    if len(_query) > 500:
        return _vane_jsonify({"error": "Search query is too long"}), 400

    _cache_key = _query.casefold()
    _now = _vane_time.monotonic()
    with _VANE_CACHE_LOCK:
        _cached = _VANE_CACHE.get(_cache_key)
        if _cached and _now - _cached[0] < _VANE_CACHE_TTL:
            return _vane_jsonify(_cached[1])

    try:
        _output = _vane_call(_query)
        with _VANE_CACHE_LOCK:
            if len(_VANE_CACHE) >= _VANE_CACHE_MAX:
                _VANE_CACHE.pop(next(iter(_VANE_CACHE)), None)
            _VANE_CACHE[_cache_key] = (_vane_time.monotonic(), _output)
        return _vane_jsonify(_output)
    except _vane_requests.Timeout:
        return _vane_jsonify({"error": "Vane took too long to respond. Please try again."}), 504
    except _vane_requests.RequestException as _exc:
        logger.error("Vane AI Overview request failed: %s", _exc)
        return _vane_jsonify({"error": "Could not connect to Vane."}), 502
    except (ValueError, TypeError, KeyError) as _exc:
        logger.error("Invalid Vane AI Overview response/configuration: %s", _exc)
        return _vane_jsonify({"error": "Vane returned an invalid response or configuration."}), 502


@app.route("/ai-overview-followup", methods=["POST"])
def vane_ai_overview_followup():
    _body = _vane_request.get_json(silent=True)
    if not isinstance(_body, dict):
        return _vane_jsonify({"error": "Invalid request"}), 400

    _query = _body.get("q", "")
    _history = _body.get("history", [])
    if not isinstance(_query, str) or not _query.strip():
        return _vane_jsonify({"error": "Missing question"}), 400
    _query = _query.strip()
    if len(_query) > 500:
        return _vane_jsonify({"error": "Question is too long"}), 400
    if not isinstance(_history, list) or len(_history) > 20:
        return _vane_jsonify({"error": "Invalid conversation history"}), 400

    _clean_history = []
    for _entry in _history:
        if not isinstance(_entry, (list, tuple)) or len(_entry) != 2:
            return _vane_jsonify({"error": "Invalid conversation history"}), 400
        _role, _content = _entry
        if _role not in ("human", "assistant"):
            return _vane_jsonify({"error": "Invalid conversation role"}), 400
        if not isinstance(_content, str) or len(_content) > 12000:
            return _vane_jsonify({"error": "Invalid conversation message"}), 400
        _clean_history.append([_role, _content])

    try:
        return _vane_jsonify(_vane_call(_query, _clean_history))
    except _vane_requests.Timeout:
        return _vane_jsonify({"error": "Vane took too long to respond. Please try again."}), 504
    except _vane_requests.RequestException as _exc:
        logger.error("Vane follow-up request failed: %s", _exc)
        return _vane_jsonify({"error": "Could not connect to Vane."}), 502
    except (ValueError, TypeError, KeyError) as _exc:
        logger.error("Invalid Vane follow-up response/configuration: %s", _exc)
        return _vane_jsonify({"error": "Vane returned an invalid response or configuration."}), 502

# END VANE_AI_OVERVIEW_ROUTE
