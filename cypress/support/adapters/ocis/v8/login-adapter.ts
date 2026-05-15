/// <reference types="cypress" />

import type { LoginAdapter } from "../../../contracts/login";
import {
  assertOcisLoggedIn,
  loginOcisViaUi,
  openOcisLoginPage,
  submitOcisLoginForm,
} from "../shared/login";

export const ocisV8LoginAdapter: LoginAdapter = {
  key: "ocis/v8",
  openLoginPage() {
    openOcisLoginPage();
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
