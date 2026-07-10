import { describe, expect, test } from "bun:test";
import {
  assertHubLaunchOrigin,
  extractHubLaunchOriginFromOpenInApp,
  extractHubLaunchOriginFromRedirectHtml,
} from "./webapp-share-launch-artifact";

const formActionHtml = `<!DOCTYPE html>
<html>
<body>
<form id="ocm-launch" method="POST" action="https://jupyterhub1.docker/hub/ocm-login" target="_self" enctype="application/x-www-form-urlencoded">
  <input type="hidden" name="access_token" value="token">
  <input type="hidden" name="expired_session_redirect_uri" value="https://nextcloud2.docker/apps/ocmremotewebapp/">
</form>
<script nonce="abc">document.getElementById('ocm-launch').submit();</script>
</body>
</html>`;

describe("extractHubLaunchOriginFromRedirectHtml", () => {
  test("extracts hub origin from form action HTML", () => {
    expect(extractHubLaunchOriginFromRedirectHtml(formActionHtml)).toBe(
      "https://jupyterhub1.docker",
    );
  });

  test("decodes HTML entities in form action URLs", () => {
    const html = formActionHtml.replace(
      'action="https://jupyterhub1.docker/hub/ocm-login"',
      'action="https://jupyterhub1.docker/hub/ocm-login?next=%2Flab&amp;foo=bar"',
    );
    expect(extractHubLaunchOriginFromRedirectHtml(html)).toBe(
      "https://jupyterhub1.docker",
    );
  });

  test("extracts hub origin from window.location.replace branch", () => {
    const html =
      '<script>window.location.replace("https://jupyterhub1.docker/user/alice/lab");</script>';
    expect(extractHubLaunchOriginFromRedirectHtml(html)).toBe(
      "https://jupyterhub1.docker",
    );
  });

  test("returns null for garbage or missing URLs", () => {
    expect(extractHubLaunchOriginFromRedirectHtml("<html></html>")).toBeNull();
    expect(extractHubLaunchOriginFromRedirectHtml("not html at all")).toBeNull();
    expect(
      extractHubLaunchOriginFromRedirectHtml(
        '<form action="ftp://jupyterhub1.docker/hub/ocm-login"></form>',
      ),
    ).toBeNull();
  });
});

describe("extractHubLaunchOriginFromOpenInApp", () => {
  test("extracts hub origin from an object app_url", () => {
    expect(
      extractHubLaunchOriginFromOpenInApp({
        app_url: "https://jupyterhub1.docker/services/ocm/open",
        access_token: "token",
      }),
    ).toBe("https://jupyterhub1.docker");
  });

  test("extracts hub origin from a stringified JSON body", () => {
    expect(
      extractHubLaunchOriginFromOpenInApp(
        JSON.stringify({ app_url: "https://jupyterhub1.docker/hub/ocm-login" }),
      ),
    ).toBe("https://jupyterhub1.docker");
  });

  test("returns null for missing, malformed, or non-http(s) app_url", () => {
    expect(extractHubLaunchOriginFromOpenInApp(null)).toBeNull();
    expect(extractHubLaunchOriginFromOpenInApp({})).toBeNull();
    expect(extractHubLaunchOriginFromOpenInApp("not json")).toBeNull();
    expect(
      extractHubLaunchOriginFromOpenInApp({ app_url: "ftp://jupyterhub1.docker" }),
    ).toBeNull();
  });
});

describe("assertHubLaunchOrigin", () => {
  test("throws on null or empty hub origin", () => {
    expect(() => assertHubLaunchOrigin(null)).toThrow(
      /absolute hub origin extracted from the ocm\/open launch HTML/i,
    );
    expect(() => assertHubLaunchOrigin("")).toThrow(
      /absolute hub origin extracted from the ocm\/open launch HTML/i,
    );
  });

  test("throws on non-http(s) origins", () => {
    expect(() => assertHubLaunchOrigin("not-a-url")).toThrow(
      /absolute http\(s\) hub origin/i,
    );
    expect(() => assertHubLaunchOrigin("ftp://jupyterhub1.docker")).toThrow(
      /absolute http\(s\) hub origin/i,
    );
  });

  test("throws when hub origin equals receiver origin", () => {
    expect(() =>
      assertHubLaunchOrigin(
        "https://nextcloud2.docker",
        "https://nextcloud2.docker",
      ),
    ).toThrow(/distinct remote hub origin/i);
  });

  test("passes on a valid distinct hub origin", () => {
    expect(() =>
      assertHubLaunchOrigin(
        "https://jupyterhub1.docker",
        "https://nextcloud2.docker",
      ),
    ).not.toThrow();
  });
});
