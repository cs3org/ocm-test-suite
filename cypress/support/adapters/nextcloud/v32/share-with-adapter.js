"use strict";
/// <reference types="cypress" />
Object.defineProperty(exports, "__esModule", { value: true });
exports.nextcloudV32ShareWithReceiverAdapter = exports.nextcloudV32ShareWithSenderAdapter = void 0;
var files_1 = require("../shared/files");
var sharing_1 = require("../shared/sharing");
exports.nextcloudV32ShareWithSenderAdapter = {
    key: "nextcloud/v32",
    prepareShareFile: function (_a) {
        var _b = _a.sourceFileName, sourceFileName = _b === void 0 ? "welcome.txt" : _b, sharedFileName = _a.sharedFileName;
        (0, files_1.ensureFilesAppActive)();
        cy.log("prepare share file: ".concat(sourceFileName, " -> ").concat(sharedFileName));
        (0, files_1.ensureFileExists)(sourceFileName);
        (0, files_1.renameFile)(sourceFileName, sharedFileName);
        (0, files_1.ensureFileExists)(sharedFileName);
    },
    shareWithFederatedRecipient: function (_a) {
        var sharedFileName = _a.sharedFileName, federatedRecipientId = _a.federatedRecipientId;
        (0, files_1.ensureFilesAppActive)();
        cy.log("share ".concat(sharedFileName, " -> ").concat(federatedRecipientId));
        (0, sharing_1.openSharingPanel)(sharedFileName);
        (0, sharing_1.addExternalShare)(federatedRecipientId);
    },
};
exports.nextcloudV32ShareWithReceiverAdapter = {
    key: "nextcloud/v32",
    acceptIncomingShare: function (_a) {
        var sharedFileName = _a.sharedFileName;
        (0, files_1.ensureFilesAppLoadedForShareAcceptance)();
        (0, sharing_1.handleShareAcceptance)(sharedFileName, { remainingAttempts: 3 });
    },
};
