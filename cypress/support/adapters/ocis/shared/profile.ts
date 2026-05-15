export interface OcisFilesSelectors {
  webContent: string;
  appSwitcherButton: string;
  filesAppMenuItem: string;
  filesView: string;
  filesViewSentinels: string;
  resourceByName: (escapedName: string) => string;
  openFileContextMenuTrigger: string;
  openFileContextDownloadAction: string;
  newFileMenuButton: string;
  newFileMenuDrop: string;
  newTextFileMenuItem: string;
  modal: string;
  modalInput: string;
  modalConfirm: string;
  editorRouteFragment: string;
  editorWrapper: string;
  editorContent: string;
  saveButton: string;
}

export interface OcisSharingSelectors {
  // Returns the [data-test-resource-name] element selector; helper code walks
  // to the action-dropdown button via closest()/within() because v12.3.2
  // ContextMenuQuickAction.vue does not carry data-test-context-menu-resource-name.
  resourceActionDropdown: (escapedName: string) => string;
  resourceContainerSelector: string;
  actionDropdownButton: string;
  contextMenu: string;
  // Inline quick-action class from QuickActions.vue: files-quick-action-${action.name}.
  // Locale-independent; present whenever the row renders quick actions in table view.
  quickActionShowShares: string;
  showSharesAction: string;
  enableSyncAction: string;
  sharingSidebar: string;
  inviteRoleTypeFilter: string;
  inviteRoleTypePill: string;
  inviteRoleTypeItem: string;
  externalUsersLabel: string;
  inviteInput: string;
  recipientListbox: string;
  recipientItemPreferred: string;
  recipientItemFallback: string;
  createShareButton: string;
  shareSuccessText: string;
  collaboratorsList: string;
  webNavSidebar: string;
  sharesNavLabel: string;
  receivedResourceByName: (escapedName: string) => string;
}

export interface OcisNetwork {
  webdavSpacesGlob: string;
  webdavPutCreateStatus: number;
  webdavPutSaveStatus: number;
  webdavPropfindStatus: number;
  graphUserSearchGlob: string;
  graphInviteGlob: string;
  graphListPermissionsGlob: string;
}

export interface OcisProfile {
  selectors: {
    files: OcisFilesSelectors;
    sharing: OcisSharingSelectors;
  };
  network: OcisNetwork;
}
