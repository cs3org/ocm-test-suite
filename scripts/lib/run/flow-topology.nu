# Loads sender-hub topology declarations from flow *.nuon files.
# Returns a record keyed by flow_id: {sender_hub: record|null}.

export def load-flow-topology [root: string] {
    let flows_dir = ($root | path join "config/matrix/flows")
    let files = (glob ($flows_dir | path join "*.nuon"))
    if ($files | is-empty) {
        return {}
    }
    $files
    | each {|f|
        let data = (open $f)
        let flow_id = $data.flow_id
        let sender_hub = ($data | get --optional "sender_hub")
        { ($flow_id): { sender_hub: $sender_hub } }
    }
    | reduce --fold {} {|it, acc| $acc | merge $it}
}

export def flow-has-sender-hub [flow_id: string, topology: record]: nothing -> bool {
    let entry = ($topology | get --optional $flow_id)
    if $entry == null {
        return false
    }
    ($entry.sender_hub?.enabled? | default false)
}

export def sender-hub-config [flow_id: string, topology: record] {
    if not (flow-has-sender-hub $flow_id $topology) {
        error make {
            msg: $"flow '($flow_id)' has no enabled sender_hub declaration in flow topology"
        }
    }
    ($topology | get $flow_id | get sender_hub)
}
