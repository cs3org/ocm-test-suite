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
  screenshot,
  setBaseUrl,
  writeRuntime,
} from "../../support/shared/procedural-flow";

type RuntimeState = {
  acceptedContactUrl?: string;
  redirectUrl: string;
  sharedFileName: string;
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
          screenshot(scenarioCase.id, "sender", "after-login");

          return scenarioCase.contactWayfSender.createInviteLink({
            note: `cypress ${scenarioCase.id}`,
          }).then((inviteLink) => {
            screenshot(scenarioCase.id, "sender", "after-invite-created");

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
        screenshot(scenarioCase.id, "receiver", "after-login");

        return readRuntime(scenarioRuntimePath).then((runtime) => {
          const redirectUrl = requireString(
            scenarioRuntimePath,
            runtime,
            "redirectUrl",
          );

          return scenarioCase.contactWayfReceiver.acceptInviteFromRedirect({
            redirectUrl,
          }).then((acceptedContactUrl) => {
            screenshot(scenarioCase.id, "receiver", "after-invite-accepted");
            scenarioCase.contactWayfReceiver.assertAcceptedContactExists({
              acceptedContactUrl,
            });
            screenshot(scenarioCase.id, "receiver", "accepted-contact-exists");

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
            screenshot(scenarioCase.id, "sender", "after-login");

            scenarioCase.senderShareWith.prepareShareFile({
              sourceFileName: "welcome.txt",
              sharedFileName,
            });

            scenarioCase.senderShareWith.shareWithFederatedRecipient({
              sharedFileName,
              federatedRecipientId,
            });

            screenshot(scenarioCase.id, "sender", "after-share-saved");
          });
        });
      });
    });

    it("receiver accepts share -> file visible", () => {
      return resolveActorCredentials(scenarioCase.receiver).then((receiverCredentials) => {
        setBaseUrl(scenarioCase.receiverIdentity.getBaseUrl());

        scenarioCase.receiverLogin.login(receiverCredentials);
        scenarioCase.receiverLogin.assertLoggedIn();
        screenshot(scenarioCase.id, "receiver", "after-login");

        return readRuntime(scenarioRuntimePath).then((runtime) => {
          const sharedFileName = requireString(
            scenarioRuntimePath,
            runtime,
            "sharedFileName",
          );

          scenarioCase.receiverShareWith.acceptIncomingShare({ sharedFileName });
          screenshot(scenarioCase.id, "receiver", "after-share-visible");
        });
      });
    });
  });
}
