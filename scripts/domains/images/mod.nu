# Images domain: container image configuration queries.

use ../../lib/images.nu [list-platforms-versions validate-platform-version resolve-images]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]

def main [] {
    print "Usage: nu scripts/ocmts.nu images <verb> [flags]"
    print ""
    print "Verbs:"
    print "  list              List all configured platforms and versions"
    print "  show              Show raw image config for one platform/version"
    print "  resolve           Resolve all image refs for a sender platform/version"
}

# List all configured platforms and versions from config/images.nuon.
def "main list" [--json] {
    let rows = list-platforms-versions
    if $json {
        $rows | to json
    } else {
        $rows | table
    }
}

# Show image config and resolved value for one platform/version.
def "main show" [
    --platform: string,  # Sender platform (e.g. nextcloud)
    --version: string,   # Platform version (e.g. v33)
] {
    validate-platform-version $platform $version
    let root = get-ocmts-root
    let imgs = open ($root | path join "config/images.nuon")
    let plat_spec = ($imgs.platforms | get $platform)
    let spec = ($plat_spec | get $version)
    let platform_env = ($plat_spec.override_env? | default "")
    let version_env = ($spec.override_env? | default "")
    let effective_env = if not ($version_env | is-empty) { $version_env } else { $platform_env }
    let env_val = if ($effective_env | is-empty) {
        ""
    } else {
        ($env | get --optional $effective_env | default "")
    }
    let resolved = if ($env_val | is-empty) { $spec.default } else { $env_val }
    print $"platform:               ($platform)"
    print $"version:                ($version)"
    print $"default:                ($spec.default)"
    print $"platform_override_env:  ($platform_env)"
    print $"version_override_env:   ($version_env)"
    print $"effective_override_env: ($effective_env)"
    print $"resolved:               ($resolved)"
    if not ($env_val | is-empty) {
        print $"note: ($effective_env) is set; using env override"
    }
}

# Resolve all image refs for a sender platform/version.
def "main resolve" [
    --sender-platform: string,  # Sender platform (e.g. nextcloud)
    --sender-version: string,   # Platform version (e.g. v33)
    --json,
] {
    let result = resolve-images $sender_platform $sender_version
    if $json {
        $result | to json
    } else {
        print $"platform:    ($result.platform)"
        print $"cypress_ci:  ($result.cypress_ci)"
        print $"cypress_dev: ($result.cypress_dev)"
        print $"mariadb:     ($result.mariadb)"
        print $"valkey:      ($result.valkey)"
    }
}
