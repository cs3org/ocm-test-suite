/// <reference types="cypress" />

import type { ExternalIdpLoginAdapter } from "../../../contracts/login";
import {
  assertCernboxLoggedIn,
  completeCernboxAppLogin,
  establishCernboxIdpSession,
  type CernboxIdpSlot,
} from "../shared/login";

export function createCernboxV11LoginAdapter(
  slot: CernboxIdpSlot,
): ExternalIdpLoginAdapter {
  return {
    mechanism: "external-idp",
    key: "cernbox/v11",
    establishIdpSession(credentials, scenarioId) {
      establishCernboxIdpSession(credentials, { slot, scenarioId });
    },
    completeAppLogin() {
      completeCernboxAppLogin();
    },
    login(credentials) {
      establishCernboxIdpSession(credentials, { slot });
      completeCernboxAppLogin();
      assertCernboxLoggedIn();
    },
    assertLoggedIn() {
      assertCernboxLoggedIn();
    },
  };
}

// Default registry login adapter: sender slot (one-party / manual runs).
export const cernboxV11LoginAdapter = createCernboxV11LoginAdapter("sender");
