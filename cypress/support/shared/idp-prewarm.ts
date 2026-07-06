/// <reference types="cypress" />

import { resolveActorCredentials } from "../actors/credentials";
import type { ActorRef, LoginAdapter } from "../contracts/login";

export type IdpPrewarmEntry = {
  role: string;
  login: LoginAdapter;
  actor: ActorRef;
  scenarioId: string;
};

// External-IdP logins (e.g. CERNBox -> Keycloak) cannot log in and assert on the
// app origin inside one it(): visiting the IdP in cy.session setup locks Cypress's
// tracked origin to the IdP, and cy.origin() is banned in this suite. So for each
// external-idp actor we emit a dedicated it() that only establishes+caches the IdP
// SSO session. Later functional login() calls then restore that session from the
// cy.session cache (no in-test IdP visit) and complete the app-side silent OIDC
// handshake on the app origin only. Same-origin logins need no pre-warm.
export function defineIdpLoginPrewarm(entries: IdpPrewarmEntry[]): void {
  for (const entry of entries) {
    if (entry.login.mechanism !== "external-idp") {
      continue;
    }
    const idpLogin = entry.login;
    it(`${entry.role} authenticates at identity provider`, () => {
      return resolveActorCredentials(entry.actor).then((credentials) => {
        idpLogin.establishIdpSession(credentials, entry.scenarioId);
      });
    });
  }
}
