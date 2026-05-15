/// <reference types="cypress" />

import { resolveActorCredentials } from "../../support/actors/credentials";
import type { ScenarioCase } from "./cases";
import {
  clearRuntime,
  ensureRuntimeDir,
  installHooks,
  readRuntime,
  requireString,
  runtimePath,
  setBaseUrl,
  writeRuntime,
} from "../../support/shared/procedural-flow";
import { takeEvidenceScreenshot } from "../../support/shared/evidence";

type RuntimeState = {
  acceptedContactUrl?: string;
  inviteToken: string;
  sharedFileName: string;
  expectedContent?: string;
};

export function defineContactTokenScenarioCase(scenarioCase: ScenarioCase) {
  describe(scenarioCase.id, () => {
    const flowId = "contact-token";
    const scenarioRuntimePath = runtimePath(flowId, scenarioCase.id);

    installHooks();

    before(() => {
      return ensureRuntimeDir();
    });

    it("sender creates token and stores runtime", () => {
      const sharedFileName = `contact-token-${scenarioCase.id}.txt`;

      return cy
        .then(() => clearRuntime(scenarioRuntimePath))
        .then(() => resolveActorCredentials(scenarioCase.sender))
        .then((senderCredentials) => {
          scenarioCase.senderLogin.login(senderCredentials);
          scenarioCase.senderLogin.assertLoggedIn();
          takeEvidenceScreenshot({
            scenarioId: scenarioCase.id,
            sequence: 1,
            actor: "sender",
            checkpoint: "authenticated",
          });

          return scenarioCase.contactTokenSender.createInviteToken({
            note: `cypress ${scenarioCase.id}`,
          }).then((inviteToken) => {
            takeEvidenceScreenshot({
              scenarioId: scenarioCase.id,
              sequence: 2,
              actor: "sender",
              checkpoint: "invite-created",
            });

            const runtimeState: RuntimeState = {
              inviteToken,
              sharedFileName,
            };

            return writeRuntime(scenarioRuntimePath, runtimeState);
          });
        });
    });

    it("receiver accepts token and verifies contact", () => {
      return resolveActorCredentials(scenarioCase.receiver).then((receiverCredentials) => {
        setBaseUrl(scenarioCase.receiverIdentity.getBaseUrl());

        scenarioCase.receiverLogin.login(receiverCredentials);
        scenarioCase.receiverLogin.assertLoggedIn();
        takeEvidenceScreenshot({
          scenarioId: scenarioCase.id,
          sequence: 3,
          actor: "receiver",
          checkpoint: "authenticated",
        });

        return readRuntime(scenarioRuntimePath).then((runtime) => {
          const inviteToken = requireString(
            scenarioRuntimePath,
            runtime,
            "inviteToken",
          );

          return scenarioCase.contactTokenReceiver.acceptInviteToken({
            inviteToken,
          }).then((acceptedContactUrl) => {
            takeEvidenceScreenshot({
              scenarioId: scenarioCase.id,
              sequence: 4,
              actor: "receiver",
              checkpoint: "invite-accepted",
            });
            scenarioCase.contactTokenReceiver.assertAcceptedContactExists({
              acceptedContactUrl,
            });
            takeEvidenceScreenshot({
              scenarioId: scenarioCase.id,
              sequence: 5,
              actor: "receiver",
              checkpoint: "contact-visible",
            });

            return writeRuntime(scenarioRuntimePath, {
              ...runtime,
              acceptedContactUrl,
            });
          });
        });
      });
    });

    it("sender shares file -> receiver can accept", () => {
      return readRuntime(scenarioRuntimePath).then((runtime) => {
        const sharedFileName = requireString(
          scenarioRuntimePath,
          runtime,
          "sharedFileName",
        );

        return resolveActorCredentials(scenarioCase.sender).then((senderCredentials) => {
          return resolveActorCredentials(scenarioCase.receiver).then((receiverCredentials) => {
            const federatedRecipientId =
              scenarioCase.receiverIdentity.buildFederatedRecipientId({
                credentials: receiverCredentials,
              });

            scenarioCase.senderLogin.login(senderCredentials);
            scenarioCase.senderLogin.assertLoggedIn();

            scenarioCase.senderShareFile
              .prepareShareFile({
                sourceFileName: "welcome.txt",
                sharedFileName,
              })
              .then(({ expectedContent }) => {
                if (expectedContent !== undefined) {
                  return writeRuntime(scenarioRuntimePath, { ...runtime, expectedContent });
                }
                return undefined;
              });

            scenarioCase.senderShareFile.sendFileToFederatedRecipient({
              sharedFileName,
              federatedRecipientId,
            });

            takeEvidenceScreenshot({
              scenarioId: scenarioCase.id,
              sequence: 6,
              actor: "sender",
              checkpoint: "share-saved",
            });
          });
        });
      });
    });

    it("receiver accepts share -> file visible", () => {
      return resolveActorCredentials(scenarioCase.receiver).then((receiverCredentials) => {
        setBaseUrl(scenarioCase.receiverIdentity.getBaseUrl());

        scenarioCase.receiverLogin.login(receiverCredentials);
        scenarioCase.receiverLogin.assertLoggedIn();

        return readRuntime(scenarioRuntimePath).then((runtime) => {
          const sharedFileName = requireString(
            scenarioRuntimePath,
            runtime,
            "sharedFileName",
          );

          scenarioCase.receiverShareFile.acceptIncomingShare({ sharedFileName });
          takeEvidenceScreenshot({
            scenarioId: scenarioCase.id,
            sequence: 7,
            actor: "receiver",
            checkpoint: "share-visible",
          });

          const expectedContent =
            typeof runtime["expectedContent"] === "string"
              ? runtime["expectedContent"]
              : undefined;

          if (
            scenarioCase.receiverShareFile.assertSharedFileContent !== undefined &&
            expectedContent !== undefined
          ) {
            scenarioCase.receiverShareFile.assertSharedFileContent({
              sharedFileName,
              expectedContent,
            });
          }
        });
      });
    });
  });
}
