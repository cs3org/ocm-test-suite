/// <reference types="cypress" />

import {
  assertNextcloudLoggedIn,
  loginNextcloudViaUi,
} from "../../support/adapters/nextcloud/shared-login";
import { resolveActorCredentials } from "../../support/actors/credentials";
import type { ScenarioCase } from "../../support/contracts/share-with";

export function defineShareWithScenarioCase(scenarioCase: ScenarioCase) {
  describe(scenarioCase.id, () => {
    const originalBaseUrl = Cypress.config("baseUrl");

    function takeStepScreenshot(stepLabel: string) {
      cy.screenshot(`${scenarioCase.id}--${stepLabel}`);
    }

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

            loginNextcloudViaUi(senderCredentials);
            assertNextcloudLoggedIn();
            takeStepScreenshot("sender--after-login");

            scenarioCase.adapter.prepareShareFile({
              sourceFileName: "welcome.txt",
              sharedFileName,
            });

            scenarioCase.adapter.shareWithFederatedRecipient({
              sharedFileName,
              federatedRecipientId,
            });

            takeStepScreenshot("sender--after-share-saved");
          },
        );
      });
    });

    it("receiver accepts incoming share", () => {
      resolveActorCredentials(scenarioCase.receiver).then((receiverCredentials) => {
        Cypress.config("baseUrl", receiverBaseUrl);

        loginNextcloudViaUi(receiverCredentials);
        assertNextcloudLoggedIn();
        takeStepScreenshot("receiver--after-login");
        scenarioCase.adapter.acceptIncomingShare({ sharedFileName });
        takeStepScreenshot("receiver--after-share-visible");
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
