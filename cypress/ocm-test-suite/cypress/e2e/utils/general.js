/**
 * @fileoverview
 * Utility functions for Cypress tests.
 *
 * @author Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
 */

export const revaBasedPlatforms = new Set(["nextcloud", "owncloud"]);
export const revaBasedWayfPlatforms = new Set([""]);
export const usernameContactPlatforms = new Set(["nextcloud", "owncloud"]);

/**
 * Escapes special characters in a string to be used in a CSS selector.
 * This is necessary because file names may contain characters that have special meanings in CSS selectors.
 *
 * @param {string} selector - The string to escape.
 * @returns {string} - The escaped string safe for use in a CSS selector.
 */
export function escapeCssSelector(selector) {
  // Replace any character that is a CSS selector special character with its escaped version
  return selector.replace(/([ !"#$%&'()*+,.\/:;<=>?@[\\\]^`{|}~])/g, "\\$1");
}

/**
 * Constructs a federated share URL based on the platform and provided parameters.
 * This function handles the URL construction for different platforms (Nextcloud, ownCloud).
 *
 * @param {Object} params - The parameters needed to construct the URL
 * @param {string} params.shareUrl - The original share URL to extract token from
 * @param {string} params.senderUrl - The URL of the sender's instance
 * @param {string} params.recipientUrl - The URL of the recipient's instance
 * @param {string} params.senderUsername - The username of the sender
 * @param {string} params.fileName - The name of the shared file
 * @param {string} params.platform - The platform type ('nextcloud' or 'owncloud')
 * @returns {string} The constructed federated share URL
 */
export function constructFederatedShareUrl(params) {
  const {
    shareUrl,
    senderUrl,
    recipientUrl,
    senderUsername,
    fileName,
    platform,
  } = params;

  // Extract token from the share URL
  const token = shareUrl.replace(`${senderUrl}/s/`, "");

  // Clean up URLs by ensuring they use https and removing trailing slashes
  const cleanSenderUrl = senderUrl
    .replace(/^https?:\/\//, "https://")
    .replace(/\/$/, "");
  const cleanRecipientUrl = recipientUrl
    .replace(/^https?:\/\//, "https://")
    .replace(/\/$/, "");

  // Construct the URL based on the platform
  if (platform === "owncloud") {
    return `${cleanRecipientUrl}/index.php/apps/files#remote=${cleanSenderUrl}&token=${token}&owner=${senderUsername}&ownerDisplayName=${senderUsername}&name=${fileName}&protected=0`;
  } else if (platform === "nextcloud") {
    return `${cleanRecipientUrl}/index.php/login?redirect_url=%252Findex.php%252Fapps%252Ffiles#remote=${cleanSenderUrl}&token=${token}&owner=${senderUsername}&ownerDisplayName=${senderUsername}&name=${fileName}&protected=0`;
  } else {
    throw new Error(`Unsupported platform: ${platform}`);
  }
}

/**
 * isBase64(str, { urlSafe = false } = {}) → boolean
 *
 * Accepts the RFC-4648 standard alphabet.
 * Optionally accepts the URL-safe variant ( - _ instead of + / ).
 * Ignores the amount of trailing '=' padding (0–2).
 */
export function isBase64(str, { urlSafe = false } = {}) {
  if (typeof str !== "string" || str.length === 0 || str.length % 4 !== 0)
    return false;

  const alphabet = urlSafe ? "A-Za-z0-9-_" : "A-Za-z0-9+/";

  // syntax check
  const syntax = new RegExp(
    `^(?:[${alphabet}]{4})*(?:[${alphabet}]{2}==|[${alphabet}]{3}=)?$`
  );
  if (!syntax.test(str)) return false;

  // semantic check with padding-insensitive compare
  try {
    const bytes =
      typeof Buffer === "function"
        ? Buffer.from(str, "base64")
        : Uint8Array.from(atob(str), (c) => c.charCodeAt(0));

    // if decoding produced nothing, reject (e.g. "====")
    if (!bytes.length) return false;

    const reencoded =
      typeof Buffer === "function"
        ? Buffer.from(bytes).toString("base64")
        : btoa(String.fromCharCode(...bytes));

    // strip both variants for a fair match
    const normalise = (s) =>
      (urlSafe ? s.replace(/\+/g, "-").replace(/\//g, "_") : s).replace(
        /=+$/,
        ""
      );

    return normalise(str) === normalise(reencoded);
  } catch {
    return false; // atob / Buffer threw – not Base64
  }
}

/**
 * encodeBase64(input, { urlSafe = false } = {}) → string
 *
 * Accepts:
 * string  – treated as UTF-8 text
 * Uint8Array / ArrayBuffer / Buffer – raw bytes
 */
export function encodeBase64(input, { urlSafe = false } = {}) {
  // convert to Uint8Array
  let bytes;
  if (typeof input === "string") {
    bytes = new TextEncoder().encode(input);
  } else if (input instanceof ArrayBuffer) {
    bytes = new Uint8Array(input);
  } else if (ArrayBuffer.isView(input)) {
    bytes = new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
  } else {
    throw new TypeError("Unsupported input type");
  }

  //  encode to Base64
  const b64 =
    typeof Buffer !== "undefined"
      ? Buffer.from(bytes).toString("base64")
      : btoa(Array.from(bytes, (b) => String.fromCharCode(b)).join(""));

  // URL-safe tweak
  return urlSafe
    ? b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
    : b64;
}
