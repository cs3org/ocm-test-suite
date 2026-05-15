# Stub after-down validator for the OCM code-flow.
# Real MITM evidence validation (redirect capture, token exchange checks) will
# be implemented here later.

# Run after-down validation for the code-flow. Stub: returns noop report.
export def run-after-down [artifacts_base: string, base_outcome: string] {
    {
        validators: [],
        override_outcome: null,
        override_exit_code: null,
        notes: [],
    }
}
