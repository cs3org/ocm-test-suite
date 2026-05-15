/// <reference types="cypress" />

type RequireMatrixProofCellOptions<T extends string> = {
  flowId: string;
  matrixCellIds: readonly T[];
};

function includesMatrixCellId<T extends string>(
  matrixCellIds: readonly T[],
  proofCell: string,
): proofCell is T {
  return matrixCellIds.some((matrixCellId) => matrixCellId === proofCell);
}

export function requireMatrixProofCell<T extends string>({
  flowId,
  matrixCellIds,
}: RequireMatrixProofCellOptions<T>): T {
  const exposed = Cypress.expose("proof_cell");
  const proofCell =
    typeof exposed === "string"
      ? exposed.trim()
      : String(exposed ?? "").trim();

  if (proofCell.length === 0) {
    throw new Error(
      [
        `[${flowId}] Missing required Cypress value: Cypress.expose("proof_cell").`,
        "This flow now runs exactly one generated matrix cell per spec invocation.",
        'Use "nu scripts/ocmts.nu services up run",',
        '"nu scripts/ocmts.nu services up open", and',
        '"nu scripts/ocmts.nu test cypress run" to start services, inspect them, and run a single matrix cell.',
      ].join(" "),
    );
  }

  if (!includesMatrixCellId(matrixCellIds, proofCell)) {
    throw new Error(
      [
        `[${flowId}] Invalid proof_cell="${proofCell}".`,
        `Expected one of this flow's generated matrixCellIds: ${matrixCellIds.join(", ")}`,
      ].join(" "),
    );
  }

  return proofCell;
}
