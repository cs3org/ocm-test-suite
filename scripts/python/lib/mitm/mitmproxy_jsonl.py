import json
import hashlib
import os
import threading
import time
from typing import Any, Dict, Optional, Tuple

from mitmproxy import ctx
from mitmproxy import http


def _utc_now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


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


def _headers_to_dict(headers: http.Headers) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for k, v in headers.items(multi=False):
        out[str(k)] = str(v)
    return out


def _decode_preview_bytes(data: Optional[bytes], max_bytes: int) -> Tuple[Optional[str], bool]:
    if not data:
        return None, False
    b = data
    truncated = False
    if len(b) > max_bytes:
        b = b[:max_bytes]
        truncated = True
    try:
        text = b.decode("utf-8", errors="replace")
    except Exception:
        text = None
    return text, truncated


def _get_decoded_content(message: http.Message) -> Optional[bytes]:
    """
    Return decoded (Content-Encoding) bytes when possible.
    Uses strict=False so we still get bytes on decode errors.
    """
    try:
        return message.get_content(strict=False)
    except Exception:
        return None


def _make_body(message: Optional[http.Message], max_preview_bytes: int) -> Optional[Dict[str, Any]]:
    if message is None:
        return None
    decoded = _get_decoded_content(message)
    size_bytes = len(decoded or b"")
    sha256 = hashlib.sha256(decoded).hexdigest() if decoded else None
    preview, truncated = _decode_preview_bytes(decoded, max_preview_bytes)
    return {
        "size_bytes": size_bytes,
        "sha256": sha256,
        "preview": preview,
        "truncated": truncated,
        "content_encoding": message.headers.get("Content-Encoding"),
    }


def _empty_body() -> Dict[str, Any]:
    return {
        "size_bytes": 0,
        "sha256": None,
        "preview": None,
        "truncated": False,
        "content_encoding": None,
    }


class OcmtsJsonlExporter:
    def __init__(self) -> None:
        self.traffic_path = os.environ.get("OCMTS_MITM_TRAFFIC_PATH", "/mitm/flows/traffic.jsonl")
        self.session_path = os.environ.get("OCMTS_MITM_SESSION_PATH", "/mitm/flows/session.json")
        self.redaction_path = os.environ.get("OCMTS_MITM_REDACTION_REPORT_PATH", "/mitm/redaction-report.json")
        self.body_max_bytes = _parse_int_env(os.environ.get("OCMTS_MITM_BODY_MAX_BYTES"), 10240)

        self.cell_id = os.environ.get("OCMTS_CELL_ID", "")
        self.flow_id = os.environ.get("OCMTS_FLOW_ID", "")
        # Policy: run_id defaults to execution_id when not provided.
        self.run_id = os.environ.get("OCMTS_RUN_ID") or os.environ.get("OCMTS_EXECUTION_ID", "")

        self._lock = threading.Lock()
        self._started_at = _utc_now_iso()
        self._flow_count = 0
        self._error_count = 0
        self._record_count = 0
        self._event_seq = 0

    def load(self, loader: Any) -> None:
        ctx.log.info(
            "ocmts jsonl exporter enabled "
            f"traffic_path={self.traffic_path} "
            f"session_path={self.session_path} "
            f"body_max_bytes={self.body_max_bytes} "
            f"cell_id={self.cell_id} "
            f"flow_id={self.flow_id} "
            f"run_id={self.run_id}"
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
        rec: Dict[str, Any] = {
            "mitmproxy_flow_id": getattr(flow, "id", None),
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
                "headers": _headers_to_dict(flow.request.headers),
                "body": _make_body(flow.request, self.body_max_bytes),
            },
            "response": {
                "status_code": flow.response.status_code if flow.response else None,
                "reason": flow.response.reason if flow.response else None,
                "http_version": flow.response.http_version if flow.response else None,
                "headers": _headers_to_dict(flow.response.headers) if flow.response else None,
                "body": _make_body(flow.response, self.body_max_bytes),
            },
        }
        self._append_jsonl(rec)

    def error(self, flow: http.HTTPFlow) -> None:
        self._error_count += 1
        req = flow.request if getattr(flow, "request", None) is not None else None
        rec: Dict[str, Any] = {
            "mitmproxy_flow_id": getattr(flow, "id", None),
            "request": {
                "method": req.method if req else None,
                "scheme": req.scheme if req else None,
                "host": req.host if req else None,
                "port": req.port if req else None,
                "path": req.path if req else None,
                "url": req.pretty_url if req else None,
                "http_version": req.http_version if req else None,
                "headers": _headers_to_dict(req.headers) if req else {},
                "body": _make_body(req, self.body_max_bytes) if req else _empty_body(),
            },
            "response": {
                "status_code": None,
                "reason": None,
                "http_version": None,
                "headers": {},
                "body": _empty_body(),
            },
            "error": str(flow.error) if getattr(flow, "error", None) else "unknown error",
        }
        self._append_jsonl(rec)

    def done(self) -> None:
        finished_at = _utc_now_iso()
        session: Dict[str, Any] = {
            "schema_version": 1,
            "cell_id": self.cell_id,
            "run_id": self.run_id,
            "capture_mode": "mitmproxy-jsonl",
            "record_count": self._record_count,
            "started_at": self._started_at,
            "finished_at": finished_at,
        }
        try:
            os.makedirs(os.path.dirname(self.session_path), exist_ok=True)
            with open(self.session_path, "w", encoding="utf-8") as f:
                json.dump(session, f, sort_keys=True, indent=2)
                f.write("\n")
        except Exception as e:
            ctx.log.warn(f"ocmts jsonl exporter could not write session json: {e}")

        # Policy: no redaction. Report is emitted for consumers to detect intent.
        try:
            with open(self.redaction_path, "w", encoding="utf-8") as f:
                json.dump(
                    {
                        "schema_version": 1,
                        "cell_id": self.cell_id,
                        "run_id": self.run_id,
                        "emitted_at": finished_at,
                        "redaction_enabled": False,
                        "policy": "debug-visible-test-evidence",
                        "dropped_fields": [],
                        "redacted_fields": [],
                    },
                    f,
                    sort_keys=True,
                    indent=2,
                )
                f.write("\n")
        except Exception as e:
            ctx.log.warn(f"ocmts jsonl exporter could not write redaction report: {e}")

    def _append_jsonl(self, obj: Dict[str, Any]) -> None:
        with self._lock:
            try:
                self._event_seq += 1
                seq = self._event_seq
                obj = dict(obj)
                obj.update(
                    {
                        "schema_version": 1,
                        "captured_at": _utc_now_iso(),
                        "event_id": f"evt_{seq:06d}",
                        "exchange_id": f"xchg_{seq:06d}",
                        "flow_id": self.flow_id,
                        "cell_id": self.cell_id,
                        "run_id": self.run_id,
                        "transport": "http",
                    }
                )
                line = json.dumps(obj, sort_keys=True)
                os.makedirs(os.path.dirname(self.traffic_path), exist_ok=True)
                with open(self.traffic_path, "a", encoding="utf-8") as f:
                    f.write(line)
                    f.write("\n")
                self._record_count += 1
            except Exception as e:
                ctx.log.warn(f"ocmts jsonl exporter could not append jsonl: {e}")


addons = [OcmtsJsonlExporter()]
