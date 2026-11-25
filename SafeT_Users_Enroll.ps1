# TrustBuilder Safe-T Users Enroll - v1.0
# TrustBuilder Safe-T Script to enroll/reenroll users without a MFA tool or with enroll link expired
# DISCLAIMER : This script is provided "AS IS" WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES of any kind. You use this script at your know risk
# Help with -help option command line. Implemented @ end of script

#region Parameters
# CommandLine Args management
[CmdletBinding( DefaultParameterSetName='run' )]
Param (
    # Show help
    [Parameter(ParameterSetName='help')]
    [Alias('?','h')][switch]$help=$false,
    # Safe-T tenant id
    [Parameter(Position=0,mandatory=$true,ParameterSetName='run')]
    [Alias('t','tenant')][string]$tenantid = '',
    # Reenroll users with expired enrolment link
    [Parameter(ParameterSetName='run')]
    [Alias('r')][switch]$reenroll=$false,
    # Enroll newly users not already with enrolment link
    [Parameter(ParameterSetName='run')]
    [Alias('f')][switch]$firstenroll=$false,
    # Show users list
    [Parameter(ParameterSetName='run')]
    [Alias('u')][switch]$users=$false,
    # Output as object, not text
    [Parameter(ParameterSetName='run')]
    [Alias('o')][switch]$object=$false

)
#endregion

    
# Script variables for various things
$ScriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
Push-Location $ScriptPath
$ScriptName = $MyInvocation.MyCommand.Name
$RootScriptName = $ScriptName.Split('.')[0]
# Don't show Invoke-WebRequest progress
$progressPreference = 'silentlyContinue'
$global:progressPreference = 'silentlyContinue'

$Name    = "TrustBuilder Safe-T Users Enroll/Reenroll"
$Version = "1.0"
$timestamp = Get-Date

# Show help recursive call
if ($help) { get-help (Join-Path $ScriptPath $ScriptName) -Detailed ; exit 0 }

# ------------ Use OAuth Module ------------ 
if (-not (Get-Module PSAuthClient)) { Install-Module PSAuthClient -Scope:CurrentUser -force -WarningAction SilentlyContinue}
    
$apibaseurl = "https://api.trustbuilder.io"
if ($tenantid.Contains("preview") ) { $apibaseurl = "https://api.preview.trustbuilder.io" }

# ------------ Discover Safe-T tenant ------------ 
try { 
    $ng = Invoke-WebRequest -UseBasicParsing -Method "GET" -Uri ($apibaseurl + "/api/v1/tenants/public?domain=" + $tenantid + ".admin.trustbuilder.io")
    $admin_portal = (($ng.Content | convertfrom-json).applications | where client_id -eq "admin_portal").issuer_uri
        }
        catch [System.Net.WebException] {
            if ($_.Exception.Response.StatusCode.Value__ -eq 404) {Write-host ("The tenant "+ $tenantid +" does not exist, exiting !")}
            else {Write-host ("Error unknown, exiting !")}
            exit -1 }
        catch {
            Write-host ("Error unknown, exiting !")
            exit -1 }

# ------------ try OIDC discovery URL ------------ 
try {
    $WellKnown = Get-OidcDiscoveryMetadata ($admin_portal +"/.well-known/openid-configuration")
        }
        catch [System.Net.WebException] {
            if ($_.Exception.Response.StatusCode.Value__ -eq 404) {Write-host ("The Safe-T tenant "+ $tenantid +" does not exist, exiting !")}
            else {Write-host ("Error unknown, exiting !")}
            exit -1 }
        catch {
            Write-host ("Error unknown, exiting !")
            exit -1 }

$Client_id    = "admin_portal"
$redirect_uri = "https://" + $tenantid + ".admin.trustbuilder.io/auth/login-redirect"
# Ensure UserAgent is authorize within Safe-T
$UserAgent    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36"

$scope       = "applications:read applications:write attributes:read attributes:write audits:read certificates:read certificates:write config:read config:write enrollments:read enrollments:write fido_keys:read fido_keys:write fido_policies:read fido_policies:write idps:read idps:write mfa_policies:write mfa_secret_codes:ask_reset mfa_secure_tokens:write openid users:config:write users:read users:write"

# Clear Variables
$resp_user = ""
$resp = ""
$rest = ""
# Declare token as global if not exist, else do nothing (reusing token under same pws instance)
if (-not (Get-Variable token -Scope Global -ErrorAction SilentlyContinue)) { $Global:token=@{access_token=""} }

 # ------------ Authenticate ------------ 
$Authorize=@{
    Uri = $WellKnown.authorization_endpoint
    Scope = $scope
    Client_id = $Client_id
    usePkce = $true
    redirect_uri = $redirect_uri
    userAgent = $UserAgent
    }

write-debug ("Current time      : " + (Get-UnixTime) +" - "+ (Get-Date)               )
write-debug ("Access_token exp  : " + (Get-UnixTime) +" - "+ (Get-UnixTime -epoch $access_token_clear.exp ))
write-debug ("Refresh_token     : " + $Global:token.refresh_token )

# test access_token if exist and valid
if (-not [string]::IsNullOrEmpty($Global:token) -and $Global:token.access_token.StartsWith("eyJ")) {
    $access_token_clear  = $Global:token.access_token  | ConvertFrom-JsonWebToken
    # 20 secs time window for execution
    if ( $access_token_clear.exp -gt ((get-unixtime)+20) ) {
        # use refresh_token if exist to renew access_token and refresh_token
        if (-not [string]::IsNullOrEmpty($Global:token.refresh_token) ) {
            write-debug ("Access_token valid, got refresh_token : refresh !")
            $Global:token = Invoke-OAuth2TokenEndpoint -uri $WellKnown.token_endpoint -refresh_token $Global:token.refresh_token -client_id $Client_id -scope $scope -nonce $code.nonce
            write-debug ("Access_token refreshed, new exp  : " + (Get-UnixTime) +" - "+ (Get-UnixTime -epoch $access_token_clear.exp ))
            write-debug ("New Refresh_token                : " + $Global:token.refresh_token )
            }
        } else {
            # access_token expired, full authent
            write-debug ("No refresh_token : full auth !")
            $code  = Authorize @Authorize
            $code.uri = $WellKnown.token_endpoint
            $Global:token = Token @code          
            }
    } else {
        # no access_token, full authent
        $code  = Authorize @Authorize
        $code.uri = $WellKnown.token_endpoint
        $Global:token = Token @code          
        }

# ------------ tenant users count ------------ 
$rest=@{
    Header = @{'authorization' = 'Bearer ' + $token.access_token }
    Method = "GET"
    Uri = $apibaseurl + "/api/v1/users?offset=0&limit=1"
    ContentType = "text/html"
    UserAgent   = $UserAgent
    }
try {
    $resp = Invoke-WebRequest -UseBasicParsing @rest
    } catch {
        Write-host ("Error requesting users count, exiting !")
        exit -1 }

$UsersCount = ($resp.Content | ConvertFrom-Json).total
write-debug ("tenant users count  : " + $UsersCount)

# ------------ Retrieve users with paging ------------ 

$AccountsList=[System.Collections.Generic.List[object]]::new()
$offset = 0
$page = 5
$usersretrievedcount = 0
while ( $usersretrievedcount -lt $UsersCount) {
    
    $rest=@{
        Header = @{'authorization' = 'Bearer ' + $token.access_token }
        Method = "GET"
        Uri = $apibaseurl + "/api/v1/users?offset=" + $offset + "&limit=" + $page
        ContentType = "text/html"
        UserAgent   = $UserAgent
        }
    try {
        $resp = Invoke-WebRequest -UseBasicParsing @rest
        } catch {
            Write-host ("Error requesting users, exiting !")
            exit -1 }
    
    $offset += $page
    
    $resp = $resp.Content | ConvertFrom-Json  
    $usersretrievedcount += $resp.items.count
   
    $resp.items | % { 
        # More readable date time, TODO culture format
        if ($_.enrollment_info.updated_at.length -gt 0)   {$updatedDate = [datetime]$_.enrollment_info.updated_at}  else {$updatedDate  = [System.Nullable[datetime]] $null}
        if ($_.enrollment_info.expiry.length -gt 0)       {$expiryDate  = [datetime]$_.enrollment_info.expiry}      else {$expiryDate   = [System.Nullable[datetime]] $null}
        
        if ($_.enrollment_info.status -eq "IN_PROGRESS") {
            $enroll_duration=[math]::Floor(($expiryDate-$updatedDate).TotalHours)
            if ($expiryDate -le $timestamp -and $expiryDate) {$enroll_expired = $true} else {$enroll_expired = $false} 
            }
        else {$enroll_expired = $null; $enroll_duration=$null}
        

        $AccountsList.Add([PSCustomObject]@{id=$_.id;username=$_.username;preferred_email=$_.preferred_email;enroll_status=$_.enrollment_info.status;enroll_updated_at=$updatedDate;enroll_expiry=$expiryDate;enroll_duration=$enroll_duration;enroll_expired=$enroll_expired } ) 
        }
        write-debug ("usersretrievedcount     : " + $usersretrievedcount )
        $progressPreference = 'Continue'; 
        Write-Progress -Activity "Fetching users in progress .." -Status (([math]::round(100 * $usersretrievedcount / $UsersCount)).tostring()+"% Complete") -PercentComplete (100 * $usersretrievedcount / $UsersCount)
        $progressPreference = "Silentlycontinue"
}


# Show all users list as text
if ($users -and !$object) { 
    Write-Output ("`r`n`r`nSafe-T Users list, tenant " + $tenantid)
    Write-Output "-----------------------------------------"
    $AccountsList | ft * 
    }

# Output all users list as object (default)
if (($users -and $object) -or (!$users -and !$reenroll -and !$firstenroll)) { $AccountsList }


  
$TempAccountsEnrolment=[System.Collections.Generic.List[object]]::new()
# ------------ Generate (&send if activated) enroll link for users with no enroll status ($firstenroll) or IN_PROGRESS expired ($reenroll) ------------ 
if ($reenroll -or $firstenroll) { 
    $i=0
    $AccountsList | % {
            # reenroll                                                                 or  #first enroll
        if (($reenroll -and $_.enroll_status -eq "IN_PROGRESS" -and $_.enroll_expired) -or ($firstenroll -and !$_.enroll_status)) {

            $body='{"user_ids": ["' + $_.id + '"]}'

            $rest=@{
                Header = @{'authorization' = 'Bearer ' + $token.access_token }
                Method = "POST"
                Uri = $apibaseurl + "/api/v1/sso/registration/enroll"
                ContentType = "application/json"
                UserAgent   = $UserAgent
                Body = $body
                }
            try {
                $resp_enroll  = Invoke-WebRequest -UseBasicParsing @rest
                } catch {
                    Write-host ("Error requesting enroll link, exiting !")
                    exit 0 }
        
            $enroll_link = ($resp_enroll.Content | ConvertFrom-Json).enrollment_links[0].link
            $TempAccountsEnrolment.Add([PSCustomObject]@{id=$_.id;enroll_link=$enroll_link } )

        $progressPreference = 'Continue'; 
        Write-Progress -Activity "Fetching users in progress .." -Status (([math]::round(100 * $i / $UsersCount)).tostring()+"% Complete") -PercentComplete (100 * $i++ / $UsersCount)
        $progressPreference = "Silentlycontinue"
        }
    }
    # ------------ Retrieve USers for new enrolment info ------------ 
    # There is a delay between enrolment link generation and related info available on safe-t users endpoint
    # As a workaround, we have generated enroll link for users, then wait for 3 sec for last users, and then retrieve all (re)enrolled info
    if ($TempAccountsEnrolment.count -gt 0) { Write-host ("Waiting users synchro, 3 sec"); sleep 3 }
   
    $AccountsEnrolment=[System.Collections.Generic.List[object]]::new()
    $i=0
    $TempAccountsEnrolment | % {
            $rest=@{
                Header = @{'authorization' = 'Bearer ' + $token.access_token }
                Method = "GET"
                Uri = $apibaseurl + "/api/v1/users/" + $_.id
                ContentType = "text/html"
                UserAgent   = $UserAgent
                }
            try {
                $resp_user  = Invoke-WebRequest -UseBasicParsing @rest
                } catch {
                    Write-host ("Error requesting selected user, exiting !")
                    exit 0 }

            $cu = ($resp_user.Content | ConvertFrom-Json)
                    
            # More readable date time, TODO culture format
            if ($cu.enrollment_info.updated_at.length -gt 0)   {$updatedDate = [datetime]$cu.enrollment_info.updated_at}  else {$updatedDate  = [System.Nullable[datetime]] $null}
            if ($cu.enrollment_info.expiry.length -gt 0)       {$expiryDate  = [datetime]$cu.enrollment_info.expiry}      else {$expiryDate   = [System.Nullable[datetime]] $null}
        
            if ($cu.enrollment_info.status -eq "IN_PROGRESS") {
                $enroll_duration=[math]::Floor(($expiryDate-$updatedDate).TotalHours)
                if ($expiryDate -le $timestamp -and $expiryDate) {$enroll_expired = $true} else {$enroll_expired = $false} 
                }
            $AccountsEnrolment.Add([PSCustomObject]@{id=$cu.id;username=$cu.username;preferred_email=$cu.preferred_email;enroll_status=$cu.enrollment_info.status;enroll_updated_at=$updatedDate;enroll_expiry=$expiryDate;enroll_duration=$enroll_duration;enroll_link=$_.enroll_link } )
            
        
        }


    # Show (re)enrolled users list
    if (!$object) { 
        Write-Output ("`r`n`r`nSafe-T (re)enrolled Users list, tenant " + $tenantid)
        Write-Output "------------------------------------------------"
        $AccountsEnrolment | ft * 
        }
    if ($object) { $AccountsEnrolment }

}
<#
.SYNOPSIS
TrustBuilder Safe-T Users Enroll - v1.0
DISCLAIMER : This script is provided "AS IS" WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES of any kind. You use this script at your know risk

.DESCRIPTION
TrustBuilder Safe-T Script to enroll/reenroll users without a MFA tool or with enroll link expired
Can also provide users informations from TrustBuilder Safe-T
In case of first enroll or reenroll, the link is displayed by the script, but note that if the registration policy is set to email distribution mode, the link will be sent to the user also
The administrator user will be authenticated with whatever MFA tool available for him on the Safe-T tenant admin portal

The use of this script required:
    * A Safe-T tenant access with admin role
    * An internet connection to TrustBuilder services
    * Powershell at least v5.1 on Windows 11
	* .Net 4.5 must be installed to support TLS 1.2 and 1.3
    * Possibility to install a PowerShellGallery module (PSAuthClient)
      (installation of the external PS module : https://www.powershellgallery.com/packages/PSAuthClient)
      this package provide OIDC authentication within embedded webview (Microsoft webview binay within this module)

Versions history :	
v1.0 - 2026.11.25	- Initial version

.INPUTS
None. You cannot pipe objects to this script

.OUTPUTS
Users text view (without switch), Array of users (-object switch)
(re)enrolled users text view with link (with -reenroll/-firstenroll switches), Array of (re)enrolled users with link (with -reenroll/-firstenroll and -object switches)

.PARAMETER  help
Optional, default is false
Aliases : h
Show this detailed help

.PARAMETER tenant
Mandatory, default is true
Aliases : t
The Safe-T tenant to use

.PARAMETER object
Optional, default is false
Outputs as PSobject

.PARAMETER reenroll
Optional, default is false
Aliases : r
Regenerate link for users for which the enrolment link is expired

.PARAMETER firstenroll
Optional, default is false
Aliases : f
Generate a link for users which never got an enrolment link

.PARAMETER users
Optional, default is false
Aliases : u
Output list of the Safe-T tenant's users

.EXAMPLE
PS> .\SafeT_Users_Enroll.ps1 -t <tenantid>
PS> .\SafeT_Users_Enroll.ps1 -t <tenantid> -users -object
Show all users of the tenant as Array of PSObject

.EXAMPLE
PS> .\SafeT_Users_Enroll.ps1 -t <tenantid> -users
Show all users of the tenant as text

.EXAMPLE
PS> .\SafeT_Users_Enroll.ps1 -t <tenantid> -reenroll
Generate and display (and send) an enrolment link for users with expired one
if the registration policy is set to email distribution mode, the link will be sent to the user also

.EXAMPLE
PS> .\SafeT_Users_Enroll.ps1 -t <tenantid> -firstenroll
Generate and display (and send) an enrolment link for users never enrolled
if the registration policy is set to email distribution mode, the link will be sent to the user also

.EXAMPLE
PS> .\SafeT_Users_Enroll.ps1 -t <tenantid> -reenroll -firstenroll -object
Generate (and send) an enrolment link for users never enrolled and for users never enrolled
if the registration policy is set to email distribution mode, the link will be sent to the user also
Output as Array of PSObject

#>