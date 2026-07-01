/// <reference types="cypress" />

import type { LoginAdapter } from "../../../contracts/login";
import { captureSameOriginLoginPageReadyEvidence } from "../../../shared/evidence";
import {
  assertOpenCloudLoggedIn,
  loginOpenCloudViaUi,
  openOpenCloudLoginPage,
  submitOpenCloudLoginForm,
} from "../shared/login";

export const opencloudV6LoginAdapter: LoginAdapter = {
  mechanism: "same-origin",
  key: "opencloud/v6",
  openLoginPage() {
    openOpenCloudLoginPage();
  },
  captureLoginPageReadyEvidence(scenarioId) {
    captureSameOriginLoginPageReadyEvidence(scenarioId);
  },
  submitLogin(credentials) {
    submitOpenCloudLoginForm(credentials);
  },
  login(credentials) {
    loginOpenCloudViaUi(credentials);
  },
  assertLoggedIn() {
    assertOpenCloudLoggedIn();
  },
};
