/// <reference types="cypress" />

import type { LoginAdapter } from "../../../contracts/login";
import {
  assertNextcloudLoggedIn,
  loginNextcloudViaUi,
  openNextcloudLoginPage,
  submitNextcloudLoginForm,
} from "../shared/login";

export const nextcloudV34LoginAdapter: LoginAdapter = {
  key: "nextcloud/v34",
  openLoginPage() {
    openNextcloudLoginPage();
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
