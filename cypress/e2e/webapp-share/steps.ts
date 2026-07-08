/// <reference types="cypress" />

import { resolveActorCredentials } from "../../support/actors/credentials";
import type { ScenarioCase } from "../../support/contracts/webapp-share";
import {
  ensureRuntimeDir,
  installHooks,
  readRuntime,
  requireString,
  runtimePath,
  setBaseUrl,
} from "../../support/shared/procedural-flow";
import { takeEvidenceScreenshot } from "../../support/shared/evidence";
import { defineIdpLoginPrewarm } from "../../support/shared/idp-prewarm";
import { defineContactTrustSetupSteps } from "../../support/shared/contact-trust-setup";
import {
  assertMitmExpectations,
  captureMitmTrafficScopeMarker,
  type MitmExpectation,
  type MitmTrafficRecord,
} from "../../support/shared/mitm-traffic";

// Launch-leg proof for the CERNBox -> JupyterHub Layer 2 handoff. Cross-origin
// navigation makes in-browser assertions unreliable, so the MITM capture is the
// authoritative oracle: the remote open reaches the hub and redirects toward the
// notebook workspace.
function mentionsLab(record: MitmTrafficRecord): boolean {
  return [
    record.response?.headers?.Location,
    record.response?.headers?.location,
    record.response?.body?.preview,
    record.request.url,
  ].some((value) => typeof value === "string" && value.includes("/lab"));
}

const WEBAPP_SHARE_LAUNCH_EXPECTATIONS: MitmExpectation[] = [
  {
    label: "POST /services/ocm/open",
    predicate: (record) =>
      record.request.method === "POST" &&
      (record.request.path ?? "").includes("/services/ocm/open"),
  },
  {
    // The OCM service launcher submits a cross-origin form POST to the hub's
    // OCMLoginHandler (hub/.../handlers.py: OCMLoginHandler implements post()
    // only); asserting GET here never matches real launch traffic.
    label: "POST /hub/ocm-login",
    predicate: (record) =>
      record.request.method === "POST" &&
      (record.request.path ?? "").includes("/hub/ocm-login"),
  },
  {
    label: "redirect toward /lab handoff boundary",
    predicate: mentionsLab,
  },
];

export function defineWebappShareScenarioCase(scenarioCase: ScenarioCase) {
  describe(scenarioCase.id, () => {
    const flowId = "webapp-share";
    const scenarioRuntimePath = runtimePath(flowId, scenarioCase.id);

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

              scenarioCase.senderAdapter.prepareShareFolder({ sharedFolderName });
              scenarioCase.senderAdapter.shareWebappWithFederatedRecipient({
                sharedFolderName,
                federatedRecipientId,
              });

              takeEvidenceScreenshot({
                scenarioId: scenarioCase.id,
                sequence: 6,
                actor: "sender",
                checkpoint: "share-saved",
              });
            },
          );
        });
      });
    });

    it("receiver launches remote webapp through Layer 2 handoff", () => {
      return resolveActorCredentials(scenarioCase.receiver).then((receiverCredentials) => {
        setBaseUrl(scenarioCase.receiverIdentity.getBaseUrl());

        scenarioCase.receiverLogin.login(receiverCredentials);
        scenarioCase.receiverLogin.assertLoggedIn();
        takeEvidenceScreenshot({
          scenarioId: scenarioCase.id,
          sequence: 7,
          actor: "receiver",
          checkpoint: "authenticated",
        });

        return readRuntime(scenarioRuntimePath).then((runtime) => {
          const sharedFolderName = requireString(
            scenarioRuntimePath,
            runtime,
            "sharedFolderName",
          );

          scenarioCase.receiverAdapter.acceptIncomingWebappShare({
            sharedFolderName,
          });
          takeEvidenceScreenshot({
            scenarioId: scenarioCase.id,
            sequence: 8,
            actor: "receiver",
            checkpoint: "share-visible",
          });

          return captureMitmTrafficScopeMarker().then((marker) => {
            scenarioCase.receiverAdapter.launchRemoteWebapp({ sharedFolderName });
            return assertMitmExpectations({
              title: "webapp-share launch leg",
              marker,
              expectations: WEBAPP_SHARE_LAUNCH_EXPECTATIONS,
            });
          });
        });
      });
    });
  });
}
