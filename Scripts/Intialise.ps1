# NOTE: This script is run when the module is imported so we need to keep it as simple as possible.
#       We don't want to negatively the startup time of user's shells.

# Check if the user has any package managers installed
function Test-PackageManagers {
    $packageManagers = @{'winget' = $false
                         'scoop' = $false 
                         'choco' = $false}

    foreach ($packageManager in $($packageManagers.Keys)) {
        $packageManagers[$packageManager] = Get-Command $packageManager -ErrorAction SilentlyContinue
    }

    return $packageManagers
}

# Check if fzf is installed
if (!(Get-Command fzf -ErrorAction SilentlyContinue)) {
    Write-Host "[Fuzzy-Winget] fzf is not installed. Please install fzf before using this module" -ForegroundColor Red
    
    # Check if the user has any package managers installed
    $packageManagers = Test-PackageManagers

    # If the user has no package managers installed then exit
    if ($packageManagers.Values -notcontains $true) {
        Write-Host "[Fuzzy-Winget] No package managers are installed. Please install a package manager before using this module (Winget, Scoop or Chocolatey)" -ForegroundColor Red
        exit
    }

    # If the user has multiple package managers installed then prompt them to select one
    if ($packageManagers.Values -contains $true -and $packageManagers.Values | Where-Object {$_ -eq $true} | Measure-Object | Select-Object -ExpandProperty Count -gt 1) {
        
        # TODO: Improve this so that numbers aren't skipped if a package manager isn't installed
        # Print a number next to each package manager that is installed
        $packageManagers.Keys | ForEach-Object {
            if ($packageManagers[$_] -eq $true) {
                Write-Host "$($packageManagers.Keys.IndexOf($_)) - $_"
            }
        }

        # Prompt the user to select a package manager
        $packageManager = Read-Host "Please select a package manager to install fzf with"

        # Check if the user entered a valid number
        if ($packageManager -lt 0 -or $packageManager -gt $packageManagers.Count) {
            Write-Host "[Fuzzy-Winget] Invalid package manager number: $packageManager" -ForegroundColor Red
            exit
        }

        # Get the package manager name from the number
        $packageManager = $packageManagers.Keys[$packageManager]
    } else {
        $packageManager = $packageManagers.Keys | Where-Object {$packageManagers[$_] -eq $true}
    }

    # Install fzf using the selected package manager
    if ($packageManager -eq "winget") {
        winget install fzf # Keep it simple, don't try to use the powershell module
    } elseif ($packageManager -eq "scoop") {
        scoop install fzf
    } elseif ($packageManager -eq "choco") {
        choco install fzf
    } else {
        Write-Host "[Fuzzy-Winget] Unknown package manager: $packageManager" -ForegroundColor Red
    }


}

# Check the version of fzf, strip the commit hash
$version = $(fzf --version) -split " " | Select-Object -First 1
$testedVersion = "0.38.0" # TODO: Move this to the manifest? 

# Check if the version is greater than the minimum tested version
if ($version -lt $testedVersion) {
    Write-Host "[Fuzzy-Winget] fzf $version has not been tested with this module. Consider upgrading to fzf to version $testedVersion or greater" -ForegroundColor Yellow
    exit
}