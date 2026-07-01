# Login mechanism parity: the platforms.nuon login SSOT must agree with the
# Cypress adapters per (platform, version line). Two invariants:
#   1. Every login adapter file that declares a `mechanism:` literal matches the
#      SSOT mechanism for its platform (catches a divergent per-version adapter).
#   2. The registry registers a login adapter for every SSOT version line
#      (so a new version line cannot ship without a parity-checked adapter).
# Run: nu scripts/tests/matrix/check/login-parity.nu

const SUITE_PATH = path self

use ../../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../../lib/tests/assert.nu *
use ../../../lib/tests/runner.nu [run-suite]

# SSOT: platform -> login.mechanism from platforms.nuon.
def read-login-mechanisms [root: string] {
    let cfg = (open ($root | path join "config/matrix/platforms.nuon"))
    ($cfg.platforms
        | transpose platform entry
        | reduce --fold {} {|row, acc|
            $acc | upsert $row.platform ($row.entry.login.mechanism)
        })
}

# SSOT: flat list of {platform, version} from platforms.nuon version_lines.
def read-platform-versions [root: string] {
    let cfg = (open ($root | path join "config/matrix/platforms.nuon"))
    ($cfg.platforms
        | transpose platform entry
        | each {|row|
            $row.entry.version_lines | each {|v| ({platform: $row.platform, version: $v}) }
        }
        | flatten)
}

def read-text [path: string] {
    open -r $path
}

# Invariant 1: per-file mechanism literal matches the platform SSOT.
# Files that delegate to a shared factory (e.g. the nextcloud version shims)
# carry no literal and are skipped; the shared factory file is checked instead.
def test-adapter-mechanism-matches-ssot [] {
    test-log "\n[test-adapter-mechanism-matches-ssot]"
    let root = (get-ocmts-root)
    let mechanisms = (read-login-mechanisms $root)
    let adapters_dir = ($root | path join "cypress/support/adapters")

    let files = (glob ($adapters_dir | path join "**/login*.ts"))
    $files | each {|file|
        let rel = ($file | str replace --regex '.*/adapters/' '')
        let platform = ($rel | split row '/' | first)
        let parsed = (read-text $file | parse --regex 'mechanism:\s*"(?<mech>[^"]+)"')
        if ($parsed | is-empty) {
            null
        } else {
            let mech = ($parsed | get mech | first)
            let expected = ($mechanisms | get --optional $platform)
            (assert-eq $mech $expected
                $"($rel) mechanism matches SSOT for ($platform)")
        }
    } | compact
}

# Invariant 2: the registry's loginAdapters table registers every SSOT version.
def test-registry-covers-ssot-versions [] {
    test-log "\n[test-registry-covers-ssot-versions]"
    let root = (get-ocmts-root)
    let versions = (read-platform-versions $root)
    let registry = (read-text ($root | path join "cypress/support/adapters/registry.ts"))

    let parsed_block = ($registry
        | parse --regex '(?s)const loginAdapters[^=]*=\s*\{(?<body>.*?)\n\};')
    let block = (if ($parsed_block | is-empty) { "" } else { $parsed_block | get body | first })

    $versions | each {|pv|
        let re = ('(?s)' + $pv.platform + ':\s*\{(?<body>.*?)\}')
        let pb = ($block | parse --regex $re)
        let platform_block = (if ($pb | is-empty) { "" } else { $pb | get body | first })
        (assert-truthy ($platform_block | str contains $"($pv.version):")
            $"registry loginAdapters registers ($pv.platform)/($pv.version)")
    }
}

def main [] {
    test-log "=== matrix/check/login-parity Tests ==="
    let results = ([]
        | append (test-adapter-mechanism-matches-ssot)
        | append (test-registry-covers-ssot-versions)
    )
    run-suite "matrix/check/login-parity" $SUITE_PATH $results
}
