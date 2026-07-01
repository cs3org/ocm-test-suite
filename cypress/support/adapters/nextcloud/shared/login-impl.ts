/// <reference types="cypress" />

import type { LoginAdapter } from "../../../contracts/login";
import { captureSameOriginLoginPageReadyEvidence } from "../../../shared/evidence";
import {
  assertNextcloudLoggedIn,
  loginNextcloudViaUi,
  openNextcloudLoginPage,
  submitNextcloudLoginForm,
} from "./login";

export type NextcloudLoginVersion = "v32" | "v33" | "v34";

export function createNextcloudLoginAdapter(
  version: NextcloudLoginVersion,
): LoginAdapter {
  return {
    mechanism: "same-origin",
    key: `nextcloud/${version}`,
    openLoginPage() {
      openNextcloudLoginPage();
    },
    captureLoginPageReadyEvidence(scenarioId) {
      captureSameOriginLoginPageReadyEvidence(scenarioId);
    },
    submitLogin(credentials) {
      submitNextcloudLoginForm(credentials);
    },
    login(credentials) {
      loginNextcloudViaUi(credentials);
    },
    assertLoggedIn() {
      assertNextcloudLoggedIn();
    },
  };
}
