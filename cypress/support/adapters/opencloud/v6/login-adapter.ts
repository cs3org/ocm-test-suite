/// <reference types="cypress" />

import type { LoginAdapter } from "../../../contracts/login";
import {
  assertOpenCloudLoggedIn,
  loginOpenCloudViaUi,
  openOpenCloudLoginPage,
  submitOpenCloudLoginForm,
} from "../shared/login";

export const opencloudV6LoginAdapter: LoginAdapter = {
  key: "opencloud/v6",
  openLoginPage() {
    openOpenCloudLoginPage();
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
