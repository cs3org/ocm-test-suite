"use strict";
/// <reference types="cypress" />
Object.defineProperty(exports, "__esModule", { value: true });
exports.nextcloudV32LoginAdapter = void 0;
var login_1 = require("../shared/login");
exports.nextcloudV32LoginAdapter = {
    key: "nextcloud/v32",
    login: function (credentials) {
        (0, login_1.loginNextcloudViaUi)(credentials);
    },
    assertLoggedIn: function () {
        (0, login_1.assertNextcloudLoggedIn)();
    },
};
