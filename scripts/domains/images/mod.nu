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
    let spec = ($imgs.platforms | get $platform | get $version)
    let env_val = ($env | get --optional $spec.override_env | default "")
    let resolved = if ($env_val | is-empty) { $spec.default } else { $env_val }
    print $"platform:     ($platform)"
    print $"version:      ($version)"
    print $"default:      ($spec.default)"
    print $"override_env: ($spec.override_env)"
    print $"resolved:     ($resolved)"
    if not ($env_val | is-empty) {
        print $"note: ($spec.override_env) is set; using env override"
    }
}

# Resolve all image refs for a sender platform/version (login slice).
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
