/// <reference types="cypress" />

import { createCernboxV11LoginAdapter } from "../../support/adapters/cernbox/v11/login-adapter";
import {
  resolveContactTokenReceiverAdapter,
  resolveContactTokenSenderAdapter,
  resolveLoginAdapter,
  resolveProviderIdentityAdapter,
  resolveWebappShareFlowReceiverAdapter,
  resolveWebappShareFlowSenderAdapter,
  type AdapterRef,
} from "../../support/adapters/registry";
import type { ActorRef, LoginAdapter } from "../../support/contracts/login";
import type { ScenarioCase } from "../../support/contracts/webapp-share";
import type { MatrixCellId } from "./matrix";

const senderActor: ActorRef = {
  id: "sender",
  usernameEnvKeys: ["sender_username"],
  passwordEnvKeys: ["sender_password"],
};

const receiverActor: ActorRef = {
  id: "receiver",
  usernameEnvKeys: ["receiver_username"],
  passwordEnvKeys: ["receiver_password"],
};

function parsePlatformVersionToken(token: string): AdapterRef {
  const idx = token.lastIndexOf("-");
  const platform = idx > 0 ? token.slice(0, idx) : "";
  const versionLine = idx > 0 ? token.slice(idx + 1) : "";

  if (platform.length === 0 || versionLine.length === 0) {
    throw new Error(
      [
        `[webapp-share] Invalid case token "${token}".`,
        'Expected "<platform>-<versionLine>", for example "nextcloud-v35".',
      ].join(" "),
    );
  }

  return { platform, versionLine };
}

export type WebappShareLoginSlot = "sender" | "receiver";

export type WebappShareLoginBinding =
  | { kind: "cernbox-v11"; slot: WebappShareLoginSlot }
  | { kind: "registry" };

export function resolveWebappShareLoginBinding(
  ref: AdapterRef,
  slot: WebappShareLoginSlot,
): WebappShareLoginBinding {
  if (ref.platform === "cernbox" && ref.versionLine === "v11") {
    return { kind: "cernbox-v11", slot };
  }
  return { kind: "registry" };
}

function resolveWebappShareLogin(
  ref: AdapterRef,
  slot: WebappShareLoginSlot,
): LoginAdapter {
  const binding = resolveWebappShareLoginBinding(ref, slot);
  if (binding.kind === "cernbox-v11") {
    return createCernboxV11LoginAdapter(binding.slot);
  }
  return resolveLoginAdapter(ref);
}

function makeWebappShareCase(senderRef: AdapterRef, receiverRef: AdapterRef): ScenarioCase {
  return {
    id: `webapp-share__${senderRef.platform}-${senderRef.versionLine}__${receiverRef.platform}-${receiverRef.versionLine}`,
    sender: senderActor,
    receiver: receiverActor,
    senderLogin: resolveWebappShareLogin(senderRef, "sender"),
    receiverLogin: resolveWebappShareLogin(receiverRef, "receiver"),
    contactTokenSender: resolveContactTokenSenderAdapter(senderRef),
    contactTokenReceiver: resolveContactTokenReceiverAdapter(receiverRef),
    receiverIdentity: resolveProviderIdentityAdapter(receiverRef),
    senderAdapter: resolveWebappShareFlowSenderAdapter(senderRef),
    receiverAdapter: resolveWebappShareFlowReceiverAdapter(receiverRef),
  };
}

export function resolveWebappShareScenarioCase(caseId: MatrixCellId): ScenarioCase {
  const parts = caseId.split("__");
  if (parts.length !== 3 || parts[0] !== "webapp-share") {
    throw new Error(
      [
        `[webapp-share] proof_cell="${caseId}" is not a webapp-share case id.`,
        'Expected "webapp-share__<senderPlatform>-<senderVersionLine>__<receiverPlatform>-<receiverVersionLine>".',
      ].join(" "),
    );
  }

  const senderRef = parsePlatformVersionToken(parts[1] ?? "");
  const receiverRef = parsePlatformVersionToken(parts[2] ?? "");
  return { ...makeWebappShareCase(senderRef, receiverRef), id: caseId };
}
