# Read a CI cells JSON asset file and print compact one-line JSON.
# Output is suitable for writing to $GITHUB_OUTPUT as cells=<json>.
# Errors on invalid or missing JSON (non-zero exit), replacing jq -c . in CI.

def main [path: string] {
    print (open $path | to json --raw)
}
