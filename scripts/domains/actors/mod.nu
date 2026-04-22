# Actors domain: operator actor configuration queries and validation.

use ../../lib/actors/load.nu [list-scenario-names load-actor-for-scenario]
use ../../lib/actors/validate.nu [validate-actor-config]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]

def main [] {
    print "Usage: nu scripts/ocmts.nu actors <verb> [flags]"
    print ""
    print "Verbs:"
    print "  list              List scenarios with actor configs"
    print "  show              Show actor config for a scenario"
    print "  validate          Validate actor config; optionally check platform match"
    print "  validate-all      Validate actor configs for all enabled scenarios"
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
    --scenario: string,                 # Scenario name (e.g. login)
    --sender-platform: string = "",     # Optional: expected actor/sender platform
    --receiver-platform: string = "",   # Optional: expected receiver platform (two-party)
] {
    let root = get-ocmts-root
    let rules_path = ($root | path join "config/matrix-rules.nuon")
    let fid = if ($rules_path | path exists) {
        (open $rules_path).scenarios | get --optional $scenario | default {} | get flow_id? | default $scenario
    } else { $scenario }
    validate-actor-config $scenario $root $sender_platform $receiver_platform --flow-id $fid
    print $"actor config for '($scenario)': ok"
}

# Validate actor configs for all enabled scenarios in config/matrix-rules.nuon.
# For each enabled scenario, expected platforms are taken from matrix rules.
# Prints one ok line per scenario; errors on first failure.
def "main validate-all" [] {
    let root = get-ocmts-root
    let rules_path = ($root | path join "config/matrix-rules.nuon")
    if not ($rules_path | path exists) {
        error make {msg: "config/matrix-rules.nuon not found; generate it first with 'matrix gen'"}
    }
    let rules = (open $rules_path)
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
