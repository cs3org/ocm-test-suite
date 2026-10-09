import { describe, expect, test } from "bun:test";
import { readCernboxLaunchPayload, verifyLaunchForm, nextReplayHop } from "./cernbox-launch-replay";

const secret = "SYNTHETIC-LAUNCH-SECRET";
const payload = readCernboxLaunchPayload({
  app_url: "https://jupyterhub1.docker/services/ocm/open", access_token: secret,
});
const post = { url: payload.appUrl, method: "POST" as const, body: { access_token: secret } };
function form(attributes: Record<string, string>, fields: Array<Record<string, any>>) {
  return {
    getAttribute: (name: string) => attributes[name] ?? null,
    querySelectorAll: () => fields,
  } as unknown as HTMLFormElement;
}
function documentWith(forms: HTMLFormElement[]) {
  return { querySelectorAll: () => forms } as unknown as Document;
}
const noForms = () => documentWith([]);

describe("launch payload", () => {
  test("object and JSON preserve the token only in the payload", () => {
    expect(readCernboxLaunchPayload(JSON.stringify({ app_url: payload.appUrl, access_token: secret }))).toEqual(payload);
  });
  test("rejects every malformed shape, URL scheme, credentials and token query", () => {
    for (const value of [
      undefined, null, [], {}, "not JSON",
      { app_url: payload.appUrl, access_token: "" },
      { app_url: payload.appUrl, access_token: " " },
      { app_url: payload.appUrl, access_token: 4 },
      { app_url: "javascript:alert(1)", access_token: secret },
      { app_url: "http://jupyterhub1.docker/services/ocm/open", access_token: secret },
      { app_url: "https://user:pass@jupyterhub1.docker/services/ocm/open", access_token: secret },
      { app_url: payload.appUrl + "?access_token=" + secret, access_token: secret },
      { app_url: payload.appUrl + "/share-id", access_token: secret },
    ]) {
      try { readCernboxLaunchPayload(value); throw new Error("accepted"); }
      catch (error) {
        expect((error as Error).message).toBe("Invalid CERNBox webapp launch handoff");
        expect((error as Error).message).not.toContain(secret);
      }
    }
  });
});
describe("native form is verified before being stubbed", () => {
  const input = { name: "access_token", type: "hidden", value: secret };
  function submitted(overrides: any = {}) {
    return {
      method: "post", action: payload.appUrl, target: "ocm-remote-123",
      querySelectorAll: () => [input], ...overrides,
    } as unknown as HTMLFormElement;
  }
  test("exact method, URL, named window and hidden body pass", () => {
    expect(() => verifyLaunchForm(submitted(), payload, "ocm-remote-123")).not.toThrow();
  });
  test("wrong target, action, method or token fails without a secret echo", () => {
    for (const value of [
      submitted({ target: "_self" }), submitted({ action: payload.appUrl + "/share-id" }),
      submitted({ method: "get" }),
      submitted({ querySelectorAll: () => [{ ...input, value: "wrong" }] }),
      submitted({ querySelectorAll: () => [{ ...input, type: "text" }] }),
      submitted({ querySelectorAll: () => [] }),
      submitted({ querySelectorAll: () => [input, input] }),
    ]) {
      expect(() => verifyLaunchForm(value, payload, "ocm-remote-123")).toThrow("Invalid CERNBox webapp launch handoff");
    }
  });
});
describe("request replay handoff", () => {
  test("HTTP 200 auto-submit becomes a POST with every hidden field", () => {
    const html = '<form method="POST" action="/hub/ocm-login"></form>';
    const parsed = () => documentWith([form({ method: "POST", action: "/hub/ocm-login" }, [
      { name: "access_token", type: "hidden", value: secret, disabled: false },
      { name: "next", type: "hidden", value: "/user/demo/share-1/lab", disabled: false },
    ])]);
    expect(nextReplayHop(post, { status: 200, headers: {}, body: html }, payload.hubOrigin, parsed)).toEqual({
      hop: { url: payload.hubOrigin + "/hub/ocm-login", method: "POST",
        body: { access_token: secret, next: "/user/demo/share-1/lab" } },
    });
  });
  test("302/303 drop the POST body; 307/308 retain it", () => {
    for (const status of [302, 303, 307, 308]) {
      const result = nextReplayHop(post, {
        status, headers: { location: "/hub/ocm-login" }, body: "",
      }, payload.hubOrigin, noForms) as { hop: any };
      expect(result.hop.method).toBe(status >= 307 ? "POST" : "GET");
      expect(result.hop.body).toEqual(status >= 307 ? post.body : undefined);
    }
  });
  test("unnamed and named server Lab URLs are terminal and query-free", () => {
    for (const suffix of ["/user/demo/lab", "/user/demo/share-1/lab"]) {
      expect(nextReplayHop({ url: payload.hubOrigin + suffix + "?workspace=one", method: "GET" }, {
        status: 200, headers: {}, body: '<script id="jupyter-config-data"></script>',
      }, payload.hubOrigin, noForms)).toEqual({ labUrl: payload.hubOrigin + suffix });
    }
  });
  test("location.replace is decoded without executing HTML or JavaScript", () => {
    expect(nextReplayHop(post, { status: 200, headers: {}, body:
      '<script>window.location.replace("/user/demo/share-1/lab?one=1&amp;two=2")</script>',
    }, payload.hubOrigin, noForms)).toEqual({
      hop: { method: "GET", url: payload.hubOrigin + "/user/demo/share-1/lab?one=1&two=2" },
    });
  });
  test("external redirect, login HTML, unexpected status and duplicate fields fail closed", () => {
    for (const response of [
      { status: 302, headers: { location: "https://attacker.test/?access_token=" + secret }, body: "" },
      { status: 302, headers: { location: "https://other.test/lab" }, body: "" },
      { status: 401, headers: {}, body: secret },
      { status: 200, headers: {}, body: "<html>login</html>" },
    ]) {
      expect(() => nextReplayHop(post, response, payload.hubOrigin, noForms)).toThrow("Invalid CERNBox webapp launch handoff");
    }
    const duplicate = () => documentWith([form({ method: "POST", action: "/hub/ocm-login" }, [
      { name: "access_token", type: "hidden", value: secret },
      { name: "access_token", type: "hidden", value: secret },
    ])]);
    expect(() => nextReplayHop(post, { status: 200, headers: {}, body: "form" }, payload.hubOrigin, duplicate))
      .toThrow("Invalid CERNBox webapp launch handoff");
  });
});
