import { describe, expect, test } from "bun:test";
import {
  resolveContactTokenCaseLoginBindings,
  resolveContactTokenLoginBinding,
} from "../../cypress/e2e/contact-token/cases";

describe("resolveContactTokenLoginBinding", () => {
  test("cernbox v11 sender slot binds to cernbox-v11 sender login adapter", () => {
    const binding = resolveContactTokenLoginBinding(
      { platform: "cernbox", versionLine: "v11" },
      "sender",
    );
    expect(binding).toEqual({ kind: "cernbox-v11", slot: "sender" });
  });

  test("cernbox v11 receiver slot binds to cernbox-v11 receiver login adapter", () => {
    const binding = resolveContactTokenLoginBinding(
      { platform: "cernbox", versionLine: "v11" },
      "receiver",
    );
    expect(binding).toEqual({ kind: "cernbox-v11", slot: "receiver" });
  });

  test("non-cernbox platforms use registry login adapter routing", () => {
    const binding = resolveContactTokenLoginBinding(
      { platform: "nextcloud", versionLine: "v34" },
      "sender",
    );
    expect(binding).toEqual({ kind: "registry" });
  });
});

describe("resolveContactTokenCaseLoginBindings", () => {
  test("cernbox v11 contact-token case binds sender and receiver to distinct slots", () => {
    const bindings = resolveContactTokenCaseLoginBindings(
      { platform: "cernbox", versionLine: "v11" },
      { platform: "cernbox", versionLine: "v11" },
    );
    expect(bindings).toEqual({
      sender: { kind: "cernbox-v11", slot: "sender" },
      receiver: { kind: "cernbox-v11", slot: "receiver" },
    });
  });
});
