# Actors domain: operator actor configuration queries and validation.

use ../../lib/actors/load.nu [
    list-matrix-keys
    list-override-files
    load-actor-for-tuple
    load-sender-for-tuple
    load-receiver-for-tuple
]
use ../../lib/actors/validate.nu [
    validate-actor-config
    require-sender-platform
]
use ../../lib/matrix/topology.nu [require-receiver-platform-for-two-party]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/matrix/cell.nu [tuple-matrix-key]
use ../../lib/matrix/rules-gen.nu [load-matrix-rules]
use ../../lib/run/execution-id.nu [validate-path-segment]

def main [] {
    print "Usage: nu scripts/ocmts.nu actors <verb> [flags]"
    print ""
    print "Verbs:"
    print "  list              List matrix keys enabled in the matrix SSOT"
    print "  list overrides    List matrix keys with override files"
    print "  show              Show resolved actor config for a tuple"
    print "  validate          Validate actor config; optionally check platform match"
    print "  validate-all      Validate actor configs for all enabled matrix entries"
}

def "main list" [] {
    let root = get-ocmts-root
    let keys = (list-matrix-keys $root)
    if ($keys | is-empty) {
        print "No enabled matrix entries in matrix SSOT."
    } else {
        for k in $keys { print $"  ($k)" }
    }
}

def "main list overrides" [] {
    let root = get-ocmts-root
    let files = (list-override-files $root)
    if ($files | is-empty) {
        print "No override files in config/actors/overrides/."
    } else {
        for s in $files { print $"  ($s)" }
    }
}

def "main show" [
    --flow: string,
    --sender-platform: string,
    --receiver-platform: string = "",
] {
    let sender_platform = (require-sender-platform $sender_platform)
    let fid = (validate-path-segment $flow "flow_id")
    let root = get-ocmts-root
    let canonical_two_party = (
        require-receiver-platform-for-two-party $fid $receiver_platform
    )
    validate-actor-config $fid $root $sender_platform $receiver_platform
    let tuple = (tuple-matrix-key $fid $sender_platform $receiver_platform)
    let mk = $tuple.matrix_key
    if $canonical_two_party {
        let sender = (load-sender-for-tuple $tuple.flow_id $tuple.sender_platform $tuple.receiver_platform $root $tuple.sender_platform)
        if $sender == null {
            error make {msg: $"No sender actor config for tuple flow=($flow) sender=($sender_platform) receiver=($receiver_platform)"}
        }
        let receiver = (load-receiver-for-tuple $tuple.flow_id $tuple.sender_platform $tuple.receiver_platform $root $tuple.receiver_platform)
        if $receiver == null {
            error make {msg: $"No receiver actor config for tuple flow=($flow) sender=($sender_platform) receiver=($receiver_platform)"}
        }
        print $"matrix_key: ($mk)"
        print "sender:"
        print $"  platform:   ($sender.platform)"
        print $"  account:    ($sender.account)"
        print $"  username:   ($sender.username)"
        print $"  password:   ($sender.password)"
        print "receiver:"
        print $"  platform:   ($receiver.platform)"
        print $"  account:    ($receiver.account)"
        print $"  username:   ($receiver.username)"
        print $"  password:   ($receiver.password)"
    } else {
        let a = (load-actor-for-tuple $tuple.flow_id $tuple.sender_platform $root $tuple.sender_platform)
        if $a == null {
            error make {msg: $"No actor config for tuple flow=($flow) sender=($sender_platform)"}
        }
        print $"matrix_key: ($mk)"
        print $"platform:   ($a.platform)"
        print $"account:    ($a.account)"
        print $"username:   ($a.username)"
        print $"password:   ($a.password)"
    }
}

def "main validate" [
    --flow: string,
    --sender-platform: string,
    --receiver-platform: string = "",
] {
    let fid = (validate-path-segment $flow "flow_id")
    let root = get-ocmts-root
    let canonical_two_party = (
        require-receiver-platform-for-two-party $fid $receiver_platform
    )
    validate-actor-config $fid $root $sender_platform $receiver_platform
    let tuple = (tuple-matrix-key $fid $sender_platform $receiver_platform)
    let mk = $tuple.matrix_key
    print $"actor config for '($mk)': ok"
}

def "main validate-all" [] {
    let root = get-ocmts-root
    let rules = (load-matrix-rules $root)
    let all_entries = ($rules.matrix | transpose name rule)
    let enabled = ($all_entries | where {|row| $row.rule.enabled})
    for item in $enabled {
        let mk = $item.name
        let rule = $item.rule
        let sp = (if $rule.sender? == null { "" } else { $rule.sender.platform? | default "" })
        let rp = (if $rule.receiver? == null { "" } else { $rule.receiver.platform? | default "" })
        let fid = ($rule.flow_id? | default "")
        validate-actor-config $fid $root $sp $rp
        print $"  ($mk): ok"
    }
}
