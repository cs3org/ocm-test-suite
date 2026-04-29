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


def _peer_address(conn: Any) -> Tuple[Optional[str], Optional[int]]:
    """
    Best-effort extraction of (host_or_ip, port) from a mitmproxy
    Connection-like object. Returns (None, None) when no address is
    available. Tries `peername` first (newer mitmproxy), then `address`.
    """
    if conn is None:
        return None, None
    try:
        addr = getattr(conn, "peername", None) or getattr(conn, "address", None)
        if not addr:
            return None, None
        host = addr[0] if len(addr) > 0 else None
        port = addr[1] if len(addr) > 1 else None
        host_s = str(host) if host is not None else None
        port_i: Optional[int] = None
        if port is not None:
            try:
                port_i = int(port)
            except Exception:
                port_i = None
        return host_s, port_i
    except Exception:
        return None, None


class OcmtsJsonlExporter:
    def __init__(self) -> None:
        self.traffic_path = os.environ.get("OCMTS_MITM_TRAFFIC_PATH", "/mitm/flows/traffic.jsonl")
        self.session_path = os.environ.get("OCMTS_MITM_SESSION_PATH", "/mitm/flows/session.json")
        self.redaction_path = os.environ.get("OCMTS_MITM_REDACTION_REPORT_PATH", "/mitm/redaction-report.json")
        self.startup_path = os.environ.get("OCMTS_MITM_STARTUP_PATH", "/mitm/startup.v1.json")
        self.connect_errors_path = os.environ.get(
            "OCMTS_MITM_CONNECT_ERRORS_PATH", "/mitm/connect-errors.v1.jsonl"
        )
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
        self._connect_error_seq = 0

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
        # Write the startup record once per addon load.
        try:
            listen_host = "0.0.0.0"
            listen_port = 8080
            try:
                opt_host = getattr(ctx.options, "listen_host", None)
                opt_port = getattr(ctx.options, "listen_port", None)
                if opt_host:
                    listen_host = str(opt_host)
                if opt_port:
                    listen_port = int(opt_port)
            except Exception:
                pass

            # mitmproxy verifies upstream certs by default unless ssl_insecure is set.
            ssl_verify_upstream = True

            confdir = os.environ.get("MITMPROXY_CONFDIR", "/mitm/conf")
            overrides: list = []
            if self.body_max_bytes != 10240:
                overrides.append(f"body_max_bytes={self.body_max_bytes}")

            startup = {
                "schema_version": 1,
                "emitted_at": _utc_now_iso(),
                "cell_id": self.cell_id,
                "run_id": self.run_id,
                "addon": {"name": "ocmts_jsonl_exporter", "version": "1.0.0"},
                "listen": {
                    "host": listen_host,
                    "port": listen_port,
                    "tls": "intercept",
                    "http2": True,
                },
                "ca": {
                    "name": "dockypody",
                    "cert": confdir + "/mitmproxy-ca.pem",
                    "bundle": confdir + "/upstream-ca-bundle.pem",
                },
                "ssl_verify_upstream": ssl_verify_upstream,
                "config_overrides": overrides,
            }
            os.makedirs(os.path.dirname(self.startup_path), exist_ok=True)
            with open(self.startup_path, "w", encoding="utf-8") as f:
                json.dump(startup, f, sort_keys=True, indent=2)
                f.write("\n")
        except Exception as e:
            ctx.log.warn(f"ocmts jsonl exporter could not write startup record: {e}")

        # Make sure the traffic file starts fresh for the run.
        try:
            os.makedirs(os.path.dirname(self.traffic_path), exist_ok=True)
            with open(self.traffic_path, "w", encoding="utf-8") as f:
                f.write("")
        except Exception as e:
            ctx.log.warn(f"ocmts jsonl exporter could not initialize traffic file: {e}")

        # Truncate the connect-errors file so each run starts clean.
        try:
            os.makedirs(os.path.dirname(self.connect_errors_path), exist_ok=True)
            with open(self.connect_errors_path, "w", encoding="utf-8") as f:
                f.write("")
        except Exception as e:
            ctx.log.warn(
                f"ocmts jsonl exporter could not initialize connect-errors file: {e}"
            )

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

    def tcp_error(self, flow) -> None:
        try:
            err = getattr(flow, "error", None)
            msg = ""
            if err is not None:
                msg = getattr(err, "msg", None) or str(err)
            kind = self._classify_tcp_error(msg)
            host, port = _peer_address(getattr(flow, "server_conn", None))
            client_ip, client_port = _peer_address(getattr(flow, "client_conn", None))
            self._append_connect_error(
                kind,
                {
                    "client": {"ip": client_ip, "port": client_port},
                    "message": msg or "tcp error",
                    "host": host,
                    "port": port,
                },
            )
        except Exception as e:
            ctx.log.warn(f"ocmts jsonl exporter tcp_error hook failed: {e}")

    def server_connect(self, data) -> None:
        # Belt-and-suspenders: most server_connect failures surface via tcp_error.
        # We only emit when an obvious DNS-style failure is attached to `data`.
        try:
            err = getattr(data, "error", None)
            if err is None:
                return
            msg = getattr(err, "msg", None) or str(err)
            low = msg.lower() if isinstance(msg, str) else ""
            if (
                "dns" in low
                or "resolution" in low
                or "resolve" in low
                or err.__class__.__name__.lower().endswith("dnserror")
            ):
                kind = "name-resolution"
            else:
                kind = "other"
            server = getattr(data, "server", None) or data
            host, port = _peer_address(server)
            self._append_connect_error(
                kind,
                {
                    "client": {"ip": None, "port": None},
                    "message": msg,
                    "host": host,
                    "port": port,
                },
            )
        except Exception as e:
            ctx.log.warn(f"ocmts jsonl exporter server_connect hook failed: {e}")

    def client_disconnected(self, client) -> None:
        # Only record when the client closed with an error attached
        # (e.g. TLS handshake failure). Clean disconnects are silent.
        try:
            err = getattr(client, "error", None)
            if err is None:
                return
            msg = getattr(err, "msg", None) or str(err)
            low = msg.lower() if isinstance(msg, str) else ""
            if "tls" in low or "handshake" in low or "ssl" in low:
                kind = "tls-handshake"
            else:
                kind = "client-disconnect"
            client_ip, client_port = _peer_address(client)
            self._append_connect_error(
                kind,
                {
                    "client": {"ip": client_ip, "port": client_port},
                    "message": msg,
                    "host": None,
                    "port": None,
                },
            )
        except Exception as e:
            ctx.log.warn(
                f"ocmts jsonl exporter client_disconnected hook failed: {e}"
            )

    def _classify_tcp_error(self, msg: Optional[str]) -> str:
        if not isinstance(msg, str):
            return "other"
        low = msg.lower()
        if "name resolution" in low or "resolve" in low or "resolution" in low:
            return "name-resolution"
        if "refused" in low:
            return "server-connect-refused"
        if "timed out" in low or "timeout" in low:
            return "server-connect-timeout"
        return "other"

    def _append_connect_error(self, kind: str, payload: Dict[str, Any]) -> None:
        with self._lock:
            try:
                self._connect_error_seq += 1
                seq = self._connect_error_seq
                rec: Dict[str, Any] = {
                    "schema_version": 1,
                    "event_id": f"err_{seq:06d}",
                    "captured_at": _utc_now_iso(),
                    "cell_id": self.cell_id,
                    "run_id": self.run_id,
                    "kind": kind,
                }
                rec.update(payload)
                line = json.dumps(rec, sort_keys=True)
                os.makedirs(os.path.dirname(self.connect_errors_path), exist_ok=True)
                with open(self.connect_errors_path, "a", encoding="utf-8") as f:
                    f.write(line)
                    f.write("\n")
            except Exception as e:
                ctx.log.warn(
                    f"ocmts jsonl exporter could not append connect-error: {e}"
                )

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
