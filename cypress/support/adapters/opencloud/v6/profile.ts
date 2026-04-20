import type { OpenCloudProfile } from "../shared/profile";

export const opencloudV6Profile: OpenCloudProfile = {
  selectors: {
    files: {
      webContent: "#web-content",
      appSwitcherButton: "nav#applications-menu button#_appSwitcherButton",
      filesAppMenuItem:
        'nav#applications-menu a[data-test-id="app.files.menuItem"]',
      filesView: "#files-view, .files-view-wrapper",
      filesViewSentinels:
        "#files-view, .files-view-wrapper, [data-test-resource-type], .files-list__table",
      resourceByName: (n) =>
        `:is(#files-files-table, .oc-tiles-item, #files-shared-with-me-accepted-section, .files-table) [data-test-resource-name="${n}"]`,
      openFileContextMenuTrigger: "#oc-openfile-contextmenu-trigger",
      openFileContextDownloadAction:
        "#oc-openfile-contextmenu .oc-files-actions-download-file-trigger",
      fab: ".oc-app-floating-action-button",
      fabDrop: "#create-or-upload-drop",
      newTextFileMenuItem: ".new-file-btn-txt",
      modal: ".oc-modal",
      modalInput: ".oc-modal input",
      modalConfirm: ".oc-modal-body-actions-confirm",
      editorRouteFragment: "/text-editor/",
      editorWrapper: ".oc-text-editor",
      // v6.1.0 ships md-editor-v3 + CodeMirror 6. The editable content area
      // is `#text-editor-container .cm-content`. v7 will swap to Tiptap and
      // a future v7/profile.ts will override this to
      // `.text-editor-provider .ProseMirror`.
      editorContent: "#text-editor-container .cm-content",
      saveButton: "button#app-save-action",
    },
    sharing: {
      // View-agnostic per-resource action-dropdown selector. Matches the same
      // conceptual button in both list/table view and tile view via
      // data-test-context-menu-resource-name plus either action-dropdown class.
      resourceActionDropdown: (n) =>
        `button[data-test-context-menu-resource-name="${n}"].resource-tiles-btn-action-dropdown, button[data-test-context-menu-resource-name="${n}"].resource-table-btn-action-dropdown`,
      contextMenu: "#oc-files-context-menu",
      // Note: v6.1.0 names this `show-shares-trigger` (plural). NOT `show-sharing-trigger`.
      showSharesAction: ".oc-files-actions-show-shares-trigger",
      enableSyncAction: ".oc-files-actions-enable-sync-trigger",
      sharingSidebar: "div#oc-files-sharing-sidebar",
      inviteRoleTypeFilter: ".invite-form-share-role-type",
      inviteRoleTypePill: ".invite-form-share-role-type .oc-pill",
      inviteRoleTypeItem: ".invite-form-share-role-type-item",
      externalUsersLabel: "External users",
      inviteInput: "input#files-share-invite-input",
      recipientListbox: 'ul[role="listbox"]',
      recipientItemPreferred: '[data-testid^="recipient-autocomplete-item-"]',
      recipientItemFallback: '[role="option"], li',
      createShareButton: "button#new-collaborators-form-create-button",
      shareSuccessText: "Share was added successfully",
      collaboratorsList: "#files-collaborators-list",
      webNavSidebar: "div#web-nav-sidebar",
      sharesNavLabel: "Shares",
      receivedResourceByName: (n) => `span[data-test-resource-name="${n}"]`,
    },
  },
  network: {
    webdavSpacesGlob: "**/remote.php/dav/spaces/**",
    webdavPutCreateStatus: 201,
    webdavPutSaveStatus: 204,
    webdavPropfindStatus: 207,
    graphUserSearchGlob: "**/graph/v1.0/users?*",
    graphInviteGlob: "**/graph/**/invite",
    graphListPermissionsGlob:
      "**/graph/v1beta1/drives/**/items/**/permissions**",
  },
};
