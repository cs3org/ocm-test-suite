# Emit images.v1.json for a cell run: service/role/tag mapping + docker inspect pins.
# Writes to <artifacts_base>/meta/images.v1.json.

use ./inspect.nu [inspect-one-image]
use ../time/utc.nu [utc-now]

# Build and write images.v1.json for the given stack.
# Two-party stacks emit 7 service entries; one-party emit 3 (or sender + bundle slots).
# Entries whose role tag is absent or empty are skipped.
# inspect-one-image failures yield null fields without aborting.
export def emit-cell-images [
    artifacts_base: string,
    stack_id: string,
    images: record,
    is_two_party: bool,
] {
    let sender_bundle = ($images.bundle? | default {})
    let receiver_bundle = ($images.receiver_bundle? | default {})
    let sender_bundle_services = ($images.bundle_services? | default {})
    let receiver_bundle_services = ($images.receiver_bundle_services? | default {})
    let pairs = if $is_two_party and (not ($sender_bundle | is-empty) or not ($receiver_bundle | is-empty)) {
        mut bundle_pairs = []
        $bundle_pairs = ($bundle_pairs | append {service: "sender", role: "platform"})
        for slot in ($sender_bundle | columns) {
            $bundle_pairs = ($bundle_pairs | append {
                service: ($sender_bundle_services | get --optional $slot | default $"sender-($slot)"),
                role: $slot,
            })
        }
        $bundle_pairs = ($bundle_pairs | append {service: "receiver", role: "receiver_platform"})
        for slot in ($receiver_bundle | columns) {
            $bundle_pairs = ($bundle_pairs | append {
                service: ($receiver_bundle_services | get --optional $slot | default $"receiver-($slot)"),
                role: $"recv_($slot)",
            })
        }
        $bundle_pairs | append {service: "mitm", role: "mitmproxy"}
    } else if $is_two_party {
        [
            {service: "sender",         role: "platform"},
            {service: "receiver",       role: "receiver_platform"},
            {service: "sender-db",      role: "mariadb"},
            {service: "receiver-db",    role: "mariadb"},
            {service: "sender-cache",   role: "valkey"},
            {service: "receiver-cache", role: "valkey"},
            {service: "mitm",           role: "mitmproxy"},
        ]
    } else if not ($sender_bundle | is-empty) {
        mut bundle_pairs = [{service: "sender", role: "platform"}]
        for slot in ($sender_bundle | columns) {
            $bundle_pairs = ($bundle_pairs | append {
                service: ($sender_bundle_services | get --optional $slot | default $"sender-($slot)"),
                role: $slot,
            })
        }
        $bundle_pairs
    } else {
        [
            {service: "sender",       role: "platform"},
            {service: "sender-db",    role: "mariadb"},
            {service: "sender-cache", role: "valkey"},
        ]
    }

    # Keep only entries with a non-empty tag.
    let surviving = ($pairs | each {|p|
        let tag = (
            if ($p.role in ($sender_bundle | columns)) {
                $sender_bundle | get $p.role
            } else if ($p.role | str starts-with "recv_") {
                let slot = ($p.role | str substring 5..)
                $receiver_bundle | get --optional $slot | default ""
            } else {
                $images | get --optional $p.role | default ""
            }
        )
        if ($tag | is-empty) { null } else { $p | insert tag $tag }
    } | where {|x| $x != null})

    # Inspect each unique tag; cache to avoid duplicate docker calls.
    mut tag_cache: record = {}
    for entry in $surviving {
        let tag = $entry.tag
        if not ($tag in ($tag_cache | columns)) {
            let result = (try { inspect-one-image $tag } catch { null })
            $tag_cache = ($tag_cache | upsert $tag $result)
        }
    }
    let frozen_cache = $tag_cache

    let services = ($surviving | each {|entry|
        let inspect = (
            $frozen_cache
            | transpose key val
            | where {|r| $r.key == $entry.tag}
            | if ($in | is-empty) { null } else { ($in | first).val }
        )
        let repo_digests = if $inspect != null {
            let rd = ($inspect.repo_digests? | default [])
            if ($rd | describe | str starts-with "list") { $rd } else { [] }
        } else {
            []
        }
        let digest = if ($repo_digests | is-empty) {
            null
        } else {
            let first_d = ($repo_digests | first)
            if ($first_d | str contains "@") {
                $first_d | split row "@" | last
            } else {
                null
            }
        }
        {
            service: $entry.service,
            role: $entry.role,
            tag: $entry.tag,
            local_image_id: (if $inspect != null { $inspect.local_image_id? | default null } else { null }),
            repo_digests: $repo_digests,
            digest: $digest,
        }
    })

    let out = {
        schema_version: 1,
        captured_at: (utc-now),
        stack_id: $stack_id,
        services: $services,
    }

    mkdir ($artifacts_base | path join "meta")
    $out | to json --indent 2 | save --force ($artifacts_base | path join "meta" "images.v1.json")
}
