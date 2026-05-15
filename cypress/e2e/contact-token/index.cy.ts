/// <reference types="cypress" />

import { requireMatrixProofCell } from "../proof-cell";
import { resolveContactTokenScenarioCase } from "./cases";
import { matrixCellIds } from "./matrix";
import { defineContactTokenScenarioCase } from "./steps";

const scenarioCase = resolveContactTokenScenarioCase(
  requireMatrixProofCell({ flowId: "contact-token", matrixCellIds }),
);

defineContactTokenScenarioCase(scenarioCase);
