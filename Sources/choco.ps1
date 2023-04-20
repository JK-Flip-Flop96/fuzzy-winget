@{
    # Source information
    Name             = 'choco'
    ShortName        = 'ch'
    DisplayName      = 'Chocolatey'

    # Style
    Color            = "$($PSStyle.Foreground.Yellow)"

    # Package queries
    # -r provides machine-readable output
    AvailableQuery   = { choco search -r }
    InstalledQuery   = { choco list --local-only -r } # FUTURE: Remove --local-only once choco updates to 2.0
    UpdateQuery      = { choco outdated -r }

    # Package commands
    # -y automatically answers yes to all prompts
    InstallCommand   = { 
        param($Package)
        choco install $Package.Name -y
    }
    UninstallCommand = { 
        param($Package) 
        choco uninstall $Package.Name -y
    }
    UpdateCommand    = { 
        param($Package)
        choco upgrade $Package.Name -y
    }

    # Source commands
    RefreshCommand   = { } # Choco doesn't have a refresh command

    # Package formatters
    Formatter        = {
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

    CheckStatus      = {
        # Check if choco is installed
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            return $true
        } else {
            return $false
        }
    }

    ResultCheck      = {
        # Check if the choco command was successful
        # 0 is returned when the command is successful
        # 1641 is returned when a reboot is initiated
        # 3010 is returned when a reboot is required
        $LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 1641 -or $LASTEXITCODE -eq 3010
    }
}