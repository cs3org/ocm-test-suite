/// <reference types="cypress" />

import type { LoginAdapter } from "../contracts/login";
import type {
  ContactTokenReceiverAdapter,
  ContactTokenSenderAdapter,
  ContactWayfReceiverAdapter,
  ContactWayfSenderAdapter,
  ProviderIdentityAdapter,
} from "../contracts/contact";
import type {
  ShareWithFlowReceiverAdapter,
  ShareWithFlowSenderAdapter,
} from "../contracts/share-with";
import type {
  WebappShareFlowReceiverAdapter,
  WebappShareFlowSenderAdapter,
} from "../contracts/webapp-share";
import type {
  ShareFileReceiverAdapter,
  ShareFileSenderAdapter,
} from "../contracts/share-file";
import { ocmgoV1LoginAdapter } from "./ocmgo/v1/login-adapter";
import {
  ocmgoV1ShareFileReceiverAdapter,
  ocmgoV1ShareWithFlowReceiverAdapter,
} from "./ocmgo/v1/share-with-receiver-adapter";
import {
  ocmgoV1ShareFileSenderAdapter,
  ocmgoV1ShareWithFlowSenderAdapter,
} from "./ocmgo/v1/share-with-sender-adapter";
import { ocisV8LoginAdapter } from "./ocis/v8/login-adapter";
import {
  ocisV8ContactTokenReceiverAdapter,
  ocisV8ContactTokenSenderAdapter,
  ocisV8ProviderIdentityAdapter,
} from "./ocis/v8/contact-adapter";
import {
  ocisV8ShareFileReceiverAdapter,
  ocisV8ShareFileSenderAdapter,
} from "./ocis/v8/share-file-adapter";
import { opencloudV6LoginAdapter } from "./opencloud/v6/login-adapter";
import {
  opencloudV6ContactTokenReceiverAdapter,
  opencloudV6ContactTokenSenderAdapter,
  opencloudV6ProviderIdentityAdapter,
} from "./opencloud/v6/contact-adapter";
import {
  opencloudV6ShareFileReceiverAdapter,
  opencloudV6ShareFileSenderAdapter,
} from "./opencloud/v6/share-file-adapter";
import { nextcloudV32LoginAdapter } from "./nextcloud/v32/login-adapter";
import {
  nextcloudV32ShareFileReceiverAdapter,
  nextcloudV32ShareFileSenderAdapter,
  nextcloudV32ShareWithFlowReceiverAdapter,
  nextcloudV32ShareWithFlowSenderAdapter,
} from "./nextcloud/v32/share-with-adapter";
import { nextcloudV33LoginAdapter } from "./nextcloud/v33/login-adapter";
import {
  nextcloudV33ShareFileReceiverAdapter,
  nextcloudV33ShareFileSenderAdapter,
  nextcloudV33ShareWithFlowReceiverAdapter,
  nextcloudV33ShareWithFlowSenderAdapter,
} from "./nextcloud/v33/share-with-adapter";
import {
  cernboxV11ContactTokenReceiverAdapter,
  cernboxV11ContactTokenSenderAdapter,
  cernboxV11ProviderIdentityAdapter,
} from "./cernbox/v11/contact-adapter";
import { cernboxV11LoginAdapter } from "./cernbox/v11/login-adapter";
import {
  cernboxV11ShareFileReceiverAdapter,
  cernboxV11ShareFileSenderAdapter,
} from "./cernbox/v11/share-file-adapter";
import { nextcloudV34LoginAdapter } from "./nextcloud/v34/login-adapter";
import { nextcloudV35LoginAdapter } from "./nextcloud/v35/login-adapter";
import {
  nextcloudV34ContactTokenReceiverAdapter,
  nextcloudV34ContactTokenSenderAdapter,
  nextcloudV34ContactWayfReceiverAdapter,
  nextcloudV34ContactWayfSenderAdapter,
  nextcloudV34ProviderIdentityAdapter,
} from "./nextcloud/v34/contact-adapter";
import {
  nextcloudV34ShareFileReceiverAdapter,
  nextcloudV34ShareFileSenderAdapter,
  nextcloudV34ShareWithFlowReceiverAdapter,
  nextcloudV34ShareWithFlowSenderAdapter,
} from "./nextcloud/v34/share-with-adapter";
import {
  nextcloudV35ContactTokenReceiverAdapter,
  nextcloudV35ContactTokenSenderAdapter,
  nextcloudV35ContactWayfReceiverAdapter,
  nextcloudV35ContactWayfSenderAdapter,
  nextcloudV35ProviderIdentityAdapter,
} from "./nextcloud/v35/contact-adapter";
import {
  nextcloudV35ShareFileReceiverAdapter,
  nextcloudV35ShareFileSenderAdapter,
  nextcloudV35ShareWithFlowReceiverAdapter,
  nextcloudV35ShareWithFlowSenderAdapter,
} from "./nextcloud/v35/share-with-adapter";
import {
  nextcloudV35WebappShareFlowReceiverAdapter,
  nextcloudV35WebappShareFlowSenderAdapter,
} from "./nextcloud/v35/webapp-share-adapter";
import { cernboxV11WebappShareFlowReceiverAdapter } from "./cernbox/v11/webapp-share-adapter";

export type AdapterRef = {
  platform: string;
  versionLine: string;
};

const loginAdapters: Record<string, Record<string, LoginAdapter>> = {
  nextcloud: {
    v32: nextcloudV32LoginAdapter,
    v33: nextcloudV33LoginAdapter,
    v34: nextcloudV34LoginAdapter,
    v35: nextcloudV35LoginAdapter,
  },
  ocmgo: {
    v1: ocmgoV1LoginAdapter,
  },
  ocis: {
    v8: ocisV8LoginAdapter,
  },
  opencloud: {
    v6: opencloudV6LoginAdapter,
  },
  cernbox: {
    v11: cernboxV11LoginAdapter,
  },
};

const shareWithFlowSenderAdapters: Record<string, Record<string, ShareWithFlowSenderAdapter>> = {
  nextcloud: {
    v32: nextcloudV32ShareWithFlowSenderAdapter,
    v33: nextcloudV33ShareWithFlowSenderAdapter,
    v34: nextcloudV34ShareWithFlowSenderAdapter,
    v35: nextcloudV35ShareWithFlowSenderAdapter,
  },
  ocmgo: {
    v1: ocmgoV1ShareWithFlowSenderAdapter,
  },
};

const webappShareFlowSenderAdapters: Record<
  string,
  Record<string, WebappShareFlowSenderAdapter>
> = {
  nextcloud: {
    v35: nextcloudV35WebappShareFlowSenderAdapter,
  },
};

const webappShareFlowReceiverAdapters: Record<
  string,
  Record<string, WebappShareFlowReceiverAdapter>
> = {
  cernbox: {
    v11: cernboxV11WebappShareFlowReceiverAdapter,
  },
  nextcloud: {
    v35: nextcloudV35WebappShareFlowReceiverAdapter,
  },
};

const shareWithFlowReceiverAdapters: Record<string, Record<string, ShareWithFlowReceiverAdapter>> = {
  nextcloud: {
    v32: nextcloudV32ShareWithFlowReceiverAdapter,
    v33: nextcloudV33ShareWithFlowReceiverAdapter,
    v34: nextcloudV34ShareWithFlowReceiverAdapter,
    v35: nextcloudV35ShareWithFlowReceiverAdapter,
  },
  ocmgo: {
    v1: ocmgoV1ShareWithFlowReceiverAdapter,
  },
};

const shareFileSenderAdapters: Record<string, Record<string, ShareFileSenderAdapter>> = {
  nextcloud: {
    v32: nextcloudV32ShareFileSenderAdapter,
    v33: nextcloudV33ShareFileSenderAdapter,
    v34: nextcloudV34ShareFileSenderAdapter,
    v35: nextcloudV35ShareFileSenderAdapter,
  },
  ocmgo: {
    v1: ocmgoV1ShareFileSenderAdapter,
  },
  ocis: {
    v8: ocisV8ShareFileSenderAdapter,
  },
  opencloud: {
    v6: opencloudV6ShareFileSenderAdapter,
  },
  cernbox: {
    v11: cernboxV11ShareFileSenderAdapter,
  },
};

const shareFileReceiverAdapters: Record<string, Record<string, ShareFileReceiverAdapter>> = {
  nextcloud: {
    v32: nextcloudV32ShareFileReceiverAdapter,
    v33: nextcloudV33ShareFileReceiverAdapter,
    v34: nextcloudV34ShareFileReceiverAdapter,
    v35: nextcloudV35ShareFileReceiverAdapter,
  },
  ocmgo: {
    v1: ocmgoV1ShareFileReceiverAdapter,
  },
  ocis: {
    v8: ocisV8ShareFileReceiverAdapter,
  },
  opencloud: {
    v6: opencloudV6ShareFileReceiverAdapter,
  },
  cernbox: {
    v11: cernboxV11ShareFileReceiverAdapter,
  },
};

const contactTokenSenderAdapters: Record<string, Record<string, ContactTokenSenderAdapter>> = {
  nextcloud: {
    v34: nextcloudV34ContactTokenSenderAdapter,
    v35: nextcloudV35ContactTokenSenderAdapter,
  },
  ocis: {
    v8: ocisV8ContactTokenSenderAdapter,
  },
  opencloud: {
    v6: opencloudV6ContactTokenSenderAdapter,
  },
  cernbox: {
    v11: cernboxV11ContactTokenSenderAdapter,
  },
};

const contactTokenReceiverAdapters: Record<string, Record<string, ContactTokenReceiverAdapter>> = {
  nextcloud: {
    v34: nextcloudV34ContactTokenReceiverAdapter,
    v35: nextcloudV35ContactTokenReceiverAdapter,
  },
  ocis: {
    v8: ocisV8ContactTokenReceiverAdapter,
  },
  opencloud: {
    v6: opencloudV6ContactTokenReceiverAdapter,
  },
  cernbox: {
    v11: cernboxV11ContactTokenReceiverAdapter,
  },
};

const contactWayfSenderAdapters: Record<string, Record<string, ContactWayfSenderAdapter>> = {
  nextcloud: {
    v34: nextcloudV34ContactWayfSenderAdapter,
    v35: nextcloudV35ContactWayfSenderAdapter,
  },
};

const contactWayfReceiverAdapters: Record<string, Record<string, ContactWayfReceiverAdapter>> = {
  nextcloud: {
    v34: nextcloudV34ContactWayfReceiverAdapter,
    v35: nextcloudV35ContactWayfReceiverAdapter,
  },
};

const providerIdentityAdapters: Record<string, Record<string, ProviderIdentityAdapter>> = {
  nextcloud: {
    v34: nextcloudV34ProviderIdentityAdapter,
    v35: nextcloudV35ProviderIdentityAdapter,
  },
  ocis: {
    v8: ocisV8ProviderIdentityAdapter,
  },
  opencloud: {
    v6: opencloudV6ProviderIdentityAdapter,
  },
  cernbox: {
    v11: cernboxV11ProviderIdentityAdapter,
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

export function resolveWebappShareFlowSenderAdapter(
  ref: AdapterRef,
): WebappShareFlowSenderAdapter {
  return resolveFromTable(
    "webapp-share-flow sender adapter",
    webappShareFlowSenderAdapters,
    ref,
  );
}

export function resolveWebappShareFlowReceiverAdapter(
  ref: AdapterRef,
): WebappShareFlowReceiverAdapter {
  return resolveFromTable(
    "webapp-share-flow receiver adapter",
    webappShareFlowReceiverAdapters,
    ref,
  );
}

export function resolveShareWithFlowSenderAdapter(ref: AdapterRef): ShareWithFlowSenderAdapter {
  return resolveFromTable("share-with-flow sender adapter", shareWithFlowSenderAdapters, ref);
}

export function resolveShareWithFlowReceiverAdapter(ref: AdapterRef): ShareWithFlowReceiverAdapter {
  return resolveFromTable("share-with-flow receiver adapter", shareWithFlowReceiverAdapters, ref);
}

export function resolveShareFileSenderAdapter(ref: AdapterRef): ShareFileSenderAdapter {
  return resolveFromTable("share-file sender adapter", shareFileSenderAdapters, ref);
}

export function resolveShareFileReceiverAdapter(ref: AdapterRef): ShareFileReceiverAdapter {
  return resolveFromTable("share-file receiver adapter", shareFileReceiverAdapters, ref);
}

export function resolveContactTokenSenderAdapter(ref: AdapterRef): ContactTokenSenderAdapter {
  return resolveFromTable("contact-token sender adapter", contactTokenSenderAdapters, ref);
}

export function resolveContactTokenReceiverAdapter(ref: AdapterRef): ContactTokenReceiverAdapter {
  return resolveFromTable("contact-token receiver adapter", contactTokenReceiverAdapters, ref);
}

export function resolveContactWayfSenderAdapter(ref: AdapterRef): ContactWayfSenderAdapter {
  return resolveFromTable("contact-wayf sender adapter", contactWayfSenderAdapters, ref);
}

export function resolveContactWayfReceiverAdapter(ref: AdapterRef): ContactWayfReceiverAdapter {
  return resolveFromTable("contact-wayf receiver adapter", contactWayfReceiverAdapters, ref);
}

export function resolveProviderIdentityAdapter(ref: AdapterRef): ProviderIdentityAdapter {
  return resolveFromTable("provider-identity adapter", providerIdentityAdapters, ref);
}
