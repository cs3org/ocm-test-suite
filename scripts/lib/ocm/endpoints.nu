# Focused OCM endpoint resolver.
# Reads config/matrix/platforms.nuon and produces provider records for
# stack.env consumption. Models ocm_host, webdav_host, and webdav_path
# separately and supports per-version-line overrides when present in
# the platforms manifest.

# Per-platform OCM endpoint defaults (path components only).
# Used only when the platform manifest carries no ocm_endpoints section.
# All paths include a trailing slash so callers can append sub-paths safely.
def platform-ocm-defaults [platform: string] {
    match $platform {
        "nextcloud" => {
            ocm_path: "/ocm/",
            webdav_path: "/remote.php/webdav/",
        },
        "ocis" => {
            ocm_path: "/ocm/",
            webdav_path: "/dav/",
        },
        "ocmgo" => {
            ocm_path: "/ocm/",
            webdav_path: "/webdav/",
        },
        _ => {
            ocm_path: "/ocm/",
            webdav_path: "/dav/",
        },
    }
}

# Map a host role to a fully-qualified hostname.
# Supported roles:
#   party      -> <platform><index>.docker  (default)
#   reva-party -> reva<platform><index>.docker
def role-to-host [role: string, platform: string, index: int] {
    match $role {
        "party" => $"($platform)($index).docker",
        "reva-party" => $"reva($platform)($index).docker",
        _ => {
            error make {msg: $"resolve-ocm-provider: unknown host role '($role)'; supported: party, reva-party"}
        }
    }
}

# Load and validate the platforms manifest from config/matrix/platforms.nuon.
# Errors on missing file, wrong schema_version, or missing platforms key.
def load-platforms-manifest [root: string] {
    let path = ($root | path join "config/matrix/platforms.nuon")
    if not ($path | path exists) {
        error make {msg: $"platforms manifest not found: ($path)"}
    }
    let raw = (open $path)
    if ($raw.schema_version? | default 0) != 1 {
        error make {msg: $"platforms manifest: unsupported schema_version (expected 1): ($path)"}
    }
    if ($raw.platforms? | default null) == null {
        error make {msg: $"platforms manifest missing required 'platforms' key: ($path)"}
    }
    $raw
}

# Resolve the OCM provider record for one party.
# Returns a record with name, full_name, organization, description, domain,
# homepage, ocm_endpoint, ocm_path, ocm_host, webdav_endpoint, webdav_path,
# webdav_host.
#
# - root: repo root (used to locate platforms.nuon)
# - platform: platform key (e.g. "nextcloud", "ocis", "ocmgo")
# - index: party hostname index (1 = sender, 2 = receiver)
# - version_line: optional version key (e.g. "v34"); enables per-version
#   overrides when the platforms manifest contains ocm_endpoints.version_lines.
#
# Resolution order for paths and host roles (highest wins):
#   manifest ocm_endpoints.version_lines.<vl>
#   > manifest ocm_endpoints.default
#   > hardcoded platform-ocm-defaults fallback (paths) / "party" role (hosts)
#
# Supported host roles (ocm_host_role, webdav_host_role):
#   party      -> <platform><index>.docker  (default)
#   reva-party -> reva<platform><index>.docker
#
# domain and homepage always use the party identity (<platform><index>.docker).
# ocm_host and webdav_host (and their endpoints) use the resolved role hosts.
export def resolve-ocm-provider [
    root: string,
    platform: string,
    index: int,
    version_line: string = "",
]: nothing -> record {
    let manifest = (load-platforms-manifest $root)
    let platforms = $manifest.platforms

    if ($platform | is-empty) {
        error make {msg: "resolve-ocm-provider: platform must not be empty"}
    }
    if not ($platform in ($platforms | columns)) {
        let known = ($platforms | columns | str join ", ")
        error make {msg: $"resolve-ocm-provider: unknown platform '($platform)'; known: ($known)"}
    }

    let plat_config = ($platforms | get $platform)

    # ocm_ep is {} when the platform has no ocm_endpoints section.
    let ocm_ep = ($plat_config.ocm_endpoints? | default {})

    # Manifest default wins over hardcoded fallback when present.
    let base_defaults = (
        if ($ocm_ep.default? | default null) != null {
            $ocm_ep.default
        } else {
            platform-ocm-defaults $platform
        }
    )

    # Version-line override from manifest's version_lines wins over default.
    let vl_overrides = (
        if not ($version_line | is-empty) {
            let vl_section = ($ocm_ep.version_lines? | default {})
            $vl_section | get --optional $version_line | default {}
        } else {
            {}
        }
    )

    let ocm_path = ($vl_overrides.ocm_path? | default $base_defaults.ocm_path)
    let webdav_path = ($vl_overrides.webdav_path? | default $base_defaults.webdav_path)

    # Host roles: version-line override > manifest default > hardcoded "party".
    let ocm_host_role = (
        $vl_overrides.ocm_host_role?
        | default ($base_defaults.ocm_host_role? | default "party")
    )
    let webdav_host_role = (
        $vl_overrides.webdav_host_role?
        | default ($base_defaults.webdav_host_role? | default "party")
    )

    let ocm_host = (role-to-host $ocm_host_role $platform $index)
    let webdav_host = (role-to-host $webdav_host_role $platform $index)

    # domain and homepage identify the party; endpoints use role-resolved hosts.
    let domain = $"($platform)($index).docker"
    {
        name: $domain,
        full_name: $"($domain) provider",
        organization: $domain,
        description: $"($domain) cloud storage",
        domain: $domain,
        homepage: $"https://($domain)",
        ocm_endpoint: $"https://($ocm_host)($ocm_path)",
        ocm_path: $ocm_path,
        ocm_host: $ocm_host,
        webdav_endpoint: $"https://($webdav_host)($webdav_path)",
        webdav_path: $webdav_path,
        webdav_host: $webdav_host,
    }
}

# Return 12 blank OCM_PROVIDER_<index>_* KEY= lines for Docker Compose
# substitution. Use when a stack slot is unused but the Compose file still
# needs the variable defined to avoid unset-variable substitution errors.
export def provider-env-blank-lines [index: int]: nothing -> list<string> {
    [
        $"OCM_PROVIDER_($index)_NAME=",
        $"OCM_PROVIDER_($index)_FULL_NAME=",
        $"OCM_PROVIDER_($index)_ORGANIZATION=",
        $"OCM_PROVIDER_($index)_DESCRIPTION=",
        $"OCM_PROVIDER_($index)_DOMAIN=",
        $"OCM_PROVIDER_($index)_HOMEPAGE=",
        $"OCM_PROVIDER_($index)_OCM_ENDPOINT=",
        $"OCM_PROVIDER_($index)_OCM_PATH=",
        $"OCM_PROVIDER_($index)_OCM_HOST=",
        $"OCM_PROVIDER_($index)_WEBDAV_ENDPOINT=",
        $"OCM_PROVIDER_($index)_WEBDAV_PATH=",
        $"OCM_PROVIDER_($index)_WEBDAV_HOST=",
    ]
}

# Convert a list of provider records into indexed KEY=VALUE env var lines
# suitable for appending to stack.env.
# Provider at index 0 maps to env vars OCM_PROVIDER_0_*, index 1 to
# OCM_PROVIDER_1_*, and so on. Emits 12 vars per provider: NAME, FULL_NAME,
# ORGANIZATION, DESCRIPTION, DOMAIN, HOMEPAGE, OCM_ENDPOINT, OCM_PATH,
# OCM_HOST, WEBDAV_ENDPOINT, WEBDAV_PATH, WEBDAV_HOST.
export def provider-env-lines [providers: list]: nothing -> list<string> {
    $providers | enumerate | each {|e|
        let i = $e.index
        let p = $e.item
        [
            $"OCM_PROVIDER_($i)_NAME=($p.name)",
            $"OCM_PROVIDER_($i)_FULL_NAME=($p.full_name)",
            $"OCM_PROVIDER_($i)_ORGANIZATION=($p.organization)",
            $"OCM_PROVIDER_($i)_DESCRIPTION=($p.description)",
            $"OCM_PROVIDER_($i)_DOMAIN=($p.domain)",
            $"OCM_PROVIDER_($i)_HOMEPAGE=($p.homepage)",
            $"OCM_PROVIDER_($i)_OCM_ENDPOINT=($p.ocm_endpoint)",
            $"OCM_PROVIDER_($i)_OCM_PATH=($p.ocm_path)",
            $"OCM_PROVIDER_($i)_OCM_HOST=($p.ocm_host)",
            $"OCM_PROVIDER_($i)_WEBDAV_ENDPOINT=($p.webdav_endpoint)",
            $"OCM_PROVIDER_($i)_WEBDAV_PATH=($p.webdav_path)",
            $"OCM_PROVIDER_($i)_WEBDAV_HOST=($p.webdav_host)",
        ]
    } | flatten
}
