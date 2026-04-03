/// <reference types="cypress" />

import { shareWithCases } from "./cases";
import { defineShareWithScenarioCase } from "./steps";

const proofCell = String(Cypress.expose("proof_cell") ?? "");
const selected = proofCell
  ? shareWithCases.filter((c) => c.id === proofCell)
  : shareWithCases;

for (const scenarioCase of selected) {
  defineShareWithScenarioCase(scenarioCase);
}
