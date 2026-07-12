# Image config validator tests.
# Run: nu scripts/tests/images/validate.nu

const SUITE_PATH = path self

use ../../lib/images/validate.nu [validate-images-cfg]
use ../../lib/tests/assert.nu *
use ../../lib/tests/fixtures.nu [with-tmp-dir]
use ../../lib/tests/runner.nu [run-suite]

def repo-root [] {
    $SUITE_PATH | path dirname | path dirname | path dirname | path dirname
}

def ocmts-script [] {
    (repo-root) | path join "scripts/ocmts.nu"
}

def write-images-matrix-base [tmp_root: string] {
    mkdir ($tmp_root | path join "config/matrix/flows")

    ({
        browsers_default: ["chrome"],
    } | to nuon)
    | save --force ($tmp_root | path join "config/matrix/defaults.nuon")

    ({
        platforms: {
            nextcloud: {version_lines: ["v34"]},
        },
    } | to nuon)
    | save --force ($tmp_root | path join "config/matrix/platforms.nuon")

    ({
        schema_version: 1,
        flow_id: "login",
        label: "Login",
        subtitle: "Login flow",
        glyph_id: "key",
        display_order: 10,
        enabled: true,
        two_party: false,
        mitm: false,
        browsers: null,
        required_capabilities: {sender: [], receiver: []},
        include: {senders: ["nextcloud"]},
        versions_sender: {nextcloud: ["v34"]},
    } | to nuon)
    | save --force ($tmp_root | path join "config/matrix/flows/login.nuon")
}

def write-images-validate-fixture [tmp_root: string] {
    write-images-matrix-base $tmp_root

    ({
        schema_version: 3,
        platforms: {
            nextcloud: {
                v34: {
                    default: "ghcr.io/example/nextcloud:v34",
                    override_env: "OCMTS_NEXTCLOUD_V34_IMAGE",
                    by_flow: {
                        not-a-real-flow: {
                            default: "ghcr.io/example/typo:latest",
                            override_env: "OCMTS_TYPO_IMAGE",
                        },
                    },
                },
            },
        },
    } | to nuon)
    | save --force ($tmp_root | path join "config/images.nuon")
}

def write-images-matrix-key-typo-fixture [tmp_root: string] {
    write-images-matrix-base $tmp_root

    ({
        schema_version: 3,
        platforms: {
            nextcloud: {
                v34: {
                    default: "ghcr.io/example/nextcloud:v34",
                    override_env: "OCMTS_NEXTCLOUD_V34_IMAGE",
                    by_matrix_key: {
                        not-a-real-matrix-key: {
                            default: "ghcr.io/example/matrix-typo:latest",
                            override_env: "OCMTS_MATRIX_TYPO_IMAGE",
                        },
                    },
                },
            },
        },
    } | to nuon)
    | save --force ($tmp_root | path join "config/images.nuon")
}

def write-images-bundle-flow-typo-fixture [tmp_root: string] {
    write-images-matrix-base $tmp_root

    ({
        schema_version: 3,
        platforms: {
            nextcloud: {
                v34: {
                    default: "ghcr.io/example/nextcloud:v34",
                    override_env: "OCMTS_NEXTCLOUD_V34_IMAGE",
                    bundle: {
                        idp: {
                            by_flow: {
                                not-a-real-bundle-flow: {
                                    default: "ghcr.io/example/bundle-typo:latest",
                                    override_env: "OCMTS_BUNDLE_TYPO_IMAGE",
                                },
                            },
                        },
                    },
                },
            },
        },
    } | to nuon)
    | save --force ($tmp_root | path join "config/images.nuon")
}

def write-images-capless-flow-fixture [tmp_root: string] {
    write-images-matrix-base $tmp_root

    ({
        schema_version: 1,
        flow_id: "webapp-share",
        label: "Webapp Share",
        subtitle: "Webapp share flow",
        glyph_id: "share",
        display_order: 50,
        enabled: false,
        two_party: false,
        mitm: false,
        browsers: null,
    } | to nuon)
    | save --force ($tmp_root | path join "config/matrix/flows/webapp-share.nuon")

    ({
        schema_version: 3,
        platforms: {
            nextcloud: {
                v34: {
                    default: "ghcr.io/example/nextcloud:v34",
                    override_env: "OCMTS_NEXTCLOUD_V34_IMAGE",
                    by_flow: {
                        webapp-share: {
                            default: "ghcr.io/example/webapp-share:v1",
                            override_env: "OCMTS_WEBAPP_SHARE_IMAGE",
                        },
                    },
                },
            },
        },
    } | to nuon)
    | save --force ($tmp_root | path join "config/images.nuon")
}

def test-images-validate-passes-on-repo [] {
    test-log "\n[test-images-validate-passes-on-repo]"
    let out = (with-env {OCMTS_ROOT: (repo-root)} {
        ^nu (ocmts-script) images validate | complete
    })
    [
        (assert-eq $out.exit_code 0
            "ocmts images validate exits 0 on committed images config")
        (assert-string-contains $out.stdout "OK"
            "ocmts images validate reports OK")
    ]
}

def test-validate-images-cfg-flags-unknown-by-matrix-key [] {
    test-log "\n[test-validate-images-cfg-flags-unknown-by-matrix-key]"
    with-tmp-dir {|tmp|
        write-images-matrix-key-typo-fixture $tmp
        let result = (validate-images-cfg $tmp)
        [
            (assert-truthy (not $result.ok)
                "unknown by_matrix_key yields ok false")
            (assert-truthy (($result.unknown_matrix_keys | length) > 0)
                "unknown by_matrix_key is reported")
            (assert-truthy (
                ($result.unknown_matrix_keys | any {|e|
                    ($e.key == "not-a-real-matrix-key") and ($e.location | str contains "by_matrix_key")
                })
            ) "unknown by_matrix_key entry includes key and location")
        ]
    }
}

def test-validate-images-cfg-flags-unknown-bundle-by-flow-key [] {
    test-log "\n[test-validate-images-cfg-flags-unknown-bundle-by-flow-key]"
    with-tmp-dir {|tmp|
        write-images-bundle-flow-typo-fixture $tmp
        let result = (validate-images-cfg $tmp)
        [
            (assert-truthy (not $result.ok)
                "unknown bundle by_flow key yields ok false")
            (assert-truthy (($result.unknown_flow_keys | length) > 0)
                "unknown bundle by_flow key is reported")
            (assert-truthy (
                ($result.unknown_flow_keys | any {|e|
                    ($e.key == "not-a-real-bundle-flow") and ($e.location | str contains "bundle") and ($e.location | str contains "by_flow")
                })
            ) "unknown bundle by_flow entry includes key and location")
        ]
    }
}

def test-validate-images-cfg-accepts-capability-less-flow [] {
    test-log "\n[test-validate-images-cfg-accepts-capability-less-flow]"
    with-tmp-dir {|tmp|
        write-images-capless-flow-fixture $tmp
        let result = (validate-images-cfg $tmp)
        [
            (assert-truthy $result.ok
                "capability-less flow referenced by by_flow yields ok true")
            (assert-truthy (($result.unknown_flow_keys | is-empty))
                "capability-less flow is not reported as unknown")
        ]
    }
}

def test-images-validate-fails-on-fixture-typo [] {
    test-log "\n[test-images-validate-fails-on-fixture-typo]"
    with-tmp-dir {|tmp|
        write-images-validate-fixture $tmp
        ^ln -s ((repo-root) | path join "scripts") ($tmp | path join "scripts")
        let out = (with-env {OCMTS_ROOT: $tmp} {
            ^nu (ocmts-script) images validate | complete
        })
        [
            (assert-truthy ($out.exit_code != 0)
                "ocmts images validate exits non-zero on typo fixture")
            (assert-string-contains $out.stderr "not-a-real-flow"
                "ocmts images validate stderr includes typo flow key")
        ]
    }
}

def test-validate-images-cfg-flags-unknown-by-flow-key [] {
    test-log "\n[test-validate-images-cfg-flags-unknown-by-flow-key]"
    with-tmp-dir {|tmp|
        write-images-validate-fixture $tmp
        let result = (validate-images-cfg $tmp)
        [
            (assert-truthy (not $result.ok)
                "unknown by_flow key yields ok false")
            (assert-truthy (($result.unknown_flow_keys | length) > 0)
                "unknown by_flow key is reported")
            (assert-truthy (
                ($result.unknown_flow_keys | any {|e|
                    ($e.key == "not-a-real-flow") and ($e.location | str contains "platforms.nextcloud.v34.by_flow")
                })
            ) "unknown by_flow entry includes key and location")
        ]
    }
}

def main [] {
    test-log "=== images/validate tests ==="
    let results = (
        (test-validate-images-cfg-flags-unknown-by-flow-key)
        | append (test-validate-images-cfg-flags-unknown-by-matrix-key)
        | append (test-validate-images-cfg-flags-unknown-bundle-by-flow-key)
        | append (test-validate-images-cfg-accepts-capability-less-flow)
        | append (test-images-validate-passes-on-repo)
        | append (test-images-validate-fails-on-fixture-typo)
    ) | flatten
    run-suite "images/validate" $SUITE_PATH $results
}
