import { afterEach, expect, test } from "bun:test";
import { replayCernboxLaunch } from "./cernbox-launch-replay";
const globals = globalThis as any;
const priorCy = globals.cy;
const priorCypress = globals.Cypress;
afterEach(() => { globals.cy = priorCy; globals.Cypress = priorCypress; });

function driver(responses: any[], cookie = true) {
  const requests: any[] = [];
  const listeners = new Map<string, any>();
  globals.Cypress = {
    once: (name: string, handler: any) => listeners.set(name, handler),
    off: (name: string) => listeners.delete(name),
  };
  globals.cy = {
    request: (options: any) => {
      requests.push(options);
      const response = responses.shift();
      return Promise.resolve(response);
    },
    getAllCookies: () => Promise.resolve(cookie ? [{ domain: "hub.test", secure: true }] : []),
    wrap: (value: any) => Promise.resolve(value),
  };
  return { requests, listeners };
}
const payload = { appUrl: "https://hub.test/services/ocm/open", hubOrigin: "https://hub.test", accessToken: "SYNTHETIC-TOKEN" };
const emptyDocument = () => ({ querySelectorAll: () => [] } as unknown as Document);
test("real POST, cookie-only contents proof and secret-free artifact", async () => {
  const state = driver([
    { status: 303, headers: { location: "/user/demo/share-1/lab" }, body: "" },
    { status: 200, headers: {}, body: "jupyterlab" },
    { status: 200, headers: {}, body: { content: [{ name: "notebook.ipynb" }] } },
  ]);
  const result = await (replayCernboxLaunch(payload, emptyDocument) as any);
  expect(result).toEqual({ hubOrigin: payload.hubOrigin, labUrl: "https://hub.test/user/demo/share-1/lab" });
  expect(JSON.stringify(result)).not.toContain(payload.accessToken);
  expect(state.requests[0].body).toEqual({ access_token: payload.accessToken });
  expect(state.requests[0].form).toBe(true);
  expect(state.requests[0].followRedirect).toBe(false);
  expect(state.requests.every((request) => request.log === false)).toBe(true);
  expect(state.requests[1].body).toBeUndefined();
  expect(state.requests[2].url).toBe("https://hub.test/user/demo/share-1/api/contents");
  expect(state.requests[2].headers).toBeUndefined();
  expect(state.listeners.size).toBe(0);
});
test("missing cookie or unauthorized contents cannot become success", async () => {
  for (const cookie of [true, false]) {
    const state = driver([
      { status: 303, headers: { location: "/user/demo/share-1/lab" }, body: "" },
      { status: 200, headers: {}, body: "jupyterlab" },
      { status: cookie ? 403 : 200, headers: {}, body: { content: [{ name: "notebook.ipynb" }] } },
    ], cookie);
    await expect(replayCernboxLaunch(payload, emptyDocument) as any).rejects.toThrow("Invalid CERNBox webapp launch handoff");
    expect(state.listeners.has("fail")).toBe(true);
    expect(() => state.listeners.get("fail")({ message: payload.accessToken }))
      .toThrow("CERNBox webapp launch replay failed");
  }
});
test("redirect cycle stops at 12 requests", async () => {
  const state = driver(Array.from({ length: 12 }, () => ({
    status: 302, headers: { location: "/hub/cycle" }, body: "",
  })));
  await expect(replayCernboxLaunch(payload, emptyDocument) as any).rejects.toThrow("Invalid CERNBox webapp launch handoff");
  expect(state.requests).toHaveLength(12);
});
