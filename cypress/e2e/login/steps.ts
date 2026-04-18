/// <reference types="cypress" />

import { resolveActorCredentials } from "../../support/actors/credentials";
import type { ScenarioCase } from "../../support/contracts/login";
import { takeEvidenceScreenshot } from "../../support/shared/evidence";

export function defineLoginScenarioCase(scenarioCase: ScenarioCase) {
  describe(scenarioCase.id, () => {
    beforeEach(() => {
      cy.task("runtime:clear");
      cy.task("runtime:set", { key: "proof_cell", value: scenarioCase.id });
    });

    it("visit / -> logs in and shows authenticated UI", () => {
      resolveActorCredentials(scenarioCase.actor).then((credentials) => {
        scenarioCase.adapter.openLoginPage();
        takeEvidenceScreenshot({
          scenarioId: scenarioCase.id,
          sequence: 1,
          actor: "single",
          checkpoint: "login-page-ready",
        });
        scenarioCase.adapter.submitLogin(credentials);
        scenarioCase.adapter.assertLoggedIn();
        takeEvidenceScreenshot({
          scenarioId: scenarioCase.id,
          sequence: 2,
          actor: "single",
          checkpoint: "authenticated",
        });
      });
    });
  });
}
