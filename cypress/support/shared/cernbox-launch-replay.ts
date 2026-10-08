/// <reference types="cypress" />

export type LaunchPayload = { appUrl: string; accessToken: string; hubOrigin: string };
export type ReplayHop = { url: string; method: "GET" | "POST"; body?: Record<string, string> };
export type ReplayResponse = { status: number; headers: Record<string, unknown>; body: unknown };

function reject(): never {
  throw new Error("Invalid CERNBox webapp launch handoff");
}

function checkedUrl(raw: string, base?: string): URL {
  try {
    const url = base ? new URL(raw, base) : new URL(raw);
    if (url.protocol !== "https:" || url.username || url.password ||
        url.searchParams.has("access_token") || url.searchParams.has("token")) reject();
    return url;
  } catch { return reject(); }
}

export function readCernboxLaunchPayload(body: unknown): LaunchPayload {
  let value: any;
  try { value = typeof body === "string" ? JSON.parse(body) : body; } catch { return reject(); }
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      typeof value.app_url !== "string" || typeof value.access_token !== "string" ||
      value.access_token.trim() === "") reject();
  const url = checkedUrl(value.app_url);
  if (url.pathname !== "/services/ocm/open" || url.hash) reject();
  return { appUrl: url.href, accessToken: value.access_token, hubOrigin: url.origin };
}

export function verifyLaunchForm(form: HTMLFormElement, payload: LaunchPayload, windowName: string): void {
  const inputs = Array.from(form.querySelectorAll<HTMLInputElement>('input[name="access_token"]'));
  if (form.method.toUpperCase() !== "POST" ||
      form.action !== payload.appUrl ||
      !/^ocm-remote-\d+$/.test(form.target) || form.target !== windowName ||
      inputs.length !== 1 || inputs[0].type !== "hidden" ||
      inputs[0].value !== payload.accessToken ||
      form.querySelectorAll("input").length !== 1) reject();
}

export function nextReplayHop(
  hop: ReplayHop,
  response: ReplayResponse,
  hubOrigin: string,
  parseHtml: (html: string) => Document,
): { hop: ReplayHop } | { labUrl: string } {
  const current = checkedUrl(hop.url);
  if (current.origin !== hubOrigin) reject();
  const status = response.status;
  if ([301, 302, 303, 307, 308].includes(status)) {
    const location = response.headers.location ?? response.headers.Location;
    if (typeof location !== "string") reject();
    const target = checkedUrl(location, hop.url);
    if (target.origin !== hubOrigin) reject();
    const preservePost = [307, 308].includes(status) && hop.method === "POST";
    return { hop: { url: target.href, method: preservePost ? "POST" : "GET",
      ...(preservePost ? { body: hop.body } : {}) } };
  }
  if (status !== 200 || typeof response.body !== "string") reject();
  if (hop.method === "GET" && /^\/user\/[^/]+\/(?:[^/]+\/)?lab(?:\/.*)?$/.test(current.pathname)) {
    if (!/jupyter-config-data|jupyterlab|jp-LabShell/.test(response.body)) reject();
    return { labUrl: current.origin + current.pathname };
  }
  const document = parseHtml(response.body);
  const forms = Array.from(document.querySelectorAll<HTMLFormElement>("form"));
  const candidates = forms.filter((form) => {
    const rawAction = form.getAttribute("action");
    if (!rawAction) return false;
    try {
      const url = checkedUrl(rawAction, hop.url);
      return url.origin === hubOrigin && url.pathname === "/hub/ocm-login";
    } catch { return false; }
  });
  if (candidates.length === 1 && forms.length === 1) {
    const form = candidates[0];
    if ((form.getAttribute("method") || "GET").toUpperCase() !== "POST") reject();
    const fields: Record<string, string> = {};
    for (const input of Array.from(form.querySelectorAll<HTMLInputElement>("input"))) {
      if (!input.name || input.type !== "hidden" || input.disabled || input.name in fields) reject();
      fields[input.name] = input.value;
    }
    if (typeof fields.access_token !== "string" || fields.access_token.trim() === "") reject();
    const target = checkedUrl(form.getAttribute("action")!, hop.url);
    return { hop: { url: target.href, method: "POST", body: fields } };
  }
  const replace = response.body.match(/(?:window\.)?location\.replace\(\s*(["'])(.*?)\1\s*\)/);
  if (replace?.[2] && forms.length === 0) {
    const decoded = replace[2].replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#39;/g, "'");
    const target = checkedUrl(decoded, hop.url);
    if (target.origin !== hubOrigin) reject();
    return { hop: { url: target.href, method: "GET" } };
  }
  return reject();
}

export function replayCernboxLaunch(
  payload: LaunchPayload,
  parseHtml: (html: string) => Document,
): Cypress.Chainable<{ hubOrigin: string; labUrl: string }> {
  const deadline = Date.now() + 90000;
  const redactedFailure = () => { throw new Error("CERNBox webapp launch replay failed"); };
  Cypress.once("fail", redactedFailure);

  function request(hop: ReplayHop, count: number): Cypress.Chainable<{ hubOrigin: string; labUrl: string }> {
    if (count >= 12 || Date.now() >= deadline) reject();
    return cy.request({
      method: hop.method, url: hop.url, body: hop.body,
      form: hop.method === "POST",
      followRedirect: false,
      failOnStatusCode: false,
      retryOnNetworkFailure: false,
      log: false,
      timeout: Math.max(1, Math.min(15000, deadline - Date.now())),
    }).then((response) => {
      const next = nextReplayHop(hop, response, payload.hubOrigin, parseHtml);
      if ("hop" in next) return request(next.hop, count + 1);
      const contentsUrl = next.labUrl.replace(/\/lab(?:\/.*)?$/, "/api/contents");
      if (Date.now() >= deadline) reject();
      return cy.request({
        method: "GET", url: contentsUrl, followRedirect: false,
        failOnStatusCode: false, retryOnNetworkFailure: false, log: false,
        timeout: Math.max(1, Math.min(15000, deadline - Date.now())),
      }).then((contents) => {
        const value = contents.body as { content?: Array<{ name?: string }> };
        const notebookPresent = contents.status === 200 && Array.isArray(value?.content) &&
          value.content.some((entry) => typeof entry.name === "string" && /\.ipynb$/i.test(entry.name));
        if (!notebookPresent) reject();
        return cy.getAllCookies({ log: false }).then((cookies) => {
          const hostname = new URL(payload.hubOrigin).hostname;
          const hubCookiePresent = cookies.some((cookie) =>
            cookie.domain.replace(/^\./, "") === hostname && cookie.secure);
          if (!hubCookiePresent) reject();
          Cypress.off("fail", redactedFailure);
          return cy.wrap({ hubOrigin: payload.hubOrigin, labUrl: next.labUrl }, { log: false });
        });
      });
    });
  }

  return request({ url: payload.appUrl, method: "POST", body: { access_token: payload.accessToken } }, 0);
}
