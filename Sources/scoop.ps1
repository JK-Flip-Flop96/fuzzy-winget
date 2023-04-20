<#
.SYNOPSIS
    Scoop source for FuzzyPackages
#>
@{
    # Source information
    Name             = 'scoop'
    ShortName        = 'sc'
    DisplayName      = 'Scoop'

    # Style
    Color            = "$($PSStyle.Foreground.Cyan)"

    # Package queries 
    AvailableQuery   = { scoop search 6> $null }
    InstalledQuery   = { scoop list 6> $null }
    UpdateQuery      = { scoop status 6> $null }

    # Package commands
    InstallCommand   = {
        param($Package)
        scoop install $Package.Name
    }
    UninstallCommand = { 
        param($Package)
        scoop uninstall $Package.Name
    }
    UpdateCommand    = { 
        param($Package)
        scoop update $Package.Name
    }

    # Source commands
    RefreshCommand   = { scoop update *> $null }

    # Package formatters
    Formatter        = {
        [OutputType([FuzzyPackage])]
        param(
            [Parameter(ValueFromPipeline)]
            [object]$Package,

            [switch]$isUpdate
        )

        process {
            $ScoopPackage = [FuzzyPackage]@{
                Name   = $Package.Name
                Source = 'scoop'
            }

            if ($isUpdate) {
                $ScoopPackage.Repo = 'scoop' # Bucket name is not returned by scoop status
                $ScoopPackage.Version = $Package.'Installed version'
                $ScoopPackage.AvailableVersions = $Package.'Latest version'
            } else {
                $ScoopPackage.Repo = $Package.Source
                $ScoopPackage.Version = $Package.Version
            }

            $ScoopPackage
        }
    }

    CheckStatus      = {
        # Check if scoop is installed
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            return $true
        } else {
            return $false
        }
    }

    ResultCheck      = {
        # Check if the scoop command was successful
        $? -eq $true
    }
}