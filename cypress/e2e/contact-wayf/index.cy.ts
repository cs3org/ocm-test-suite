/// <reference types="cypress" />

import { contactWayfCases, resolveContactWayfScenarioCase } from "./cases";
import { defineContactWayfScenarioCase } from "./steps";

const proofCell = String(Cypress.expose("proof_cell") ?? "");
const selected = proofCell.length > 0
  ? [resolveContactWayfScenarioCase(proofCell)]
  : contactWayfCases;

for (const scenarioCase of selected) {
  defineContactWayfScenarioCase(scenarioCase);
}
