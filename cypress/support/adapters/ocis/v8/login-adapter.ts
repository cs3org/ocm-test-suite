/// <reference types="cypress" />

import type { LoginAdapter } from "../../../contracts/login";
import { captureSameOriginLoginPageReadyEvidence } from "../../../shared/evidence";
import {
  assertOcisLoggedIn,
  loginOcisViaUi,
  openOcisLoginPage,
  submitOcisLoginForm,
} from "../shared/login";

export const ocisV8LoginAdapter: LoginAdapter = {
  mechanism: "same-origin",
  key: "ocis/v8",
  openLoginPage() {
    openOcisLoginPage();
  },
  captureLoginPageReadyEvidence(scenarioId) {
    captureSameOriginLoginPageReadyEvidence(scenarioId);
  },
  submitLogin(credentials) {
    submitOcisLoginForm(credentials);
  },
  login(credentials) {
    loginOcisViaUi(credentials);
  },
  assertLoggedIn() {
    assertOcisLoggedIn();
  },
};
