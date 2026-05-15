import type { OcisProfile } from "../shared/profile";

export const ocisV8Profile: OcisProfile = {
  selectors: {
    files: {
      webContent: "#web-content",
      // The underscore in _appSwitcherButton is oCIS-specific; the id was
      // prefixed with an underscore in ownCloud Web to avoid a CSS id clash.
      appSwitcherButton: "nav#applications-menu button#_appSwitcherButton",
      filesAppMenuItem:
        'nav#applications-menu a[data-test-id="app.files.menuItem"]',
      filesView: "#files-view, .files-view-wrapper",
      filesViewSentinels:
        "#files-view, .files-view-wrapper, [data-test-resource-type], .files-list__table",
      // The inline <resource-name> component renders data-test-resource-name on
      // both table rows and tile cards in v12.3.2 (ResourceName.vue:6).
      resourceByName: (n) => `[data-test-resource-name="${n}"]`,
      openFileContextMenuTrigger: "#oc-openfile-contextmenu-trigger",
      openFileContextDownloadAction:
        "#oc-openfile-contextmenu .oc-files-actions-download-file-trigger",
      newFileMenuButton: "button#new-file-menu-btn",
      newFileMenuDrop: "div#new-file-menu-drop",
      // Locale-independent class hook: the class is constructed as
      // `new-file-btn-${fileAction.ext}` at CreateAndUpload.vue:53.
      newTextFileMenuItem: ".new-file-btn-txt",
      modal: '[role="dialog"]',
      // OcTextInput.vue:177 uses uniqueId('oc-textinput-') to build the id.
      modalInput: 'input[id^="oc-textinput"]',
      modalConfirm: ".oc-modal-body-actions-confirm",
      editorRouteFragment: "/text-editor/",
      editorWrapper: ".oc-text-editor",
      // v12.3.2 ships md-editor-v3 + CodeMirror 6; the editable area is
      // `#text-editor-container .cm-content`. No ProseMirror fallback needed.
      editorContent: "#text-editor-container .cm-content",
      saveButton: "button#app-save-action",
    },
    sharing: {
      // resourceActionDropdown returns the resource-name element selector.
      // ContextMenuQuickAction.vue in v12.3.2 does not carry
      // data-test-context-menu-resource-name, so helper code walks from this
      // element to its containing row or tile card via closest()/within().
      resourceActionDropdown: (escapedName) =>
        `[data-test-resource-name="${escapedName}"]`,
      // Table rows render as `tr`; tile cards carry class `oc-tiles-item`
      // (ResourceTiles.vue:32). Both contain the action-dropdown button.
      resourceContainerSelector: "tr, .oc-tiles-item",
      // Both view-mode action-dropdown classes are verified at v12.3.2
      // (ResourceTable.vue:235 and ResourceTiles.vue:88).
      actionDropdownButton:
        ".resource-table-btn-action-dropdown, .resource-tiles-btn-action-dropdown",
      contextMenu: "#oc-files-context-menu",
      // Inline quick-action rendered by QuickActions.vue as
      // files-quick-action-${action.name}; name is "show-shares"
      // (useFileActionsShowShares.ts). Locale-independent.
      quickActionShowShares: ".files-quick-action-show-shares",
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
    // oCIS does not route DAV through remote.php; that path belongs to the
    // ownCloud-era DAV stack that oCIS dropped.
    webdavSpacesGlob: "**/dav/spaces/**",
    webdavPutCreateStatus: 201,
    webdavPutSaveStatus: 204,
    webdavPropfindStatus: 207,
    graphUserSearchGlob: "**/graph/v1.0/users?*",
    graphInviteGlob: "**/graph/**/invite",
    graphListPermissionsGlob:
      "**/graph/v1beta1/drives/**/items/**/permissions**",
  },
};
