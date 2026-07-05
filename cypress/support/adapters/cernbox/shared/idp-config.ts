/// <reference types="cypress" />

export type CernboxIdpSlot = "sender" | "receiver";

const defaultIdpOrigin = "https://idp1.docker";
const defaultRealm = "cernbox";

function coerceNonEmpty(value: unknown): string | undefined {
  if (value === undefined || value === null) return undefined;
  const s = String(value).trim();
  return s === "" ? undefined : s;
}

// Pure slot-aware IdP resolution for unit tests and Cypress runtime.
export function resolveCernboxIdpConfigFromExpose(
  readExpose: (key: string) => unknown,
  slot: CernboxIdpSlot,
): { idpOrigin: string; realm: string } {
  const prefix = slot === "sender" ? "sender" : "receiver";
  const configuredOrigin = coerceNonEmpty(readExpose(`${prefix}_idp_origin`));
  const configuredRealm = coerceNonEmpty(readExpose(`${prefix}_idp_realm`));

  if (slot === "receiver") {
    return {
      idpOrigin:
        configuredOrigin ??
        coerceNonEmpty(readExpose("sender_idp_origin")) ??
        defaultIdpOrigin,
      realm:
        configuredRealm ??
        coerceNonEmpty(readExpose("sender_idp_realm")) ??
        defaultRealm,
    };
  }

  return {
    idpOrigin: configuredOrigin ?? defaultIdpOrigin,
    realm: configuredRealm ?? defaultRealm,
  };
}

export function resolveCernboxIdpConfig(
  slot: CernboxIdpSlot,
): { idpOrigin: string; realm: string } {
  return resolveCernboxIdpConfigFromExpose(
    (key) => Cypress.expose(key),
    slot,
  );
}
