# Status-specific warnings:
#   test-implementation-pending or vendor-unsupported without
#     tracking_url and tracking_note -> warning
#   vendor-out-of-scope without rationale -> warning

export def collect-status-warnings [adapters: record] {
    $adapters | transpose adapter_key entry | each {|row|
        $row.entry.capabilities | transpose cap_key cap_entry | each {|cap_row|
            let status = $cap_row.cap_entry.status
            let has_tracking_url = (($cap_row.cap_entry.tracking_url? | default "" | str length) > 0)
            let has_tracking_note = (($cap_row.cap_entry.tracking_note? | default "" | str length) > 0)
            let has_rationale = (($cap_row.cap_entry.rationale? | default "" | str length) > 0)

            if (($status == "test-implementation-pending") or ($status == "vendor-unsupported")) {
                if ((not $has_tracking_url) and (not $has_tracking_note)) {
                    {message: $"($row.adapter_key) / ($cap_row.cap_key) \(status=($status)\): no tracking_url or tracking_note"}
                }
            } else if $status == "vendor-out-of-scope" {
                if not $has_rationale {
                    {message: $"($row.adapter_key) / ($cap_row.cap_key) \(status=vendor-out-of-scope\): no rationale"}
                }
            }
        } | compact
    } | flatten
}
