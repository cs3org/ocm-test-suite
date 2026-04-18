/// <reference types="cypress" />

import type { LoginAdapter } from "../../../contracts/login";
import {
  assertNextcloudLoggedIn,
  loginNextcloudViaUi,
  openNextcloudLoginPage,
  submitNextcloudLoginForm,
} from "../shared/login";

export const nextcloudV32LoginAdapter: LoginAdapter = {
  key: "nextcloud/v32",
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
