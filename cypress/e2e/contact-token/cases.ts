/// <reference types="cypress" />

import { createCernboxV11LoginAdapter } from "../../support/adapters/cernbox/v11/login-adapter";
import {
  resolveContactTokenReceiverAdapter,
  resolveContactTokenSenderAdapter,
  resolveLoginAdapter,
  resolveProviderIdentityAdapter,
  resolveShareFileReceiverAdapter,
  resolveShareFileSenderAdapter,
  type AdapterRef,
} from "../../support/adapters/registry";
import type {
  ContactTokenReceiverAdapter,
  ContactTokenSenderAdapter,
  ProviderIdentityAdapter,
} from "../../support/contracts/contact";
import type { ActorRef } from "../../support/contracts/login";
import type {
  ShareFileReceiverAdapter,
  ShareFileSenderAdapter,
} from "../../support/contracts/share-file";
import type { LoginAdapter } from "../../support/contracts/login";
import type { MatrixCellId } from "./matrix";

export type ScenarioCase = {
  id: string;
  sender: ActorRef;
  receiver: ActorRef;
  senderLogin: LoginAdapter;
  receiverLogin: LoginAdapter;
  senderShareFile: ShareFileSenderAdapter;
  receiverShareFile: ShareFileReceiverAdapter;
  contactTokenSender: ContactTokenSenderAdapter;
  contactTokenReceiver: ContactTokenReceiverAdapter;
  receiverIdentity: ProviderIdentityAdapter;
};

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
        `[contact-token] Invalid case token "${token}".`,
        'Expected "<platform>-<versionLine>", for example "nextcloud-v34".',
      ].join(" "),
    );
  }

  return { platform, versionLine };
}

export type ContactTokenLoginSlot = "sender" | "receiver";

export type ContactTokenLoginBinding =
  | { kind: "cernbox-v11"; slot: ContactTokenLoginSlot }
  | { kind: "registry" };

// Pure slot routing for unit tests; mirrors resolveContactTokenLogin decisions.
export function resolveContactTokenLoginBinding(
  ref: AdapterRef,
  slot: ContactTokenLoginSlot,
): ContactTokenLoginBinding {
  if (ref.platform === "cernbox" && ref.versionLine === "v11") {
    return { kind: "cernbox-v11", slot };
  }
  return { kind: "registry" };
}

export function resolveContactTokenCaseLoginBindings(
  senderRef: AdapterRef,
  receiverRef: AdapterRef,
): {
  sender: ContactTokenLoginBinding;
  receiver: ContactTokenLoginBinding;
} {
  return {
    sender: resolveContactTokenLoginBinding(senderRef, "sender"),
    receiver: resolveContactTokenLoginBinding(receiverRef, "receiver"),
  };
}

function resolveContactTokenLogin(
  ref: AdapterRef,
  slot: ContactTokenLoginSlot,
): LoginAdapter {
  const binding = resolveContactTokenLoginBinding(ref, slot);
  if (binding.kind === "cernbox-v11") {
    return createCernboxV11LoginAdapter(binding.slot);
  }
  return resolveLoginAdapter(ref);
}

function makeContactTokenCase(senderRef: AdapterRef, receiverRef: AdapterRef): ScenarioCase {
  return {
    id: `contact-token__${senderRef.platform}-${senderRef.versionLine}__${receiverRef.platform}-${receiverRef.versionLine}`,
    sender: senderActor,
    receiver: receiverActor,
    senderLogin: resolveContactTokenLogin(senderRef, "sender"),
    receiverLogin: resolveContactTokenLogin(receiverRef, "receiver"),
    senderShareFile: resolveShareFileSenderAdapter(senderRef),
    receiverShareFile: resolveShareFileReceiverAdapter(receiverRef),
    contactTokenSender: resolveContactTokenSenderAdapter(senderRef),
    contactTokenReceiver: resolveContactTokenReceiverAdapter(receiverRef),
    receiverIdentity: resolveProviderIdentityAdapter(receiverRef),
  };
}

export function resolveContactTokenScenarioCase(
  caseId: MatrixCellId,
): ScenarioCase {
  const parts = caseId.split("__");
  if (parts.length !== 3 || parts[0] !== "contact-token") {
    throw new Error(
      [
        `[contact-token] proof_cell="${caseId}" is not a contact-token case id.`,
        'Expected "contact-token__<senderPlatform>-<senderVersionLine>__<receiverPlatform>-<receiverVersionLine>".',
      ].join(" "),
    );
  }

  const senderRef = parsePlatformVersionToken(parts[1] ?? "");
  const receiverRef = parsePlatformVersionToken(parts[2] ?? "");
  return { ...makeContactTokenCase(senderRef, receiverRef), id: caseId };
}
