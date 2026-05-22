/// <reference types="cypress" />

import type { ShareWithFlowSenderAdapter } from "../../../contracts/share-with";
import type { ShareFileSenderAdapter } from "../../../contracts/share-file";

// UI form path: sender-container mount point for the source file.
const SHARE_DIR = "/tmp/ocmts-share";

// Runner-visible path: the shared host artifacts mount exposed to the
// Cypress runner. The sender platform container mounts
// ${OCMTS_ARTIFACTS_BASE}/share at /tmp/ocmts-share, so writing here
// makes the file visible inside the sender container at SHARE_DIR.
const ARTIFACTS_SHARE_DIR = "/artifacts/share";

function prepareShareFileImpl(
  { sharedFileName, sourceFileName: _sourceFileName }: { sharedFileName: string; sourceFileName?: string },
): Cypress.Chainable<{ expectedContent?: string }> {
  const artifactsPath = `${ARTIFACTS_SHARE_DIR}/${sharedFileName}`;

  cy.exec(`mkdir -p ${ARTIFACTS_SHARE_DIR}`, { log: false });
  cy.writeFile(
    artifactsPath,
    `OCMGo shared file: ${sharedFileName}\n`,
    { log: false },
  );
  return cy.wrap({});
}

function sendShareImpl({ sharedFileName, federatedRecipientId }: { sharedFileName: string; federatedRecipientId: string }): void {
  cy.visit("/ui/outgoing");
  cy.get("#outgoing-share-form", { timeout: 20000 }).should("be.visible");

  cy.get("#share-with", { timeout: 20000 }).clear().type(federatedRecipientId);
  cy.get("#local-path", { timeout: 20000 })
    .clear()
    .type(`${SHARE_DIR}/${sharedFileName}`);

  // Intercept before click so the alias is registered in time.
  cy.intercept("POST", "**/api/shares/outgoing**").as("postOutgoingShare");

  cy.get("#share-submit", { timeout: 20000 }).click();

  // Assert on the raw API response first. On non-2xx this surfaces the HTTP
  // status and server message immediately instead of timing out on #share-result.
  cy.wait("@postOutgoingShare", { timeout: 20000 }).then((interception) => {
    if (interception.response == null) {
      throw new Error("api/shares/outgoing failed: no response received");
    }
    const status = interception.response.statusCode;
    if (typeof status !== "number" || Number.isNaN(status)) {
      throw new Error(`api/shares/outgoing failed: invalid or missing HTTP status code (got ${String(status)})`);
    }
    if (status < 200 || status >= 300) {
      const body = interception.response.body as unknown;
      let detail: string;
      if (typeof body === "object" && body !== null && "message" in body) {
        const msg = (body as Record<string, unknown>).message;
        if (typeof msg === "string") {
          detail = msg;
        } else {
          try {
            detail = JSON.stringify(msg) ?? String(msg);
          } catch {
            detail = String(msg);
          }
        }
      } else if (typeof body === "string") {
        detail = body;
      } else {
        try {
          detail = JSON.stringify(body) ?? String(body);
        } catch {
          detail = "[unstringifiable body]";
        }
      }
      throw new Error(`api/shares/outgoing failed: HTTP ${status} - ${detail}`);
    }
  });

  cy.get("#share-result", { timeout: 20000 })
    .should("be.visible")
    .and("contain.text", "Share sent successfully");
}

export const ocmgoV1ShareWithFlowSenderAdapter: ShareWithFlowSenderAdapter = {
  key: "ocmgo/v1",
  prepareShareFile: prepareShareFileImpl,
  shareWithFederatedRecipient: sendShareImpl,
};

export const ocmgoV1ShareFileSenderAdapter: ShareFileSenderAdapter = {
  key: "ocmgo/v1",
  prepareShareFile: prepareShareFileImpl,
  sendFileToFederatedRecipient: sendShareImpl,
};
