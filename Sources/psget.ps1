@{
    # Source information
    Name             = 'psget'
    ShortName        = 'ps'
    DisplayName      = 'PowerShellGet'

    # Style
    Color            = "$($PSStyle.Foreground.Blue)"

    # Package queries
    GetAvailablePackages   = { Find-Module }
    GetInstalledPackages   = { Get-InstalledModule }
    GetPackageUpdates      = {
        # PSGet doesn't have a built-in update query, so we have to do it ourselves 
        Get-InstalledModule | ForEach-Object {
            $LatestVersion = Find-Module $_.Name | Select-Object -ExpandProperty Version
            if ($LatestVersion -gt $_.Version) {
                # Add the latest version to the package object so that it can be used in the PackageFormatter
                $_ | Add-Member -MemberType NoteProperty -Name LatestVersion -Value $LatestVersion
                $_
            }
        }
    } 

    # Package commands
    InstallPackage   = { 
        param($Package)
        Install-Module $Package.Name
    }
    UninstallPackage = { 
        param($Package)
        Uninstall-Module $Package.Name
    }
    UpdatePackage    = { 
        param($Package)
        Update-Module $Package.Name
    }

    # Source commands
    UpdateSources   = { } # PSGet doesn't have a refresh command

    # Package formatters
    PackageFormatter        = {
        [OutputType([FuzzyPackage])]
        param(
            [Parameter(ValueFromPipeline)]
            [object]$Package,

            [switch]$isUpdate
        )

        process {
            [FuzzyPackage]@{
                Name             = $Package.Name
                Source           = 'psget'
                Repo             = $Package.Repository
                Version          = $Package.Version
                AvailableVersion = if ($isUpdate) { $Package.LatestVersion }
            }
        }
    }

    SourceCheck      = {
        # HACK: I'm not sure if this is the best way to check if PSGet is installed
        return $($(Get-Module -Name PowerShellGet -ListAvailable) | Measure-Object).Count -gt 0
    }

    ResultCheck      = {
        $? -eq $true
    }
}