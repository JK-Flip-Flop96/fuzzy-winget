@{
    # Source information
    Name             = 'winget'
    ShortName        = 'wg'
    DisplayName      = 'Windows Package Manager'

    # Style information
    Color            = "$($PSStyle.Foreground.Magenta)"

    # Package queries
    AvailableQuery   = { Find-WinGetPackage }
    InstalledQuery   = { Get-WinGetPackage }
    UpdateQuery      = { 
        Get-WinGetPackage | 
            Where-Object { ($IncludeUnknown -or ($_.Version -ne 'Unknown')) -and $_.IsUpdateAvailable } 
    }

    # Package commands
    InstallCommand   = { 
        param($Package)
        Install-WinGetPackage $Package.Id
    }
    UninstallCommand = { 
        param($Package)
        Uninstall-WinGetPackage $Package.Id
    }
    UpdateCommand    = { 
        param($Package)
        Update-WinGetPackage $Package.Id
    }

    # Source commands
    RefreshCommand   = { winget source update *> $null }

    # Package formatters
    Formatter        = {
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

    CheckStatus      = {
        # Check if winget is installed
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            return $true
        } else {
            return $false
        }
    }

    ResultCheck      = {
        # Check if the winget command was successful
        $_.status -eq 'Ok'
    }
}