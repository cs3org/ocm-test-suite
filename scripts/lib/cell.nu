# Compute deterministic cell and artifact identifiers.

use ./execution-id.nu [validate-path-segment]
use ./domain/core/ocmts-root.nu [get-ocmts-root]

# Validate browser against the supported allowlist for the current image slice.
# Only chrome is supported in the current images. Error message is readable.
export def validate-browser [browser: string] {
    let allowed = ["chrome"]
    if not ($browser in $allowed) {
        error make {msg: $"browser '($browser)' not in supported list: ($allowed | str join ', ')"}
    }
    $browser
}

export def compute-cell [
    scenario: string,
    platform: string,
    version: string,
    browser: string,
] {
    let s = (validate-path-segment $scenario "scenario")
    let p = (validate-path-segment $platform "platform")
    let v = (validate-path-segment $version "version")
    let b = (validate-browser $browser)
    {
        cell_id: $"($s)__($p)-($v)",
        artifact_name: $"cell-($s)-($p)-($v)",
        scenario: $s,
        sender_platform: $p,
        sender_version: $v,
        browser: $b,
    }
}

# Validate cell inputs against config/matrix-rules.nuon.
# Errors readably when scenario, browser, platform, or version is not in rules.
export def validate-cell-rules [
    scenario: string,
    sender_platform: string,
    sender_version: string,
    browser: string,
] {
    let root = get-ocmts-root
    let rules = open ($root | path join "config/matrix-rules.nuon")
    let known_scenarios = ($rules.scenarios | columns)
    if not ($scenario in $known_scenarios) {
        error make {msg: $"Scenario '($scenario)' not in config/matrix-rules.nuon. Known: ($known_scenarios | str join ', ')"}
    }
    let sc = ($rules.scenarios | get $scenario)
    let known_browsers = $sc.browsers
    if not ($browser in $known_browsers) {
        error make {msg: $"Browser '($browser)' not valid for scenario '($scenario)'. Known: ($known_browsers | str join ', ')"}
    }
    let sender = $sc.sender
    if $sender.platform != $sender_platform {
        error make {msg: $"Sender platform '($sender_platform)' not valid for scenario '($scenario)'. Expected: ($sender.platform)"}
    }
    let known_versions = $sender.version_lines
    if not ($sender_version in $known_versions) {
        error make {msg: $"Version '($sender_version)' not in matrix for '($scenario)'/'($sender_platform)'. Known: ($known_versions | str join ', ')"}
    }
}
