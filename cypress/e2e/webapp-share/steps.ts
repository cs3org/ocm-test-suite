/// <reference types="cypress" />

import { resolveActorCredentials } from "../../support/actors/credentials";
import {
  buildSenderFederatedId,
  type ScenarioCase,
  WEBAPP_SHARE_APP_NAME,
} from "../../support/contracts/webapp-share";
import {
  ensureRuntimeDir,
  installHooks,
  readRuntime,
  requireString,
  runtimePath,
  setBaseUrl,
  writeRuntime,
} from "../../support/shared/procedural-flow";
import { takeEvidenceScreenshot } from "../../support/shared/evidence";
import { defineIdpLoginPrewarm } from "../../support/shared/idp-prewarm";
import { defineContactTrustSetupSteps } from "../../support/shared/contact-trust-setup";
import {
  assertMitmExpectations,
  captureMitmTrafficScopeMarker,
} from "../../support/shared/mitm-traffic";
import { resolveWebappShareMitmLaunchExpectations } from "../../support/shared/webapp-share-launch-oracle";

export function defineWebappShareScenarioCase(scenarioCase: ScenarioCase) {
  describe(scenarioCase.id, () => {
    const flowId = "webapp-share";
    const scenarioRuntimePath = runtimePath(flowId, scenarioCase.id);
    const mitmLaunchExpectations = resolveWebappShareMitmLaunchExpectations(
      scenarioCase.receiverAdapter.key,
    );

    installHooks();

    before(() => {
      return ensureRuntimeDir();
    });

    defineIdpLoginPrewarm([
      {
        role: "sender",
        login: scenarioCase.senderLogin,
        actor: scenarioCase.sender,
        scenarioId: scenarioCase.id,
      },
      {
        role: "receiver",
        login: scenarioCase.receiverLogin,
        actor: scenarioCase.receiver,
        scenarioId: scenarioCase.id,
      },
    ]);

    defineContactTrustSetupSteps({
      scenarioCase,
      scenarioRuntimePath,
      resourceRuntimeKey: "sharedFolderName",
      resourceName: `webapp-share-${scenarioCase.id}`,
    });

    it("sender shares JupyterHub webapp folder to receiver", () => {
      return readRuntime(scenarioRuntimePath).then((runtime) => {
        const sharedFolderName = requireString(
          scenarioRuntimePath,
          runtime,
          "sharedFolderName",
        );

        return resolveActorCredentials(scenarioCase.sender).then((senderCredentials) => {
          return resolveActorCredentials(scenarioCase.receiver).then(
            (receiverCredentials) => {
              const federatedRecipientId =
                scenarioCase.receiverIdentity.buildFederatedRecipientId({
                  credentials: receiverCredentials,
                });

              scenarioCase.senderLogin.login(senderCredentials);
              scenarioCase.senderLogin.assertLoggedIn();

              scenarioCase.senderAdapter.prepareShareFolder({
                sharedFolderName,
                credentials: senderCredentials,
              });
              takeEvidenceScreenshot({
                scenarioId: scenarioCase.id,
                sequence: 6,
                actor: "sender",
                checkpoint: "folder-ready",
              });

              scenarioCase.senderAdapter.openWebappShareDialog({ sharedFolderName });
              takeEvidenceScreenshot({
                scenarioId: scenarioCase.id,
                sequence: 7,
                actor: "sender",
                checkpoint: "share-dialog-ready",
              });

              scenarioCase.senderAdapter.submitWebappShare({ federatedRecipientId });
              takeEvidenceScreenshot({
                scenarioId: scenarioCase.id,
                sequence: 8,
                actor: "sender",
                checkpoint: "share-saved",
              });

              const senderHost = new URL(String(Cypress.config("baseUrl"))).host;
              const senderFederatedId = buildSenderFederatedId({
                username: senderCredentials.username,
                host: senderHost,
              });

              return writeRuntime(scenarioRuntimePath, {
                ...runtime,
                senderFederatedId,
              });
            },
          );
        });
      });
    });

    it("receiver accepts share and launches remote webapp", () => {
      return resolveActorCredentials(scenarioCase.receiver).then((receiverCredentials) => {
        setBaseUrl(scenarioCase.receiverIdentity.getBaseUrl());

        scenarioCase.receiverLogin.login(receiverCredentials);
        scenarioCase.receiverLogin.assertLoggedIn();
        takeEvidenceScreenshot({
          scenarioId: scenarioCase.id,
          sequence: 9,
          actor: "receiver",
          checkpoint: "authenticated",
        });

        return readRuntime(scenarioRuntimePath).then((runtime) => {
          const sharedFolderName = requireString(
            scenarioRuntimePath,
            runtime,
            "sharedFolderName",
          );
          const senderFederatedId = requireString(
            scenarioRuntimePath,
            runtime,
            "senderFederatedId",
          );
          const incomingShareRef = {
            sharedFolderName,
            senderFederatedId,
            appName: WEBAPP_SHARE_APP_NAME,
          };

          scenarioCase.receiverAdapter.acceptIncomingWebappShare(incomingShareRef);
          takeEvidenceScreenshot({
            scenarioId: scenarioCase.id,
            sequence: 10,
            actor: "receiver",
            checkpoint: "share-visible",
          });

          takeEvidenceScreenshot({
            scenarioId: scenarioCase.id,
            sequence: 11,
            actor: "receiver",
            checkpoint: "launch-ready",
          });

          return captureMitmTrafficScopeMarker().then((marker) => {
            scenarioCase.receiverAdapter.launchRemoteWebapp(incomingShareRef);
            takeEvidenceScreenshot({
              scenarioId: scenarioCase.id,
              sequence: 12,
              actor: "receiver",
              checkpoint: "launch-gated",
            });
            if (mitmLaunchExpectations.length === 0) {
              return;
            }
            return assertMitmExpectations({
              title: "webapp-share MITM launch leg",
              marker,
              expectations: mitmLaunchExpectations,
            });
          });
        });
      });
    });
  });
}
