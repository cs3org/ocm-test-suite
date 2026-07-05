import { describe, expect, test } from "bun:test";
import { resolveCernboxIdpConfigFromExpose } from "../../cypress/support/adapters/cernbox/shared/idp-config";

describe("resolveCernboxIdpConfigFromExpose", () => {
  test("sender slot uses manual defaults when expose keys are absent", () => {
    const config = resolveCernboxIdpConfigFromExpose(() => undefined, "sender");
    expect(config).toEqual({
      idpOrigin: "https://idp1.docker",
      realm: "cernbox",
    });
  });

  test("sender slot reads configured sender IdP values", () => {
    const expose: Record<string, string> = {
      sender_idp_origin: "https://idp1.example.test",
      sender_idp_realm: "realm-a",
    };
    const config = resolveCernboxIdpConfigFromExpose(
      (key) => expose[key],
      "sender",
    );
    expect(config).toEqual({
      idpOrigin: "https://idp1.example.test",
      realm: "realm-a",
    });
  });

  test("sender slot treats empty and whitespace expose values as absent", () => {
    const expose: Record<string, string> = {
      sender_idp_origin: "   ",
      sender_idp_realm: "",
    };
    const config = resolveCernboxIdpConfigFromExpose(
      (key) => expose[key],
      "sender",
    );
    expect(config).toEqual({
      idpOrigin: "https://idp1.docker",
      realm: "cernbox",
    });
  });

  test("receiver slot uses receiver expose keys in two-party runs", () => {
    const expose: Record<string, string> = {
      sender_idp_origin: "https://idp1.example.test",
      sender_idp_realm: "realm-a",
      receiver_idp_origin: "https://idp2.example.test",
      receiver_idp_realm: "realm-b",
    };
    const config = resolveCernboxIdpConfigFromExpose(
      (key) => expose[key],
      "receiver",
    );
    expect(config).toEqual({
      idpOrigin: "https://idp2.example.test",
      realm: "realm-b",
    });
  });

  test("receiver slot falls back to sender expose keys when receiver keys are absent", () => {
    const expose: Record<string, string> = {
      sender_idp_origin: "https://idp1.example.test",
      sender_idp_realm: "realm-a",
    };
    const config = resolveCernboxIdpConfigFromExpose(
      (key) => expose[key],
      "receiver",
    );
    expect(config).toEqual({
      idpOrigin: "https://idp1.example.test",
      realm: "realm-a",
    });
  });

  test("receiver slot uses manual defaults when all expose keys are absent", () => {
    const config = resolveCernboxIdpConfigFromExpose(() => undefined, "receiver");
    expect(config).toEqual({
      idpOrigin: "https://idp1.docker",
      realm: "cernbox",
    });
  });

  test("receiver slot treats empty and whitespace receiver expose values as absent", () => {
    const expose: Record<string, string> = {
      sender_idp_origin: "https://idp1.example.test",
      sender_idp_realm: "realm-a",
      receiver_idp_origin: "",
      receiver_idp_realm: "  ",
    };
    const config = resolveCernboxIdpConfigFromExpose(
      (key) => expose[key],
      "receiver",
    );
    expect(config).toEqual({
      idpOrigin: "https://idp1.example.test",
      realm: "realm-a",
    });
  });

  test("receiver slot falls back per field when only one receiver key is configured", () => {
    const expose: Record<string, string> = {
      sender_idp_origin: "https://idp1.example.test",
      sender_idp_realm: "realm-a",
      receiver_idp_origin: "https://idp2.example.test",
    };
    const config = resolveCernboxIdpConfigFromExpose(
      (key) => expose[key],
      "receiver",
    );
    expect(config).toEqual({
      idpOrigin: "https://idp2.example.test",
      realm: "realm-a",
    });
  });

  test("receiver slot falls back origin to sender while keeping configured receiver realm", () => {
    const expose: Record<string, string> = {
      sender_idp_origin: "https://idp1.example.test",
      sender_idp_realm: "realm-a",
      receiver_idp_realm: "realm-b",
    };
    const config = resolveCernboxIdpConfigFromExpose(
      (key) => expose[key],
      "receiver",
    );
    expect(config).toEqual({
      idpOrigin: "https://idp1.example.test",
      realm: "realm-b",
    });
  });
});
