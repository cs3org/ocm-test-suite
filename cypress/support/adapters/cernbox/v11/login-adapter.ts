/// <reference types="cypress" />

import type { LoginAdapter } from "../../../contracts/login";
import {
  assertCernboxLoggedIn,
  completeCernboxAppLogin,
  establishCernboxIdpSession,
} from "../shared/login";

export const cernboxV11LoginAdapter: LoginAdapter = {
  mechanism: "external-idp",
  key: "cernbox/v11",
  establishIdpSession(credentials, scenarioId) {
    establishCernboxIdpSession(credentials, scenarioId);
  },
  completeAppLogin() {
    completeCernboxAppLogin();
  },
  login(credentials) {
    establishCernboxIdpSession(credentials);
    completeCernboxAppLogin();
    assertCernboxLoggedIn();
  },
  assertLoggedIn() {
    assertCernboxLoggedIn();
  },
};
