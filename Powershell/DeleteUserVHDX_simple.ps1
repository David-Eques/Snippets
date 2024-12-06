# Script to delete a user's VHDX file given their SID
param (
    [Parameter(Mandatory=$true)]
    [string]$UserSID,
    
    [Parameter(Mandatory=$true)]
    [string]$EnvironmentPath,
    
    [Parameter()]
    [switch]$DryRun = $true
)

# Construct the path to the user's .vhdx file in the selected environment
$profilePath = Join-Path $EnvironmentPath "UVHD-$UserSID.vhdx"

# Check if the .vhdx file exists in the folder
if (Test-Path $profilePath) {
    Write-Output "Found profile: $profilePath"
    
    if ($DryRun) {
        Write-Output "[DRY RUN] Would delete profile file: $profilePath"
    } else {
        Write-Output "Deleting the profile .vhdx file: $profilePath"
        # Delete the .vhdx file
        Remove-Item -Path $profilePath -Force

        # Confirm deletion
        if (!(Test-Path $profilePath)) {
            Write-Output "Profile .vhdx file has been successfully deleted."
        } else {
            Write-Output "Failed to delete the profile .vhdx file."
        }
    }
} else {
    Write-Output "Profile .vhdx file for SID $UserSID not found in the environment path: $EnvironmentPath"
}

