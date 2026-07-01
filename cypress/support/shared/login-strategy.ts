/// <reference types="cypress" />

import { resolveActorCredentials } from "../actors/credentials";
import type { ScenarioCase } from "../contracts/login";
import { takeEvidenceScreenshot } from "./evidence";

function captureAuthenticatedEvidence(scenarioId: string): void {
  takeEvidenceScreenshot({
    scenarioId,
    sequence: 2,
    actor: "single",
    checkpoint: "authenticated",
  });
}

// Emits the it() blocks for a login scenario based on the adapter mechanism.
// external-idp produces two steps (authenticate at the IdP, then app SSO);
// same-origin produces the single open -> capture -> submit -> assert step.
export function defineLoginSteps(scenarioCase: ScenarioCase): void {
  const { adapter } = scenarioCase;

  if (adapter.mechanism === "external-idp") {
    it("authenticates at the identity provider", () => {
      resolveActorCredentials(scenarioCase.actor).then((credentials) => {
        adapter.establishIdpSession(credentials, scenarioCase.id);
      });
    });

    it("application grants access via SSO", () => {
      resolveActorCredentials(scenarioCase.actor).then((credentials) => {
        // testIsolation clears all-domain cookies between tests, so restore the
        // cached IdP session before proving the app-side silent OIDC handshake.
        adapter.establishIdpSession(credentials);
        adapter.completeAppLogin();
        adapter.assertLoggedIn();
        captureAuthenticatedEvidence(scenarioCase.id);
      });
    });

    return;
  }

  it("visit / -> logs in and shows authenticated UI", () => {
    resolveActorCredentials(scenarioCase.actor).then((credentials) => {
      adapter.openLoginPage();
      adapter.captureLoginPageReadyEvidence(scenarioCase.id);
      adapter.submitLogin(credentials);
      adapter.assertLoggedIn();
      captureAuthenticatedEvidence(scenarioCase.id);
    });
  });
}
