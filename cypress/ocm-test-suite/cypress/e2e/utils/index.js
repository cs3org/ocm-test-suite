// CERNBox
import * as cernbox2 from './cernbox/v2/interface.js';
// Nextcloud
import * as nc27 from './nextcloud/v27/interface.js';
import * as nc28 from './nextcloud/v28/interface.js';
import * as nc29 from './nextcloud/v29/interface.js';
import * as nc30 from './nextcloud/v30/interface.js';
import * as nc31 from './nextcloud/v31/interface.js';
import * as nc32 from './nextcloud/v32/interface.js';
import * as nc33 from './nextcloud/v33/interface.js';
// oCIS
import * as ocis5 from './ocis/v5/interface.js';
import * as ocis7 from './ocis/v7/interface.js';
// OpenCloud 
import * as opencloud2 from './opencloud/v2/interface.js';
// OcmStub
import * as os1 from './ocmstub/v1/interface.js';
// ownCloud
import * as oc10 from './owncloud/v10/interface.js';
// Seafile
import * as sf11 from './seafile/v11/interface.js';

const REGISTRY = new Map();

/**
 * Registers a util module (called at module-load time).
 * Also registers any versionAliases exported by the module.
 */
function register(mod) {
  const { platform, version, versionAliases } = mod;
  if (!platform || !version)
    throw new Error('Util file must export { platform, version } metadata');

  if (!REGISTRY.has(platform)) REGISTRY.set(platform, new Map());
  REGISTRY.get(platform).set(String(version), mod);

  // Register version aliases if provided
  if (Array.isArray(versionAliases)) {
    versionAliases.forEach(alias => {
      REGISTRY.get(platform).set(String(alias), mod);
    });
  }
}

// One-liners — pull them up-front
[
  cernbox2,
  nc27,
  nc28,
  nc29,
  nc30,
  nc31,
  nc32,
  nc33,
  ocis5,
  ocis7,
  opencloud2,
  os1,
  oc10,
  sf11
].forEach(register);

/**
 * @param {string} platform  e.g. 'nextcloud'
 * @param {string|number} version e.g. 'v29'
 * @returns {Record<string,Function>}
 */
export function getUtils(platform, version) {
  const platMap = REGISTRY.get(String(platform));
  if (!platMap) throw new Error(`Unknown platform “${platform}”`);

  const mod = platMap.get(String(version));
  if (!mod) throw new Error(`Unsupported ${platform} version ${version}`);

  // Optional: fail fast if a util is missing in the module
  return new Proxy(mod, {
    get(t, prop) {
      if (!(prop in t))
        throw new Error(`${platform} ${version} lacks function ${String(prop)}`);
      return t[prop];
    },
  });
}
