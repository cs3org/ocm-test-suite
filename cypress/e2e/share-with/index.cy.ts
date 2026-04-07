/// <reference types="cypress" />

import { resolveShareWithScenarioCase, shareWithCases } from "./cases";
import { defineShareWithScenarioCase } from "./steps";

const proofCell = String(Cypress.expose("proof_cell") ?? "");
const selected = proofCell.length > 0
  ? [resolveShareWithScenarioCase(proofCell)]
  : shareWithCases;

for (const scenarioCase of selected) {
  defineShareWithScenarioCase(scenarioCase);
}
