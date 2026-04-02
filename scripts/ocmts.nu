# Public OCM Test Suite CLI entrypoint.
# Run `nu scripts/ocmts.nu <domain> [<verb>...] [flags]` from the repo root.
# Domain routers forward with `def --wrapped` so unknown flags reach the child.

use ./lib/domain/core/nu-forward.nu [forward-to]

# Print top-level usage when no domain command matches.
def main [] {
    print "Usage: nu scripts/ocmts.nu <domain> [<verb>...] [flags]"
    print ""
    print "Domains:"
    print "  version    Print the OCM test suite version"
    print "  matrix     Test matrix management"
    print "  images     Container image configuration queries"
    print "  actors     Actor (user account) configuration queries and validation"
    print "  services   Docker Compose service lifecycle"
    print "  test       Test execution"
    print "  artifacts  Artifact inspection"
    print "  site       Site clone, ingest, build, and publish"
}

# Forward to scripts/domains/version/mod.nu (passthrough argv).
def --wrapped "main version" [...args: string] {
    forward-to "scripts/domains/version/mod.nu" $args
}

# Forward to scripts/domains/matrix/mod.nu (passthrough argv).
def --wrapped "main matrix" [...args: string] {
    forward-to "scripts/domains/matrix/mod.nu" $args
}

# Forward to scripts/domains/images/mod.nu (passthrough argv).
def --wrapped "main images" [...args: string] {
    forward-to "scripts/domains/images/mod.nu" $args
}

# Forward to scripts/domains/actors/mod.nu (passthrough argv).
def --wrapped "main actors" [...args: string] {
    forward-to "scripts/domains/actors/mod.nu" $args
}

# Forward to scripts/domains/services/mod.nu (passthrough argv).
def --wrapped "main services" [...args: string] {
    forward-to "scripts/domains/services/mod.nu" $args
}

# Forward to scripts/domains/test/mod.nu (passthrough argv).
def --wrapped "main test" [...args: string] {
    forward-to "scripts/domains/test/mod.nu" $args
}

# Forward to scripts/domains/artifacts/mod.nu (passthrough argv).
def --wrapped "main artifacts" [...args: string] {
    forward-to "scripts/domains/artifacts/mod.nu" $args
}

# Forward to scripts/domains/site/mod.nu (passthrough argv).
def --wrapped "main site" [...args: string] {
    forward-to "scripts/domains/site/mod.nu" $args
}
