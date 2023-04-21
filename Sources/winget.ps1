@{
    # Source information
    Name                 = 'winget'
    ShortName            = 'wg'
    DisplayName          = 'Windows Package Manager'

    # Style information
    Color                = "$($PSStyle.Foreground.Magenta)"

    # Package queries
    GetAvailablePackages = { Find-WinGetPackage }
    GetInstalledPackages = { Get-WinGetPackage }
    GetPackageUpdates    = { 
        Get-WinGetPackage | 
            Where-Object { ($IncludeUnknown -or ($_.Version -ne 'Unknown')) -and $_.IsUpdateAvailable } 
    }

    # Package commands
    InstallPackage       = { 
        param($Package)
        Install-WinGetPackage $Package.Id
    }
    UninstallPackage     = { 
        param($Package)
        Uninstall-WinGetPackage $Package.Id
    }
    UpdatePackage        = { 
        param($Package)
        Update-WinGetPackage $Package.Id
    }

    # Source commands
    UpdateSources       = { winget source update *> $null }

    # Package formatters
    PackageFormatter            = {
        [OutputType([FuzzyPackage])]
        param(
            [Parameter(ValueFromPipeline)]
            [object]$Package,

            [switch]$isUpdate
        )

        process {
            [FuzzyPackage]@{
                Name             = $Package.Name
                Id               = $Package.Id
                Version          = $Package.Version
                Source           = 'winget'   
                Repo             = if (-not $Package.Source) { 'N/A' } else { $Package.Source }
                AvailableVersion = if ($isUpdate) { $Package.AvailableVersions[0] }
            }
        }
    }

    SourceCheck          = {
        # Check if winget is installed
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            # Check if powershell module is installed
            # Wildcard is used here because I'm not sure whether the -PSModule suffix will remain
            if (Get-Module -Name 'Microsoft.WinGet.Client*' -ErrorAction SilentlyContinue) {
                $true
            } else {
                $false
            }
        } else {
            return $false
        }
    }

    ResultCheck          = {
        # Check if the winget command was successful
        $_.status -eq 'Ok'
    }
}

# Notes
# -----
# This script could be rewritten remove the requirement for the Microsoft.WinGet.Client module.