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
  redirectUrl: string;
  sharedFileName: string;
  expectedContent?: string;
};

export function defineContactWayfScenarioCase(scenarioCase: ScenarioCase) {
  describe(scenarioCase.id, () => {
    const flowId = "contact-wayf";
    const scenarioRuntimePath = runtimePath(flowId, scenarioCase.id);

    installHooks();

    before(() => {
      return ensureRuntimeDir();
    });

    it("sender creates invite and stores WAYF redirect URL", () => {
      const sharedFileName = `contact-wayf-${scenarioCase.id}.txt`;

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

          return scenarioCase.contactWayfSender.createInviteLink({
            note: `cypress ${scenarioCase.id}`,
          }).then((inviteLink) => {
            takeEvidenceScreenshot({
              scenarioId: scenarioCase.id,
              sequence: 2,
              actor: "sender",
              checkpoint: "invite-created",
            });

            const providerUrl = scenarioCase.receiverIdentity.getProviderUrl({
              inviteLink,
            });

            return scenarioCase.contactWayfSender.captureReceiverRedirectUrl({
              inviteLink,
              providerUrl,
            }).then((redirectUrl) => {
              const runtimeState: RuntimeState = {
                redirectUrl,
                sharedFileName,
              };

              return writeRuntime(scenarioRuntimePath, runtimeState);
            });
          });
        });
    });

    it("receiver accepts invite and verifies contact", () => {
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
          const redirectUrl = requireString(
            scenarioRuntimePath,
            runtime,
            "redirectUrl",
          );

          return scenarioCase.contactWayfReceiver.acceptInviteFromRedirect({
            redirectUrl,
          }).then((acceptedContactUrl) => {
            takeEvidenceScreenshot({
              scenarioId: scenarioCase.id,
              sequence: 4,
              actor: "receiver",
              checkpoint: "invite-accepted",
            });
            scenarioCase.contactWayfReceiver.assertAcceptedContactExists({
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

            scenarioCase.senderShareWith
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

            scenarioCase.senderShareWith.shareWithFederatedRecipient({
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

          scenarioCase.receiverShareWith.acceptIncomingShare({ sharedFileName });
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
            scenarioCase.receiverShareWith.assertSharedFileContent !== undefined &&
            expectedContent !== undefined
          ) {
            scenarioCase.receiverShareWith.assertSharedFileContent({
              sharedFileName,
              expectedContent,
            });
          }
        });
      });
    });
  });
}
