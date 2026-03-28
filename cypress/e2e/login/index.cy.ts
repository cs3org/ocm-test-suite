/// <reference types="cypress" />

import { loginCases } from "./cases";
import { defineLoginScenarioCase } from "./steps";

for (const scenarioCase of loginCases) {
  defineLoginScenarioCase(scenarioCase);
}
