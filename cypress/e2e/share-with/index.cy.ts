/// <reference types="cypress" />

import { requireMatrixProofCell } from "../proof-cell";
import { resolveShareWithScenarioCase } from "./cases";
import { matrixCellIds } from "./matrix";
import { defineShareWithScenarioCase } from "./steps";

const scenarioCase = resolveShareWithScenarioCase(
  requireMatrixProofCell({ flowId: "share-with", matrixCellIds }),
);

defineShareWithScenarioCase(scenarioCase);
