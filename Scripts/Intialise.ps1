# NOTE: This script is run when the module is imported so we need to keep it as simple as possible.
#       We don't want to negatively the startup time of user's shells.

# Check if the user has any package managers installed - this is only run if fzf is not installed so performance is less of an issue
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
    Write-Host "[Fuzzy-Winget] fzf is not installed. Attempting to install it now..." -ForegroundColor Yellow
    
    # Check if the user has any package managers installed
    $packageManagers = Test-PackageManagers

    # If the user has no package managers installed then exit
    if ($packageManagers.Values -notcontains $true) {
        Write-Host "[Fuzzy-Winget] No package managers are installed. Please install a package manager before using this module (Winget, Scoop or Chocolatey)" -ForegroundColor Red
        exit
    }

    # Count the number of package managers that are installed
    $installedPackageManagerCount = $($packageManagers.Keys | Where-Object {$packageManagers[$_] -eq $true} | Measure-Object | Select-Object -ExpandProperty Count)

    # If the user has multiple package managers installed then prompt them to select one
    if ($installedPackageManagerCount -gt 1) {
        
        # Filter the package managers to only include the ones that are installed
        $installedPackageManagers = $packageManagers.Keys | Where-Object {$packageManagers[$_] -eq $true} | ForEach-Object {$_.ToString()}

        # Print the package managers that are installed
        # e.g. [Number] PackageManager
        Write-Host "Select a package manager to install fzf:"
        for ($i = 0; $i -lt $installedPackageManagerCount; $i++) {
            Write-Host "[$($i + 1)] $($installedPackageManagers[$i])"
        }

        # Prompt the user to select a package manager
        $UserSelection = Read-Host "[C]ancel or [Number] ->"

        # Check if the user entered "c" or "C"
        if ($UserSelection -eq "c" -or $UserSelection -eq "C") {
            Write-Host "[Fuzzy-Winget] fzf is required to use this module" -ForegroundColor Red
            exit
        }

        # Check if the user entered a valid number
        if ($UserSelection -notmatch "^[0-9]+$") {
            Write-Host "[Fuzzy-Winget] `"$UserSelection`" is not a valid number" -ForegroundColor Red
            exit
        }

        # Check if the user entered a valid package manager number
        # NOTE: The user enters a number starting at 1, but the array starts at 0
        if ($UserSelection -gt $installedPackageManagerCount -or $UserSelection -eq 0) {
            Write-Host "[Fuzzy-Winget] `"$UserSelection`" falls outside of the accepted range" -ForegroundColor Red
            exit
        }

        # Get the package manager name from the number the user entered
        $packageManager = $installedPackageManagers[$UserSelection - 1]
    } else {
        $packageManager = $packageManagers.Keys | Where-Object {$packageManagers[$_] -eq $true}
    }

    Write-Host $packageManager

    # Install fzf using the selected package manager
    if ($packageManager -eq "winget") {
        winget install fzf # Keep it simple, don't try to use the powershell module
    } elseif ($packageManager -eq "scoop") {
        scoop install fzf
    } elseif ($packageManager -eq "choco") {
        choco install fzf
    } else {
        # This should never happen
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