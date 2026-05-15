/// <reference types="cypress" />

import { requireMatrixProofCell } from "../proof-cell";
import { resolveContactWayfScenarioCase } from "./cases";
import { matrixCellIds } from "./matrix";
import { defineContactWayfScenarioCase } from "./steps";

const scenarioCase = resolveContactWayfScenarioCase(
  requireMatrixProofCell({ flowId: "contact-wayf", matrixCellIds }),
);

defineContactWayfScenarioCase(scenarioCase);
