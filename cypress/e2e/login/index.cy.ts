/// <reference types="cypress" />

import { requireMatrixProofCell } from "../proof-cell";
import { resolveLoginScenarioCase } from "./cases";
import { matrixCellIds } from "./matrix";
import { defineLoginScenarioCase } from "./steps";

const scenarioCase = resolveLoginScenarioCase(
  requireMatrixProofCell({ flowId: "login", matrixCellIds }),
);

defineLoginScenarioCase(scenarioCase);
