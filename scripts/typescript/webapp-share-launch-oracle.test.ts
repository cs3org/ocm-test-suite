import { describe, expect, test } from "bun:test";
import {
  CERNBOX_WEBAPP_SHARE_MITM_LAUNCH_EXPECTATIONS,
  NEXTCLOUD_WEBAPP_SHARE_MITM_LAUNCH_EXPECTATIONS,
  resolveWebappShareMitmLaunchExpectations,
} from "../../cypress/support/shared/webapp-share-launch-oracle";

describe("resolveWebappShareMitmLaunchExpectations", () => {
  test("nextcloud/v35 returns empty Nextcloud expectations (launch gated in-browser)", () => {
    const expectations =
      resolveWebappShareMitmLaunchExpectations("nextcloud/v35");
    expect(expectations).toBe(NEXTCLOUD_WEBAPP_SHARE_MITM_LAUNCH_EXPECTATIONS);
    expect(expectations).toHaveLength(0);
  });

  test("cernbox/v11 returns empty CERNBox expectations (launch gated in-browser)", () => {
    const expectations = resolveWebappShareMitmLaunchExpectations("cernbox/v11");
    expect(expectations).toBe(CERNBOX_WEBAPP_SHARE_MITM_LAUNCH_EXPECTATIONS);
    expect(expectations).toHaveLength(0);
  });

  test("unknown adapter throws", () => {
    expect(() =>
      resolveWebappShareMitmLaunchExpectations("unknown/v1"),
    ).toThrow(/No MITM launch expectations/);
  });
});
