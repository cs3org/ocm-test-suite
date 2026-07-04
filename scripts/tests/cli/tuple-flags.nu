# Tuple CLI flag regression tests.
# Run: nu scripts/tests/cli/tuple-flags.nu
# Guards the tuple-identity cutover: legacy --scenario must stay removed.

const SUITE_PATH = path self

use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def repo-root [] {
    $SUITE_PATH | path dirname | path dirname | path dirname | path dirname
}

def ocmts-script [] {
    (repo-root) | path join "scripts/ocmts.nu"
}

def assert-scenario-flag-rejected [cmd: list<string>, label: string] {
    let out = (^nu (ocmts-script) ...$cmd | complete)
    [
        (assert-eq $out.exit_code 1
            $"($label): --scenario exits 1")
        (assert-truthy (
            ($out.stderr | str contains "unknown_flag")
            or ($out.stderr | str contains "doesn't have flag `scenario`")
            or ($out.stderr | str contains "doesn't have flag 'scenario'")
        ) $"($label): stderr reports unknown --scenario flag")
    ]
}

def test-matrix-cell-rejects-scenario-flag [] {
    test-log "\n[test-matrix-cell-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        matrix cell
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "matrix cell"
}

def test-actors-show-rejects-scenario-flag [] {
    test-log "\n[test-actors-show-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        actors show
        --flow login
        --sender-platform nextcloud
        --scenario login
    ] "actors show"
}

def test-images-resolve-rejects-scenario-flag [] {
    test-log "\n[test-images-resolve-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        images resolve
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "images resolve"
}

def test-actors-validate-rejects-scenario-flag [] {
    test-log "\n[test-actors-validate-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        actors validate
        --flow login
        --sender-platform nextcloud
        --scenario login
    ] "actors validate"
}

def test-services-up-run-rejects-scenario-flag [] {
    test-log "\n[test-services-up-run-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        services up run
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "services up run"
}

def test-services-up-rejects-scenario-flag [] {
    test-log "\n[test-services-up-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        services up
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "services up"
}

def test-services-up-open-rejects-scenario-flag [] {
    test-log "\n[test-services-up-open-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        services up open
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "services up open"
}

def test-services-list-cell-images-rejects-scenario-flag [] {
    test-log "\n[test-services-list-cell-images-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        services list-cell-images
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "services list-cell-images"
}

def test-services-down-rejects-scenario-flag [] {
    test-log "\n[test-services-down-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        services down
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "services down"
}

def test-test-cypress-run-rejects-scenario-flag [] {
    test-log "\n[test-test-cypress-run-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        test cypress run
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "test cypress run"
}

def test-artifacts-list-rejects-scenario-flag [] {
    test-log "\n[test-artifacts-list-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        artifacts list
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "artifacts list"
}

def test-artifacts-collect-rejects-scenario-flag [] {
    test-log "\n[test-artifacts-collect-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        artifacts collect
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "artifacts collect"
}

def test-artifacts-publish-rejects-scenario-flag [] {
    test-log "\n[test-artifacts-publish-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        artifacts publish
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "artifacts publish"
}

def test-artifacts-prune-rejects-scenario-flag [] {
    test-log "\n[test-artifacts-prune-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        artifacts prune
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "artifacts prune"
}

def test-artifacts-show-rejects-scenario-flag [] {
    test-log "\n[test-artifacts-show-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        artifacts show
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "artifacts show"
}

def test-ci-emit-blocked-rejects-scenario-flag [] {
    test-log "\n[test-ci-emit-blocked-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        ci emit-blocked
        --execution-id 20260101t000000-aaaaaaaa
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --failure-reason blocked
        --scenario login
    ] "ci emit-blocked"
}

def test-help-does-not-mention-scenario-flag [] {
    test-log "\n[test-help-does-not-mention-scenario-flag]"
    let out = (^nu (ocmts-script) matrix cell --help | complete)
    [
        (assert-eq $out.exit_code 0
            "matrix cell --help exits 0")
        (assert-truthy (not ($out.stdout | str contains "--scenario"))
            "matrix cell --help does not list --scenario")
    ]
}

def test-matrix-cell-one-party-happy [] {
    test-log "\n[test-matrix-cell-one-party-happy]"
    let out = (^nu (ocmts-script) matrix cell
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --json
        | complete)
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "matrix cell one-party exits 0")
        (assert-eq $data.matrix_key "login__nextcloud"
            "matrix cell one-party resolves matrix_key")
        (assert-eq $data.cell_id "login__nextcloud-v32"
            "matrix cell one-party resolves cell_id")
        (assert-truthy (not ($data.images.platform? | default "" | is-empty))
            "matrix cell one-party resolves sender platform image")
    ]
}

def test-matrix-cell-two-party-happy [] {
    test-log "\n[test-matrix-cell-two-party-happy]"
    let out = (^nu (ocmts-script) matrix cell
        --flow share-with
        --sender-platform nextcloud
        --sender-version v32
        --receiver-platform ocmgo
        --receiver-version v1
        --json
        | complete)
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "matrix cell two-party exits 0")
        (assert-eq $data.matrix_key "share-with__nextcloud__ocmgo"
            "matrix cell two-party resolves matrix_key")
        (assert-eq $data.cell_id "share-with__nextcloud-v32__ocmgo-v1"
            "matrix cell two-party resolves cell_id")
        (assert-truthy (not ($data.receiver_image? | default "" | is-empty))
            "matrix cell two-party resolves receiver image")
    ]
}

def test-images-resolve-one-party-happy [] {
    test-log "\n[test-images-resolve-one-party-happy]"
    let out = (^nu (ocmts-script) images resolve
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --json
        | complete)
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve one-party exits 0")
        (assert-truthy (not ($data.platform? | default "" | is-empty))
            "images resolve one-party resolves sender platform image")
        (assert-truthy (not ($data.cypress_ci? | default "" | is-empty))
            "images resolve one-party resolves cypress_ci image")
    ]
}

const CERNBOX_WEB_DEFAULT = "ghcr.io/mahdibaghbani/containers/cernbox-web:master"
const CERNBOX_REVAD_DEFAULT = "ghcr.io/mahdibaghbani/containers/cernbox-revad:master-development"
const CERNBOX_IDP_DEFAULT = "ghcr.io/mahdibaghbani/containers/idp:v26.4.2"
const NEXTCLOUD_V32_DEFAULT = "ghcr.io/mahdibaghbani/containers/nextcloud:v32.0.12"
const NEXTCLOUD_CONTACTS_DEFAULT = "ghcr.io/mahdibaghbani/containers/nextcloud-contacts:ocm-contacts-app"

def test-images-show-nextcloud-v32-role-aware [] {
    test-log "\n[test-images-show-nextcloud-v32-role-aware]"
    let out = (^nu (ocmts-script) images show
        --platform nextcloud
        --version v32
        | complete)
    let stdout = $out.stdout
    [
        (assert-eq $out.exit_code 0
            "images show nextcloud/v32 exits 0")
        (assert-truthy ($stdout | str contains "platform:      nextcloud")
            "images show nextcloud/v32 prints platform")
        (assert-truthy ($stdout | str contains "version:       v32")
            "images show nextcloud/v32 prints version")
        (assert-truthy ($stdout | str contains $"default:       ($NEXTCLOUD_V32_DEFAULT)")
            "images show nextcloud/v32 prints default ref")
        (assert-truthy ($stdout | str contains "override_env:  OCMTS_NEXTCLOUD_V32_IMAGE")
            "images show nextcloud/v32 prints override_env")
        (assert-truthy ($stdout | str contains "sender_override_env:   OCMTS_NEXTCLOUD_V32_SENDER_IMAGE")
            "images show nextcloud/v32 prints sender_override_env")
        (assert-truthy ($stdout | str contains "receiver_override_env: OCMTS_NEXTCLOUD_V32_RECEIVER_IMAGE")
            "images show nextcloud/v32 prints receiver_override_env")
        (assert-truthy ($stdout | str contains "note: this is the raw version-scoped config")
            "images show nextcloud/v32 prints raw-config note")
        (assert-truthy ($stdout | str contains "note: use 'images resolve --flow ...' for full effective resolution")
            "images show nextcloud/v32 prints resolve note")
        (assert-truthy (not ($stdout | str contains "bundle:"))
            "images show nextcloud/v32 omits bundle section")
    ]
}

def test-images-show-cernbox-v11-bundle [] {
    test-log "\n[test-images-show-cernbox-v11-bundle]"
    let out = (^nu (ocmts-script) images show
        --platform cernbox
        --version v11
        | complete)
    let stdout = $out.stdout
    [
        (assert-eq $out.exit_code 0
            "images show cernbox/v11 exits 0")
        (assert-truthy ($stdout | str contains "platform:      cernbox")
            "images show cernbox/v11 prints platform")
        (assert-truthy ($stdout | str contains "version:       v11")
            "images show cernbox/v11 prints version")
        (assert-truthy ($stdout | str contains $"default:       ($CERNBOX_WEB_DEFAULT)")
            "images show cernbox/v11 prints default ref")
        (assert-truthy ($stdout | str contains "override_env:  OCMTS_CERNBOX_WEB_V11_IMAGE")
            "images show cernbox/v11 prints override_env")
        (assert-truthy ($stdout | str contains "bundle:")
            "images show cernbox/v11 prints bundle header")
        (assert-truthy ($stdout | str contains $"  revad: default=($CERNBOX_REVAD_DEFAULT) override_env=OCMTS_CERNBOX_REVAD_IMAGE")
            "images show cernbox/v11 prints revad bundle slot")
        (assert-truthy ($stdout | str contains $"  idp: default=($CERNBOX_IDP_DEFAULT) override_env=OCMTS_CERNBOX_IDP_IMAGE")
            "images show cernbox/v11 prints idp bundle slot")
        (assert-truthy ($stdout | str contains "note: this is the raw version-scoped config")
            "images show cernbox/v11 prints raw-config note")
        (assert-truthy ($stdout | str contains "note: use 'images resolve --flow ...' for full effective resolution")
            "images show cernbox/v11 prints resolve note")
    ]
}

def role-image-env-mask [] {
    [
        OCMTS_NEXTCLOUD_V32_SENDER_IMAGE
        OCMTS_NEXTCLOUD_V32_RECEIVER_IMAGE
        OCMTS_OCMGO_V1_SENDER_IMAGE
        OCMTS_OCMGO_V1_RECEIVER_IMAGE
        OCMTS_OPENCLOUD_V6_SENDER_IMAGE
        OCMTS_OPENCLOUD_V6_RECEIVER_IMAGE
        OCMTS_OCIS_V8_SENDER_IMAGE
        OCMTS_OCIS_V8_RECEIVER_IMAGE
        OCMTS_NEXTCLOUD_V34_SENDER_IMAGE
        OCMTS_NEXTCLOUD_V34_RECEIVER_IMAGE
        OCMTS_NEXTCLOUD_V35_SENDER_IMAGE
        OCMTS_NEXTCLOUD_V35_RECEIVER_IMAGE
        OCMTS_NEXTCLOUD_V35_CONTACT_TOKEN_SENDER_IMAGE
        OCMTS_NEXTCLOUD_V35_CONTACT_TOKEN_RECEIVER_IMAGE
        OCMTS_NEXTCLOUD_V35_CONTACT_WAYF_SENDER_IMAGE
        OCMTS_NEXTCLOUD_V35_CONTACT_WAYF_RECEIVER_IMAGE
        OCMTS_CERNBOX_WEB_V11_IMAGE
        OCMTS_CERNBOX_REVAD_IMAGE
        OCMTS_CERNBOX_IDP_IMAGE
        OCMTS_NEXTCLOUD_V34_IMAGE
        OCMTS_NEXTCLOUD_V35_IMAGE
        OCMTS_NEXTCLOUD_V35_CONTACT_TOKEN_IMAGE
        OCMTS_NEXTCLOUD_V35_CONTACT_WAYF_IMAGE
    ]
    | reduce --fold {} {|k, acc|
        if $k in $env { $acc | upsert $k null } else { $acc }
    }
}

def test-images-resolve-cernbox-bundle [] {
    test-log "\n[test-images-resolve-cernbox-bundle]"
    let out = (
        with-env (role-image-env-mask) {
            (^nu (ocmts-script) images resolve
                --flow login
                --sender-platform cernbox
                --sender-version v11
                --json
                | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    let bundle = ($data.bundle? | default {})
    let bundle_services = ($data.bundle_services? | default {})
    [
        (assert-eq $out.exit_code 0
            "images resolve cernbox bundle exits 0")
        (assert-eq ($data.platform? | default "") $CERNBOX_WEB_DEFAULT
            "cernbox bundle: platform web ref on public CLI")
        (assert-eq ($bundle | get --optional revad | default "") $CERNBOX_REVAD_DEFAULT
            "cernbox bundle: revad slot on public CLI")
        (assert-eq ($bundle | get --optional idp | default "") $CERNBOX_IDP_DEFAULT
            "cernbox bundle: idp slot on public CLI")
        (assert-eq ($bundle_services | get --optional revad | default "") "sender-revad-gateway"
            "cernbox bundle_services: revad compose name on public CLI")
        (assert-eq ($bundle_services | get --optional idp | default "") "sender-idp"
            "cernbox bundle_services: idp compose name on public CLI")
    ]
}

def test-images-resolve-cernbox-bundle-env-override [] {
    test-log "\n[test-images-resolve-cernbox-bundle-env-override]"
    let custom_web = "ghcr.io/example/cernbox-web:cli-override"
    let custom_revad = "ghcr.io/example/cernbox-revad:cli-override"
    let custom_idp = "ghcr.io/example/idp:cli-override"
    let out = (
        with-env (
            role-image-env-mask
            | merge {
                OCMTS_CERNBOX_WEB_V11_IMAGE: $custom_web
                OCMTS_CERNBOX_REVAD_IMAGE: $custom_revad
                OCMTS_CERNBOX_IDP_IMAGE: $custom_idp
            }
        ) {
            (^nu (ocmts-script) images resolve
                --flow login
                --sender-platform cernbox
                --sender-version v11
                --json
                | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    let bundle = ($data.bundle? | default {})
    [
        (assert-eq $out.exit_code 0
            "images resolve cernbox bundle env override exits 0")
        (assert-eq ($data.platform? | default "") $custom_web
            "OCMTS_CERNBOX_WEB_V11_IMAGE honored on public CLI")
        (assert-eq ($bundle | get --optional revad | default "") $custom_revad
            "OCMTS_CERNBOX_REVAD_IMAGE honored on public CLI")
        (assert-eq ($bundle | get --optional idp | default "") $custom_idp
            "OCMTS_CERNBOX_IDP_IMAGE honored on public CLI")
    ]
}

def test-images-resolve-role-env-beats-generic [] {
    test-log "\n[test-images-resolve-role-env-beats-generic]"
    let sender_role = "ghcr.io/example/nextcloud:sender-role"
    let receiver_role = "ghcr.io/example/ocmgo:receiver-role"
    let sender_generic = "ghcr.io/example/nextcloud:generic"
    let receiver_generic = "ghcr.io/example/ocmgo:generic"
    let cmd = [
        images resolve
        --flow share-with
        --sender-platform nextcloud
        --sender-version v32
        --receiver-platform ocmgo
        --receiver-version v1
        --json
    ]
    let out = (
        with-env {
            OCMTS_NEXTCLOUD_V32_IMAGE: $sender_generic
            OCMTS_NEXTCLOUD_V32_SENDER_IMAGE: $sender_role
            OCMTS_OCMGO_V1_IMAGE: $receiver_generic
            OCMTS_OCMGO_V1_RECEIVER_IMAGE: $receiver_role
        } {
            (^nu (ocmts-script) ...$cmd | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve role-env precedence exits 0")
        (assert-eq ($data.platform? | default "") $sender_role
            "sender OCMTS_NEXTCLOUD_V32_SENDER_IMAGE beats OCMTS_NEXTCLOUD_V32_IMAGE")
        (assert-eq ($data.receiver_platform? | default "") $receiver_role
            "receiver OCMTS_OCMGO_V1_RECEIVER_IMAGE beats OCMTS_OCMGO_V1_IMAGE")
    ]
}

def test-images-resolve-generic-fallback-when-role-env-unset [] {
    test-log "\n[test-images-resolve-generic-fallback-when-role-env-unset]"
    let sender_generic = "ghcr.io/example/nextcloud:generic-cli"
    let receiver_generic = "ghcr.io/example/ocmgo:generic-cli"
    let cmd = [
        images resolve
        --flow share-with
        --sender-platform nextcloud
        --sender-version v32
        --receiver-platform ocmgo
        --receiver-version v1
        --json
    ]
    let out = (
        with-env (
            role-image-env-mask
            | merge {
                OCMTS_NEXTCLOUD_V32_IMAGE: $sender_generic
                OCMTS_OCMGO_V1_IMAGE: $receiver_generic
            }
        ) {
            (^nu (ocmts-script) ...$cmd | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve generic fallback exits 0")
        (assert-eq ($data.platform? | default "") $sender_generic
            "OCMTS_NEXTCLOUD_V32_IMAGE applies when sender role env is unset")
        (assert-eq ($data.receiver_platform? | default "") $receiver_generic
            "OCMTS_OCMGO_V1_IMAGE applies when receiver role env is unset")
    ]
}

def test-images-resolve-empty-role-env-falls-back-to-generic [] {
    test-log "\n[test-images-resolve-empty-role-env-falls-back-to-generic]"
    let sender_generic = "ghcr.io/example/nextcloud:generic-empty-cli"
    let receiver_generic = "ghcr.io/example/ocmgo:generic-empty-cli"
    let cmd = [
        images resolve
        --flow share-with
        --sender-platform nextcloud
        --sender-version v32
        --receiver-platform ocmgo
        --receiver-version v1
        --json
    ]
    let out = (
        with-env (
            role-image-env-mask
            | merge {
                OCMTS_NEXTCLOUD_V32_IMAGE: $sender_generic
                OCMTS_NEXTCLOUD_V32_SENDER_IMAGE: ""
                OCMTS_OCMGO_V1_IMAGE: $receiver_generic
                OCMTS_OCMGO_V1_RECEIVER_IMAGE: ""
            }
        ) {
            (^nu (ocmts-script) ...$cmd | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve empty role env fallback exits 0")
        (assert-eq ($data.platform? | default "") $sender_generic
            "empty sender role env falls back to OCMTS_NEXTCLOUD_V32_IMAGE on CLI")
        (assert-eq ($data.receiver_platform? | default "") $receiver_generic
            "empty receiver role env falls back to OCMTS_OCMGO_V1_IMAGE on CLI")
    ]
}

def test-images-resolve-opposite-role-isolation [] {
    test-log "\n[test-images-resolve-opposite-role-isolation]"
    let sender_role = "ghcr.io/example/nextcloud:sender-isolated"
    let receiver_role = "ghcr.io/example/ocmgo:receiver-isolated"
    let bogus_sender = "ghcr.io/example/nextcloud:sender-leak-cli"
    let bogus_receiver = "ghcr.io/example/ocmgo:receiver-leak-cli"
    let cmd = [
        images resolve
        --flow share-with
        --sender-platform nextcloud
        --sender-version v32
        --receiver-platform ocmgo
        --receiver-version v1
        --json
    ]
    let out = (
        with-env (
            role-image-env-mask
            | merge {
                OCMTS_NEXTCLOUD_V32_SENDER_IMAGE: $sender_role
                OCMTS_OCMGO_V1_RECEIVER_IMAGE: $receiver_role
                OCMTS_OCMGO_V1_SENDER_IMAGE: $bogus_receiver
                OCMTS_NEXTCLOUD_V32_RECEIVER_IMAGE: $bogus_sender
            }
        ) {
            (^nu (ocmts-script) ...$cmd | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve opposite-role isolation exits 0")
        (assert-eq ($data.platform? | default "") $sender_role
            "sender path ignores receiver role env on CLI")
        (assert-eq ($data.receiver_platform? | default "") $receiver_role
            "receiver path ignores sender role env on CLI")
    ]
}

def opencloud-ocis-images-resolve-cmd [] {
    [
        images resolve
        --flow contact-token
        --sender-platform opencloud
        --sender-version v6
        --receiver-platform ocis
        --receiver-version v8
        --json
    ]
}

def test-images-resolve-opencloud-ocis-role-env [] {
    test-log "\n[test-images-resolve-opencloud-ocis-role-env]"
    let sender_role = "ghcr.io/example/opencloud:sender-role"
    let receiver_role = "ghcr.io/example/ocis:receiver-role"
    let sender_generic = "ghcr.io/example/opencloud:generic"
    let receiver_generic = "ghcr.io/example/ocis:generic"
    let out = (
        with-env (
            role-image-env-mask
            | merge {
                OCMTS_OPENCLOUD_V6_IMAGE: $sender_generic
                OCMTS_OPENCLOUD_V6_SENDER_IMAGE: $sender_role
                OCMTS_OCIS_V8_IMAGE: $receiver_generic
                OCMTS_OCIS_V8_RECEIVER_IMAGE: $receiver_role
            }
        ) {
            (^nu (ocmts-script) ...(opencloud-ocis-images-resolve-cmd) | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve opencloud/ocis role env exits 0")
        (assert-eq ($data.platform? | default "") $sender_role
            "OCMTS_OPENCLOUD_V6_SENDER_IMAGE beats OCMTS_OPENCLOUD_V6_IMAGE on public CLI")
        (assert-eq ($data.receiver_platform? | default "") $receiver_role
            "OCMTS_OCIS_V8_RECEIVER_IMAGE beats OCMTS_OCIS_V8_IMAGE on public CLI")
    ]
}

def test-images-resolve-opencloud-ocis-generic-fallback-when-role-env-unset [] {
    test-log "\n[test-images-resolve-opencloud-ocis-generic-fallback-when-role-env-unset]"
    let sender_generic = "ghcr.io/example/opencloud:generic-cli"
    let receiver_generic = "ghcr.io/example/ocis:generic-cli"
    let out = (
        with-env (
            role-image-env-mask
            | merge {
                OCMTS_OPENCLOUD_V6_IMAGE: $sender_generic
                OCMTS_OCIS_V8_IMAGE: $receiver_generic
            }
        ) {
            (^nu (ocmts-script) ...(opencloud-ocis-images-resolve-cmd) | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve opencloud/ocis generic fallback exits 0")
        (assert-eq ($data.platform? | default "") $sender_generic
            "OCMTS_OPENCLOUD_V6_IMAGE applies when sender role env is unset on CLI")
        (assert-eq ($data.receiver_platform? | default "") $receiver_generic
            "OCMTS_OCIS_V8_IMAGE applies when receiver role env is unset on CLI")
    ]
}

def test-images-resolve-opencloud-ocis-empty-role-env-falls-back-to-generic [] {
    test-log "\n[test-images-resolve-opencloud-ocis-empty-role-env-falls-back-to-generic]"
    let sender_generic = "ghcr.io/example/opencloud:generic-empty-cli"
    let receiver_generic = "ghcr.io/example/ocis:generic-empty-cli"
    let out = (
        with-env (
            role-image-env-mask
            | merge {
                OCMTS_OPENCLOUD_V6_IMAGE: $sender_generic
                OCMTS_OPENCLOUD_V6_SENDER_IMAGE: ""
                OCMTS_OCIS_V8_IMAGE: $receiver_generic
                OCMTS_OCIS_V8_RECEIVER_IMAGE: ""
            }
        ) {
            (^nu (ocmts-script) ...(opencloud-ocis-images-resolve-cmd) | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve opencloud/ocis empty role env fallback exits 0")
        (assert-eq ($data.platform? | default "") $sender_generic
            "empty opencloud sender role env falls back to OCMTS_OPENCLOUD_V6_IMAGE on CLI")
        (assert-eq ($data.receiver_platform? | default "") $receiver_generic
            "empty ocis receiver role env falls back to OCMTS_OCIS_V8_IMAGE on CLI")
    ]
}

def nextcloud-v35-contact-token-images-resolve-cmd [] {
    [
        images resolve
        --flow contact-token
        --sender-platform nextcloud
        --sender-version v35
        --receiver-platform nextcloud
        --receiver-version v35
        --json
    ]
}

def nextcloud-v35-contact-wayf-images-resolve-cmd [] {
    [
        images resolve
        --flow contact-wayf
        --sender-platform nextcloud
        --sender-version v35
        --receiver-platform nextcloud
        --receiver-version v35
        --json
    ]
}

def test-images-resolve-nextcloud-v35-contact-token-flow-default-beats-version-default [] {
    test-log "\n[test-images-resolve-nextcloud-v35-contact-token-flow-default-beats-version-default]"
    let out = (
        with-env (role-image-env-mask) {
            (^nu (ocmts-script) ...(nextcloud-v35-contact-token-images-resolve-cmd) | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve nextcloud/v35 contact-token default exits 0")
        (assert-eq ($data.platform? | default "") $NEXTCLOUD_CONTACTS_DEFAULT
            "contact-token by_flow default wins over nextcloud/v35 version default on CLI")
    ]
}

def test-images-resolve-nextcloud-v35-contact-wayf-flow-default-beats-version-default [] {
    test-log "\n[test-images-resolve-nextcloud-v35-contact-wayf-flow-default-beats-version-default]"
    let out = (
        with-env (role-image-env-mask) {
            (^nu (ocmts-script) ...(nextcloud-v35-contact-wayf-images-resolve-cmd) | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve nextcloud/v35 contact-wayf default exits 0")
        (assert-eq ($data.platform? | default "") $NEXTCLOUD_CONTACTS_DEFAULT
            "contact-wayf by_flow default wins over nextcloud/v35 version default on CLI")
    ]
}

def test-images-resolve-nextcloud-v35-contact-token-flow-role-env-beats-version-role-env [] {
    test-log "\n[test-images-resolve-nextcloud-v35-contact-token-flow-role-env-beats-version-role-env]"
    let flow_role = "ghcr.io/example/nextcloud-contacts:flow-sender-role-cli"
    let version_role = "ghcr.io/example/nextcloud:version-sender-role-cli"
    let out = (
        with-env (
            role-image-env-mask
            | merge {
                OCMTS_NEXTCLOUD_V35_SENDER_IMAGE: $version_role
                OCMTS_NEXTCLOUD_V35_CONTACT_TOKEN_SENDER_IMAGE: $flow_role
            }
        ) {
            (^nu (ocmts-script) ...(nextcloud-v35-contact-token-images-resolve-cmd) | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve nextcloud/v35 contact-token flow role env exits 0")
        (assert-eq ($data.platform? | default "") $flow_role
            "contact-token flow-scoped sender_override_env beats version-scoped sender_override_env on CLI")
    ]
}

def test-images-resolve-nextcloud-v35-contact-token-flow-generic-env-beats-version-role-env [] {
    test-log "\n[test-images-resolve-nextcloud-v35-contact-token-flow-generic-env-beats-version-role-env]"
    let flow_generic = "ghcr.io/example/nextcloud-contacts:flow-generic-cli"
    let version_role = "ghcr.io/example/nextcloud:version-sender-role-cli"
    let out = (
        with-env (
            role-image-env-mask
            | merge {
                OCMTS_NEXTCLOUD_V35_SENDER_IMAGE: $version_role
                OCMTS_NEXTCLOUD_V35_CONTACT_TOKEN_IMAGE: $flow_generic
            }
        ) {
            (^nu (ocmts-script) ...(nextcloud-v35-contact-token-images-resolve-cmd) | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve nextcloud/v35 contact-token flow generic env exits 0")
        (assert-eq ($data.platform? | default "") $flow_generic
            "contact-token flow-scoped generic override_env beats version-scoped role env on CLI")
    ]
}

def test-images-resolve-nextcloud-v35-contact-token-receiver-flow-role-env [] {
    test-log "\n[test-images-resolve-nextcloud-v35-contact-token-receiver-flow-role-env]"
    let receiver_role = "ghcr.io/example/nextcloud-contacts:flow-receiver-role-cli"
    let out = (
        with-env (
            role-image-env-mask
            | merge { OCMTS_NEXTCLOUD_V35_CONTACT_TOKEN_RECEIVER_IMAGE: $receiver_role }
        ) {
            (^nu (ocmts-script) ...(nextcloud-v35-contact-token-images-resolve-cmd) | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve nextcloud/v35 contact-token receiver flow role env exits 0")
        (assert-eq ($data.receiver_platform? | default "") $receiver_role
            "contact-token by_flow receiver_override_env applies to receiver resolution on CLI")
    ]
}

def test-images-resolve-nextcloud-v35-contact-wayf-flow-role-env-beats-version-role-env [] {
    test-log "\n[test-images-resolve-nextcloud-v35-contact-wayf-flow-role-env-beats-version-role-env]"
    let flow_role = "ghcr.io/example/nextcloud-contacts:wayf-flow-sender-role-cli"
    let version_role = "ghcr.io/example/nextcloud:version-sender-role-cli"
    let out = (
        with-env (
            role-image-env-mask
            | merge {
                OCMTS_NEXTCLOUD_V35_SENDER_IMAGE: $version_role
                OCMTS_NEXTCLOUD_V35_CONTACT_WAYF_SENDER_IMAGE: $flow_role
            }
        ) {
            (^nu (ocmts-script) ...(nextcloud-v35-contact-wayf-images-resolve-cmd) | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve nextcloud/v35 contact-wayf flow role env exits 0")
        (assert-eq ($data.platform? | default "") $flow_role
            "contact-wayf flow-scoped sender_override_env beats version-scoped sender_override_env on CLI")
    ]
}

def test-images-resolve-nextcloud-v35-contact-wayf-flow-generic-env-beats-version-role-env [] {
    test-log "\n[test-images-resolve-nextcloud-v35-contact-wayf-flow-generic-env-beats-version-role-env]"
    let flow_generic = "ghcr.io/example/nextcloud-contacts:wayf-flow-generic-cli"
    let version_role = "ghcr.io/example/nextcloud:version-sender-role-cli"
    let out = (
        with-env (
            role-image-env-mask
            | merge {
                OCMTS_NEXTCLOUD_V35_SENDER_IMAGE: $version_role
                OCMTS_NEXTCLOUD_V35_CONTACT_WAYF_IMAGE: $flow_generic
            }
        ) {
            (^nu (ocmts-script) ...(nextcloud-v35-contact-wayf-images-resolve-cmd) | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve nextcloud/v35 contact-wayf flow generic env exits 0")
        (assert-eq ($data.platform? | default "") $flow_generic
            "contact-wayf flow-scoped generic override_env beats version-scoped role env on CLI")
    ]
}

def test-images-resolve-nextcloud-v35-contact-wayf-receiver-flow-role-env [] {
    test-log "\n[test-images-resolve-nextcloud-v35-contact-wayf-receiver-flow-role-env]"
    let receiver_role = "ghcr.io/example/nextcloud-contacts:wayf-receiver-role-cli"
    let out = (
        with-env (
            role-image-env-mask
            | merge { OCMTS_NEXTCLOUD_V35_CONTACT_WAYF_RECEIVER_IMAGE: $receiver_role }
        ) {
            (^nu (ocmts-script) ...(nextcloud-v35-contact-wayf-images-resolve-cmd) | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve nextcloud/v35 contact-wayf receiver flow role env exits 0")
        (assert-eq ($data.receiver_platform? | default "") $receiver_role
            "contact-wayf by_flow receiver_override_env applies to receiver resolution on CLI")
    ]
}

def test-images-resolve-opencloud-ocis-opposite-role-isolation [] {
    test-log "\n[test-images-resolve-opencloud-ocis-opposite-role-isolation]"
    let sender_role = "ghcr.io/example/opencloud:sender-isolated"
    let receiver_role = "ghcr.io/example/ocis:receiver-isolated"
    let bogus_sender = "ghcr.io/example/opencloud:sender-leak-cli"
    let bogus_receiver = "ghcr.io/example/ocis:receiver-leak-cli"
    let out = (
        with-env (
            role-image-env-mask
            | merge {
                OCMTS_OPENCLOUD_V6_SENDER_IMAGE: $sender_role
                OCMTS_OCIS_V8_RECEIVER_IMAGE: $receiver_role
                OCMTS_OCIS_V8_SENDER_IMAGE: $bogus_receiver
                OCMTS_OPENCLOUD_V6_RECEIVER_IMAGE: $bogus_sender
            }
        ) {
            (^nu (ocmts-script) ...(opencloud-ocis-images-resolve-cmd) | complete)
        }
    )
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve opencloud/ocis opposite-role isolation exits 0")
        (assert-eq ($data.platform? | default "") $sender_role
            "opencloud sender path ignores receiver role env on CLI")
        (assert-eq ($data.receiver_platform? | default "") $receiver_role
            "ocis receiver path ignores sender role env on CLI")
    ]
}

def test-images-resolve-two-party-happy [] {
    test-log "\n[test-images-resolve-two-party-happy]"
    let out = (^nu (ocmts-script) images resolve
        --flow share-with
        --sender-platform nextcloud
        --sender-version v32
        --receiver-platform ocmgo
        --receiver-version v1
        --json
        | complete)
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve two-party exits 0")
        (assert-truthy (not ($data.receiver_platform? | default "" | is-empty))
            "images resolve two-party resolves receiver image")
        (assert-truthy (not ($data.mitmproxy? | default "" | is-empty))
            "images resolve two-party resolves mitmproxy image")
    ]
}

def test-ci-emit-blocked-rejects-flow-id-flag [] {
    test-log "\n[test-ci-emit-blocked-rejects-flow-id-flag]"
    let out = (^nu (ocmts-script)
        ci emit-blocked
        --execution-id 20260101t000000-aaaaaaaa
        --flow-id login
        --sender-platform nextcloud
        --sender-version v32
        --failure-reason blocked
        | complete)
    [
        (assert-eq $out.exit_code 1
            "ci emit-blocked --flow-id exits 1")
        (assert-truthy (
            ($out.stderr | str contains "unknown_flag")
            or ($out.stderr | str contains "doesn't have flag `flow-id`")
            or ($out.stderr | str contains "doesn't have flag 'flow-id'")
        ) "ci emit-blocked stderr reports unknown --flow-id flag")
    ]
}

def test-matrix-cell-json-omits-scenario-module [] {
    test-log "\n[test-matrix-cell-json-omits-scenario-module]"
    let out = (^nu (ocmts-script) matrix cell
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --json
        | complete)
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "matrix cell one-party json exits 0")
        (assert-truthy (not ("scenario_module" in ($data | columns)))
            "matrix cell json omits scenario_module")
    ]
}

def main [] {
    test-log "=== cli/tuple-flags tests ==="
    let results = (
        (test-matrix-cell-rejects-scenario-flag)
        | append (test-actors-show-rejects-scenario-flag)
        | append (test-actors-validate-rejects-scenario-flag)
        | append (test-images-resolve-rejects-scenario-flag)
        | append (test-services-up-rejects-scenario-flag)
        | append (test-services-up-open-rejects-scenario-flag)
        | append (test-services-list-cell-images-rejects-scenario-flag)
        | append (test-services-up-run-rejects-scenario-flag)
        | append (test-services-down-rejects-scenario-flag)
        | append (test-test-cypress-run-rejects-scenario-flag)
        | append (test-artifacts-list-rejects-scenario-flag)
        | append (test-artifacts-collect-rejects-scenario-flag)
        | append (test-artifacts-publish-rejects-scenario-flag)
        | append (test-artifacts-prune-rejects-scenario-flag)
        | append (test-artifacts-show-rejects-scenario-flag)
        | append (test-ci-emit-blocked-rejects-scenario-flag)
        | append (test-ci-emit-blocked-rejects-flow-id-flag)
        | append (test-help-does-not-mention-scenario-flag)
        | append (test-matrix-cell-json-omits-scenario-module)
        | append (test-matrix-cell-one-party-happy)
        | append (test-matrix-cell-two-party-happy)
        | append (test-images-resolve-one-party-happy)
        | append (test-images-show-nextcloud-v32-role-aware)
        | append (test-images-show-cernbox-v11-bundle)
        | append (test-images-resolve-cernbox-bundle)
        | append (test-images-resolve-cernbox-bundle-env-override)
        | append (test-images-resolve-role-env-beats-generic)
        | append (test-images-resolve-generic-fallback-when-role-env-unset)
        | append (test-images-resolve-empty-role-env-falls-back-to-generic)
        | append (test-images-resolve-opposite-role-isolation)
        | append (test-images-resolve-opencloud-ocis-role-env)
        | append (test-images-resolve-opencloud-ocis-generic-fallback-when-role-env-unset)
        | append (test-images-resolve-opencloud-ocis-empty-role-env-falls-back-to-generic)
        | append (test-images-resolve-opencloud-ocis-opposite-role-isolation)
        | append (test-images-resolve-nextcloud-v35-contact-token-flow-default-beats-version-default)
        | append (test-images-resolve-nextcloud-v35-contact-wayf-flow-default-beats-version-default)
        | append (test-images-resolve-nextcloud-v35-contact-token-flow-role-env-beats-version-role-env)
        | append (test-images-resolve-nextcloud-v35-contact-token-flow-generic-env-beats-version-role-env)
        | append (test-images-resolve-nextcloud-v35-contact-token-receiver-flow-role-env)
        | append (test-images-resolve-nextcloud-v35-contact-wayf-flow-role-env-beats-version-role-env)
        | append (test-images-resolve-nextcloud-v35-contact-wayf-flow-generic-env-beats-version-role-env)
        | append (test-images-resolve-nextcloud-v35-contact-wayf-receiver-flow-role-env)
        | append (test-images-resolve-two-party-happy)
    ) | flatten
    run-suite "cli/tuple-flags" $SUITE_PATH $results
}
