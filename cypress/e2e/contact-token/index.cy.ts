/// <reference types="cypress" />

import { contactTokenCases, resolveContactTokenScenarioCase } from "./cases";
import { defineContactTokenScenarioCase } from "./steps";

const proofCell = String(Cypress.expose("proof_cell") ?? "");
const selected = proofCell.length > 0
  ? [resolveContactTokenScenarioCase(proofCell)]
  : contactTokenCases;

for (const scenarioCase of selected) {
  defineContactTokenScenarioCase(scenarioCase);
}
