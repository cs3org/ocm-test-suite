/// <reference types="cypress" />

import {
  resolveLoginAdapter,
  resolveShareWithReceiverAdapter,
  resolveShareWithSenderAdapter,
  type AdapterRef,
} from "../../support/adapters/registry";
import type { ActorRef, ScenarioCase } from "../../support/contracts/share-with";
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
        `[share-with] Invalid case token "${token}".`,
        'Expected "<platform>-<versionLine>", for example "nextcloud-v32".',
      ].join(" "),
    );
  }

  return { platform, versionLine };
}

function makeShareWithCase(senderRef: AdapterRef, receiverRef: AdapterRef): ScenarioCase {
  return {
    id: `share-with__${senderRef.platform}-${senderRef.versionLine}__${receiverRef.platform}-${receiverRef.versionLine}`,
    senderAdapter: resolveShareWithSenderAdapter(senderRef),
    receiverAdapter: resolveShareWithReceiverAdapter(receiverRef),
    senderLogin: resolveLoginAdapter(senderRef),
    receiverLogin: resolveLoginAdapter(receiverRef),
    sender: senderActor,
    receiver: receiverActor,
  };
}

export function resolveShareWithScenarioCase(caseId: MatrixCellId): ScenarioCase {
  const parts = caseId.split("__");
  if (parts.length !== 3 || parts[0] !== "share-with") {
    throw new Error(
      [
        `[share-with] proof_cell="${caseId}" is not a share-with case id.`,
        'Expected "share-with__<senderPlatform>-<senderVersionLine>__<receiverPlatform>-<receiverVersionLine>".',
      ].join(" "),
    );
  }

  const senderRef = parsePlatformVersionToken(parts[1] ?? "");
  const receiverRef = parsePlatformVersionToken(parts[2] ?? "");
  return { ...makeShareWithCase(senderRef, receiverRef), id: caseId };
}
