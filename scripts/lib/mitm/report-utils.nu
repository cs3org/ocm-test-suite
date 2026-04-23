# Shared helpers for MITM report generation.
# Used by mitm-summary.nu and mitm-ocm-summary.nu.

# Extract sender/receiver/mitm participants from a roles record.
# Returns a record with host and ipv4 for each role; fields default to
# empty string when missing.
export def participants-from-roles [roles: record] {
    {
        sender_host:   (try { $roles.sender.hosts | first } catch { "" }),
        receiver_host: (try { $roles.receiver.hosts | first } catch { "" }),
        mitm_host:     (try { $roles.mitm.hosts | first } catch { "" }),
        sender_ipv4:   (try { $roles.sender.ipv4? | default "" } catch { "" }),
        receiver_ipv4: (try { $roles.receiver.ipv4? | default "" } catch { "" }),
        mitm_ipv4:     (try { $roles.mitm.ipv4? | default "" } catch { "" }),
    }
}

# Return the primary host for a role name from a participants record.
# Returns empty string for unknown roles.
export def role-primary-host [role: string, participants: record] {
    match $role {
        "sender"   => $participants.sender_host,
        "receiver" => $participants.receiver_host,
        "mitm"     => $participants.mitm_host,
        _          => "",
    }
}

# Build a Markdown participants preface block.
# Returns empty string when both sender_host and receiver_host are empty.
# Each host line includes (ipv4) only when the ipv4 value is non-empty.
export def md-participants-preface [participants: record] {
    let both_empty = (
        ($participants.sender_host | is-empty)
        and ($participants.receiver_host | is-empty)
    )
    if $both_empty { return "" }

    mut lines = ["## Participants" ""]

    if not ($participants.sender_host | is-empty) {
        let ipv4_part = if not ($participants.sender_ipv4 | is-empty) {
            $" \(($participants.sender_ipv4)\)"
        } else { "" }
        $lines = ($lines | append $"- sender: ($participants.sender_host)($ipv4_part)")
    }
    if not ($participants.receiver_host | is-empty) {
        let ipv4_part = if not ($participants.receiver_ipv4 | is-empty) {
            $" \(($participants.receiver_ipv4)\)"
        } else { "" }
        $lines = ($lines | append $"- receiver: ($participants.receiver_host)($ipv4_part)")
    }
    if not ($participants.mitm_host | is-empty) {
        let ipv4_part = if not ($participants.mitm_ipv4 | is-empty) {
            $" \(($participants.mitm_ipv4)\)"
        } else { "" }
        $lines = ($lines | append $"- mitm: ($participants.mitm_host)($ipv4_part)")
    }

    $lines = ($lines | append "")
    $lines | str join "\n"
}

# Format a list of strings as a Markdown table row: | v1 | v2 | ... |
# Uses a variable for the joined string to avoid nested-quote issues in $"...".
export def mk-md-row [vals: list<string>] {
    let joined = ($vals | str join " | ")
    $"| ($joined) |"
}

# Infer the sending role name from a client IP against a roles record.
export def infer-from-role [client_ip: string, roles: record] {
    if ($client_ip | is-empty) { return "unknown" }
    let matches = ($roles | items {|name, r|
        if ($r.ipv4? | default "") == $client_ip { $name } else { null }
    } | where {|v| $v != null})
    if ($matches | is-empty) { "unknown" } else { $matches | first }
}

# Infer the receiving role name from request host and server IP.
# Host match against role.hosts takes priority over server IP match.
export def infer-to-role [req_host: string, server_ip: string, roles: record] {
    let host_matches = ($roles | items {|name, r|
        if $req_host in ($r.hosts? | default []) { $name } else { null }
    } | where {|v| $v != null})
    if not ($host_matches | is-empty) { return ($host_matches | first) }
    if ($server_ip | is-empty) { return "unknown" }
    let ip_matches = ($roles | items {|name, r|
        if ($r.ipv4? | default "") == $server_ip { $name } else { null }
    } | where {|v| $v != null})
    if ($ip_matches | is-empty) { "unknown" } else { $ip_matches | first }
}

# Load identity fallbacks from meta/cell.json and meta/run.json.
# Used when flow records omit identity fields.
# Dedicated fields take precedence over scenario as a fallback:
#   flow_id:         cell.flow_id       -> cell.scenario (fallback)
#   scenario_module: cell.scenario_module -> cell.scenario (fallback)
#   cell_id:         cell.cell_id
#   run_id:          run.execution_id
# Callers that only use flow_id/cell_id/run_id ignore the scenario_module field.
export def load-meta-identity [artifacts_base: string] {
    let cell_path = ($artifacts_base | path join "meta" "cell.json")
    let run_path = ($artifacts_base | path join "meta" "run.json")
    let cell = if ($cell_path | path exists) {
        try { open $cell_path } catch { {} }
    } else { {} }
    let run = if ($run_path | path exists) {
        try { open $run_path } catch { {} }
    } else { {} }
    let cell_flow_id        = ($cell.flow_id?         | default "" | into string | str trim)
    let cell_scenario       = ($cell.scenario?        | default "" | into string | str trim)
    let cell_scenario_mod   = ($cell.scenario_module? | default "" | into string | str trim)
    {
        flow_id:         (if ($cell_flow_id      | is-empty) { $cell_scenario } else { $cell_flow_id }),
        scenario_module: (if ($cell_scenario_mod | is-empty) { $cell_scenario } else { $cell_scenario_mod }),
        cell_id:         ($cell.cell_id? | default ""),
        run_id:          ($run.execution_id? | default ""),
    }
}

# Detect which id columns are invariant (exactly one distinct non-empty value
# across all rows). Returns {preface: string, skip_cols: list<string>}.
# preface is a short inline block ending with "\n\n" when non-empty, suitable
# for inserting above a Markdown table. skip_cols are the hoisted column names.
export def compute-id-hoist [rows: list, id_cols: list<string>] {
    let hoistable = ($id_cols | where {|col|
        let non_empty = ($rows
            | each {|r|
                let raw = (try { $r | get $col } catch { null })
                $raw | default "" | into string | str trim
            }
            | where {|v| not ($v | is-empty)}
            | uniq)
        ($non_empty | length) == 1
    })
    if ($hoistable | is-empty) {
        return {preface: "", skip_cols: []}
    }
    let parts = ($hoistable | each {|col|
        let val = ($rows
            | each {|r|
                let raw = (try { $r | get $col } catch { null })
                $raw | default "" | into string | str trim
            }
            | where {|v| not ($v | is-empty)}
            | first)
        $"**($col)**: ($val)"
    })
    let preface = ($parts | str join " | ") + "\n\n"
    {preface: $preface, skip_cols: $hoistable}
}
