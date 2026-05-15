// Deterministic content written into every test-created share file.
// All sender adapters use this; all receiver content assertions check for it.
export function expectedFileContent(sharedFileName: string): string {
  return `OCM Test Suite shared file: ${sharedFileName}`;
}
