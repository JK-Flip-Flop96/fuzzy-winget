<#
.SYNOPSIS
    Scoop source for FuzzyPackages
#>
@{
    # Source information
    Name                 = 'scoop'
    ShortName            = 'sc'
    DisplayName          = 'Scoop'

    # Style
    Color                = "$($PSStyle.Foreground.Cyan)"

    # Package queries 
    GetAvailablePackages = { scoop search 6> $null }
    GetInstalledPackages = { scoop list 6> $null }
    GetPackageUpdates    = { scoop status 6> $null }

    # Package commands
    InstallPackage       = {
        param
        (
            [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
            [FuzzyPackage[]]$Packages
        )
        process {
            scoop install $($($Packages | Select-Object -ExpandProperty Name) -join ' ')
        }
    }
    UninstallPackage     = { 
        param(
            [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
            [FuzzyPackage[]]$Packages
        )
        process {
            scoop uninstall $($($Packages | Select-Object -ExpandProperty Name) -join ' ')
        }
    }
    UpdatePackage        = { 
        param(
            [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
            [FuzzyPackage[]]$Packages
        )
        process {
            scoop update $($($Packages | Select-Object -ExpandProperty Name) -join ' ')
        }
    }

    # Source commands
    UpdateSources        = { scoop update *> $null }

    # Package formatters
    PackageFormatter     = {
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
                $ScoopPackage.AvailableVersion = $Package.'Latest version'
            } else {
                $ScoopPackage.Repo = $Package.Source
                $ScoopPackage.Version = $Package.Version
            }

            $ScoopPackage
        }
    }

    SourceCheck          = {
        # Check if scoop is installed
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            return $true
        } else {
            return $false
        }
    }

    ResultCheck          = {
        # Check if the scoop command was successful
        $? -eq $true
    }
}