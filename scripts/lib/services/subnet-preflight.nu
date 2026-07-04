# Subnet conflict preflight: detect overlap between the deterministic exec_cidr
# and active Docker network subnets before compose overlays are started.
# Pure helpers (mask, overlap, find-conflicts) are unit-testable without Docker.
# The entry point check-subnet-preflight accepts --networks for injection in tests.

# Convert 4 IPv4 octets (each 0-255, most-significant first) to a 32-bit integer.
def parse-ipv4-int [octets: list<int>]: nothing -> int {
    $octets | reduce {|octet, acc| $acc * 256 + $octet}
}

# Convert a prefix length (0-32) to a 32-bit mask integer.
def prefix-to-mask [prefix: int]: nothing -> int {
    if $prefix == 0 { return 0 }
    if $prefix == 32 { return 4294967295 }
    4294967296 - (2 ** (32 - $prefix))
}

# Return true if two IPv4 CIDR strings share any address (one may contain the other).
# Returns false for non-IPv4 or malformed inputs rather than erroring.
# Validates octet range (0-255) and prefix range (0-32) before arithmetic.
export def cidr-overlaps [a: string, b: string]: nothing -> bool {
    if not ($a | str contains "/") { return false }
    if not ($b | str contains "/") { return false }
    let ap = ($a | split row "/")
    let bp = ($b | split row "/")
    # Require exactly 4 IPv4 octets; catches inputs like "10.1.1/24".
    if ($ap.0 | split row "." | length) != 4 { return false }
    if ($bp.0 | split row "." | length) != 4 { return false }
    try {
        let pa = ($ap.1 | into int)
        let pb = ($bp.1 | into int)
        if (($pa < 0) or ($pa > 32)) { return false }
        if (($pb < 0) or ($pb > 32)) { return false }
        let octets_a = ($ap.0 | split row "." | each { into int })
        let octets_b = ($bp.0 | split row "." | each { into int })
        if ($octets_a | any {|o| (($o < 0) or ($o > 255))}) { return false }
        if ($octets_b | any {|o| (($o < 0) or ($o > 255))}) { return false }
        let base_a = (parse-ipv4-int $octets_a)
        let base_b = (parse-ipv4-int $octets_b)
        let mask_a = (prefix-to-mask $pa)
        let mask_b = (prefix-to-mask $pb)
        (
            (($base_a | bits and $mask_b) == $base_b)
            or (($base_b | bits and $mask_a) == $base_a)
        )
    } catch {
        false
    }
}

# Filter network records to those whose subnets overlap exec_cidr.
# Input list shape: list<{name: string, subnets: list<string>}>.
# Missing subnets field is treated as empty (no conflicts from that network).
# Returns list<{name: string, conflicting_subnets: list<string>}>.
export def find-conflict-networks [
    exec_cidr: string,
    networks: list<record>,
]: nothing -> list<record> {
    $networks | each {|net|
        let subnets = ($net.subnets? | default [])
        let conflicts = ($subnets | where {|s| cidr-overlaps $exec_cidr $s})
        if ($conflicts | is-not-empty) {
            {name: $net.name, conflicting_subnets: $conflicts}
        }
    } | compact
}

# Validate that exec_cidr is a well-formed IPv4 CIDR; errors with a clear
# message if malformed. Does nothing if the input is valid.
def validate-exec-cidr [cidr: string] {
    let err = (
        if not ($cidr | str contains "/") {
            $"exec_cidr '($cidr)' is malformed: missing '/' separator"
        } else {
            let parts = ($cidr | split row "/")
            if ($parts | length) != 2 {
                $"exec_cidr '($cidr)' is malformed: extra '/' separator"
            } else {
                let octets = ($parts.0 | split row ".")
                if ($octets | length) != 4 {
                    let n = ($octets | length)
                    $"exec_cidr '($cidr)' is malformed: IP part must have 4 octets, got ($n)"
                } else {
                    let prefix_valid = (try {
                        let p = ($parts.1 | into int)
                        ($p >= 0) and ($p <= 32)
                    } catch { false })
                    if not $prefix_valid {
                        $"exec_cidr '($cidr)' is malformed: prefix '($parts.1)' must be an integer in 0..32"
                    } else {
                        let octet_status = (try {
                            let parsed = ($octets | each { into int })
                            if ($parsed | any {|o| (($o < 0) or ($o > 255))}) {
                                "out-of-range"
                            } else {
                                "ok"
                            }
                        } catch { "non-integer" })
                        if $octet_status == "non-integer" {
                            $"exec_cidr '($cidr)' is malformed: one or more octets are not integers"
                        } else if $octet_status == "out-of-range" {
                            $"exec_cidr '($cidr)' is malformed: one or more octets are out of range 0..255"
                        } else {
                            null
                        }
                    }
                }
            }
        }
    )
    if $err != null {
        error make {msg: $err}
    }
}

# Thin wrapper: list active Docker networks with their IPAM subnets.
# Returns list<{name: string, subnets: list<string>}>.
# Errors when docker is not installed, docker network ls fails, or any inspect fails.
# Use check-subnet-preflight --networks to inject a fixture and bypass docker entirely.
export def list-active-docker-networks []: nothing -> list<record> {
    let names_r = (try {
        ^docker network ls --format "{{.Name}}" | complete
    } catch {|e|
        let msg = $e.msg
        error make {msg: $"docker binary not found - cannot check subnet conflicts \(($msg)\); pass --networks to skip"}
    })
    if $names_r.exit_code != 0 {
        let code = $names_r.exit_code
        let err = $names_r.stderr
        error make {msg: $"docker network ls failed rc=($code): ($err)"}
    }
    let names = (
        $names_r.stdout
        | lines
        | each { str trim }
        | where {|s| not ($s | is-empty)}
    )
    $names | each {|name|
        let insp = (try {
            ^docker network inspect $name | complete
        } catch {|e|
            let msg = $e.msg
            error make {msg: $"docker network inspect ($name) failed: ($msg)"}
        })
        if $insp.exit_code != 0 {
            let code = $insp.exit_code
            let err = $insp.stderr
            error make {msg: $"docker network inspect ($name) failed rc=($code): ($err)"}
        }
        let data = (try { $insp.stdout | from json | get 0 } catch { null })
        if $data == null {
            error make {msg: $"docker network inspect ($name): could not parse JSON response"}
        }
        let subnets = (try {
            ($data.IPAM.Config
                | each {|c| $c.Subnet? | default ""}
                | where {|s| not ($s | is-empty)})
        } catch { [] })
        {name: $name, subnets: $subnets}
    }
}

# Fail fast if exec_cidr is malformed or overlaps any active Docker network subnet.
# Errors immediately with a clear message if exec_cidr is not a well-formed IPv4 CIDR.
# Error message includes exec_cidr and all conflicting network name/subnet pairs.
# --networks: inject a list<{name, subnets}> for unit tests; null (default) uses Docker.
# Docker command failures propagate as errors when --networks is not provided.
export def check-subnet-preflight [
    exec_cidr: string,
    --networks: any = null,
] {
    validate-exec-cidr $exec_cidr
    let active = if $networks != null { $networks } else { list-active-docker-networks }
    let conflicts = (find-conflict-networks $exec_cidr $active)
    if ($conflicts | is-not-empty) {
        let detail = ($conflicts | each {|c|
            let s = ($c.conflicting_subnets | str join ", ")
            $"  ($c.name) \(($s)\)"
        } | str join "\n")
        error make {
            msg: $"Subnet conflict: exec_cidr ($exec_cidr) overlaps active Docker network\(s\):\n($detail)"
        }
    }
}
