"""MCP Server for sub2api admin — HTTP (streamable_http) transport.

Thin wrapper over sub2api admin REST API (/api/v1/admin/*), exposed as MCP over HTTP.
Auth: SUB2API_ADMIN_TOKEN env var, sent via x-api-key header to upstream.
MCP clients must send Bearer token matching MCP_AUTH_TOKEN to connect.
"""
import os
import json
import time
import logging
import httpx
import uvicorn
import contextlib
from urllib.parse import urlparse, urlunparse
from mcp.server import Server
from mcp.server.streamable_http import StreamableHTTPServerTransport
from mcp.server.streamable_http_manager import StreamableHTTPSessionManager
from mcp.types import Tool, TextContent
from starlette.routing import Route, Mount
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import Response, JSONResponse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("sub2api-admin-mcp")

BASE = os.environ.get("SUB2API_BASE", "http://sub2api:8080/api/v1")
TOKEN = os.environ.get("SUB2API_ADMIN_TOKEN", "")
MCP_AUTH_TOKEN = os.environ.get("MCP_AUTH_TOKEN", "")
MCP_PORT = int(os.environ.get("MCP_PORT", "8765"))
MAX_TEXT = 6000
PATROL_STATE_FILE = os.environ.get("PATROL_STATE_FILE", "/data/patrol_state.json")

app = Server("sub2api-admin-mcp")


def _service_base_url() -> str:
    """Derive the service root from SUB2API_BASE, whose canonical value ends in /api/v1."""
    parsed = urlparse(BASE)
    path = parsed.path.rstrip("/")
    if path.endswith("/api/v1"):
        path = path[:-len("/api/v1")] or "/"
    return urlunparse(parsed._replace(path=path.rstrip("/") or "", params="", query="", fragment=""))


def _headers():
    return {"x-api-key": TOKEN, "Content-Type": "application/json"}


def _truncate(s: str) -> str:
    return s if len(s) <= MAX_TEXT else s[:MAX_TEXT] + f"\n...(truncated, total {len(s)} chars)"


async def _req(method: str, path: str, *, params=None, json_body=None, timeout=30.0):
    if not TOKEN:
        return False, "SUB2API_ADMIN_TOKEN not configured"
    try:
        async with httpx.AsyncClient(base_url=BASE, timeout=timeout) as c:
            r = await c.request(method, path, params=params, json=json_body, headers=_headers())
    except Exception as e:
        return False, f"Request error: {type(e).__name__}: {e}"
    if r.status_code != 200:
        return False, f"HTTP {r.status_code}: {r.text[:500]}"
    try:
        body = r.json()
    except Exception:
        return True, r.text
    if isinstance(body, dict) and "code" in body:
        if body.get("code") not in (0, None):
            return False, f"API error code={body.get('code')}: {body.get('message','')}"
        return True, body.get("data")
    return True, body


async def _public_req(method: str, path: str, *, timeout=30.0):
    try:
        async with httpx.AsyncClient(base_url=_service_base_url(), timeout=timeout) as c:
            r = await c.request(method, path, headers={"Accept": "application/json"})
    except Exception as e:
        return False, f"Request error: {type(e).__name__}: {e}"
    if r.status_code < 200 or r.status_code >= 300:
        return False, f"HTTP {r.status_code}: {r.text[:500]}"
    try:
        return True, r.json()
    except Exception:
        return True, r.text


@app.list_tools()
async def list_tools():
    return [
        Tool(name="pool_health",
             description="View pool health aggregate: available/error/rate-limited accounts by platform/group.",
             inputSchema={"type": "object", "properties": {
                 "platform": {"type": "string", "description": "Filter by platform (anthropic/openai/gemini)"},
                 "group_id": {"type": "integer", "description": "Filter by group ID"}
             }}),
        Tool(name="service_health",
             description="Check deployed sub2api HTTP health from the MCP runtime network.",
             inputSchema={"type": "object", "properties": {}}),
        Tool(name="service_version",
             description="Read deployed sub2api version/build identity from admin system/version.",
             inputSchema={"type": "object", "properties": {}}),
        Tool(name="release_identity",
             description="Validate deployed service commit against an expected commit prefix or full SHA.",
             inputSchema={"type": "object", "properties": {
                 "expect_commit": {"type": "string", "description": "Expected commit full SHA or prefix"}
             }, "required": ["expect_commit"]}),
        Tool(name="list_accounts",
             description="List accounts with filtering by group/status/platform/keyword + pagination.",
             inputSchema={"type": "object", "properties": {
                 "group": {"type": "string", "description": "Group ID or 'ungrouped'"},
                 "status": {"type": "string", "description": "active/inactive/error"},
                 "platform": {"type": "string"},
                 "search": {"type": "string", "description": "Name fuzzy search"},
                 "page": {"type": "integer", "default": 1},
                 "page_size": {"type": "integer", "default": 20}
             }}),
        Tool(name="account_detail",
             description="Get single account details (status/credentials/rate-limit/expiry) + usage stats.",
             inputSchema={"type": "object", "properties": {
                 "id": {"type": "integer", "description": "Account ID"},
                 "stats_days": {"type": "integer", "default": 7, "description": "Stats for last N days"}
             }, "required": ["id"]}),
        Tool(name="test_account",
             description="Send real test request to probe account. Success auto-recovers (clears error/rate-limit).",
             inputSchema={"type": "object", "properties": {
                 "id": {"type": "integer"},
                 "model_id": {"type": "string", "description": "Optional, empty uses platform default"}
             }, "required": ["id"]}),
        Tool(name="probe_account",
             description="Auto-detect upstream capabilities (protocol, TLS fingerprint). Writes to extra.",
             inputSchema={"type": "object", "properties": {
                 "id": {"type": "integer", "description": "Account ID"}
             }, "required": ["id"]}),
        Tool(name="set_schedulable",
             description="Toggle account online/offline (schedulable bool).",
             inputSchema={"type": "object", "properties": {
                 "id": {"type": "integer"},
                 "schedulable": {"type": "boolean"}
             }, "required": ["id", "schedulable"]}),
        Tool(name="clear_error",
             description="Clear account error state. Supports single (id) or batch (ids).",
             inputSchema={"type": "object", "properties": {
                 "id": {"type": "integer", "description": "Single account ID"},
                 "ids": {"type": "array", "items": {"type": "integer"}, "description": "Batch account IDs"}
             }}),
        Tool(name="bulk_update",
             description="Bulk update accounts by ID list or filters. Can change status/schedulable/group/priority.",
             inputSchema={"type": "object", "properties": {
                 "account_ids": {"type": "array", "items": {"type": "integer"}},
                 "filters": {"type": "object", "description": "{platform,type,status,group,search}"},
                 "status": {"type": "string", "description": "active/inactive/error"},
                 "schedulable": {"type": "boolean"},
                 "priority": {"type": "integer"},
                 "group_ids": {"type": "array", "items": {"type": "integer"}}
             }}),
        Tool(name="setup_autoheal",
             description="Configure scheduled test + auto-recovery for an account.",
             inputSchema={"type": "object", "properties": {
                 "account_id": {"type": "integer"},
                 "cron_expression": {"type": "string", "default": "*/15 * * * *", "description": "5-field cron"},
                 "model_id": {"type": "string", "description": "Optional, empty uses platform default"},
                 "auto_recover": {"type": "boolean", "default": True},
                 "enabled": {"type": "boolean", "default": True}
             }, "required": ["account_id"]}),
        Tool(name="list_autoheal",
             description="List scheduled test/autoheal plans for an account.",
             inputSchema={"type": "object", "properties": {
                 "account_id": {"type": "integer"}
             }, "required": ["account_id"]}),
        Tool(name="export_accounts",
             description="Export entire pool as JSON (accounts + proxies) for backup/migration.",
             inputSchema={"type": "object", "properties": {
                 "group": {"type": "string", "description": "Optional, export specific group only"},
                 "include_proxies": {"type": "boolean", "default": True}
             }}),
        Tool(name="import_accounts",
             description="Bulk import pool JSON (export_accounts format).",
             inputSchema={"type": "object", "properties": {
                 "data": {"type": "object", "description": "DataPayload:{type,version,proxies,accounts}"},
                 "skip_default_group_bind": {"type": "boolean", "default": True}
             }, "required": ["data"]}),
        Tool(name="pool_patrol",
             description="Deterministic pool patrol (zero LLM reasoning). Auto: pull health -> diff snapshot -> rule engine -> return change summary.",
             inputSchema={"type": "object", "properties": {
                 "ttft_threshold_ms": {"type": "integer", "default": 30000, "description": "Slow threshold ms"},
                 "dry_run": {"type": "boolean", "default": False, "description": "true=report only, no actions"}
             }}),
        Tool(name="create_account",
             description="Create new account. Returns new id + key fields.",
             inputSchema={"type": "object", "properties": {
                 "name": {"type": "string", "description": "Account name"},
                 "platform": {"type": "string", "description": "anthropic/openai/gemini/antigravity"},
                 "type": {"type": "string", "default": "apikey", "description": "apikey or oauth"},
                 "credentials": {"type": "object", "description": "e.g. {api_key:'sk-xx',base_url:'https://...'}"},
                 "group_ids": {"type": "array", "items": {"type": "integer"}, "description": "Bind to group IDs"},
                 "concurrency": {"type": "integer", "default": 10},
                 "priority": {"type": "integer", "default": 1}
             }, "required": ["name", "platform", "credentials"]}),
        Tool(name="update_account",
             description="Update account config. Can change name/credentials/concurrency/priority/group_ids/schedulable.",
             inputSchema={"type": "object", "properties": {
                 "id": {"type": "integer"},
                 "patch": {"type": "object", "description": "Fields to update, e.g. {group_ids:[1],priority:5}"}
             }, "required": ["id", "patch"]}),
        Tool(name="delete_account",
             description="Delete account (irreversible).",
             inputSchema={"type": "object", "properties": {
                 "id": {"type": "integer"}
             }, "required": ["id"]}),
        Tool(name="list_groups",
             description="List all groups.",
             inputSchema={"type": "object", "properties": {}}),
        Tool(name="create_group",
             description="Create new group.",
             inputSchema={"type": "object", "properties": {
                 "name": {"type": "string"},
                 "platform": {"type": "string"},
                 "description": {"type": "string"}
             }, "required": ["name", "platform"]}),
        Tool(name="update_group",
             description="Update group config.",
             inputSchema={"type": "object", "properties": {
                 "id": {"type": "integer"},
                 "patch": {"type": "object"}
             }, "required": ["id", "patch"]}),
        Tool(name="clear_rate_limit",
             description="Clear account rate-limit state.",
             inputSchema={"type": "object", "properties": {
                 "id": {"type": "integer"}
             }, "required": ["id"]}),
        Tool(name="get_models",
             description="Get available models for an account.",
             inputSchema={"type": "object", "properties": {
                 "id": {"type": "integer"}
             }, "required": ["id"]}),
        Tool(name="admin_request",
             description="Generic admin API passthrough.",
             inputSchema={"type": "object", "properties": {
                 "method": {"type": "string", "enum": ["GET","POST","PUT","DELETE"]},
                 "path": {"type": "string", "description": "Relative path, e.g. /admin/accounts/47/groups"},
                 "params": {"type": "object", "description": "URL query params"},
                 "body": {"type": "object", "description": "JSON body"}
             }, "required": ["method", "path"]}),
    ]


def _fmt(data) -> str:
    return _truncate(json.dumps(data, ensure_ascii=False, indent=2))


@app.call_tool()
async def call_tool(name: str, arguments: dict):
    a = arguments or {}

    if name == "service_health":
        ok, data = await _public_req("GET", "/health")
        return [TextContent(type="text", text=("Service health:\n" + _fmt(data)) if ok else f"Health failed: {data}")]

    if name == "service_version":
        ok, data = await _req("GET", "/admin/system/version")
        return [TextContent(type="text", text=("Service version:\n" + _fmt(data)) if ok else f"Version failed: {data}")]

    if name == "release_identity":
        expected = a["expect_commit"]
        ok, data = await _req("GET", "/admin/system/version")
        if not ok:
            return [TextContent(type="text", text=f"Release identity failed: {data}")]
        actual = data.get("commit", "") if isinstance(data, dict) else ""
        matched = bool(actual) and (actual == expected or actual.startswith(expected) or expected.startswith(actual))
        status = "MATCH" if matched else "MISMATCH"
        return [TextContent(type="text", text=f"Release identity {status}\nexpected={expected}\nactual={actual}\nversion:\n{_fmt(data)}")]

    if name == "pool_health":
        params = {k: a[k] for k in ("platform", "group_id") if a.get(k) is not None}
        ok, data = await _req("GET", "/admin/ops/account-availability", params=params)
        if not ok:
            return [TextContent(type="text", text=f"Query failed: {data}")]
        if isinstance(data, dict) and data.get("enabled") is False:
            return [TextContent(type="text", text="Realtime monitoring disabled. Use list_accounts with status filter instead.")]
        return [TextContent(type="text", text="Pool health:\n" + _fmt(data))]

    if name == "list_accounts":
        params = {"page": a.get("page", 1), "page_size": a.get("page_size", 20)}
        for k in ("group", "status", "platform", "search"):
            if a.get(k):
                params[k] = a[k]
        ok, data = await _req("GET", "/admin/accounts", params=params)
        return [TextContent(type="text", text=("Accounts:\n" + _fmt(data)) if ok else f"Query failed: {data}")]

    if name == "account_detail":
        aid = a["id"]
        ok, data = await _req("GET", f"/admin/accounts/{aid}")
        if not ok:
            return [TextContent(type="text", text=f"Query failed: {data}")]
        ok2, stats = await _req("GET", f"/admin/accounts/{aid}/stats", params={"days": a.get("stats_days", 7)})
        out = "Account detail:\n" + _fmt(data)
        if ok2:
            out += "\n\nUsage stats:\n" + _fmt(stats)
        return [TextContent(type="text", text=out)]

    if name == "test_account":
        body = {}
        if a.get("model_id"):
            body["model_id"] = a["model_id"]
        ok, data = await _req("POST", f"/admin/accounts/{a['id']}/test", json_body=body, timeout=60.0)
        return [TextContent(type="text", text=("Test result:\n" + _fmt(data)) if ok else f"Test failed: {data}")]

    if name == "probe_account":
        ok, data = await _req("POST", f"/admin/accounts/{a['id']}/probe", timeout=60.0)
        if ok:
            d = data.get("data", data) if isinstance(data, dict) else data
            return [TextContent(type="text", text=f"Probe result:\nProtocol: {d.get('WireAPI','?')}\nTLS: {'required' if d.get('TLSRequired') else 'not required'}\nStatus: {d.get('Status','?')}\nError: {d.get('Error','none')}")]
        return [TextContent(type="text", text=f"Probe failed: {data}")]

    if name == "set_schedulable":
        ok, data = await _req("POST", f"/admin/accounts/{a['id']}/schedulable",
                              json_body={"schedulable": a["schedulable"]})
        return [TextContent(type="text", text=("Updated:\n" + _fmt(data)) if ok else f"Failed: {data}")]

    if name == "clear_error":
        if a.get("ids"):
            ok, data = await _req("POST", "/admin/accounts/batch-clear-error",
                                  json_body={"account_ids": a["ids"]})
        elif a.get("id") is not None:
            ok, data = await _req("POST", f"/admin/accounts/{a['id']}/clear-error")
        else:
            return [TextContent(type="text", text="Provide id or ids")]
        return [TextContent(type="text", text=("Cleared:\n" + _fmt(data)) if ok else f"Failed: {data}")]

    if name == "bulk_update":
        body = {}
        if a.get("account_ids"):
            body["account_ids"] = a["account_ids"]
        elif a.get("filters"):
            body["filters"] = a["filters"]
        else:
            return [TextContent(type="text", text="Provide account_ids or filters")]
        for k in ("status", "schedulable", "priority", "group_ids"):
            if a.get(k) is not None:
                body[k] = a[k]
        ok, data = await _req("POST", "/admin/accounts/bulk-update", json_body=body, timeout=60.0)
        return [TextContent(type="text", text=("Bulk update done:\n" + _fmt(data)) if ok else f"Failed: {data}")]

    if name == "setup_autoheal":
        body = {
            "account_id": a["account_id"],
            "cron_expression": a.get("cron_expression", "*/15 * * * *"),
            "auto_recover": a.get("auto_recover", True),
            "enabled": a.get("enabled", True),
        }
        if a.get("model_id"):
            body["model_id"] = a["model_id"]
        ok, data = await _req("POST", "/admin/scheduled-test-plans", json_body=body)
        return [TextContent(type="text", text=("Autoheal plan created:\n" + _fmt(data)) if ok else f"Failed: {data}")]

    if name == "list_autoheal":
        ok, data = await _req("GET", f"/admin/accounts/{a['account_id']}/scheduled-test-plans")
        return [TextContent(type="text", text=("Autoheal plans:\n" + _fmt(data)) if ok else f"Query failed: {data}")]

    if name == "export_accounts":
        params = {"include_proxies": str(a.get("include_proxies", True)).lower()}
        if a.get("group"):
            params["group"] = a["group"]
        ok, data = await _req("GET", "/admin/accounts/data", params=params, timeout=60.0)
        return [TextContent(type="text", text=("Export:\n" + _fmt(data)) if ok else f"Export failed: {data}")]

    if name == "import_accounts":
        body = {"data": a["data"], "skip_default_group_bind": a.get("skip_default_group_bind", True)}
        ok, data = await _req("POST", "/admin/accounts/data", json_body=body, timeout=120.0)
        return [TextContent(type="text", text=("Import done:\n" + _fmt(data)) if ok else f"Import failed: {data}")]

    if name == "create_account":
        body = {"name": a["name"], "platform": a["platform"], "credentials": a["credentials"]}
        for k in ("type", "concurrency", "priority", "group_ids"):
            if a.get(k) is not None:
                body[k] = a[k]
        ok, data = await _req("POST", "/admin/accounts", json_body=body)
        if not ok:
            return [TextContent(type="text", text=f"Create failed: {data}")]
        d = data if isinstance(data, dict) else {}
        return [TextContent(type="text", text=f"Created | id={d.get('id')} name={d.get('name')} platform={d.get('platform')} status={d.get('status')}")]

    if name == "update_account":
        ok, data = await _req("PUT", f"/admin/accounts/{a['id']}", json_body=a["patch"])
        if not ok:
            return [TextContent(type="text", text=f"Update failed: {data}")]
        d = data if isinstance(data, dict) else {}
        return [TextContent(type="text", text=f"Updated | id={d.get('id')} name={d.get('name')} status={d.get('status')}")]

    if name == "delete_account":
        ok, data = await _req("DELETE", f"/admin/accounts/{a['id']}")
        return [TextContent(type="text", text=f"Deleted id={a['id']}" if ok else f"Delete failed: {data}")]

    if name == "list_groups":
        ok, data = await _req("GET", "/admin/groups")
        return [TextContent(type="text", text=("Groups:\n" + _fmt(data)) if ok else f"Query failed: {data}")]

    if name == "create_group":
        body = {"name": a["name"], "platform": a["platform"]}
        if a.get("description"):
            body["description"] = a["description"]
        ok, data = await _req("POST", "/admin/groups", json_body=body)
        if not ok:
            return [TextContent(type="text", text=f"Create group failed: {data}")]
        d = data if isinstance(data, dict) else {}
        return [TextContent(type="text", text=f"Group created | id={d.get('id')} name={d.get('name')} platform={d.get('platform')}")]

    if name == "update_group":
        ok, data = await _req("PUT", f"/admin/groups/{a['id']}", json_body=a["patch"])
        if not ok:
            return [TextContent(type="text", text=f"Update group failed: {data}")]
        d = data if isinstance(data, dict) else {}
        return [TextContent(type="text", text=f"Group updated | id={d.get('id')} name={d.get('name')}")]

    if name == "clear_rate_limit":
        ok, data = await _req("POST", f"/admin/accounts/{a['id']}/clear-rate-limit")
        return [TextContent(type="text", text=f"Rate limit cleared id={a['id']}" if ok else f"Failed: {data}")]

    if name == "get_models":
        ok, data = await _req("GET", f"/admin/accounts/{a['id']}/models")
        return [TextContent(type="text", text=("Models:\n" + _fmt(data)) if ok else f"Query failed: {data}")]

    if name == "admin_request":
        method = a["method"].upper()
        path = a["path"] if a["path"].startswith("/") else "/" + a["path"]
        ok, data = await _req(method, path, params=a.get("params"), json_body=a.get("body"), timeout=60.0)
        return [TextContent(type="text", text=f"{'OK' if ok else 'ERROR'} {method} {path}\n{_fmt(data) if ok else data}")]

    if name == "pool_patrol":
        return await _pool_patrol(
            ttft_threshold_ms=a.get("ttft_threshold_ms", 30000),
            dry_run=a.get("dry_run", False),
        )

    return [TextContent(type="text", text=f"Unknown tool: {name}")]


def _load_patrol_state() -> dict:
    try:
        with open(PATROL_STATE_FILE, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"accounts": {}, "last_daily_report": None, "reported_slow": {}}


def _save_patrol_state(state: dict):
    with open(PATROL_STATE_FILE, "w") as f:
        json.dump(state, f, ensure_ascii=False)


async def _pool_patrol(ttft_threshold_ms: int = 30000, dry_run: bool = False):
    """Deterministic pool patrol. Zero LLM reasoning, pure rule engine."""
    ok, health_data = await _req("GET", "/admin/ops/account-availability")
    if not ok:
        return [TextContent(type="text", text=f"Patrol failed: cannot fetch pool state ({health_data})")]

    accounts = health_data.get("account", {}) if isinstance(health_data, dict) else {}
    if not accounts:
        return [TextContent(type="text", text="Patrol complete: pool empty or data anomaly")]

    state = _load_patrol_state()
    prev_accounts = state.get("accounts", {})
    handled_ids = set(state.get("handled_ids", []))
    actions = []
    warnings = []
    recoveries = []

    for aid_str, info in accounts.items():
        aid = int(aid_str)
        name = info.get("account_name", f"#{aid}")[:30]
        err_msg = info.get("error_message", "") or ""
        has_error = info.get("has_error", False)
        is_available = info.get("is_available", False)
        prev = prev_accounts.get(aid_str, {})
        was_available = prev.get("is_available", None)

        if has_error and ("token_expired" in err_msg or "401" in err_msg[:50]) and aid not in handled_ids:
            if not dry_run:
                await _req("POST", f"/admin/accounts/{aid}/schedulable", json_body={"schedulable": False})
                handled_ids.add(aid)
            actions.append(f"OFFLINE {name} (token_expired/401)")

        elif has_error and "403" in err_msg and aid not in handled_ids:
            handled_ids.add(aid)
            warnings.append(f"QUOTA {name} insufficient balance")

        if was_available is True and not is_available:
            warnings.append(f"DOWN {name} available->unavailable")
        elif was_available is False and is_available:
            recoveries.append(f"UP {name} recovered")
            handled_ids.discard(aid)

    state["accounts"] = {aid_str: {"is_available": info.get("is_available"), "has_error": info.get("has_error")} for aid_str, info in accounts.items()}
    state["handled_ids"] = list(handled_ids)
    _save_patrol_state(state)

    total = len(accounts)
    available = sum(1 for a in accounts.values() if a.get("is_available"))
    errors = sum(1 for a in accounts.values() if a.get("has_error"))

    if not actions and not warnings and not recoveries:
        return [TextContent(type="text", text=f"No changes | available {available}/{total} errors {errors}")]

    lines = []
    if actions:
        lines.append("[ACTIONS]" + (" (dry_run)" if dry_run else ""))
        lines.extend(actions)
    if warnings:
        lines.append("[WARNINGS]")
        lines.extend(warnings)
    if recoveries:
        lines.append("[RECOVERIES]")
        lines.extend(recoveries)
    lines.append(f"---\nSummary: available {available}/{total} errors {errors}")
    return [TextContent(type="text", text="\n".join(lines))]



# --- HTTP Server Entrypoint (Streamable HTTP) ---



session_manager = StreamableHTTPSessionManager(
    app=app,
    json_response=True,
    stateless=True,  # each request is independent, no session tracking needed
)


async def handle_mcp(request: Request):
    """MCP streamable HTTP endpoint - delegates to session manager."""
    # Optional: simple Bearer token auth
    if MCP_AUTH_TOKEN:
        auth = request.headers.get("authorization", "")
        if not auth.startswith("Bearer ") or auth[7:] != MCP_AUTH_TOKEN:
            return JSONResponse({"error": "unauthorized"}, status_code=401)
    await session_manager.handle_request(request.scope, request.receive, request._send)


async def health(request: Request):
    return JSONResponse({"status": "ok", "server": "sub2api-admin-mcp", "transport": "streamable_http"})


@contextlib.asynccontextmanager
async def lifespan(app):
    async with session_manager.run():
        logger.info(f"MCP HTTP server running on port {MCP_PORT}")
        yield


starlette_app = Starlette(
    debug=False,
    routes=[
        Route("/mcp", endpoint=handle_mcp, methods=["GET", "POST", "DELETE"]),
        Route("/health", endpoint=health),
    ],
    lifespan=lifespan,
)

if __name__ == "__main__":
    uvicorn.run(starlette_app, host="0.0.0.0", port=MCP_PORT, log_level="info")
