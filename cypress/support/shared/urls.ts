export function parseRemoteHostFromFederatedRecipientId(
  federatedRecipientId: string,
): string {
  const afterAt =
    federatedRecipientId.split("@").at(-1) ?? federatedRecipientId;
  const withoutProtocol = afterAt.replace(/^https?:\/\//, "");
  const hostAndMaybePath = withoutProtocol.split("/")[0] ?? withoutProtocol;
  return hostAndMaybePath.trim();
}
