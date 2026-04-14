# Strict template renderer for CI blueprint files.
# Replaces {{placeholder:name}} tokens and fails hard on any that remain.

# Replace all {{placeholder:name}} tokens in `template` using `substitutions`.
# Fails with error make if any {{placeholder:...}} token remains after all
# substitutions are applied, preventing silently broken generated files.
export def render-template [
    template: string,
    substitutions: record,
]: any -> string {
    let result = ($substitutions | items {|key, val|
        {key: $key, val: ($val | into string)}
    } | reduce --fold $template {|sub, text|
        $text | str replace --all $"{{placeholder:($sub.key)}}" $sub.val
    })

    let remaining = ($result | parse --regex '\{\{placeholder:([^}]+)\}\}' | get capture0)
    if not ($remaining | is-empty) {
        let names = ($remaining | str join ", ")
        error make {msg: $"Unresolved template placeholders: ($names)"}
    }
    $result
}

# Read a blueprint file and render it with the given substitutions.
# Blueprint path must be absolute or relative to CWD.
export def render-blueprint [
    blueprint_path: string,
    substitutions: record,
]: any -> string {
    let template = (open --raw $blueprint_path)
    render-template $template $substitutions
}
