/// <reference types="cypress" />

import { requireMatrixProofCell } from "../proof-cell";
import { resolveWebappShareScenarioCase } from "./cases";
import { matrixCellIds } from "./matrix";
import { defineWebappShareScenarioCase } from "./steps";

const scenarioCase = resolveWebappShareScenarioCase(
  requireMatrixProofCell({ flowId: "webapp-share", matrixCellIds }),
);

defineWebappShareScenarioCase(scenarioCase);
