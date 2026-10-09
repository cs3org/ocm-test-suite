# Run-scoped readiness evidence. One file, replaced at every run start.
# There is no resume mode: setup-run-context resets this store.

use ../services/records.nu [is-record]
use ../time/utc.nu [utc-now]

def empty-store [] {
    {
        schema_version: 1,
        execution_id: "",
        run_started_at: "",
        updated_at: "",
        providers: {},
    }
}

# A blank base joins to a relative meta/readiness.v1.json. Reject that,
# and any other non-absolute base, before a receipt path is used.
def require-absolute-artifacts-base [artifacts_base: string] {
    let trimmed = ($artifacts_base | str trim)
    if (
        (($trimmed | is-empty)
            or (not ($artifacts_base | str starts-with "/")))
    ) {
        error make {msg: "artifacts_base must be a non-blank absolute path"}
    }
}

export def readiness-evidence-path [artifacts_base: string] {
    require-absolute-artifacts-base $artifacts_base
    $artifacts_base | path join "meta" "readiness.v1.json"
}

# A present file that cannot be trusted loads as empty. The warning is a
# fixed line, matching the write-failure path, so file text stays out of logs.
def reject-unusable-store [] {
    print "WARNING: readiness evidence load failed"
    empty-store
}

export def readiness-evidence-load [artifacts_base: string] {
    let path = (readiness-evidence-path $artifacts_base)
    if not ($path | path exists) {
        return (empty-store)
    }
    let parsed = (try { open $path } catch { null })
    if not (is-record $parsed) {
        return (reject-unusable-store)
    }
    let version = ($parsed.schema_version? | default null)
    if $version != 1 {
        return (reject-unusable-store)
    }
    if not (is-record ($parsed.providers? | default null)) {
        return (reject-unusable-store)
    }
    $parsed
}

def write-store [path: string, store: record] {
    try {
        mkdir ($path | path dirname)
        $store | to json --indent 2 | save --force $path
        true
    } catch {
        false
    }
}

export def readiness-evidence-reset [
    artifacts_base: string,
    execution_id: string,
] {
    let now = (utc-now)
    let store = {
        schema_version: 1,
        execution_id: $execution_id,
        run_started_at: $now,
        updated_at: $now,
        providers: {},
    }
    let path = (readiness-evidence-path $artifacts_base)
    if not (write-store $path $store) {
        error make {msg: "evidence-write"}
    }
    $store
}

export def readiness-evidence-commit [
    artifacts_base: string,
    execution_id: string,
    provider: string,
    phase: string,
    body: record,
] {
    let store = (readiness-evidence-load $artifacts_base)
    let providers = ($store.providers? | default {})
    let prior = ($providers | get --optional $provider)
    let old_phases = if (is-record $prior) {
        let phases = ($prior.phases? | default null)
        if (is-record $phases) { $phases } else { {} }
    } else {
        {}
    }
    let tree = {phases: ($old_phases | upsert $phase $body)}
    let out = {
        schema_version: 1,
        execution_id: $execution_id,
        run_started_at: ($store.run_started_at? | default ""),
        updated_at: (utc-now),
        providers: ($providers | upsert $provider $tree),
    }
    let path = (readiness-evidence-path $artifacts_base)
    if not (write-store $path $out) {
        error make {msg: "evidence-write"}
    }
    $out
}
