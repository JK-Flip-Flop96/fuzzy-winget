@{
    # Source information
    Name                 = 'choco'
    ShortName            = 'ch'
    DisplayName          = 'Chocolatey'

    # Style
    Color                = "$($PSStyle.Foreground.Yellow)"

    # Package queries
    # -r provides machine-readable output
    GetAvailablePackages = { choco search -r }
    GetInstalledPackages = { choco list --local-only -r } # FUTURE: Remove --local-only once choco updates to 2.0
    GetPackageUpdates    = { choco outdated -r }

    # Package commands
    # -y automatically answers yes to all prompts
    InstallPackage       = { 
        param
        (
            [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
            [FuzzyPackage[]]$Packages
        )
        process {
            choco install $($($Packages | Select-Object -ExpandProperty Name) -join ' ') -y
        }
    }
    UninstallPackage     = { 
        param
        (
            [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
            [FuzzyPackage[]]$Packages
        )
        process {
            choco uninstall $($($Packages | Select-Object -ExpandProperty Name) -join ' ') -y
        }
    }
    UpdatePackage        = { 
        param
        (
            [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
            [FuzzyPackage[]]$Packages
        )
        process {
            choco upgrade $($($Packages | Select-Object -ExpandProperty Name) -join ' ') -y
        }
    }

    # Source commands
    UpdateSources        = { } # Choco doesn't have a refresh command

    # Package formatters
    PackageFormatter     = {
        [OutputType([FuzzyPackage])]
        param(
            [Parameter(ValueFromPipeline)]
            [string]$Package,

            [switch]$isUpdate
        )

        process {
            # Choco's results are strings rather than objects, so we need to split them
            $PackageDetails = $Package -split '\|'

            # Create a new FuzzyPackage object
            [FuzzyPackage]@{
                Name             = $PackageDetails[0]
                Source           = 'choco'
                Repo             = 'choco'
                Version          = $PackageDetails[1]
                AvailableVersion = if ($isUpdate) { $PackageDetails[2] }
            }
        }
    }

    SourceCheck          = {
        # Check if choco is installed
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            return $true
        } else {
            return $false
        }
    }

    ResultCheck          = {
        # Check if the choco command was successful
        # 0 is returned when the command is successful
        # 1641 is returned when a reboot is initiated
        # 3010 is returned when a reboot is required
        $LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 1641 -or $LASTEXITCODE -eq 3010
    }
}