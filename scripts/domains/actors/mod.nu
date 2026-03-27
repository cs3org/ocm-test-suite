# Actors domain: operator actor configuration queries and validation.

use ../../lib/actors.nu [
    list-scenario-names
    load-actor-for-scenario
    validate-actor-config
]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]

def main [] {
    print "Usage: nu scripts/ocmts.nu actors <verb> [flags]"
    print ""
    print "Verbs:"
    print "  list              List scenarios with actor configs"
    print "  show              Show actor config for a scenario"
    print "  validate          Validate actor config; optionally check platform match"
}

# List all scenarios that have actor config files.
def "main list" [] {
    let root = get-ocmts-root
    let scenarios = (list-scenario-names $root)
    if ($scenarios | is-empty) {
        print "No actor configs found in config/actors/scenarios/"
    } else {
        for s in $scenarios {
            print $"  ($s)"
        }
    }
}

# Show actor config for a scenario.
def "main show" [
    --scenario: string,  # Scenario name (e.g. login)
] {
    let root = get-ocmts-root
    let a = (load-actor-for-scenario $scenario $root)
    if $a == null {
        error make {msg: $"No actor config for scenario '($scenario)'"}
    }
    print $"scenario:  ($scenario)"
    print $"platform:  ($a.platform)"
    print $"account:   ($a.account)"
    print $"username:  ($a.username)"
    print $"password:  ($a.password)"
}

# Validate actor config for a scenario without starting Docker.
# Checks: scenario file exists, platform config exists, account exists,
# username/password non-empty. With --sender-platform, also checks platform match.
def "main validate" [
    --scenario: string,               # Scenario name (e.g. login)
    --sender-platform: string = "",   # Optional: check actor platform matches this
] {
    let root = get-ocmts-root
    validate-actor-config $scenario $root $sender_platform
    print $"actor config for '($scenario)': ok"
}
