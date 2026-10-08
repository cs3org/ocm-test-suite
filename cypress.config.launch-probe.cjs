const fs = require("node:fs");
const path = require("node:path");

function safeUrl(raw) {
  try {
    const url = new URL(raw);
    if (!["http:", "https:"].includes(url.protocol)) return "";
    const pathname = url.pathname.replace(
      /[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}/g,
      "[redacted]",
    );
    return url.origin + pathname;
  } catch {
    return "";
  }
}

function createLaunchProbe(config, deps = {}) {
  const fetchJson = deps.fetchJson || (async (url) => {
    const response = await fetch(url, { signal: AbortSignal.timeout(2000) });
    if (!response.ok) throw new Error("Launch probe endpoint unavailable");
    return response.json();
  });
  const Socket = deps.Socket || WebSocket;
  let port = null;
  let active = null;

  function record(run, data) {
    if (run.stopped) return;
    fs.appendFileSync(run.file, JSON.stringify({ at: Date.now(), ...data }) + "\n");
  }

  function stop() {
    const run = active;
    if (!run) return null;
    record(run, { kind: "stop" });
    run.stopped = true;
    clearInterval(run.timer);
    clearTimeout(run.deadline);
    for (const entry of run.commands.values()) {
      clearTimeout(entry.timer);
      entry.reject(new Error("Launch probe stopped"));
    }
    run.commands.clear();
    run.socket?.close();
    active = null;
    return null;
  }

  async function start(attempt) {
    stop();
    if (!Number.isInteger(attempt) || attempt < 1 || attempt > 3 || !port) {
      throw new Error("Launch probe requires Chrome debugging port and attempt 1-3");
    }
    fs.mkdirSync(config.downloadsFolder, { recursive: true });
    const file = path.join(config.downloadsFolder, "launch-probe-attempt-" + attempt + ".jsonl");
    const run = {
      file, stopped: false, next: 0, commands: new Map(), sessions: new Map(),
      socket: null, timer: null, deadline: null, sampling: false,
    };
    active = run;
    record(run, { kind: "start", attempt });
    const info = await fetchJson("http://127.0.0.1:" + port + "/json/version");
    const wsUrl = new URL(info.webSocketDebuggerUrl);
    if (!["127.0.0.1", "localhost"].includes(wsUrl.hostname) || wsUrl.protocol !== "ws:") {
      stop();
      throw new Error("Launch probe endpoint is not local");
    }
    const socket = new Socket(wsUrl.href);
    run.socket = socket;
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("Launch probe connection timed out")), 2000);
      socket.addEventListener("open", () => { clearTimeout(timeout); resolve(); }, { once: true });
      socket.addEventListener("error", () => { clearTimeout(timeout); reject(new Error("Launch probe connection failed")); }, { once: true });
    });

    function send(method, params = {}, sessionId) {
      return new Promise((resolve, reject) => {
        if (run.stopped) return reject(new Error("Launch probe stopped"));
        const id = ++run.next;
        const timer = setTimeout(() => {
          run.commands.delete(id);
          reject(new Error("Launch probe command timed out"));
        }, 2000);
        run.commands.set(id, { resolve, reject, timer });
        socket.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
      });
    }

    socket.addEventListener("message", (event) => {
      if (run.stopped) return;
      let message;
      try { message = JSON.parse(String(event.data)); } catch { return; }
      if (message.id) {
        const entry = run.commands.get(message.id);
        if (!entry) return;
        clearTimeout(entry.timer);
        run.commands.delete(message.id);
        if (message.error) entry.reject(new Error("Launch probe command rejected"));
        else entry.resolve(message.result || {});
        return;
      }
      const params = message.params || {};
      if (message.method === "Target.attachedToTarget") {
        if (!["page", "iframe"].includes(params.targetInfo?.type)) return;
        const session = { contexts: new Map(), pending: new Map() };
        run.sessions.set(params.sessionId, session);
        record(run, { kind: "target", url: safeUrl(params.targetInfo.url), type: params.targetInfo.type });
        Promise.all([
          send("Page.enable", {}, params.sessionId),
          send("Network.enable", {}, params.sessionId),
          send("Runtime.enable", {}, params.sessionId),
          send("Page.setLifecycleEventsEnabled", { enabled: true }, params.sessionId),
          send("Target.setAutoAttach", { autoAttach: true, waitForDebuggerOnStart: false, flatten: true }, params.sessionId),
        ]).catch(() => record(run, { kind: "session-unavailable" }));
        return;
      }
      if (message.method === "Target.detachedFromTarget") {
        run.sessions.delete(params.sessionId);
        record(run, { kind: "target-detached" });
        return;
      }
      const session = run.sessions.get(message.sessionId);
      if (!session) return;
      switch (message.method) {
        case "Runtime.executionContextCreated": {
          const context = params.context;
          if (context?.auxData?.isDefault && /^https?:/.test(context.origin)) {
            session.contexts.set(context.id, { frame: context.auxData.frameId, origin: safeUrl(context.origin) });
          }
          break;
        }
        case "Runtime.executionContextDestroyed":
          session.contexts.delete(params.executionContextId);
          break;
        case "Runtime.executionContextsCleared":
          session.contexts.clear();
          break;
        case "Network.requestWillBeSent":
          if (session.pending.size < 256 || session.pending.has(params.requestId)) {
            session.pending.set(params.requestId, {
              id: params.requestId, frame: params.frameId, type: params.type,
              method: params.request?.method, url: safeUrl(params.request?.url), since: Date.now(),
            });
          }
          break;
        case "Network.responseReceived":
          record(run, {
            kind: "response", frame: params.frameId, type: params.type,
            url: safeUrl(params.response?.url), status: params.response?.status,
            diskCache: Boolean(params.response?.fromDiskCache),
            serviceWorker: Boolean(params.response?.fromServiceWorker),
          });
          break;
        case "Network.requestServedFromCache":
          record(run, { kind: "cache", id: params.requestId });
          break;
        case "Network.loadingFinished":
        case "Network.loadingFailed":
          session.pending.delete(params.requestId);
          record(run, { kind: message.method, id: params.requestId, canceled: Boolean(params.canceled) });
          break;
        case "Page.frameNavigated":
          record(run, { kind: "frame", frame: params.frame?.id,
            parent: params.frame?.parentId, url: safeUrl(params.frame?.url) });
          break;
        case "Page.frameDetached":
          record(run, { kind: "frame-detached", frame: params.frameId });
          break;
        case "Page.lifecycleEvent":
          record(run, { kind: "lifecycle", frame: params.frameId, name: params.name });
          break;
        case "Runtime.exceptionThrown": {
          const details = params.exceptionDetails || {};
          record(run, {
            kind: "exception", className: details.exception?.className || "Error",
            source: safeUrl(details.url), line: details.lineNumber, column: details.columnNumber,
          });
          break;
        }
      }
    });

    await send("Target.setAutoAttach", { autoAttach: true, waitForDebuggerOnStart: false, flatten: true });
    run.sample = async () => {
      if (run.stopped || run.sampling) return;
      run.sampling = true;
      try {
        for (const [sessionId, session] of run.sessions) {
          record(run, { kind: "pending", requests: [...session.pending.values()].map((item) => ({
            ...item, ageMs: Date.now() - item.since,
          })) });
          for (const [contextId, context] of session.contexts) {
            try {
              const result = await send("Runtime.evaluate", {
                contextId,
                expression: "({readyState:document.readyState,href:location.href,completed:performance.getEntriesByType('resource').map(r=>({url:r.name,duration:r.duration,initiator:r.initiatorType}))})",
                returnByValue: true,
              }, sessionId);
              const value = result.result?.value;
              if (value) record(run, {
                kind: "document", frame: context.frame, origin: context.origin,
                readyState: value.readyState, url: safeUrl(value.href),
                completed: (value.completed || []).slice(-50).map((item) => ({
                  url: safeUrl(item.url), duration: item.duration, initiator: item.initiator,
                })),
              });
            } catch {
              record(run, { kind: "context-replaced", frame: context.frame });
            }
          }
        }
      } finally { run.sampling = false; }
    };
    run.timer = setInterval(run.sample, 500);
    run.deadline = setTimeout(stop, 300000);
    return null;
  }

  return {
    capturePort(args) {
      const entry = args.find((arg) => /^--remote-debugging-port=\d+$/.test(arg));
      port = entry ? Number(entry.split("=")[1]) : null;
    },
    start: async (attempt) => {
      try { return await start(attempt); } catch {
        stop();
        throw new Error("Launch probe could not start");
      }
    },
    finish: async () => {
      const run = active;
      if (run && !run.stopped) {
        for (let i = 0; i < 25 && run.sampling; i += 1) {
          await new Promise((resolve) => setTimeout(resolve, 100));
        }
        await run.sample();
      }
      return stop();
    },
    stop,
  };
}

module.exports = { createLaunchProbe, safeUrl };
