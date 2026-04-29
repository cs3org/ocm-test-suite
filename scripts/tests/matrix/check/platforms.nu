# Platform completeness check tests.
# Run: nu scripts/tests/matrix/check/platforms.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../../lib/matrix/check/platforms.nu [check-platform-completeness]
use ../../../lib/tests/assert.nu *
use ../../../lib/tests/runner.nu [run-suite]
use ../../../lib/tests/fixtures.nu [with-tmp-dir]

# Build a minimal platforms.nuon with nextcloud/{v32,v33} and ocmgo/v1.
def write-platforms-config [tmp_root: string] {
    mkdir ($tmp_root | path join "config/matrix")
    let cfg = {
        schema_version: 1,
        platforms: {
            nextcloud: {slug: "nc", version_lines: ["v32", "v33"]},
            ocmgo: {slug: "ocmgo", version_lines: ["v1"]},
        }
    }
    ($cfg | to json) | save --force ($tmp_root | path join "config/matrix/platforms.nuon")
}

# Adapter keys match exactly the declared set -> no drift.
def test-no-drift [] {
    test-log "\n[test-no-drift]"
    with-tmp-dir {|tmp|
        write-platforms-config $tmp
        let adapter_keys = ["nextcloud/v32" "nextcloud/v33" "ocmgo/v1"]
        let result = (check-platform-completeness $tmp $adapter_keys)
        [
            (assert-eq $result.missing_from_json []
                "missing_from_json is empty when keys match exactly")
            (assert-eq $result.extra_in_json []
                "extra_in_json is empty when keys match exactly")
        ]
    }
}

# One platform declared in config but missing from adapter keys.
def test-missing-from-json [] {
    test-log "\n[test-missing-from-json]"
    with-tmp-dir {|tmp|
        write-platforms-config $tmp
        # Omit nextcloud/v33 from adapter_keys.
        let adapter_keys = ["nextcloud/v32" "ocmgo/v1"]
        let result = (check-platform-completeness $tmp $adapter_keys)
        [
            (assert-list-contains $result.missing_from_json "nextcloud/v33"
                "nextcloud/v33 appears in missing_from_json")
            (assert-eq $result.extra_in_json []
                "extra_in_json is empty")
        ]
    }
}

# One adapter key present but not declared in config.
def test-extra-in-json [] {
    test-log "\n[test-extra-in-json]"
    with-tmp-dir {|tmp|
        write-platforms-config $tmp
        # Add an extra key not in config.
        let adapter_keys = ["nextcloud/v32" "nextcloud/v33" "ocmgo/v1" "ocis/v8"]
        let result = (check-platform-completeness $tmp $adapter_keys)
        [
            (assert-eq $result.missing_from_json []
                "missing_from_json is empty")
            (assert-list-contains $result.extra_in_json "ocis/v8"
                "ocis/v8 appears in extra_in_json")
        ]
    }
}

# Both directions of drift at once.
def test-both-directions [] {
    test-log "\n[test-both-directions]"
    with-tmp-dir {|tmp|
        write-platforms-config $tmp
        let adapter_keys = ["nextcloud/v32" "ocmgo/v1" "ocis/v8"]
        let result = (check-platform-completeness $tmp $adapter_keys)
        [
            (assert-list-contains $result.missing_from_json "nextcloud/v33"
                "nextcloud/v33 is missing from json")
            (assert-list-contains $result.extra_in_json "ocis/v8"
                "ocis/v8 is extra in json")
        ]
    }
}

def main [] {
    test-log "=== matrix/check/platforms Tests ==="
    let results = ([]
        | append (test-no-drift)
        | append (test-missing-from-json)
        | append (test-extra-in-json)
        | append (test-both-directions)
    )
    run-suite "matrix/check/platforms" $SUITE_PATH $results
}
