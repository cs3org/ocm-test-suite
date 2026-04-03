/// <reference types="cypress" />

import { loginCases } from "./cases";
import { defineLoginScenarioCase } from "./steps";

const proofCell = String(Cypress.expose("proof_cell") ?? "");
const selected = proofCell
  ? loginCases.filter((c) => c.id === proofCell)
  : loginCases;

for (const scenarioCase of selected) {
  defineLoginScenarioCase(scenarioCase);
}
