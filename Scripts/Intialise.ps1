# NOTE: This script is run when the module is imported so we need to keep it as simple as possible.
#       We don't want to negatively the startup time of user's shells.

# Check if fzf is installed
if (!(Get-Command fzf -ErrorAction SilentlyContinue)) {
    Write-Host "[Fuzzy-Winget] fzf is not installed. Please install fzf before using this module" -ForegroundColor Red
    exit # The rest of the tests are pointless if fzf isn't installed
}

# Check the version of fzf, strip the commit hash
$version = $(fzf --version) -split " " | Select-Object -First 1
$testedVersion = "0.38.0" # TODO: Move this to the manifest? 

# Check if the version is greater than the minimum tested version
if ($version -lt $testedVersion) {
    Write-Host "[Fuzzy-Winget] fzf $version has not been tested with this module. Consider upgrading to fzf to version $testedVersion or greater" -ForegroundColor Yellow
    exit
}