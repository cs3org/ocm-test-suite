# Account credentials loader.
# Reads platform config files from config/actors/platforms/ and validates accounts.

use ../run/execution-id.nu [validate-path-segment]

# Load and validate account credentials from a platform config file.
export def load-account-credentials [root: string, platform: string, account_name: string, label: string] {
    if ($platform | is-empty) {
        error make {msg: $"($label) platform is empty"}
    }
    if ($account_name | is-empty) {
        error make {msg: $"($label) account is empty"}
    }
    validate-path-segment $platform $"($label).platform"
    validate-path-segment $account_name $"($label).account"

    let platform_cfg_path = ($root | path join $"config/actors/platforms/($platform).nuon")
    if not ($platform_cfg_path | path exists) {
        error make {msg: $"Actor platform config not found: config/actors/platforms/($platform).nuon"}
    }
    let platform_cfg = (open $platform_cfg_path)

    if ($platform_cfg.accounts? == null) {
        error make {msg: $"Platform config '($platform).nuon' missing accounts record"}
    }
    let account = ($platform_cfg.accounts | get --optional $account_name)
    if $account == null {
        error make {msg: $"Actor account '($account_name)' not found in platform '($platform)' config [role: ($label)]"}
    }

    if ($account.username? | default "" | is-empty) {
        error make {msg: $"Actor account '($account_name)' on '($platform)' has empty username [role: ($label)]"}
    }
    if ($account.password? | default "" | is-empty) {
        error make {msg: $"Actor account '($account_name)' on '($platform)' has empty password [role: ($label)]"}
    }

    {
        platform: $platform,
        account: $account_name,
        username: $account.username,
        password: $account.password,
    }
}
