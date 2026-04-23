# OCM endpoint resolver tests.
# Run: nu scripts/tests/ocm/endpoints.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/ocm/endpoints.nu [resolve-ocm-provider provider-env-lines provider-env-blank-lines]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Locate the repo root by walking up from the script location.
def find-repo-root [] {
    let here = ($env.CURRENT_FILE | path dirname | path dirname | path dirname | path dirname)
    $here
}

# Create a temp repo root containing a platforms.nuon with the given platforms
# record. The caller must delete the returned path when done.
def make-temp-manifest-root [platforms: record]: nothing -> string {
    let tmp = (^mktemp -d | str trim)
    let config_dir = ($tmp | path join "config/matrix")
    ^mkdir -p $config_dir
    {schema_version: 1, platforms: $platforms} | save ($config_dir | path join "platforms.nuon")
    $tmp
}

def test-nextcloud-sender-defaults [] {
    test-log "\n[test-nextcloud-sender-defaults]"
    let root = find-repo-root
    let p = (resolve-ocm-provider $root "nextcloud" 1)
    [
        (assert-eq $p.domain "nextcloud1.docker"
            "nextcloud sender domain is nextcloud1.docker")
        (assert-eq $p.homepage "https://nextcloud1.docker"
            "nextcloud sender homepage")
        (assert-eq $p.ocm_host "nextcloud1.docker"
            "nextcloud sender ocm_host matches domain")
        (assert-eq $p.webdav_host "nextcloud1.docker"
            "nextcloud sender webdav_host matches domain")
        (assert-eq $p.ocm_path "/ocm/"
            "nextcloud sender ocm_path is /ocm/")
        (assert-eq $p.webdav_path "/remote.php/webdav/"
            "nextcloud sender webdav_path is /remote.php/webdav/")
        (assert-eq $p.ocm_endpoint "https://nextcloud1.docker/ocm/"
            "nextcloud sender ocm_endpoint")
        (assert-eq $p.webdav_endpoint "https://nextcloud1.docker/remote.php/webdav/"
            "nextcloud sender webdav_endpoint")
    ]
}

def test-nextcloud-receiver-defaults [] {
    test-log "\n[test-nextcloud-receiver-defaults]"
    let root = find-repo-root
    let p = (resolve-ocm-provider $root "nextcloud" 2)
    [
        (assert-eq $p.domain "nextcloud2.docker"
            "nextcloud receiver domain is nextcloud2.docker")
        (assert-eq $p.ocm_host "nextcloud2.docker"
            "nextcloud receiver ocm_host uses party index 2")
    ]
}

def test-ocis-defaults [] {
    test-log "\n[test-ocis-defaults]"
    let root = find-repo-root
    let p = (resolve-ocm-provider $root "ocis" 1)
    [
        (assert-eq $p.domain "ocis1.docker"
            "ocis sender domain")
        (assert-eq $p.ocm_path "/ocm/"
            "ocis ocm_path is /ocm/")
        (assert-eq $p.webdav_path "/dav/"
            "ocis webdav_path is /dav/")
    ]
}

def test-ocmgo-defaults [] {
    test-log "\n[test-ocmgo-defaults]"
    let root = find-repo-root
    let p = (resolve-ocm-provider $root "ocmgo" 1)
    [
        (assert-eq $p.domain "ocmgo1.docker"
            "ocmgo sender domain")
        (assert-eq $p.ocm_path "/ocm/"
            "ocmgo ocm_path is /ocm/")
        (assert-eq $p.webdav_path "/webdav/"
            "ocmgo webdav_path is /webdav/")
    ]
}

def test-version-line-no-override [] {
    test-log "\n[test-version-line-no-override]"
    let root = find-repo-root
    # Real platforms.nuon has no ocm_endpoints; version line has no effect.
    let p_plain = (resolve-ocm-provider $root "nextcloud" 1)
    let p_versioned = (resolve-ocm-provider $root "nextcloud" 1 "v34")
    [
        (assert-eq $p_versioned.ocm_path $p_plain.ocm_path
            "version line with no manifest override returns same ocm_path as plain call")
        (assert-eq $p_versioned.webdav_path $p_plain.webdav_path
            "version line with no manifest override returns same webdav_path as plain call")
    ]
}

# Prove that ocm_endpoints.default in the manifest is consumed.
# Temp manifest used so the test is self-contained and does not depend on
# platforms.nuon having the section yet.
def test-manifest-default-consumed [] {
    test-log "\n[test-manifest-default-consumed]"
    let tmp = (make-temp-manifest-root {
        testplat: {
            slug: "tp",
            ocm_endpoints: {
                default: {
                    ocm_path: "/custom-ocm/",
                    webdav_path: "/custom-webdav/",
                }
            }
        }
    })
    let p = (resolve-ocm-provider $tmp "testplat" 1)
    let results = [
        (assert-eq $p.ocm_path "/custom-ocm/"
            "manifest ocm_endpoints.default.ocm_path is consumed")
        (assert-eq $p.webdav_path "/custom-webdav/"
            "manifest ocm_endpoints.default.webdav_path is consumed")
        (assert-eq $p.domain "testplat1.docker"
            "domain uses platform name and index")
        (assert-eq $p.ocm_endpoint "https://testplat1.docker/custom-ocm/"
            "ocm_endpoint built from manifest default path")
        (assert-eq $p.webdav_endpoint "https://testplat1.docker/custom-webdav/"
            "webdav_endpoint built from manifest default path")
    ]
    ^rm -rf $tmp
    $results
}

# Prove that ocm_endpoints.version_lines override wins over default, and that
# an unrecognised version line falls back to the manifest default.
def test-manifest-version-override [] {
    test-log "\n[test-manifest-version-override]"
    let tmp = (make-temp-manifest-root {
        testplat: {
            slug: "tp",
            ocm_endpoints: {
                default: {
                    ocm_path: "/ocm/",
                    webdav_path: "/default-webdav/",
                },
                version_lines: {
                    v2: {
                        ocm_path: "/ocm/",
                        webdav_path: "/v2-webdav/",
                    }
                }
            }
        }
    })
    let p_plain = (resolve-ocm-provider $tmp "testplat" 1)
    let p_v2 = (resolve-ocm-provider $tmp "testplat" 1 "v2")
    let p_v1 = (resolve-ocm-provider $tmp "testplat" 1 "v1")
    let results = [
        (assert-eq $p_plain.webdav_path "/default-webdav/"
            "no version_line uses manifest default")
        (assert-eq $p_v2.webdav_path "/v2-webdav/"
            "version_line v2 override wins over manifest default")
        (assert-eq $p_v1.webdav_path "/default-webdav/"
            "unknown version_line falls back to manifest default")
        (assert-eq $p_v2.ocm_path "/ocm/"
            "version_line v2 ocm_path from override record")
    ]
    ^rm -rf $tmp
    $results
}

def test-provider-record-has-identity-fields [] {
    test-log "\n[test-provider-record-has-identity-fields]"
    let root = find-repo-root
    let p = (resolve-ocm-provider $root "nextcloud" 1)
    [
        (assert-eq $p.name "nextcloud1.docker"
            "name is the party domain")
        (assert-eq $p.full_name "nextcloud1.docker provider"
            "full_name is '{domain} provider'")
        (assert-eq $p.organization "nextcloud1.docker"
            "organization is the party domain")
        (assert-eq $p.description "nextcloud1.docker cloud storage"
            "description is '{domain} cloud storage'")
    ]
}

def test-provider-env-lines-one-party [] {
    test-log "\n[test-provider-env-lines-one-party]"
    let root = find-repo-root
    let p = (resolve-ocm-provider $root "nextcloud" 1)
    let lines = (provider-env-lines [$p])
    let joined = ($lines | str join "\n")
    [
        (assert-string-contains $joined "OCM_PROVIDER_0_NAME=nextcloud1.docker"
            "one-party env lines contain OCM_PROVIDER_0_NAME")
        (assert-string-contains $joined "OCM_PROVIDER_0_FULL_NAME=nextcloud1.docker provider"
            "one-party env lines contain OCM_PROVIDER_0_FULL_NAME")
        (assert-string-contains $joined "OCM_PROVIDER_0_ORGANIZATION=nextcloud1.docker"
            "one-party env lines contain OCM_PROVIDER_0_ORGANIZATION")
        (assert-string-contains $joined "OCM_PROVIDER_0_DESCRIPTION=nextcloud1.docker cloud storage"
            "one-party env lines contain OCM_PROVIDER_0_DESCRIPTION")
        (assert-string-contains $joined "OCM_PROVIDER_0_DOMAIN=nextcloud1.docker"
            "one-party env lines contain OCM_PROVIDER_0_DOMAIN")
        (assert-string-contains $joined "OCM_PROVIDER_0_OCM_ENDPOINT=https://nextcloud1.docker/ocm/"
            "one-party env lines contain OCM_PROVIDER_0_OCM_ENDPOINT")
        (assert-string-contains $joined "OCM_PROVIDER_0_OCM_PATH=/ocm/"
            "one-party env lines contain OCM_PROVIDER_0_OCM_PATH")
        (assert-string-contains $joined "OCM_PROVIDER_0_OCM_HOST=nextcloud1.docker"
            "one-party env lines contain OCM_PROVIDER_0_OCM_HOST")
        (assert-string-contains $joined "OCM_PROVIDER_0_WEBDAV_ENDPOINT=https://nextcloud1.docker/remote.php/webdav/"
            "one-party env lines contain OCM_PROVIDER_0_WEBDAV_ENDPOINT")
        (assert-string-contains $joined "OCM_PROVIDER_0_WEBDAV_PATH=/remote.php/webdav/"
            "one-party env lines contain OCM_PROVIDER_0_WEBDAV_PATH")
        (assert-string-contains $joined "OCM_PROVIDER_0_WEBDAV_HOST=nextcloud1.docker"
            "one-party env lines contain OCM_PROVIDER_0_WEBDAV_HOST")
        (assert-truthy (not ($joined | str contains "OCM_PROVIDER_1_"))
            "one-party env lines do not contain OCM_PROVIDER_1_")
        (assert-truthy (not ($joined | str contains "OCM_OCM_PROVIDER_AUTHORIZER_PROVIDERS_FILE"))
            "one-party env lines do not set OCM_OCM_PROVIDER_AUTHORIZER_PROVIDERS_FILE")
    ]
}

def test-provider-env-lines-two-party [] {
    test-log "\n[test-provider-env-lines-two-party]"
    let root = find-repo-root
    let sender = (resolve-ocm-provider $root "nextcloud" 1)
    let receiver = (resolve-ocm-provider $root "nextcloud" 2)
    let lines = (provider-env-lines [$sender $receiver])
    let joined = ($lines | str join "\n")
    [
        (assert-string-contains $joined "OCM_PROVIDER_0_DOMAIN=nextcloud1.docker"
            "two-party: sender at index 0")
        (assert-string-contains $joined "OCM_PROVIDER_1_DOMAIN=nextcloud2.docker"
            "two-party: receiver at index 1")
        (assert-string-contains $joined "OCM_PROVIDER_1_OCM_ENDPOINT=https://nextcloud2.docker/ocm/"
            "two-party: receiver OCM endpoint uses party index 2 hostname")
        (assert-eq ($lines | length) 24
            "two-party: 12 env vars per provider, 24 total")
        (assert-truthy (not ($joined | str contains "OCM_OCM_PROVIDER_AUTHORIZER_PROVIDERS_FILE"))
            "two-party env lines do not set OCM_OCM_PROVIDER_AUTHORIZER_PROVIDERS_FILE")
    ]
}

def test-unknown-platform-errors [] {
    test-log "\n[test-unknown-platform-errors]"
    let root = find-repo-root
    let caught = (try {
        resolve-ocm-provider $root "nonexistent-platform" 1
        false
    } catch {
        true
    })
    [
        (assert-truthy $caught "unknown platform raises an error")
    ]
}

def test-empty-platform-errors [] {
    test-log "\n[test-empty-platform-errors]"
    let root = find-repo-root
    let caught = (try {
        resolve-ocm-provider $root "" 1
        false
    } catch {
        true
    })
    [
        (assert-truthy $caught "empty platform raises an error")
    ]
}

# Prove that split host roles work: ocm_host_role=reva-party while
# webdav_host_role=party gives different hosts for the two endpoints.
def test-split-host-roles [] {
    test-log "\n[test-split-host-roles]"
    let tmp = (make-temp-manifest-root {
        testplat: {
            slug: "tp",
            ocm_endpoints: {
                default: {
                    ocm_path: "/ocm/",
                    webdav_path: "/remote.php/webdav/",
                    ocm_host_role: "reva-party",
                    webdav_host_role: "party",
                }
            }
        }
    })
    let p = (resolve-ocm-provider $tmp "testplat" 1)
    let results = [
        (assert-eq $p.domain "testplat1.docker"
            "domain is always the party identity")
        (assert-eq $p.homepage "https://testplat1.docker"
            "homepage is always the party identity")
        (assert-eq $p.ocm_host "revatestplat1.docker"
            "ocm_host resolved via reva-party role")
        (assert-eq $p.webdav_host "testplat1.docker"
            "webdav_host resolved via party role")
        (assert-eq $p.ocm_endpoint "https://revatestplat1.docker/ocm/"
            "ocm_endpoint uses reva-party host")
        (assert-eq $p.webdav_endpoint "https://testplat1.docker/remote.php/webdav/"
            "webdav_endpoint uses party host")
    ]
    ^rm -rf $tmp
    $results
}

# Prove that a version-line override can change host roles independently of
# the manifest default, and that the default role still wins when the version
# line does not carry a role key.
def test-version-override-changes-roles [] {
    test-log "\n[test-version-override-changes-roles]"
    let tmp = (make-temp-manifest-root {
        testplat: {
            slug: "tp",
            ocm_endpoints: {
                default: {
                    ocm_path: "/ocm/",
                    webdav_path: "/dav/",
                    ocm_host_role: "party",
                    webdav_host_role: "party",
                },
                version_lines: {
                    vreva: {
                        ocm_path: "/ocm/",
                        webdav_path: "/dav/",
                        ocm_host_role: "reva-party",
                        webdav_host_role: "reva-party",
                    },
                    vpathonly: {
                        ocm_path: "/custom/",
                        webdav_path: "/dav/",
                    }
                }
            }
        }
    })
    let p_plain = (resolve-ocm-provider $tmp "testplat" 2)
    let p_vreva = (resolve-ocm-provider $tmp "testplat" 2 "vreva")
    let p_vpathonly = (resolve-ocm-provider $tmp "testplat" 2 "vpathonly")
    let results = [
        (assert-eq $p_plain.ocm_host "testplat2.docker"
            "no version_line: default party role for ocm_host")
        (assert-eq $p_vreva.ocm_host "revatestplat2.docker"
            "vreva version_line: reva-party role for ocm_host")
        (assert-eq $p_vreva.webdav_host "revatestplat2.docker"
            "vreva version_line: reva-party role for webdav_host")
        (assert-eq $p_vreva.ocm_endpoint "https://revatestplat2.docker/ocm/"
            "vreva ocm_endpoint uses reva host")
        (assert-eq $p_vreva.webdav_endpoint "https://revatestplat2.docker/dav/"
            "vreva webdav_endpoint uses reva host")
        (assert-eq $p_vpathonly.ocm_host "testplat2.docker"
            "vpathonly version_line with no role keys falls back to default party role")
        (assert-eq $p_vpathonly.ocm_path "/custom/"
            "vpathonly version_line overrides ocm_path")
    ]
    ^rm -rf $tmp
    $results
}

# Guard that real default platforms still resolve with party role (no regressions).
def test-real-defaults-use-party-role [] {
    test-log "\n[test-real-defaults-use-party-role]"
    let root = find-repo-root
    let platforms = ["nextcloud" "ocis" "ocmgo"]
    let results = ($platforms | each {|plat|
        let p = (resolve-ocm-provider $root $plat 1)
        [
            (assert-eq $p.ocm_host $"($plat)1.docker"
                $"($plat): ocm_host is party domain by default")
            (assert-eq $p.webdav_host $"($plat)1.docker"
                $"($plat): webdav_host is party domain by default")
        ]
    } | flatten)
    $results
}

def test-provider-env-blank-lines [] {
    test-log "\n[test-provider-env-blank-lines]"
    let lines = (provider-env-blank-lines 1)
    let joined = ($lines | str join "\n")
    # Index parameter check: index 0 must use OCM_PROVIDER_0_ prefix.
    let lines0 = (provider-env-blank-lines 0)
    let joined0 = ($lines0 | str join "\n")
    [
        (assert-eq ($lines | length) 12
            "blank lines for index 1 emits exactly 12 lines")
        (assert-string-contains $joined "OCM_PROVIDER_1_NAME="
            "blank lines contain OCM_PROVIDER_1_NAME=")
        (assert-string-contains $joined "OCM_PROVIDER_1_FULL_NAME="
            "blank lines contain OCM_PROVIDER_1_FULL_NAME=")
        (assert-string-contains $joined "OCM_PROVIDER_1_ORGANIZATION="
            "blank lines contain OCM_PROVIDER_1_ORGANIZATION=")
        (assert-string-contains $joined "OCM_PROVIDER_1_DESCRIPTION="
            "blank lines contain OCM_PROVIDER_1_DESCRIPTION=")
        (assert-string-contains $joined "OCM_PROVIDER_1_DOMAIN="
            "blank lines contain OCM_PROVIDER_1_DOMAIN=")
        (assert-string-contains $joined "OCM_PROVIDER_1_HOMEPAGE="
            "blank lines contain OCM_PROVIDER_1_HOMEPAGE=")
        (assert-string-contains $joined "OCM_PROVIDER_1_OCM_ENDPOINT="
            "blank lines contain OCM_PROVIDER_1_OCM_ENDPOINT=")
        (assert-string-contains $joined "OCM_PROVIDER_1_OCM_PATH="
            "blank lines contain OCM_PROVIDER_1_OCM_PATH=")
        (assert-string-contains $joined "OCM_PROVIDER_1_OCM_HOST="
            "blank lines contain OCM_PROVIDER_1_OCM_HOST=")
        (assert-string-contains $joined "OCM_PROVIDER_1_WEBDAV_ENDPOINT="
            "blank lines contain OCM_PROVIDER_1_WEBDAV_ENDPOINT=")
        (assert-string-contains $joined "OCM_PROVIDER_1_WEBDAV_PATH="
            "blank lines contain OCM_PROVIDER_1_WEBDAV_PATH=")
        (assert-string-contains $joined "OCM_PROVIDER_1_WEBDAV_HOST="
            "blank lines contain OCM_PROVIDER_1_WEBDAV_HOST=")
        (assert-truthy (not ($joined | str contains "OCM_PROVIDER_0_"))
            "blank lines for index 1 do not contain OCM_PROVIDER_0_")
        (assert-truthy ($lines | all {|l| ($l | str ends-with "=")})
            "every blank line has an empty value")
        (assert-string-contains $joined0 "OCM_PROVIDER_0_NAME="
            "blank lines for index 0 use OCM_PROVIDER_0_ prefix")
        (assert-truthy (not ($joined0 | str contains "OCM_PROVIDER_1_"))
            "blank lines for index 0 do not contain OCM_PROVIDER_1_")
    ]
}

def test-no-authorizer-providers-file-in-env [] {
    test-log "\n[test-no-authorizer-providers-file-in-env]"
    # Verify that provider-env-lines never emits the file-based authorizer key.
    let root = find-repo-root
    let platforms = ["nextcloud" "ocis" "ocmgo"]
    let results = ($platforms | each {|plat|
        let p = (resolve-ocm-provider $root $plat 1)
        let lines = (provider-env-lines [$p])
        let joined = ($lines | str join "\n")
        (assert-truthy (not ($joined | str contains "OCM_OCM_PROVIDER_AUTHORIZER_PROVIDERS_FILE"))
            $"($plat): no PROVIDERS_FILE env var emitted")
    } | flatten)
    $results
}

def main [] {
    test-log "=== OCM Endpoint Resolver Tests ==="
    let results = (
        (test-nextcloud-sender-defaults)
        | append (test-nextcloud-receiver-defaults)
        | append (test-ocis-defaults)
        | append (test-ocmgo-defaults)
        | append (test-version-line-no-override)
        | append (test-manifest-default-consumed)
        | append (test-manifest-version-override)
        | append (test-split-host-roles)
        | append (test-version-override-changes-roles)
        | append (test-real-defaults-use-party-role)
        | append (test-provider-record-has-identity-fields)
        | append (test-provider-env-lines-one-party)
        | append (test-provider-env-lines-two-party)
        | append (test-provider-env-blank-lines)
        | append (test-unknown-platform-errors)
        | append (test-empty-platform-errors)
        | append (test-no-authorizer-providers-file-in-env)
    ) | flatten
    run-suite "ocm/endpoints" $SUITE_PATH $results
}
