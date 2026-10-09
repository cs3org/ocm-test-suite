import { afterEach, expect, test } from "bun:test";
import { createRequire } from "node:module";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
const require = createRequire(import.meta.url);
const { createLaunchProbe, safeUrl } = require("../../cypress.config.launch-probe.cjs");
const dirs: string[] = [];
const probes: any[] = [];
afterEach(() => {
  for (const probe of probes.splice(0)) probe.stop();
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});
test("URL evidence strips query, fragment and opaque schemes", () => {
  expect(safeUrl("https://hub.test/lab?access_token=SYNTHETIC-SECRET#code")).toBe("https://hub.test/lab");
  expect(safeUrl("data:text/plain,SYNTHETIC-SECRET")).toBe("");
  expect(safeUrl("not a URL")).toBe("");
});

class Socket extends EventTarget {
  closed = false;
  constructor(_url: string) {
    super();
    queueMicrotask(() => this.dispatchEvent(new Event("open")));
  }
  emit(payload: any) {
    this.dispatchEvent(new MessageEvent("message", { data: JSON.stringify(payload) }));
  }
  send(raw: string) {
    const message = JSON.parse(raw);
    queueMicrotask(() => {
      this.emit({ id: message.id, result: message.method === "Runtime.evaluate" ? {
        result: { value: {
          readyState: "complete",
          href: "https://hub.test/user/demo/lab?code=SYNTHETIC-SECRET",
          completed: [],
        } },
      } : {} });
      if (message.method === "Target.setAutoAttach" && !message.sessionId) {
        this.emit({ method: "Target.attachedToTarget", params: {
          sessionId: "page-1", targetInfo: { type: "page", url: "https://hub.test/lab" },
        } });
      }
      if (message.method === "Runtime.enable") {
        this.emit({ sessionId: "page-1", method: "Page.frameNavigated", params: {
          frame: { id: "aut", parentId: "runner", url: "https://hub.test/user/demo/lab?code=SYNTHETIC-SECRET" },
        } });
        this.emit({ sessionId: "page-1", method: "Runtime.executionContextCreated", params: {
          context: { id: 2, origin: "https://hub.test", auxData: { isDefault: true, frameId: "aut" } },
        } });
        this.emit({ sessionId: "page-1", method: "Network.requestWillBeSent", params: {
          requestId: "pending-1", frameId: "aut", type: "Script",
          request: { method: "GET", url: "https://hub.test/asset.js?token=SYNTHETIC-SECRET" },
        } });
        this.emit({ sessionId: "page-1", method: "Runtime.exceptionThrown", params: {
          exceptionDetails: { exception: { className: "TypeError", description: "SYNTHETIC-SECRET" },
            url: "https://hub.test/bridge.js?token=SYNTHETIC-SECRET", lineNumber: 7, columnNumber: 9 },
        } });
      }
    });
  }
  close() { this.closed = true; }
}
test("samples independently, records pending/readyState, redacts and stops", async () => {
  const dir = mkdtempSync(join(tmpdir(), "ocmts-probe-"));
  dirs.push(dir);
  const probe = createLaunchProbe({ downloadsFolder: dir }, {
    Socket,
    fetchJson: async () => ({ webSocketDebuggerUrl: "ws://127.0.0.1:1234/devtools/browser/test" }),
  });
  probes.push(probe);
  probe.capturePort(["--remote-debugging-port=1234"]);
  await probe.start(1);
  await new Promise((resolve) => setTimeout(resolve, 700));
  await probe.finish();
  const raw = readFileSync(join(dir, "launch-probe-attempt-1.jsonl"), "utf8");
  expect(raw).toContain('"readyState":"complete"');
  expect(raw).toContain('"kind":"frame"');
  expect(raw).toContain('"type":"Script"');
  expect(raw).toContain('"className":"TypeError"');
  expect(raw).not.toContain("SYNTHETIC-SECRET");
  await new Promise((resolve) => setTimeout(resolve, 600));
  expect(readFileSync(join(dir, "launch-probe-attempt-1.jsonl"), "utf8")).toBe(raw);
});
test("no port and nonlocal endpoint fail with fixed messages", async () => {
  const dir = mkdtempSync(join(tmpdir(), "ocmts-probe-reject-"));
  dirs.push(dir);
  const missingPort = createLaunchProbe({ downloadsFolder: dir }, { Socket });
  probes.push(missingPort);
  await expect(missingPort.start(1)).rejects.toThrow("Launch probe could not start");
  const nonlocal = createLaunchProbe({ downloadsFolder: dir }, {
    Socket,
    fetchJson: async () => ({ webSocketDebuggerUrl: "ws://external.test/devtools/browser/test" }),
  });
  probes.push(nonlocal);
  nonlocal.capturePort(["--remote-debugging-port=1234"]);
  await expect(nonlocal.start(1)).rejects.toThrow("Launch probe could not start");
});
