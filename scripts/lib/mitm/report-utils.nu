# Shared helpers for MITM report generation.
# Used by mitm-summary.nu and mitm-ocm-summary.nu.

# Extract sender/receiver/mitm participants from a roles record.
# Returns a record with host and ipv4 for each role; fields default to
# empty string when missing.
# Presence of endpoints selects v2 even when the list is empty.
export def roles-have-endpoints [roles: record] {
    $roles | values | any {|role| "endpoints" in ($role | columns)}
}

def participant-for-role [roles: record, name: string] {
    let value = (try { $roles | get $name } catch { {} })
    if "endpoints" in ($value | columns) {
        let endpoint = ($value.endpoints? | default [] | first 1)
        if ($endpoint | is-empty) { return {host: "", ipv4: ""} }
        let primary = ($endpoint | first)
        return {
            host: (try { $primary.hosts | first } catch { "" })
            ipv4: ($primary.ipv4? | default "")
        }
    }
    {
        host: (try { $value.hosts | first } catch { "" })
        ipv4: ($value.ipv4? | default "")
    }
}

export def participants-from-roles [roles: record] {
    let sender = (participant-for-role $roles "sender")
    let receiver = (participant-for-role $roles "receiver")
    let mitm = (participant-for-role $roles "mitm")
    {
        sender_host: $sender.host,
        receiver_host: $receiver.host,
        mitm_host: $mitm.host,
        sender_ipv4: $sender.ipv4,
        receiver_ipv4: $receiver.ipv4,
        mitm_ipv4: $mitm.ipv4,
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

def legacy-infer-from-role [client_ip: string, roles: record] {
    if ($client_ip | is-empty) { return "unknown" }
    let matches = ($roles | items {|name, r|
        if ($r.ipv4? | default "") == $client_ip { $name } else { null }
    } | where {|v| $v != null})
    if ($matches | is-empty) { "unknown" } else { $matches | first }
}

def legacy-infer-to-role [req_host: string, server_ip: string, roles: record] {
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

def all-role-endpoints [roles: record] {
    $roles | items {|name, value|
        if "endpoints" in ($value | columns) {
            $value.endpoints? | default [] | each {|endpoint| $endpoint | insert role $name}
        } else {
            [{
                role: $name,
                service: "",
                ipv4: ($value.ipv4? | default ""),
                hosts: ($value.hosts? | default []),
            }]
        }
    } | flatten
}

def resolved-endpoint [matches: list] {
    if ($matches | length) != 1 {
        return {role: "unknown", service: "", host: ""}
    }
    let endpoint = ($matches | first)
    {
        role: $endpoint.role,
        service: ($endpoint.service? | default ""),
        host: (try { $endpoint.hosts | first } catch { "" }),
    }
}

export def resolve-from-endpoint [client_ip: string, roles: record] {
    if not (roles-have-endpoints $roles) {
        let role = (legacy-infer-from-role $client_ip $roles)
        return {role: $role, service: "", host: (role-primary-host $role (participants-from-roles $roles))}
    }
    if ($client_ip | is-empty) { return {role: "unknown", service: "", host: ""} }
    let matches = (all-role-endpoints $roles | where {|endpoint| $endpoint.ipv4 == $client_ip})
    resolved-endpoint $matches
}

export def resolve-to-endpoint [req_host: string, server_ip: string, roles: record] {
    if not (roles-have-endpoints $roles) {
        let role = (legacy-infer-to-role $req_host $server_ip $roles)
        return {role: $role, service: "", host: (role-primary-host $role (participants-from-roles $roles))}
    }
    let endpoints = (all-role-endpoints $roles)
    let host = ($req_host | str downcase)
    let host_matches = ($endpoints | where {|endpoint| not ($host | is-empty) and $host in $endpoint.hosts})
    if not ($host_matches | is-empty) { return (resolved-endpoint $host_matches) }
    if ($server_ip | is-empty) { return {role: "unknown", service: "", host: ""} }
    let ip_matches = ($endpoints | where {|endpoint| $endpoint.ipv4 == $server_ip})
    if not ($ip_matches | is-empty) { return (resolved-endpoint $ip_matches) }
    resolved-endpoint ($endpoints | where {|endpoint| ($server_ip | str downcase) in $endpoint.hosts})
}

export def infer-from-role [client_ip: string, roles: record] {
    resolve-from-endpoint $client_ip $roles | get role
}

export def infer-to-role [req_host: string, server_ip: string, roles: record] {
    resolve-to-endpoint $req_host $server_ip $roles | get role
}

# Re-export for MITM report callers. SSOT: scripts/lib/run/tuple-identity.nu.
export use ../run/tuple-identity.nu [load-meta-identity]

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
