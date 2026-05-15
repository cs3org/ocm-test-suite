export function cssEscapeAttributeValue(value: string): string {
  // CSS attribute values are in double quotes in our selectors.
  return value.replaceAll("\\", "\\\\").replaceAll('"', '\\"');
}
