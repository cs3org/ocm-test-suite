// Sidecar tests for webapp-share receiver resolution and adapter-owned MITM expectations.
//
// Run:
//   bun test scripts/typescript/webapp-share-resolver.test.ts

import { describe, expect, test } from "bun:test";
import { resolveWebappShareFlowReceiverAdapter } from "../../cypress/support/adapters/registry";

describe("resolveWebappShareFlowReceiverAdapter", () => {
  test("nextcloud/v35 receiver resolves with empty mitmLaunchExpectations", () => {
    const adapter = resolveWebappShareFlowReceiverAdapter({
      platform: "nextcloud",
      versionLine: "v35",
    });
    expect(adapter.mitmLaunchExpectations).toEqual([]);
    expect(adapter.mitmLaunchExpectations).toHaveLength(0);
  });

  test("cernbox/v11 receiver resolves with empty mitmLaunchExpectations", () => {
    const adapter = resolveWebappShareFlowReceiverAdapter({
      platform: "cernbox",
      versionLine: "v11",
    });
    expect(adapter.mitmLaunchExpectations).toEqual([]);
    expect(adapter.mitmLaunchExpectations).toHaveLength(0);
  });

  test("unknown platform throws", () => {
    expect(() =>
      resolveWebappShareFlowReceiverAdapter({
        platform: "unknown",
        versionLine: "v1",
      }),
    ).toThrow(/Unknown platform/);
  });

  test("unknown version throws", () => {
    expect(() =>
      resolveWebappShareFlowReceiverAdapter({
        platform: "nextcloud",
        versionLine: "v99",
      }),
    ).toThrow(/Unknown version/);
  });
});
