# Actors domain: operator actor configuration queries and validation.

use ../../lib/actors/load.nu [list-matrix-scenarios list-override-files load-actor-for-scenario]
use ../../lib/actors/validate.nu [validate-actor-config]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/matrix/rules-gen.nu [load-matrix-rules]

def main [] {
    print "Usage: nu scripts/ocmts.nu actors <verb> [flags]"
    print ""
    print "Verbs:"
    print "  list              List scenarios enabled in the matrix SSOT"
    print "  list overrides    List scenarios with override files"
    print "  show              Show resolved actor config for a scenario"
    print "  validate          Validate actor config; optionally check platform match"
    print "  validate-all      Validate actor configs for all enabled scenarios"
}

# List scenarios enabled in the matrix SSOT.
def "main list" [] {
    let root = get-ocmts-root
    let scenarios = (list-matrix-scenarios $root)
    if ($scenarios | is-empty) {
        print "No enabled scenarios in matrix SSOT."
    } else {
        for s in $scenarios { print $"  ($s)" }
    }
}

# List scenarios that have an override file under config/actors/scenarios/.
# File presence means "override exists", not "scenario enabled". Use
# `actors list` to enumerate enabled scenarios from the matrix SSOT.
def "main list overrides" [] {
    let root = get-ocmts-root
    let files = (list-override-files $root)
    if ($files | is-empty) {
        print "No override files in config/actors/scenarios/."
    } else {
        for s in $files { print $"  ($s)" }
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
# Checks: platform config exists, account exists, username/password non-empty.
# With --sender-platform, also checks platform match.
def "main validate" [
    --scenario: string,                 # Scenario name (e.g. login)
    --sender-platform: string = "",     # Optional: expected actor/sender platform
    --receiver-platform: string = "",   # Optional: expected receiver platform (two-party)
] {
    let root = get-ocmts-root
    let rules = (load-matrix-rules $root)
    let fid = ($rules.scenarios | get --optional $scenario | default {} | get flow_id? | default $scenario)
    validate-actor-config $scenario $root $sender_platform $receiver_platform --flow-id $fid
    print $"actor config for '($scenario)': ok"
}

# Validate actor configs for all enabled scenarios in the matrix SSOT under config/matrix/.
# For each enabled scenario, expected platforms are taken from matrix rules.
# Prints one ok line per scenario; errors on first failure.
def "main validate-all" [] {
    let root = get-ocmts-root
    let rules = (load-matrix-rules $root)
    let all_scenarios = ($rules.scenarios | transpose name rule)
    let enabled = ($all_scenarios | where {|row| $row.rule.enabled})
    for item in $enabled {
        let name = $item.name
        let rule = $item.rule
        let sp = (if $rule.sender? == null { "" } else { $rule.sender.platform? | default "" })
        let rp = (if $rule.receiver? == null { "" } else { $rule.receiver.platform? | default "" })
        let fid = ($rule.flow_id? | default $name)
        validate-actor-config $name $root $sp $rp --flow-id $fid
        print $"  ($name): ok"
    }
}
