/// <reference types="cypress" />

import { resolveActorCredentials } from "../../support/actors/credentials";
import type { ScenarioCase } from "../../support/contracts/share-with";
import { takeEvidenceScreenshot } from "../../support/shared/evidence";

export function defineShareWithScenarioCase(scenarioCase: ScenarioCase) {
  describe(scenarioCase.id, () => {
    const originalBaseUrl = Cypress.config("baseUrl");

    beforeEach(() => {
      cy.task("runtime:clear");
      cy.task("runtime:set", { key: "proof_cell", value: scenarioCase.id });
    });

    const sharedFileName = `share-with-${scenarioCase.id}.txt`;

    const receiverBaseUrl = resolveRequiredBaseUrl("receiver_baseUrl");
    const receiverHost = new URL(receiverBaseUrl).host;

    afterEach(() => {
      Cypress.config("baseUrl", originalBaseUrl);
    });

    it("sender shares file from sender to receiver", () => {
      resolveActorCredentials(scenarioCase.sender).then((senderCredentials) => {
        return resolveActorCredentials(scenarioCase.receiver).then(
          (receiverCredentials) => {
            const federatedRecipientId = `${receiverCredentials.username}@${receiverHost}`;

            scenarioCase.senderLogin.login(senderCredentials);
            scenarioCase.senderLogin.assertLoggedIn();
            takeEvidenceScreenshot({
              scenarioId: scenarioCase.id,
              sequence: 1,
              actor: "sender",
              checkpoint: "authenticated",
            });

            scenarioCase.senderAdapter.prepareShareFile({
              sourceFileName: "welcome.txt",
              sharedFileName,
            });

            scenarioCase.senderAdapter.shareWithFederatedRecipient({
              sharedFileName,
              federatedRecipientId,
            });

            takeEvidenceScreenshot({
              scenarioId: scenarioCase.id,
              sequence: 2,
              actor: "sender",
              checkpoint: "share-saved",
            });
          },
        );
      });
    });

    it("receiver accepts incoming share", () => {
      resolveActorCredentials(scenarioCase.receiver).then((receiverCredentials) => {
        Cypress.config("baseUrl", receiverBaseUrl);

        scenarioCase.receiverLogin.login(receiverCredentials);
        scenarioCase.receiverLogin.assertLoggedIn();
        takeEvidenceScreenshot({
          scenarioId: scenarioCase.id,
          sequence: 3,
          actor: "receiver",
          checkpoint: "authenticated",
        });
        scenarioCase.receiverAdapter.acceptIncomingShare({ sharedFileName });
        takeEvidenceScreenshot({
          scenarioId: scenarioCase.id,
          sequence: 4,
          actor: "receiver",
          checkpoint: "share-visible",
        });
      });
    });
  });
}

function resolveRequiredBaseUrl(envKey: string): string {
  const value = Cypress.expose(envKey);
  if (value === undefined || value === null || String(value) === "") {
    throw new Error(
      [
        `Missing Cypress base URL: Cypress.expose("${envKey}").`,
        `This value should be injected via compose as CYPRESS_${envKey}.`,
      ].join(" "),
    );
  }

  return String(value);
}
