# Capped docker compose and inspect helpers for the Reva registry gate.
# Stderr is dropped. Each external call is capped at 5 seconds.

use ./records.nu [is-record]

def is-list [value: any] {
    let kind = ($value | describe)
    ($kind | str starts-with "list") or ($kind | str starts-with "table")
}

def as-int [value: any] {
    if $value == null {
        return null
    }
    if (($value | describe) == "int") {
        return $value
    }
    try { $value | into int } catch { null }
}

def run-capped-job [bin: string, rest: list<string>] {
    let out_path = (^mktemp | str trim)
    let id = (job spawn {
        let result = (try {
            ^($bin) ...$rest | complete
        } catch {
            {exit_code: 127, stdout: ""}
        })
        {exit_code: $result.exit_code, stdout: $result.stdout}
        | to json
        | save --force $out_path
    })
    let deadline = ((date now) + 5sec)
    loop {
        let alive = (not (job list | where {|row| $row.id == $id} | is-empty))
        if not $alive {
            break
        }
        if (date now) >= $deadline {
            try { job kill $id } catch {}
            try { rm -f $out_path } catch {}
            return {exit_code: 124, stdout: ""}
        }
        sleep 100ms
    }
    let raw = (try { open --raw $out_path } catch { "" })
    try { rm -f $out_path } catch {}
    let parsed = (try { $raw | from json } catch { null })
    if not (is-record $parsed) {
        return {exit_code: 1, stdout: ""}
    }
    {
        exit_code: (as-int ($parsed.exit_code? | default 1) | default 1),
        stdout: ($parsed.stdout? | default ""),
    }
}

# Cap one external command at 5 seconds. Stderr is dropped so it cannot leak.
export def run-capped [argv: list<string>] {
    if ($argv | is-empty) {
        return {exit_code: 127, stdout: ""}
    }
    let bin = ($argv | first)
    let rest = ($argv | skip 1)
    if not (which timeout | is-empty) {
        let timed = (try {
            ^timeout --signal=KILL 5s $bin ...$rest | complete
        } catch {
            {exit_code: 127, stdout: ""}
        })
        if ($timed.exit_code == 124) or ($timed.exit_code == 137) {
            return {exit_code: 124, stdout: ""}
        }
        return {exit_code: $timed.exit_code, stdout: $timed.stdout}
    }
    run-capped-job $bin $rest
}

export def compose-tail [ctx: record, files: list<string>] {
    let project = ($ctx.stack_id? | default "" | str trim)
    if ($project | is-empty) or ($files | is-empty) {
        return null
    }
    let env_file = ($ctx.env_file? | default "")
    let env_args = if ($env_file | is-empty) { [] } else { ["--env-file" $env_file] }
    let f_args = ($files | each {|f| ["-f" $f]} | flatten)
    $env_args | append $f_args | append ["-p" $project]
}

def parse-json-rows [text: string] {
    let trimmed = ($text | str trim)
    if ($trimmed | is-empty) {
        return []
    }
    let whole = (try { $trimmed | from json } catch { null })
    if (is-list $whole) {
        return $whole
    }
    if (is-record $whole) {
        return [$whole]
    }
    $trimmed | lines | each {|line|
        let item = ($line | str trim)
        if ($item | is-empty) {
            null
        } else {
            try { $item | from json } catch { null }
        }
    } | where {|row| $row != null}
}

def ps-service [row: record] {
    let from_field = ($row.Service? | default ($row.service? | default ""))
    $from_field | into string
}

def ps-id [row: record] {
    let from_field = ($row.ID? | default ($row.Id? | default ($row.id? | default "")))
    $from_field | into string
}

export def compose-ps [ctx: record, files: list<string>] {
    let tail = (compose-tail $ctx $files)
    if $tail == null {
        return null
    }
    let argv = (["docker" "compose"] | append $tail | append ["ps" "-a" "--format" "json"])
    let run = (run-capped $argv)
    if $run.exit_code != 0 {
        return null
    }
    parse-json-rows $run.stdout | each {|row|
        if not (is-record $row) {
            null
        } else {
            {service: (ps-service $row), id: (ps-id $row)}
        }
    } | where {|row| $row != null}
}

export def normalize-image-id [raw: string] {
    let text = ($raw | str trim)
    if ($text | str starts-with "sha256:") {
        $text | str substring 7..
    } else {
        $text
    }
}

# Execution network key is the compose project label. Compose publishes
# ocm-net under that name. Older stacks used ocm-net or a *_ocm-net key.
def container-ip [insp: record] {
    let nets = ($insp.NetworkSettings?.Networks? | default null)
    if not (is-record $nets) {
        return ""
    }
    let rows = ($nets | transpose name net)
    let labels = ($insp.Config?.Labels? | default null)
    let project = if not (is-record $labels) {
        ""
    } else {
        let raw = ($labels | get --optional "com.docker.compose.project" | default "")
        if $raw == null {
            ""
        } else {
            $raw | into string | str trim
        }
    }
    let by_project = if ($project | is-empty) {
        []
    } else {
        $rows | where {|row| $row.name == $project}
    }
    let chosen = if not ($by_project | is-empty) {
        $by_project
    } else {
        $rows | where {|row|
            (($row.name == "ocm-net") or ($row.name | str ends-with "_ocm-net"))
        }
    }
    if ($chosen | is-empty) {
        return ""
    }
    let net = ($chosen | first | get net)
    if not (is-record $net) {
        return ""
    }
    let raw = ($net | get --optional IPAddress | default "")
    if $raw == null {
        return ""
    }
    $raw | into string | str trim
}

def slim-inspect [insp: record] {
    let labels = ($insp.Config?.Labels? | default null)
    let service = if (is-record $labels) {
        $labels | get --optional "com.docker.compose.service" | default ""
    } else {
        ""
    }
    let restart_top = (as-int ($insp.RestartCount? | default null))
    let restart_state = (as-int ($insp.State?.RestartCount? | default null))
    let restarts = if $restart_top != null {
        $restart_top
    } else if $restart_state != null {
        $restart_state
    } else {
        0
    }
    {
        id: ($insp.Id? | default "" | into string),
        service: ($service | into string),
        status: ($insp.State?.Status? | default "" | into string),
        health: ($insp.State?.Health?.Status? | default "" | into string),
        restarts: $restarts,
        hostname: ($insp.Config?.Hostname? | default "" | into string),
        image_id: ($insp.Image? | default "" | into string),
        ip: (container-ip $insp),
    }
}

export def inspect-ids [ids: list<string>] {
    let wanted = ($ids | where {|id| not ($id | is-empty)})
    if ($wanted | is-empty) {
        return []
    }
    let argv = (["docker" "inspect"] | append $wanted)
    let run = (run-capped $argv)
    if $run.exit_code != 0 {
        return null
    }
    let rows = (parse-json-rows $run.stdout)
    $rows | each {|row|
        if (is-record $row) { slim-inspect $row } else { null }
    } | where {|row| $row != null}
}

def same-container-id [left: string, right: string] {
    if ($left | is-empty) or ($right | is-empty) {
        return false
    }
    let a = ($left | str replace --regex '^sha256:' '')
    let b = ($right | str replace --regex '^sha256:' '')
    if $a == $b {
        return true
    }
    let a_len = ($a | str length)
    let b_len = ($b | str length)
    let short = if $a_len <= $b_len { $a } else { $b }
    let long = if $a_len <= $b_len { $b } else { $a }
    if ($short | str length) < 12 {
        return false
    }
    if not ($short =~ '^[0-9a-fA-F]+$') {
        return false
    }
    $long | str starts-with $short
}

export def find-slim [rows: list, id: string] {
    let hit = ($rows | where {|row| same-container-id $row.id $id})
    if ($hit | is-empty) { null } else { $hit | first }
}

export def intended-image-ref [
    ctx: record,
    files: list<string>,
    services: list<string>,
] {
    let tail = (compose-tail $ctx $files)
    if $tail == null {
        return ""
    }
    let argv = (["docker" "compose"] | append $tail | append ["config" "--format" "json"])
    let run = (run-capped $argv)
    if $run.exit_code != 0 {
        return ""
    }
    let cfg = (try { $run.stdout | from json } catch { null })
    if not (is-record $cfg) {
        return ""
    }
    let specs = ($cfg.services? | default null)
    if not (is-record $specs) {
        return ""
    }
    let images = ($services | each {|name|
        let spec = ($specs | get --optional $name)
        if not (is-record $spec) {
            ""
        } else {
            let image = ($spec.image? | default ($spec.Image? | default ""))
            $image | into string | str trim
        }
    })
    if ($images | any {|image| $image | is-empty}) {
        return ""
    }
    let uniq = ($images | uniq)
    if ($uniq | length) != 1 {
        return ""
    }
    $uniq | first
}

export def resolved-image-id [image_ref: string] {
    if ($image_ref | is-empty) {
        return ""
    }
    let argv = ["docker" "image" "inspect" "--format" "{{.Id}}" $image_ref]
    let run = (run-capped $argv)
    if $run.exit_code != 0 {
        return ""
    }
    $run.stdout | str trim
}
