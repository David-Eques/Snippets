param (
    [Parameter(Mandatory=$true)]
    [string]$UserSID,
    
    [Parameter(Mandatory=$true)]
    [string]$EnvironmentPath
)

try {
    $vhdPath = Join-Path -Path $EnvironmentPath -ChildPath "UVHD-$UserSID.vhdx"
    
    # Check if file exists first
    if (-not (Test-Path $vhdPath)) {
        Write-Host "PROFILE_NOT_FOUND"
        exit 0
    }

    # Try to open the file with exclusive access
    try {
        $file = [System.IO.File]::Open($vhdPath, 'Open', 'Read', 'None')
        # If we get here, file is not locked
        $file.Close()
        Write-Host "PROFILE_NOT_IN_USE"
        exit 0
    }
    catch {
        # File is locked/in use
        Write-Host "PROFILE_IN_USE"
        Write-Host "Profile VHDX is locked by active session"
        exit 1
    }
} catch {
    Write-Error "Error checking profile lock: $_"
    exit 2
}