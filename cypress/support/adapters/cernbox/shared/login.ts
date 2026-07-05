/// <reference types="cypress" />

import type { ActorCredentials } from "../../../contracts/login";
import { establishIdpSession } from "../../../shared/idp-session";
import {
  resolveCernboxIdpConfig,
  type CernboxIdpSlot,
} from "./idp-config";

const loggedInUrlRe = /\/files\/spaces\//;
const postLoginTimeoutMs = 30000;

export type { CernboxIdpSlot };

export function cernboxIdpOrigin(slot: CernboxIdpSlot = "sender"): string {
  return resolveCernboxIdpConfig(slot).idpOrigin;
}

export function cernboxRealm(slot: CernboxIdpSlot = "sender"): string {
  return resolveCernboxIdpConfig(slot).realm;
}

export function establishCernboxIdpSession(
  credentials: ActorCredentials,
  options?: { slot?: CernboxIdpSlot; scenarioId?: string },
): void {
  const slot = options?.slot ?? "sender";
  const { idpOrigin, realm } = resolveCernboxIdpConfig(slot);

  establishIdpSession({
    idpOrigin,
    realm,
    credentials,
    scenarioId: options?.scenarioId,
  });
}

export function completeCernboxAppLogin(): void {
  cy.intercept("GET", "**/web-oidc-callback**").as("oidcCallback");

  cy.visit("/");
  cy.wait("@oidcCallback", { timeout: postLoginTimeoutMs }).then(
    (interception) => {
      expect(interception.response, "OIDC callback response").to.exist;
      expect(interception.response?.statusCode, "OIDC callback status").to.eq(
        200,
      );
    },
  );
}

export function assertCernboxLoggedIn(): void {
  cy.url({ timeout: postLoginTimeoutMs }).should("match", loggedInUrlRe);
  cy.get("#web-content", { timeout: postLoginTimeoutMs }).should("be.visible");
}
