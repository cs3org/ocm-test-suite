// Pair-scoped matrix cell for webapp-share milestone slice.
// Regenerate via `nu scripts/ocmts.nu matrix gen cypress` when the flow widens.
export const matrixCellIds = [
  "webapp-share__nextcloud-v35__cernbox-v11",
  "webapp-share__nextcloud-v35__nextcloud-v35",
] as const;
export type MatrixCellId = (typeof matrixCellIds)[number];
