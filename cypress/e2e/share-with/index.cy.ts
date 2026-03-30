/// <reference types="cypress" />

import { shareWithCases } from "./cases";
import { defineShareWithScenarioCase } from "./steps";

for (const scenarioCase of shareWithCases) {
  defineShareWithScenarioCase(scenarioCase);
}
