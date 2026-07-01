/// <reference types="cypress" />

import type { ScenarioCase } from "../../support/contracts/login";
import { defineLoginSteps } from "../../support/shared/login-strategy";

export function defineLoginScenarioCase(scenarioCase: ScenarioCase) {
  describe(scenarioCase.id, () => {
    beforeEach(() => {
      cy.task("runtime:clear");
      cy.task("runtime:set", { key: "proof_cell", value: scenarioCase.id });
    });

    defineLoginSteps(scenarioCase);
  });
}
