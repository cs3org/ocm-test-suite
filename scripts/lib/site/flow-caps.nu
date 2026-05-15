# Loads required-capability lists from flow *.nuon files.
# Returns a record keyed by flow_id: {sender: [caps], receiver: [caps]}.
export def load-flow-caps [flows_dir: string] {
    let files = (glob ($flows_dir | path join "*.nuon"))
    if ($files | is-empty) {
        return {}
    }
    $files
    | each {|f|
        let data = (open $f)
        let flow_id = $data.flow_id
        let req_caps = ($data | get --optional "required_capabilities")
        if $req_caps == null {
            print --stderr $"WARNING: ($f) has no required_capabilities; skipping"
            null
        } else {
            {
                ($flow_id): {
                    sender: ($req_caps.sender? | default []),
                    receiver: ($req_caps.receiver? | default []),
                }
            }
        }
    }
    | compact
    | reduce --fold {} {|it, acc| $acc | merge $it}
}
