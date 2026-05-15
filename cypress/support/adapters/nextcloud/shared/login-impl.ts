/// <reference types="cypress" />

import type { LoginAdapter } from "../../../contracts/login";
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
    key: `nextcloud/${version}`,
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
}
