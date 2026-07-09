import { describe, expect, test } from "bun:test";
import type { MitmTrafficRecord } from "../../cypress/support/shared/mitm-traffic";
import {
  isNextcloudOutboundOcmHandoff,
  NEXTCLOUD_WEBAPP_SHARE_LAUNCH_EXPECTATIONS,
  resolveWebappShareLaunchExpectations,
} from "../../cypress/support/shared/webapp-share-launch-oracle";

function makeRecord(overrides: {
  method?: string;
  path?: string;
  url?: string;
  preview?: string;
}): MitmTrafficRecord {
  return {
    request: {
      method: overrides.method ?? "POST",
      path: overrides.path ?? "",
      url: overrides.url ?? "",
    },
    response:
      overrides.preview === undefined
        ? undefined
        : { body: { preview: overrides.preview } },
  };
}

describe("isNextcloudOutboundOcmHandoff", () => {
  test("accepts POST /hub/ocm-login", () => {
    const record = makeRecord({
      method: "POST",
      path: "/hub/ocm-login",
    });
    expect(isNextcloudOutboundOcmHandoff(record)).toBe(true);
  });

  test("accepts POST /services/ocm/open", () => {
    const record = makeRecord({
      method: "POST",
      path: "/services/ocm/open",
    });
    expect(isNextcloudOutboundOcmHandoff(record)).toBe(true);
  });

  test("accepts OCM-scoped POST whose response preview contains access_token", () => {
    const record = makeRecord({
      method: "POST",
      path: "/apps/ocm/api/token",
      url: "https://nextcloud.example.test/apps/ocm/api/token",
      preview: '{"access_token":"eyJhbGciOiJIUzI1NiJ9"}',
    });
    expect(isNextcloudOutboundOcmHandoff(record)).toBe(true);
  });

  test("rejects unrelated OAuth/token POSTs that contain access_token but are not OCM-scoped", () => {
    const record = makeRecord({
      method: "POST",
      path: "/index.php/apps/oauth2/api/v1/token",
      url: "https://nextcloud.example.test/index.php/apps/oauth2/api/v1/token",
      preview: '{"access_token":"opaque-oauth-token"}',
    });
    expect(isNextcloudOutboundOcmHandoff(record)).toBe(false);
  });

  test("rejects non-POST traffic", () => {
    for (const method of ["GET", "PUT", "DELETE"] as const) {
      const record = makeRecord({
        method,
        path: "/hub/ocm-login",
      });
      expect(isNextcloudOutboundOcmHandoff(record)).toBe(false);
    }
  });
});

describe("resolveWebappShareLaunchExpectations", () => {
  test('nextcloud/v35 returns Nextcloud expectations with redirect-target GET predicate', () => {
    const expectations = resolveWebappShareLaunchExpectations("nextcloud/v35");
    expect(expectations).toBe(NEXTCLOUD_WEBAPP_SHARE_LAUNCH_EXPECTATIONS);
    expect(expectations).toHaveLength(2);

    const redirectTarget = expectations[0];
    expect(redirectTarget.label).toBe(
      "GET /apps/ocmremotewebapp/ocm/open (redirect target)",
    );

    const redirectRecord = makeRecord({
      method: "GET",
      path: "/apps/ocmremotewebapp/ocm/open",
      url: "https://nextcloud.example.test/apps/ocmremotewebapp/ocm/open?target=redirect",
    });
    expect(redirectTarget.predicate(redirectRecord)).toBe(true);

    const nonRedirectRecord = makeRecord({
      method: "GET",
      path: "/apps/ocmremotewebapp/ocm/open",
      url: "https://nextcloud.example.test/apps/ocmremotewebapp/ocm/open",
    });
    expect(redirectTarget.predicate(nonRedirectRecord)).toBe(false);

    const outboundHandoff = expectations[1];
    expect(outboundHandoff.label).toBe(
      "POST outbound OCM handoff (hub/services path or OCM-scoped access_token)",
    );
    expect(outboundHandoff.predicate).toBe(isNextcloudOutboundOcmHandoff);
  });
});
