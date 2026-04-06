/// <reference types="cypress" />

import type { LoginAdapter } from "../contracts/login";
import type {
  ShareWithReceiverAdapter,
  ShareWithSenderAdapter,
} from "../contracts/share-with";
import { ocmgoV1LoginAdapter } from "./ocmgo/v1/login-adapter";
import { ocmgoV1ShareWithReceiverAdapter } from "./ocmgo/v1/share-with-receiver-adapter";
import { ocmgoV1ShareWithSenderAdapter } from "./ocmgo/v1/share-with-sender-adapter";
import { nextcloudV32LoginAdapter } from "./nextcloud/v32/login-adapter";
import {
  nextcloudV32ShareWithReceiverAdapter,
  nextcloudV32ShareWithSenderAdapter,
} from "./nextcloud/v32/share-with-adapter";
import { nextcloudV33LoginAdapter } from "./nextcloud/v33/login-adapter";
import {
  nextcloudV33ShareWithReceiverAdapter,
  nextcloudV33ShareWithSenderAdapter,
} from "./nextcloud/v33/share-with-adapter";

export type AdapterRef = {
  platform: string;
  versionLine: string;
};

const loginAdapters: Record<string, Record<string, LoginAdapter>> = {
  nextcloud: {
    v32: nextcloudV32LoginAdapter,
    v33: nextcloudV33LoginAdapter,
  },
  ocmgo: {
    v1: ocmgoV1LoginAdapter,
  },
};

const shareWithSenderAdapters: Record<string, Record<string, ShareWithSenderAdapter>> = {
  nextcloud: {
    v32: nextcloudV32ShareWithSenderAdapter,
    v33: nextcloudV33ShareWithSenderAdapter,
  },
  ocmgo: {
    v1: ocmgoV1ShareWithSenderAdapter,
  },
};

const shareWithReceiverAdapters: Record<string, Record<string, ShareWithReceiverAdapter>> = {
  nextcloud: {
    v32: nextcloudV32ShareWithReceiverAdapter,
    v33: nextcloudV33ShareWithReceiverAdapter,
  },
  ocmgo: {
    v1: ocmgoV1ShareWithReceiverAdapter,
  },
};

function formatSupported(table: Record<string, Record<string, unknown>>): string {
  const entries: string[] = [];
  for (const platform of Object.keys(table).sort()) {
    const versions = Object.keys(table[platform] ?? {}).sort();
    for (const versionLine of versions) {
      entries.push(`${platform}-${versionLine}`);
    }
  }
  return entries.join(", ");
}

function resolveFromTable<T>(
  kind: string,
  table: Record<string, Record<string, T>>,
  ref: AdapterRef,
): T {
  const byPlatform = table[ref.platform];
  if (!byPlatform) {
    throw new Error(
      [
        `[registry] Unknown platform for ${kind}: "${ref.platform}".`,
        `Supported: ${formatSupported(table)}`,
      ].join(" "),
    );
  }

  const adapter = byPlatform[ref.versionLine];
  if (!adapter) {
    throw new Error(
      [
        `[registry] Unknown versionLine for ${kind}: "${ref.platform}-${ref.versionLine}".`,
        `Supported: ${formatSupported(table)}`,
      ].join(" "),
    );
  }

  return adapter;
}

export function resolveLoginAdapter(ref: AdapterRef): LoginAdapter {
  return resolveFromTable("login adapter", loginAdapters, ref);
}

export function resolveShareWithSenderAdapter(ref: AdapterRef): ShareWithSenderAdapter {
  return resolveFromTable("share-with sender adapter", shareWithSenderAdapters, ref);
}

export function resolveShareWithReceiverAdapter(ref: AdapterRef): ShareWithReceiverAdapter {
  return resolveFromTable("share-with receiver adapter", shareWithReceiverAdapters, ref);
}
