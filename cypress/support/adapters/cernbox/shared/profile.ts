export interface CernboxFilesSelectors {
  webContent: string;
  appSwitcherButton: string;
  filesAppMenuItem: string;
  filesView: string;
  filesViewSentinels: string;
  resourceByName: (escapedName: string) => string;
  openFileContextMenuTrigger: string;
  openFileContextDownloadAction: string;
  fab: string;
  fabDrop: string;
  newTextFileMenuItem: string;
  modal: string;
  modalInput: string;
  modalConfirm: string;
  editorRouteFragment: string;
  editorWrapper: string;
  editorContent: string;
  saveButton: string;
}

export interface CernboxSharingSelectors {
  resourceActionDropdown: (escapedName: string) => string;
  contextMenu: string;
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

export interface CernboxNetwork {
  webdavSpacesGlob: string;
  webdavPutCreateStatus: number;
  webdavPutSaveStatus: number;
  webdavPropfindStatus: number;
  graphUserSearchGlob: string;
  graphInviteGlob: string;
  graphListPermissionsGlob: string;
}

export interface CernboxProfile {
  selectors: {
    files: CernboxFilesSelectors;
    sharing: CernboxSharingSelectors;
  };
  network: CernboxNetwork;
}
