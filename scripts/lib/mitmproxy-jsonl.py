import json
import os
import threading
import time
from typing import Any, Dict, Optional, Tuple

from mitmproxy import ctx
from mitmproxy import http


SENSITIVE_HEADER_NAMES = {
    "authorization",
    "cookie",
    "set-cookie",
    "x-csrf-token",
    "requesttoken",
    "ocs-apirequest",
}


def _utc_now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _parse_bool_env(value: Optional[str], default: bool) -> bool:
    if value is None:
        return default
    v = str(value).strip().lower()
    if v in {"1", "true", "yes", "y", "on"}:
        return True
    if v in {"0", "false", "no", "n", "off"}:
        return False
    return default


def _parse_int_env(value: Optional[str], default: int) -> int:
    if value is None:
        return default
    v = str(value).strip()
    if v == "":
        return default
    try:
        n = int(v, 10)
    except Exception:
        return default
    return n if n >= 0 else default


def _headers_to_dict(headers: http.Headers, redact: bool) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for k, v in headers.items(multi=False):
        key = str(k)
        lower = key.lower()
        if redact and (lower in SENSITIVE_HEADER_NAMES):
            out[key] = "<redacted>"
        else:
            out[key] = str(v)
    return out


def _decode_preview_bytes(data: Optional[bytes], max_bytes: int) -> Tuple[Optional[str], bool, int]:
    if not data:
        return None, False, 0
    b = data
    truncated = False
    if len(b) > max_bytes:
        b = b[:max_bytes]
        truncated = True
    try:
        text = b.decode("utf-8", errors="replace")
    except Exception:
        text = None
    return text, truncated, len(b)


def _get_decoded_content(message: http.Message) -> Optional[bytes]:
    """
    Return decoded (Content-Encoding) bytes when possible.
    Uses strict=False so we still get bytes on decode errors.
    """
    try:
        return message.get_content(strict=False)
    except Exception:
        return None


class OcmtsJsonlExporter:
    def __init__(self) -> None:
        self.traffic_path = os.environ.get("OCMTS_MITM_TRAFFIC_PATH", "/mitm/flows/traffic.jsonl")
        self.session_path = os.environ.get("OCMTS_MITM_SESSION_PATH", "/mitm/flows/session.json")
        self.redaction_path = os.environ.get("OCMTS_MITM_REDACTION_REPORT_PATH", "/mitm/redaction-report.json")
        self.body_max_bytes = _parse_int_env(os.environ.get("OCMTS_MITM_BODY_MAX_BYTES"), 10240)
        # Default to no redaction for test env runs.
        self.redact_headers = _parse_bool_env(os.environ.get("OCMTS_MITM_REDACT_HEADERS"), False)
        self._lock = threading.Lock()
        self._started_at = _utc_now_iso()
        self._flow_count = 0
        self._error_count = 0

    def load(self, loader: Any) -> None:
        ctx.log.info(
            "ocmts jsonl exporter enabled "
            f"traffic_path={self.traffic_path} "
            f"session_path={self.session_path} "
            f"body_max_bytes={self.body_max_bytes} "
            f"redact_headers={self.redact_headers}"
        )
        # Make sure the traffic file starts fresh for the run.
        try:
            os.makedirs(os.path.dirname(self.traffic_path), exist_ok=True)
            with open(self.traffic_path, "w", encoding="utf-8") as f:
                f.write("")
        except Exception as e:
            ctx.log.warn(f"ocmts jsonl exporter could not initialize traffic file: {e}")

    def response(self, flow: http.HTTPFlow) -> None:
        self._flow_count += 1
        req_raw = flow.request.raw_content
        req_decoded = _get_decoded_content(flow.request)
        req_preview, req_truncated, req_preview_bytes = _decode_preview_bytes(req_decoded, self.body_max_bytes)

        resp_raw = flow.response.raw_content if flow.response else None
        resp_decoded = _get_decoded_content(flow.response) if flow.response else None
        resp_preview, resp_truncated, resp_preview_bytes = _decode_preview_bytes(resp_decoded, self.body_max_bytes)

        rec: Dict[str, Any] = {
            "ts": _utc_now_iso(),
            "type": "http",
            "id": getattr(flow, "id", None),
            "client": getattr(flow.client_conn, "address", None),
            "server": getattr(flow.server_conn, "address", None),
            "request": {
                "method": flow.request.method,
                "scheme": flow.request.scheme,
                "host": flow.request.host,
                "port": flow.request.port,
                "path": flow.request.path,
                "url": flow.request.pretty_url,
                "http_version": flow.request.http_version,
                "headers": _headers_to_dict(flow.request.headers, self.redact_headers),
                "content_encoding": flow.request.headers.get("Content-Encoding"),
                "content_length_raw": len(req_raw or b""),
                "content_length_decoded": len(req_decoded or b""),
                "content_preview_bytes": req_preview_bytes,
                "content_preview_truncated": req_truncated,
                "content_preview": req_preview,
            },
            "response": {
                "status_code": flow.response.status_code if flow.response else None,
                "reason": flow.response.reason if flow.response else None,
                "http_version": flow.response.http_version if flow.response else None,
                "headers": _headers_to_dict(flow.response.headers, self.redact_headers) if flow.response else None,
                "content_encoding": flow.response.headers.get("Content-Encoding") if flow.response else None,
                "content_length_raw": len(resp_raw or b"") if flow.response else None,
                "content_length_decoded": len(resp_decoded or b"") if flow.response else None,
                "content_preview_bytes": resp_preview_bytes if flow.response else None,
                "content_preview_truncated": resp_truncated if flow.response else None,
                "content_preview": resp_preview if flow.response else None,
            },
        }
        self._append_jsonl(rec)

    def error(self, flow: http.HTTPFlow) -> None:
        self._error_count += 1
        rec: Dict[str, Any] = {
            "ts": _utc_now_iso(),
            "type": "error",
            "id": getattr(flow, "id", None),
            "request": {
                "method": flow.request.method if flow.request else None,
                "url": flow.request.pretty_url if flow.request else None,
                "headers": _headers_to_dict(flow.request.headers, self.redact_headers) if flow.request else None,
            },
            "error": str(flow.error) if getattr(flow, "error", None) else "unknown error",
        }
        self._append_jsonl(rec)

    def done(self) -> None:
        finished_at = _utc_now_iso()
        session = {
            "schema": "ocmts.mitm.session.v1",
            "started_at": self._started_at,
            "finished_at": finished_at,
            "flows_total": self._flow_count,
            "flows_error": self._error_count,
        }
        try:
            os.makedirs(os.path.dirname(self.session_path), exist_ok=True)
            with open(self.session_path, "w", encoding="utf-8") as f:
                json.dump(session, f, sort_keys=True, indent=2)
                f.write("\n")
        except Exception as e:
            ctx.log.warn(f"ocmts jsonl exporter could not write session json: {e}")

        # Redaction report is informational. Default is no redaction.
        try:
            with open(self.redaction_path, "w", encoding="utf-8") as f:
                json.dump(
                    {
                        "schema": "ocmts.mitm.redaction-report.v1",
                        "note": "header redaction is optional and disabled by default",
                        "enabled": self.redact_headers,
                        "redacted_headers": (sorted(SENSITIVE_HEADER_NAMES) if self.redact_headers else []),
                    },
                    f,
                    sort_keys=True,
                    indent=2,
                )
                f.write("\n")
        except Exception as e:
            ctx.log.warn(f"ocmts jsonl exporter could not write redaction report: {e}")

    def _append_jsonl(self, obj: Dict[str, Any]) -> None:
        line = json.dumps(obj, sort_keys=True)
        with self._lock:
            try:
                os.makedirs(os.path.dirname(self.traffic_path), exist_ok=True)
                with open(self.traffic_path, "a", encoding="utf-8") as f:
                    f.write(line)
                    f.write("\n")
            except Exception as e:
                ctx.log.warn(f"ocmts jsonl exporter could not append jsonl: {e}")


addons = [OcmtsJsonlExporter()]
