export function parseRemoteHostFromFederatedRecipientId(
  federatedRecipientId: string,
): string {
  const afterAt =
    federatedRecipientId.split("@").at(-1) ?? federatedRecipientId;
  const withoutProtocol = afterAt.replace(/^https?:\/\//, "");
  const hostAndMaybePath = withoutProtocol.split("/")[0] ?? withoutProtocol;
  return hostAndMaybePath.trim();
}

// Returns the user/search portion of a federated recipient ID by cutting at
// the last "@". Usernames containing "@" (e.g. mahdi@dev@pondersource.com@host) are
// handled correctly: mahdi@dev@pondersource.com@ocis2.docker -> mahdi@dev@pondersource.com.
export function parseSearchTermFromFederatedRecipientId(
  federatedRecipientId: string,
): string {
  const lastAt = federatedRecipientId.lastIndexOf("@");
  if (lastAt <= 0) {
    return federatedRecipientId;
  }
  return federatedRecipientId.slice(0, lastAt);
}
