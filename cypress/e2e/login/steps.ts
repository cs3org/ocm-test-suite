/// <reference types="cypress" />

import { resolveActorCredentials } from "../../support/actors/credentials";
import type { ScenarioCase } from "../../support/contracts/login";

export function defineLoginScenarioCase(scenarioCase: ScenarioCase) {
  describe(scenarioCase.id, () => {
    beforeEach(() => {
      cy.task("runtime:clear");
      cy.task("runtime:set", { key: "proof_cell", value: scenarioCase.id });
    });

    it("visit / -> logs in and shows authenticated UI", () => {
      resolveActorCredentials(scenarioCase.actor).then((credentials) => {
        scenarioCase.adapter.login(credentials);
        scenarioCase.adapter.assertLoggedIn();
      });
    });
  });
}
