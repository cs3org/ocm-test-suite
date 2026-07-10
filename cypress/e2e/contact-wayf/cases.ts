/// <reference types="cypress" />

import {
  resolveContactWayfReceiverAdapter,
  resolveContactWayfSenderAdapter,
  resolveLoginAdapter,
  resolveProviderIdentityAdapter,
  resolveShareFileReceiverAdapter,
  resolveShareFileSenderAdapter,
  type AdapterRef,
} from "../../support/adapters/registry";
import type { ActorRef } from "../../support/contracts/login";
import type { ScenarioCase } from "../../support/contracts/contact-wayf";
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
        `[contact-wayf] Invalid case token "${token}".`,
        'Expected "<platform>-<versionLine>", for example "nextcloud-v34".',
      ].join(" "),
    );
  }

  return { platform, versionLine };
}

function makeContactWayfCase(senderRef: AdapterRef, receiverRef: AdapterRef): ScenarioCase {
  return {
    id: `contact-wayf__${senderRef.platform}-${senderRef.versionLine}__${receiverRef.platform}-${receiverRef.versionLine}`,
    sender: senderActor,
    receiver: receiverActor,
    senderLogin: resolveLoginAdapter(senderRef),
    receiverLogin: resolveLoginAdapter(receiverRef),
    senderShareFile: resolveShareFileSenderAdapter(senderRef),
    receiverShareFile: resolveShareFileReceiverAdapter(receiverRef),
    contactWayfSender: resolveContactWayfSenderAdapter(senderRef),
    contactWayfReceiver: resolveContactWayfReceiverAdapter(receiverRef),
    receiverIdentity: resolveProviderIdentityAdapter(receiverRef),
  };
}

export function resolveContactWayfScenarioCase(
  caseId: MatrixCellId,
): ScenarioCase {
  const parts = caseId.split("__");
  if (parts.length !== 3 || parts[0] !== "contact-wayf") {
    throw new Error(
      [
        `[contact-wayf] proof_cell="${caseId}" is not a contact-wayf case id.`,
        'Expected "contact-wayf__<senderPlatform>-<senderVersionLine>__<receiverPlatform>-<receiverVersionLine>".',
      ].join(" "),
    );
  }

  const senderRef = parsePlatformVersionToken(parts[1] ?? "");
  const receiverRef = parsePlatformVersionToken(parts[2] ?? "");
  return { ...makeContactWayfCase(senderRef, receiverRef), id: caseId };
}
