# TrustBuilder Safe-T — User Enrollment / Re-enrollment

Manage initial enrollment and re-enrollment for users in a TrustBuilder Safe-T tenant from PowerShell.

Use this script to review enrollment status, generate links for users who have not started enrollment, and regenerate expired links for enrollments in progress. Return the results as a readable table or as PowerShell objects for filtering, reporting, and export.

| Property | Value |
| --- | --- |
| Script | `SafeT_Users_Enroll.ps1` |
| Version | 1.0 |
| Release date | November 25, 2026 |

> Enrollment operations affect all accounts matching the selected criteria. Depending on your tenant's registration policy, generating a link may also send an email to the user. Review the user inventory before running an enrollment operation.

## Features

- List tenant users and their enrollment information.
- Identify expired enrollment links.
- Generate initial enrollment links for accounts with no enrollment status.
- Regenerate expired links for accounts with enrollment in progress.
- Authenticate interactively through OpenID Connect with PKCE.
- Reuse authentication tokens within the same PowerShell session.
- Return PowerShell objects for further processing.
- Select the preview API automatically when the tenant identifier contains `preview`.

## Requirements

- Windows 11 with PowerShell 5.1 or later.
- A TrustBuilder Safe-T tenant.
- A tenant account with the administrator role.
- Internet access to TrustBuilder services and PowerShell Gallery.
- Permission to install the `PSAuthClient` PowerShell module.
- An interactive desktop environment for the embedded authentication web view.

## Installation

Save `SafeT_Users_Enroll.ps1` to a local directory and open PowerShell in that directory.

The script attempts to install `PSAuthClient` for the current user when the module is not loaded. You can also install and import it before running the script:

```powershell
Install-Module -Name PSAuthClient -Scope CurrentUser
Import-Module PSAuthClient
```

## Quick Start

Start by listing the users in your tenant:

```powershell
.\SafeT_Users_Enroll.ps1 -tenantid 'my-tenant' -users
```

Replace `my-tenant` with the identifier used in your administration domain:

```text
my-tenant.admin.trustbuilder.io
```

Pass only the tenant identifier, not the full domain or URL. Complete the interactive sign-in when prompted.

To retrieve the inventory as PowerShell objects:

```powershell
$accounts = .\SafeT_Users_Enroll.ps1 -tenantid 'my-tenant' -users -object
```

## Parameters

| Parameter | Alias | Description |
| --- | --- | --- |
| `-tenantid <string>` | See note below | Tenant identifier. Required unless displaying help. Can also be supplied as the first positional argument. |
| `-users` | `-u` | Output the tenant user inventory. |
| `-firstenroll` | `-f` | Generate enrollment links for accounts with an empty or missing enrollment status. |
| `-reenroll` | `-r` | Regenerate expired links for accounts with status `IN_PROGRESS`. |
| `-object` | `-o` | Return PowerShell objects instead of formatted tables for the selected output. |
| `-help` | `-h`, `-?` | Display detailed help and exit. |

Use `-tenantid` explicitly in version 1.0. The current declaration, `[Alias("t,tenant")]`, does not define `-t` and `-tenant` as separate aliases. To enable both, replace it with:

```powershell
[Alias('t', 'tenant')]
```

## Usage

### Display Help

```powershell
.\SafeT_Users_Enroll.ps1 -help
```

### List All Users

Display a formatted table:

```powershell
.\SafeT_Users_Enroll.ps1 -tenantid 'my-tenant' -users
```

Return objects for further processing:

```powershell
$accounts = .\SafeT_Users_Enroll.ps1 -tenantid 'my-tenant' -users -object
```

When no inventory or enrollment switch is specified, the default output is the user inventory as PowerShell objects:

```powershell
$accounts = .\SafeT_Users_Enroll.ps1 -tenantid 'my-tenant'
```

### Review Expired Enrollment Links

Inspect affected accounts without generating new links:

```powershell
.\SafeT_Users_Enroll.ps1 -tenantid 'my-tenant' -users -object |
    Where-Object { $_.enroll_status -eq 'IN_PROGRESS' -and $_.enroll_expired } |
    Select-Object username, preferred_email, enroll_expiry
```

### Generate Initial Enrollment Links

```powershell
.\SafeT_Users_Enroll.ps1 -tenantid 'my-tenant' -firstenroll
```

This selects accounts with an empty or missing enrollment status. Selection is based on enrollment status, not on a separate audit of the user's MFA methods or enrollment history.

### Regenerate Expired Links

```powershell
.\SafeT_Users_Enroll.ps1 -tenantid 'my-tenant' -reenroll
```

This selects accounts whose enrollment status is `IN_PROGRESS` and whose enrollment link has expired.

### Run Both Enrollment Operations

```powershell
.\SafeT_Users_Enroll.ps1 -tenantid 'my-tenant' -firstenroll -reenroll
```

To capture the results as objects:

```powershell
$result = .\SafeT_Users_Enroll.ps1 -tenantid 'my-tenant' -firstenroll -reenroll -object

$result |
    Select-Object username, preferred_email, enroll_link, enroll_expiry
```

> Before using the enrollment commands in version 1.0, complete the request payload described under Known Issues.

### Export the User Inventory

```powershell
.\SafeT_Users_Enroll.ps1 -tenantid 'my-tenant' -users -object |
    Export-Csv -Path '.\safet-users.csv' -NoTypeInformation -Encoding UTF8
```

The script supports pipeline processing of its output but does not accept pipeline input.

## Enrollment Rules

| Operation | Selection criteria |
| --- | --- |
| Initial enrollment | The account has no enrollment status. |
| Re-enrollment | The account has status `IN_PROGRESS` and its link has expired. |
| Combined operation | The account matches either criterion. |

Expiration is evaluated against the timestamp captured at script startup.

Enrollment operations process all matching users in the tenant. There is no user or group targeting parameter, and filtering the output does not limit which accounts are processed.

The script does not implement `-WhatIf` or `-Confirm`.

## Email Delivery

Enrollment links are included in the operation results.

When your tenant's registration policy uses email distribution, generating an enrollment link can also send that link to the user. Configure this behavior in the tenant's registration policy; there is no separate email-delivery switch in the script.

## Output

### User Inventory

| Property | Description |
| --- | --- |
| `id` | User identifier. |
| `username` | Username. |
| `preferred_email` | Preferred email address. |
| `enroll_status` | Enrollment status returned by Safe-T. |
| `enroll_updated_at` | Last update timestamp for enrollment information. |
| `enroll_expiry` | Enrollment link expiration timestamp. |
| `enroll_duration` | Time between the update and expiration timestamps, in hours rounded down; calculated for `IN_PROGRESS`. |
| `enroll_expired` | Whether the link has expired; calculated for `IN_PROGRESS`, otherwise null. |

### Enrollment Results

Enrollment and re-enrollment results contain:

- `id`
- `username`
- `preferred_email`
- `enroll_status`
- `enroll_updated_at`
- `enroll_expiry`
- `enroll_duration`
- `enroll_link`

The enrollment result does not include `enroll_expired`.

Use `-object` to return these results as PowerShell objects. Otherwise, they are displayed as a formatted table.

Combining `-users` with an enrollment switch outputs both the initial inventory and the enrollment results. For automation, run inventory and enrollment separately to keep each result set consistent.

## Authentication

Authentication uses the `PSAuthClient` module, OpenID Connect discovery, and PKCE with the `admin_portal` client.

The access token is stored in `$Global:token`. Subsequent calls in the same PowerShell session may reuse or refresh the token rather than prompt for a new sign-in.

Use a fresh PowerShell session when switching tenants to avoid reusing authentication state from another tenant.

The requested OAuth scopes include administrative access beyond user enrollment. Run the script only in a trusted environment with an appropriately authorized account.

### Scheduled Execution

The authentication flow can require user interaction. Validate authentication under the intended execution account before using a scheduled task.

An unattended authentication flow and persistent token storage are not implemented in this version. Do not assume that an interactive session's token will be available to a scheduled task.

## Processing Flow

1. Select the production or preview API endpoint.
2. Discover the tenant's administration application.
3. Retrieve OpenID Connect metadata.
4. Authenticate or reuse the current session's token.
5. Retrieve the user count and fetch users in pages of five.
6. Calculate enrollment duration and expiration information.
7. Generate enrollment links for matching accounts when requested.
8. Wait three seconds after link generation, then retrieve updated information for the affected users.
9. Return the inventory or enrollment results.

### API Endpoints

| Environment | Base URL |
| --- | --- |
| Production | `https://api.trustbuilder.io` |
| Preview | `https://api.preview.trustbuilder.io` |

The preview endpoint is selected when the tenant identifier contains `preview`.

## Security Considerations

- Treat enrollment links as sensitive information.
- Protect exports containing user details or enrollment links.
- Do not commit tokens, enrollment links, or user exports to source control.
- Avoid writing debug output to shared logs: debug statements include refresh tokens.
- Review the selected accounts before running tenant-wide enrollment operations.


## Troubleshooting

| Problem | What to check |
| --- | --- |
| Tenant not found | Confirm the tenant identifier and whether the production or preview environment is being selected. |
| Module installation fails | Check PowerShell Gallery connectivity and your organization's module installation policies. |
| Sign-in fails | Check administrator access, authentication policies, and embedded web view availability. |
| User retrieval fails | Check connectivity, permissions, and token validity. |
| No users are processed | Confirm that accounts match the criteria for the selected enrollment operation. |
| No email is received | Check whether the tenant's registration policy uses email distribution. |

## Changelog

### 1.0 — 2026-11-25

- Initial release.
- User inventory with enrollment information.
- Initial enrollment and expired-link re-enrollment commands.
- Formatted and object-based output.

## Disclaimer

This script is provided “AS IS,” without express or implied warranties of any kind. Use it at your own risk.

## License

No distribution license is included with this release.
