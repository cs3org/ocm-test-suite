/// <reference types="cypress" />

export type EvidenceActor = "single" | "sender" | "receiver";

export type EvidenceCheckpoint =
  | "login-page-ready"
  | "authenticated"
  | "share-saved"
  | "share-visible"
  | "invite-created"
  | "invite-accepted"
  | "contact-visible";

const evidenceActors = new Set<EvidenceActor>(["single", "sender", "receiver"]);
const evidenceCheckpoints = new Set<EvidenceCheckpoint>([
  "login-page-ready",
  "authenticated",
  "share-saved",
  "share-visible",
  "invite-created",
  "invite-accepted",
  "contact-visible",
]);

export type EvidenceScreenshot = {
  scenarioId: string;
  sequence: number;
  actor: EvidenceActor;
  checkpoint: EvidenceCheckpoint;
};

function validateEvidenceScreenshot({
  scenarioId,
  sequence,
  actor,
  checkpoint,
}: EvidenceScreenshot): void {
  if (scenarioId.trim().length === 0) {
    throw new Error("Evidence screenshot requires a non-empty scenario id.");
  }
  if (scenarioId !== scenarioId.trim()) {
    throw new Error(
      "Evidence screenshot scenario id must not include leading or trailing whitespace.",
    );
  }
  if (scenarioId.includes("--")) {
    throw new Error(
      'Evidence screenshot scenario id must not include the "--" separator.',
    );
  }
  if (!Number.isInteger(sequence) || sequence < 1 || sequence > 999) {
    throw new Error(
      `Evidence screenshot sequence must be an integer from 1 through 999: ${sequence}`,
    );
  }
  if (!evidenceActors.has(actor)) {
    throw new Error(`Unsupported evidence actor: ${actor}`);
  }
  if (!evidenceCheckpoints.has(checkpoint)) {
    throw new Error(`Unsupported evidence checkpoint: ${checkpoint}`);
  }
}

export function buildEvidenceScreenshotName(
  params: EvidenceScreenshot,
): string {
  validateEvidenceScreenshot(params);
  const paddedSequence = String(params.sequence).padStart(3, "0");
  return `${params.scenarioId}--${paddedSequence}--${params.actor}--${params.checkpoint}`;
}

export function takeEvidenceScreenshot(params: EvidenceScreenshot): void {
  cy.screenshot(buildEvidenceScreenshotName(params));
}

export function captureSameOriginLoginPageReadyEvidence(
  scenarioId: string,
): void {
  takeEvidenceScreenshot({
    scenarioId,
    sequence: 1,
    actor: "single",
    checkpoint: "login-page-ready",
  });
}
