/// <reference types="cypress" />

import { resolveActorCredentials } from "../actors/credentials";
import type {
  ContactTokenReceiverAdapter,
  ContactTokenSenderAdapter,
  ProviderIdentityAdapter,
} from "../contracts/contact";
import type { ActorRef, LoginAdapter } from "../contracts/login";
import { takeEvidenceScreenshot } from "./evidence";
import {
  clearRuntime,
  readRuntime,
  requireString,
  setBaseUrl,
  writeRuntime,
} from "./procedural-flow";

// Shared contact-token trust prefix used by both the contact-token and
// webapp-share flows: the sender mints an invite token, then the receiver
// accepts it and verifies the resulting contact. The only per-flow difference
// is the runtime key/value that names the resource later steps operate on, so
// that pair is parameterized.
export type ContactTrustSetupScenario = {
  id: string;
  sender: ActorRef;
  receiver: ActorRef;
  senderLogin: LoginAdapter;
  receiverLogin: LoginAdapter;
  contactTokenSender: ContactTokenSenderAdapter;
  contactTokenReceiver: ContactTokenReceiverAdapter;
  receiverIdentity: ProviderIdentityAdapter;
};

export type ContactTrustSetupConfig = {
  scenarioCase: ContactTrustSetupScenario;
  scenarioRuntimePath: string;
  resourceRuntimeKey: string;
  resourceName: string;
};

export function defineContactTrustSetupSteps(config: ContactTrustSetupConfig): void {
  const { scenarioCase, scenarioRuntimePath, resourceRuntimeKey, resourceName } =
    config;

  it("sender creates token and stores runtime", () => {
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

        return scenarioCase.contactTokenSender
          .createInviteToken({ note: `cypress ${scenarioCase.id}` })
          .then((inviteToken) => {
            takeEvidenceScreenshot({
              scenarioId: scenarioCase.id,
              sequence: 2,
              actor: "sender",
              checkpoint: "invite-created",
            });

            return writeRuntime(scenarioRuntimePath, {
              inviteToken,
              [resourceRuntimeKey]: resourceName,
            });
          });
      });
  });

  it("receiver accepts token and verifies contact", () => {
    return resolveActorCredentials(scenarioCase.receiver).then(
      (receiverCredentials) => {
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

          return scenarioCase.contactTokenReceiver
            .acceptInviteToken({ inviteToken })
            .then((acceptedContactUrl) => {
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
      },
    );
  });
}
