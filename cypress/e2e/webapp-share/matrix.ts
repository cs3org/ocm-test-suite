// webapp-share matrix cells (manual list; regenerate via matrix gen when widened).
export const matrixCellIds = [
  "webapp-share__nextcloud-v35__cernbox-v11",
  "webapp-share__nextcloud-v35__nextcloud-v35",
] as const;
export type MatrixCellId = (typeof matrixCellIds)[number];
