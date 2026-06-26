/// <reference types="cypress" />

import type { LoginAdapter } from "../../../contracts/login";
import {
  assertCernboxLoggedIn,
  loginCernboxViaUi,
  openCernboxLoginPage,
  submitCernboxLoginForm,
} from "../shared/login";

export const cernboxV11LoginAdapter: LoginAdapter = {
  key: "cernbox/v11",
  openLoginPage() {
    openCernboxLoginPage();
  },
  submitLogin(credentials) {
    submitCernboxLoginForm(credentials);
  },
  login(credentials) {
    loginCernboxViaUi(credentials);
  },
  assertLoggedIn() {
    assertCernboxLoggedIn();
  },
};
