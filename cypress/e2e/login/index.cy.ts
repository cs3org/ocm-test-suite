/// <reference types="cypress" />

import { loginCases, resolveLoginScenarioCase } from "./cases";
import { defineLoginScenarioCase } from "./steps";

const proofCell = String(Cypress.expose("proof_cell") ?? "");
const selected = proofCell.length > 0 ? [resolveLoginScenarioCase(proofCell)] : loginCases;

for (const scenarioCase of selected) {
  defineLoginScenarioCase(scenarioCase);
}
