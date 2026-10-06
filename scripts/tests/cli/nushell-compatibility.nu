# Parse-check every tracked Nushell script under the repo (no execution).
# Run: nu scripts/tests/cli/nushell-compatibility.nu

const SUITE_PATH = path self

use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const REGRESSION_GLOB = "scripts/tests/cli/nushell-compatibility-regression/*.nu"

const STAGED_IMPORT_FILES = [
    "services/mitmproxy/scripts/entrypoint-init.nu"
    "services/nextcloud-base/scripts/entrypoint-init.nu"
    "services/revad-base/scripts/entrypoint-init.nu"
    "services/ocis/scripts/entrypoint-init.nu"
    "services/opencloud/scripts/entrypoint-init.nu"
    "services/nextcloud/scripts/hooks/00-start-log-tailing.nu"
    "services/nextcloud-contacts/scripts/hooks/before-starting/90-ensure-contacts.nu"
    "services/nextcloud-contacts/scripts/hooks/post-installation/90-enable-contacts.nu"
    "services/nextcloud-contacts/scripts/hooks/post-installation/91-enable-contacts-ocm-invites.nu"
    "services/nextcloud-webapp/scripts/hooks/before-starting/90-ensure-integration-jupyterhub.nu"
    "services/nextcloud-webapp/scripts/hooks/before-starting/91-ensure-ocmremotewebapp.nu"
    "services/nextcloud-webapp/scripts/hooks/post-installation/90-enable-integration-jupyterhub.nu"
    "services/nextcloud-webapp/scripts/hooks/post-installation/91-configure-integration-jupyterhub.nu"
    "services/nextcloud-webapp/scripts/hooks/post-installation/92-enable-ocmremotewebapp.nu"
]

def repo-root [] {
    $SUITE_PATH | path dirname | path dirname | path dirname | path dirname
}

def list-tracked-nu-files [repo_root: string] {
    let git_result = (
        ^git -C $repo_root ls-files "*.nu"
        | lines
        | where {|p| ($p | str trim) != "" }
    )
    let regression = (
        glob ($repo_root | path join $REGRESSION_GLOB)
        | each {|p| $p | path relative-to $repo_root }
    )
    ($git_result | append $regression | uniq | sort)
}

def list-parse-pass-nu-files [repo_root: string] {
    list-tracked-nu-files $repo_root
    | where {|p|
        not ($p | str starts-with "scripts/tests/cli/nushell-compatibility-regression/")
    }
}

def classify-ide-check-line [line: string] {
    let rec = (try { $line | from json } catch { null })
    if $rec == null {
        error make {msg: $"Malformed ide-check JSONL: ($line)"}
    }
    let typ = ($rec.type? | default "")
    mut severity = ""
    mut message = ($rec.message? | default $line)
    if $typ == "error" {
        $severity = "Error"
    } else if $typ == "diagnostic" {
        $severity = ($rec.severity? | default "")
    } else if $typ == "warning" {
        $severity = "Warning"
    }
    { severity: $severity, message: $message, raw_type: $typ }
}

def collect-ide-check-output [stdout: string, stderr: string] {
    let combined = ([$stdout, $stderr] | str join "\n")
    mut errors = []
    mut warnings = []
    for line in ($combined | lines | where {|l| ($l | str trim) != ""}) {
        let item = (classify-ide-check-line $line)
        if $item.severity == "Error" or $item.raw_type == "error" {
            $errors = ($errors | append $item.message)
        } else if $item.severity == "Warning" or $item.raw_type == "warning" {
            $warnings = ($warnings | append $item.message)
        }
    }
    { errors: $errors, warnings: $warnings }
}

def ordinary-parse-check [abs_file: string] {
    let result = (^nu --no-config-file --no-history --ide-check 100 $abs_file | complete)
    let parsed = (collect-ide-check-output $result.stdout $result.stderr)
    if $result.exit_code != 0 {
        error make {
            msg: $"($abs_file): ide-check exit ($result.exit_code): ($parsed.errors | str join '; ')"
        }
    }
    if not ($parsed.errors | is-empty) {
        error make {msg: $"($abs_file): ($parsed.errors | str join '; ')"}
    }
    $parsed.warnings
}

def staged-str-replace-steps [repo_root: string, rel_path: string] {
    let sshd_host = ($repo_root | path join "scripts/lib/ssh/sshd.nu")
    let utils_host = ($repo_root | path join "services/nextcloud-base/scripts/lib/utils.nu")
    let log_tailing_host = (
        $repo_root | path join "services/nextcloud-base/scripts/lib/log-tailing.nu"
    )
    let ocis_ocm_host = ($repo_root | path join "services/ocis/scripts/lib/ocmproviders.nu")
    let opencloud_ocm_host = (
        $repo_root | path join "services/opencloud/scripts/lib/ocmproviders.nu"
    )
    match $rel_path {
        "services/mitmproxy/scripts/entrypoint-init.nu"
        | "services/nextcloud-base/scripts/entrypoint-init.nu"
        | "services/revad-base/scripts/entrypoint-init.nu" => {
            [{needle: "use ./lib/sshd.nu [", replacement: $"use ($sshd_host) ["}]
        }
        "services/ocis/scripts/entrypoint-init.nu" => {
            [
                {needle: "use /usr/bin/lib/sshd.nu [", replacement: $"use ($sshd_host) ["}
                {needle: "use /usr/bin/lib/ocmproviders.nu [", replacement: $"use ($ocis_ocm_host) ["}
            ]
        }
        "services/opencloud/scripts/entrypoint-init.nu" => {
            [
                {needle: "use /usr/bin/lib/sshd.nu [", replacement: $"use ($sshd_host) ["}
                {needle: "use /usr/bin/lib/ocmproviders.nu [", replacement: $"use ($opencloud_ocm_host) ["}
            ]
        }
        "services/nextcloud/scripts/hooks/00-start-log-tailing.nu" => {
            [
                {
                    needle: "use /usr/bin/lib/log-tailing.nu ["
                    replacement: $"use ($log_tailing_host) ["
                }
            ]
        }
        "services/nextcloud-contacts/scripts/hooks/before-starting/90-ensure-contacts.nu"
        | "services/nextcloud-contacts/scripts/hooks/post-installation/90-enable-contacts.nu"
        | "services/nextcloud-contacts/scripts/hooks/post-installation/91-enable-contacts-ocm-invites.nu"
        | "services/nextcloud-webapp/scripts/hooks/before-starting/90-ensure-integration-jupyterhub.nu"
        | "services/nextcloud-webapp/scripts/hooks/before-starting/91-ensure-ocmremotewebapp.nu"
        | "services/nextcloud-webapp/scripts/hooks/post-installation/90-enable-integration-jupyterhub.nu"
        | "services/nextcloud-webapp/scripts/hooks/post-installation/91-configure-integration-jupyterhub.nu"
        | "services/nextcloud-webapp/scripts/hooks/post-installation/92-enable-ocmremotewebapp.nu" => {
            [{needle: "use /usr/bin/lib/utils.nu [", replacement: $"use ($utils_host) ["}]
        }
        _ => {
            error make {msg: $"No staged-import substitution map for ($rel_path)"}
        }
    }
}

def assert-staged-hosts-exist [repo_root: string, rel_path: string] {
    let sshd_host = ($repo_root | path join "scripts/lib/ssh/sshd.nu")
    let utils_host = ($repo_root | path join "services/nextcloud-base/scripts/lib/utils.nu")
    let log_tailing_host = (
        $repo_root | path join "services/nextcloud-base/scripts/lib/log-tailing.nu"
    )
    let ocis_ocm_host = ($repo_root | path join "services/ocis/scripts/lib/ocmproviders.nu")
    let opencloud_ocm_host = (
        $repo_root | path join "services/opencloud/scripts/lib/ocmproviders.nu"
    )
    let required = (match $rel_path {
        "services/mitmproxy/scripts/entrypoint-init.nu"
        | "services/nextcloud-base/scripts/entrypoint-init.nu"
        | "services/revad-base/scripts/entrypoint-init.nu" => [$sshd_host]
        "services/ocis/scripts/entrypoint-init.nu" => [$sshd_host $ocis_ocm_host]
        "services/opencloud/scripts/entrypoint-init.nu" => [$sshd_host $opencloud_ocm_host]
        "services/nextcloud/scripts/hooks/00-start-log-tailing.nu" => [$log_tailing_host]
        _ => [$utils_host]
    })
    for host in $required {
        if not ($host | path exists) {
            error make {msg: $"Staged import host target missing: ($host)"}
        }
    }
}

def build-staged-inner-cmd [repo_root: string, rel_path: string, check_name: string] {
    mut cmd = $"open '($check_name)' | into string"
    for step in (staged-str-replace-steps $repo_root $rel_path) {
        let needle = ($step.needle | str replace "\"" "\\\"")
        let replacement = ($step.replacement | str replace "\"" "\\\"")
        $cmd = $cmd + $" | str replace -a \"($needle)\" \"($replacement)\""
    }
    $cmd + $" | nu-check --debug '($check_name)'"
}

def staged-parse-check [repo_root: string, rel_path: string] {
    let abs_file = ($repo_root | path join $rel_path)
    if not ($abs_file | path exists) {
        error make {msg: $"Staged script missing: ($rel_path)"}
    }
    assert-staged-hosts-exist $repo_root $rel_path
    let script_dir = ($repo_root | path join ($rel_path | path dirname))
    let check_name = ($rel_path | path basename)
    let inner = (build-staged-inner-cmd $repo_root $rel_path $check_name)
    let result = (
        with-env { STAGED_DIR: $script_dir, INNER_CMD: $inner } {
            ^sh -c 'cd "$STAGED_DIR" && nu --no-config-file --no-history -c "$INNER_CMD"'
            | complete
        }
    )
    if $result.exit_code != 0 {
        let detail = ($result.stderr | str trim)
        error make {msg: $"nu-check failed for staged script ($rel_path): ($detail)"}
    }
    []
}

def parse-check-file [repo_root: string, rel_path: string] {
    let abs_file = ($repo_root | path join $rel_path)
    if $rel_path in $STAGED_IMPORT_FILES {
        staged-parse-check $repo_root $rel_path
    } else {
        ordinary-parse-check $abs_file
    }
}

def test-exit-zero-error-diagnostic-fails [] {
    test-log "\n[test-exit-zero-error-diagnostic-fails]"
    let fixture = (
        repo-root
        | path join "scripts/tests/cli/nushell-compatibility-regression/exit-zero-parse-error.nu"
    )
    let caught = (try {
        ordinary-parse-check $fixture
        false
    } catch {
        true
    })
    [
        (assert-truthy $caught
            "exit-zero Error diagnostic fixture fails parse check despite exit 0")
    ]
}

def test-all-tracked-nu-files-parse-clean [] {
    test-log "\n[test-all-tracked-nu-files-parse-clean]"
    let repo_root = (repo-root)
    let tracked = (list-parse-pass-nu-files $repo_root)
    if ($tracked | is-empty) {
        return [(assert-truthy false "tracked .nu file list is non-empty")]
    }
    let scan = ($tracked | reduce --fold {failures: [], warnings: []} {|rel, acc|
        try {
            let w = (parse-check-file $repo_root $rel)
            { failures: $acc.failures, warnings: ($acc.warnings | append $w) }
        } catch {|e|
            {
                failures: ($acc.failures | append $"($rel): ($e.msg)")
                warnings: $acc.warnings
            }
        }
    })
    let failures = $scan.failures
    let all_warnings = $scan.warnings
    if not ($all_warnings | is-empty) {
        let unique = ($all_warnings | uniq)
        test-log $"  ide-check warnings recorded: ($unique | length) unique message(s)"
        for w in $unique {
            test-log $"    warning: ($w)"
        }
    }
    test-log $"  parse-checked ($tracked | length) tracked .nu files"
    let fail_detail = ($failures | str join " ; ")
    [
        (assert-eq ($failures | length) 0
            $"all tracked .nu files parse-clean ($fail_detail)")
    ]
}

def main [] {
    test-log "=== cli/nushell-compatibility tests ==="
    let results = (
        (test-exit-zero-error-diagnostic-fails)
        | append (test-all-tracked-nu-files-parse-clean)
    ) | flatten
    run-suite "cli/nushell-compatibility" $SUITE_PATH $results
}
