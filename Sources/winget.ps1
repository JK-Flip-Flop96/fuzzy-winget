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

    # Package commands - The actions in this script are a bit more complex than the other sources
    # The Winget Module doesn't have a way to install/uninstall/update packages in bulk, so we have to do it ourselves
    # We also have to handle the reporting of errors ourselves as the module doesn't do it for us
    InstallPackage       = { 
        param(
            [Parameter(ValueFromPipeline)]
            [FuzzyPackage]$Package
        )
        process {
            $result = Install-WinGetPackage $Package.Id
            if ($result.status -eq 'Ok') {
                Write-Host "Successfully Installed $($Package.Name)" -ForegroundColor Green
            } else {
                Write-Host "Failed to Install $($Package.Name)" -ForegroundColor Red
                Write-Host "Status: $($result.status)" -ForegroundColor Red
            }
        }
    }
    UninstallPackage     = { 
        param(
            [Parameter(ValueFromPipeline)]
            [FuzzyPackage]$Package
        )
        process {
            $result = Uninstall-WinGetPackage $Package.Id
            if ($result.status -eq 'Ok') {
                Write-Host "Successfully Uninstalled $($Package.Name)" -ForegroundColor Green
            } else {
                Write-Host "Failed to Uninstall $($Package.Name)" -ForegroundColor Red
                Write-Host "Status: $($result.status)" -ForegroundColor Red
            }
        }
    }
    UpdatePackage        = { 
        param(
            [Parameter(ValueFromPipeline)]
            [FuzzyPackage]$Package
        )
        process {
            $result = Update-WinGetPackage $Package.Id
            if ($result.status -eq 'Ok') {
                Write-Host "Successfully Updated $($Package.Name)" -ForegroundColor Green
            } else {
                Write-Host "Failed to Update $($Package.Name)" -ForegroundColor Red
                Write-Host "Status: $($result.status)" -ForegroundColor Red
            }
        }
    }

    # Source commands
    UpdateSources        = { winget source update *> $null }

    # Package formatters
    PackageFormatter     = {
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
}

# Notes
# -----
# This script could be rewritten remove the requirement for the Microsoft.WinGet.Client module.