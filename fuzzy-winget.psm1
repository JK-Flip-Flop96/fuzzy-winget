###################################################################################################################
# *** FuzzyPackages ***                                                                                           #
# Author: Stuart Miller                                                                                           #
# Version: 0.2.0                                                                                                  #           
# Description: A module of functions for interacting with package managers using fzf                              #
# License: MIT                                                                                                    #
# Repository: https://github.com/JK-Flip-Flop96/Fuzzy-Winget                                                      #   
###################################################################################################################

####################
# Class Definition #
####################

# Class to store information about a source
# Default examples are defined for winget, scoop, choco and psget at the bottom of this file
class FuzzySource {

    # Source information
    [string]$Name # The name of the source
    [string]$ShortName # The short name of the source
    [string]$DisplayName # The full name of the source
    [string]$Color # The color of the source, ANSI escape codes

    # Queries 
    [scriptblock]$AvailableQuery # The query to run to get the available packages
    [scriptblock]$InstalledQuery # The query to run to get the installed packages
    [scriptblock]$UpdateQuery # The query to run to get the packages that can be updated

    # Actions
    [scriptblock]$InstallCommand # The command to run to install a package
    [scriptblock]$UninstallCommand # The command to run to uninstall a package
    [scriptblock]$UpdateCommand # The command to run to update a package

    # Misc
    [scriptblock]$RefreshCommand # The command to run to refresh the source
    [scriptblock]$CheckStatus # The command to run to check if the source is installed and working
    [scriptblock]$Formatter # The command to run to format the output of the query
    [scriptblock]$ResultCheck # Scriptblock to check if the result of an action
}

# Class to stort information about a package
class FuzzyPackage {
    [string]$Name # The name of the package
    [string]$Id # The ID of the package (if applicable)
    [string]$Version # The version of the package
    [string]$AvailableVersion # The latest available version of the package (if applicable)
    [string]$Source # The source of the package
    [string]$Repo # The repository of the package

    # Convert the FuzzyPackage to a string for display in fzf
    # Format: <Source> <Name> (<ID>) <Version> -> <AvailableVersion>
    [string]ToString() {
        $SourceDefinition = $($global:SourceDefinitions)[$this.Source]
        return "$($SourceDefinition.Color)$($SourceDefinition.ShortName):$($this.Repo)$($global:PSStyle.Reset)`t" + 
        "$($this.Name)" + 
        "$(if ($this.ID) { " ($($global:PSStyle.Foreground.Yellow)$($this.ID)$($global:PSStyle.Reset))" })`t" + 
        "$(if ($this.AvailableVersion) {
                "$($global:PSStyle.Foreground.Red)$($this.Version)$($global:PSStyle.Foreground.Cyan) -> " + 
                "$($global:PSStyle.Foreground.Green)$($this.AvailableVersion)$($global:PSStyle.Reset)" } 
            else { 
                "$($global:PSStyle.Foreground.Green)$($this.Version)$($global:PSStyle.Reset)" 
            })"
    }

    # A string to represent the package in the install/uninstall/update steps
    [string]Title() {
        return "$($this.Name)" + 
        "$(if ($this.ID) { " ($($global:PSStyle.Foreground.Yellow)$($this.ID)$($global:PSStyle.Reset))" })"
    }
}

#######################
# Source Configuraton #
#######################

# The following hash table contains the configuration for each package source
# This section must be run last so that the functions are defined

$global:SourceDefinitions = @{
    winget = [FuzzySource]@{
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
    scoop  = [FuzzySource]@{
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
    choco  = [FuzzySource]@{
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
    psget  = [FuzzySource]@{
        # Source information
        Name             = 'psget'
        ShortName        = 'ps'
        DisplayName      = 'PowerShellGet'

        # Style
        Color            = "$($PSStyle.Foreground.Blue)"

        # Package queries
        AvailableQuery   = { Find-Module }
        InstalledQuery   = { Get-InstalledModule }
        UpdateQuery      = {
            # PSGet doesn't have a built-in update query, so we have to do it ourselves 
            Get-InstalledModule | ForEach-Object {
                $LatestVersion = Find-Module $_.Name | Select-Object -ExpandProperty Version
                if ($LatestVersion -gt $_.Version) {
                    # Add the latest version to the package object so that it can be used in the formatter
                    $_ | Add-Member -MemberType NoteProperty -Name LatestVersion -Value $LatestVersion
                    $_
                }
            }
        } 

        # Package commands
        InstallCommand   = { 
            param($Package)
            Install-Module $Package.Name
        }
        UninstallCommand = { 
            param($Package)
            Uninstall-Module $Package.Name
        }
        UpdateCommand    = { 
            param($Package)
            Update-Module $Package.Name
        }

        # Source commands
        RefreshCommand   = { } # PSGet doesn't have a refresh command

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
                    Source           = 'psget'
                    Repo             = $Package.Repository
                    Version          = $Package.Version
                    AvailableVersion = if ($isUpdate) { $Package.LatestVersion }
                }
            }
        }

        CheckStatus      = {
            # HACK: I'm not sure if this is the best way to check if PSGet is installed
            return $(Get-Module -Name PowerShellGet -ListAvailable) | Measure-Object.Count -gt 0
        }

        ResultCheck      = {
            $? -eq $true
        }
    }
}

# Global Variables
# Settings for the module
# TODO: Function to set these variables, like Set-PSReadLineOption
$global:FuzzyWinget = @{
    # Directory to store the cache files in
    CacheDirectory = "$env:tmp\FuzzyPackages" 

    # All of the sources that can be used
    # Will be populated by the keys of the SourceInfo variable
    Sources        = @()

    # The default sources to use when no sources are specified
    ActiveSources  = @('winget', 'scoop', 'choco', 'psget')

    # Allow the use of Nerd Fonts
    # If this is set to $true, the module will use the Nerd Font symbols
    UseNerdFonts  = $true
}

# Set the module's cache directory to the default if it doesn't exist
# TODO: This should be moved to the Initialise script
if (-not (Test-Path $global:FuzzyWinget.CacheDirectory)) {
    New-Item -ItemType Directory -Path $global:FuzzyWinget.CacheDirectory -Force | Out-Null
}

####################
# Helper Functions #
####################

# TODO: This function is an abomination and needs to be improved
# Helper function to handle the actual running of winget commands for the other functions in this module
# NOTE: This function is not exported and should not be called directly
function Invoke-FuzzyPackager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('install', 'uninstall', 'update')] # Confirms that the action is one of the three supported actions
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [ValidateSet('winget', 'scoop', 'choco', 'psget')] # Confirms that the source is one of the supported sources
        [string[]]$Sources, 

        [switch]$Confirm, # If the user should be prompted to confirm the action

        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] # Confirms that there is at least one package to act on
        [FuzzyPackage[]]$Packages
    )

    # --- Setup for fzf ---

    # Define the ps executable to use for the preview command, pwsh for core and powershell for desktop
    $PSExecutable = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' } 

    # Set the colour and title of the fzf window based on the action being performed
    $WindowTitle = "$(switch ($Action) {
        'install' { $PSStyle.Foreground.Green }
        'uninstall' { $PSStyle.Foreground.Red }
        'update' { $PSStyle.Foreground.Yellow }
    })$((Get-Culture).TextInfo.ToTitleCase("$Action Packages"))"

    # If Nerd Fonts are enabled, use an icons depicting a package
    $PromptText = if ($global:FuzzyWinget.UseNerdFonts) { ' >' } else { '>' }
    

    # --- End of setup for fzf ---

    <# FZF Arguments:
     --ansi: Enable ANSI color support
     --multi: Allow multiple selections
     --cycle: Allow cyclic scrolling through the list
     --border: Enable a border around the fzf window
       "bold": Set the border use heavy line drawing characters
     --border-label: Set the label for the border
     --border-label-pos: Set the position of the border label
     --color: Set the color of the border label
     --preview: Set the command to run for the preview window
     --preview-window: Set the size and position of the preview window
     --prompt: Set the prompt for the fzf window 
     --with-nth: Set which fields will be displayed in fzf
        2..: Display all text from the second field onwards - Skipping the index set below
    #>

    # Call fzf to select the packages to act on
    # Call ToString on each package to get the string representation of the package used for display in fzf
    # Prepend the index of the package to the string representation of the package so that I can get the package 
    # object from the index later
    $PackageCounter = -1 # Start the counter at -1 so that the first package is 0
    $SelectedPackages = $Packages | ForEach-Object {
        $PackageCounter++
        "$($PackageCounter) $($_.ToString())" 
    } | fzf --ansi `
        --multi `
        --cycle `
        --layout=reverse `
        --border 'bold' `
        --border-label " $WindowTitle " `
        --border-label-pos=3 `
        --margin=0 `
        --preview "$PSExecutable -noLogo -noProfile -nonInteractive -File `"$PSScriptRoot\Scripts\Preview.ps1`" {} `"$($global:FuzzyWinget.CacheDirectory)\Preview`"" `
        --preview-window '40%,border-sharp,wrap' `
        --preview-label "$($PSStyle.Foreground.Magenta)Package Information" `
        --prompt=$PromptText `
        --scrollbar="▐" `
        --separator="━" `
        --tabstop=4 `
        --tiebreak=index `
        --with-nth=2.. `

    # If the user didn't select anything return
    if (-not $SelectedPackages) {
        Write-Host "[$($PSStyle.Foreground.Yellow)FuzzyPackages$($PSStyle.Reset)] No packages selected, exiting..."

        # Reset the lastexitcode to 0 then return
        $global:LASTEXITCODE = 0
        return
    }

    # If the user wants to confirm the action prompt them
    if ($Confirm) {
        # TODO: Print the packages that will be acted on
        $confirm = Read-Host -Prompt "Are you sure you want to $($Action) the selected packages? (y/n)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host 'Exiting...'
            return
        }
    }

    # Loop through the selected packages
    foreach ($PackageString in $SelectedPackages) {

        # Get the index of the package from the string representation of the package
        $Index = $PackageString | Select-String -Pattern '^\d+' | ForEach-Object { $_.Matches.Groups[0].Value }

        # Get the package object from the index
        $Package = $Packages[$Index]
        
        # If the Package's ID is null use the Package's Name instead
        $Package.Id ??= $Package.Name # Null coalescing operator

        # Run the selected action
        switch ($Action) {
            'install' { 
                # Prefix the source so that the user knows where the package is coming from
                Write-Host "[$($Package.Source.Name)] Installing $($Package.Title()) Version $($Package.Version)"

                switch ($Package.Source.Name) {
                    'winget' {
                        $result = Install-WinGetPackage $Package.Id
                        Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "Install-WinGetPackage $Package.Id"
                    }
                    'scoop' {
                        $result = scoop install $Package.Id 
                        Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "scoop install $Package.Id"
                    }
                    'choco' {
                        choco install $Package.Id -y # Don't capture output, needs -y flag to install without prompting
                        Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "choco install $Package.Id -y"
                    }
                }
            }
            'uninstall' {
                Write-Host "[$($Package.Source.Name)] Uninstalling $($Package.Title())"

                switch ($Package.Source.Name) {
                    'winget' {
                        $result = Uninstall-WinGetPackage $Package.Id
                        Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "Uninstall-WinGetPackage $Package.Id"
                    }
                    'scoop' {
                        $result = scoop uninstall $Package.Id
                        Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "scoop uninstall $Package.Id"
                    }
                    'choco' {
                        choco uninstall $Package.Id -y
                        Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "choco uninstall $Package.Id -y"
                    }
                }
            }
            'update' {
                Write-Host "[$($Package.Source.Name)] Updating $($Package.Title()) to Version $($Package.AvailableVersion)"

                switch ($Package.Source.Name) {
                    'winget' {
                        $result = Update-WinGetPackage $Package.Id
                        Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "Update-WinGetPackage $Package.Id"
                    }
                    'scoop' {
                        $result = scoop update $Package.Id
                        Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "scoop update $Package.Id"
                    }
                    'choco' {
                        choco upgrade $Package.Id -y
                        Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "choco upgrade $Package.Id -y"
                    }
                }
            }
        }

        switch ($Package.Source.Name) {
            # The WinGet cmdlets return a hashtable with a status key
            'winget' {
                if ($result.status -eq 'Ok') {
                    Write-Host "[$($Package.Source.Name)] $($Action) succeeded" -ForegroundColor Green
                } else {
                    Write-Host "[$($Package.Source.Name)] $($Action) failed" -ForegroundColor Red

                    # Output the full status if the update failed
                    $result | Format-List | Out-String | Write-Host
                }
            }
            'scoop' {
                # Do Nothing atm, scoop's own output is sufficient
            }
            'choco' {
                # Do Nothing atm, choco's own output is sufficient
            }
        }
    }
}

function Update-FuzzyPackageSources {
    [CmdletBinding()]
    param(
        # The sources to update
        [Parameter()]
        [ValidateSet('winget', 'scoop', 'choco', 'psget')] # Source names must match 
        [string[]]$Sources
    )

    # If no sources are specified update all active sources
    if (-not $Sources) {
        $Sources = $global:FuzzyWinget.ActiveSources
    }



    Write-Host "$($PSStyle.Foreground.Blue):: $($PSStyle.Reset)Refreshing Packages Sources"

    # Used for the progress bar
    $CurrentSource = 0
    $SourceCount = $Sources.Count

    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($Source in $Sources) {
        Write-Progress -Activity "Refresh Progress:" -Status "Refreshing $($SourceDefinitions[$Source].DisplayName) Packages... ($($CurrentSource + 1) of $SourceCount)" -PercentComplete (($CurrentSource / $SourceCount) * 100)

        Invoke-Command $SourceDefinitions[$Source].RefreshCommand
    }

    Write-Progress -Activity "Refresh Progress:" -Completed

    Write-Host "   $($PSStyle.Foreground.Green)Refresh Complete! Took $($Stopwatch.Elapsed.TotalSeconds) seconds"
    Write-Host '' # Newline
}

function Get-FuzzyPackageList {
    [CmdletBinding()]
    param(
        # The command that will be used to get the packages
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command,

        # The formatter that will be used to format the packages into strings for fzf
        [Parameter(Mandatory = $true)]
        [scriptblock]$Formatter,

        # Path to the cache file
        [Parameter(Mandatory = $true)]
        [string]$CacheFile,

        # The maximum age of the cache in minutes
        [Parameter(Mandatory = $true)]
        [int]$MaxCacheAge,

        # Argument to pass to the formatter
        [switch]$isUpdate
    )

    # Check if the cache exists
    if (!(Test-Path $CacheFile)) {
        # If it doesn't exist, create it
        New-Item -ItemType File -Path $CacheFile -Force | Out-Null
    }

    # Check if the cache is older than the specified max age or if it's empty
    if ((Get-Date).Subtract((Get-Item $CacheFile).LastWriteTime).TotalMinutes -gt $MaxCacheAge -or (Get-Content $CacheFile).Count -eq 0) {
        # Get all packages from WinGet and format them for fzf
        &$Command | & $Formatter -isUpdate:$isUpdate | Tee-Object -FilePath $CacheFile
    } else {
        # If the cache is still valid, use it
        Get-Content $CacheFile
    }
}

#########################
# User-facing functions #
#########################

function Invoke-FuzzyPackageInstall {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('winget', 'scoop', 'choco', 'psget')]
        [string[]]$Sources,

        [Parameter()]
        [switch]$UpdateSources,

        # The maximum age of the cache in minutes
        [Parameter()]
        [int]$MaxCacheAge = 0,

        # Pass the -Confirm switch to the main function
        [switch]$Confirm
    )

    # If no sources are specified update all active sources
    if (-not $Sources) {
        $Sources = $global:FuzzyWinget.ActiveSources
    }

    if ($UpdateSources) {
        # If the user specified the -UpdateSources switch, update the sources
        Update-FuzzyPackageSources -Sources $Sources
    }

    $ListDirectory = "$($global:FuzzyWinget.CacheDirectory)\List"

    Write-Host "$($PSStyle.Foreground.Blue):: $($PSStyle.Reset)Getting Available Packages"

    # Collect all available packagesbr
    $availablePackages = @()

    # Used for the progress bar
    $CurrentSource = 0 
    $SourceCount = $Sources.Count

    foreach ($Source in $Sources) {
        Write-Progress -Activity 'Fetch Progress:' `
            -Status "Getting $($SourceDefinitions[$Source].DisplayName) Package List... ($($CurrentSource + 1) of $($SourceCount))" `
            -PercentComplete ([math]::Round(($CurrentSource / $SourceCount) * 100))

        $availablePackages += Get-FuzzyPackageList `
            -Command $SourceDefinitions[$Source].AvailableQuery `
            -Formatter $SourceDefinitions[$Source].Formatter `
            -CacheFile "$($ListDirectory)\$($Source)\available.txt" `
            -MaxCacheAge $MaxCacheAge

        $CurrentSource++
    }

    Write-Progress -Activity 'Fetch Progress:' -Completed

    # If no packages were found, exit
    if ($availablePackages.Count -eq 0) {
        Write-Host 'No packages found.' -ForegroundColor Red
        return
    } else {
        Write-Host "Found $($availablePackages.Count) packages." -ForegroundColor Green
    }

    # Invoke the helper function to install the selected packages
    Invoke-FuzzyPackager -Action install -Packages $availablePackages -Sources $Sources -Confirm:$Confirm
}

function Invoke-FuzzyPackageUninstall {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('winget', 'scoop', 'choco', 'psget')]
        [string[]]$Sources,

        # The max age of the cache in minutes
        [Parameter()]
        [int]$MaxCacheAge = 0,

        # Pass the -Confirm switch to the main function
        [switch]$Confirm
    )

    # If no sources are specified, use all active sources
    if (-not $Sources) {
        $Sources = $global:FuzzyWinget.ActiveSources
    }

    $ListDirectory = "$($global:FuzzyWinget.CacheDirectory)\List"

    Write-Host "$($PSStyle.Foreground.Blue):: $($PSStyle.Reset)Getting Installed Packages"

    # Collect all installed packages
    $installedPackages = @()

    # Used for the progress bar
    $CurrentSource = 0 
    $SourceCount = $($Sources | Measure-Object).Count

    # Used for the progress bar
    $CurrentSource = 0 
    $SourceCount = $($Sources | Measure-Object).Count

    foreach ($Source in $Sources) {
        Write-Progress -Activity 'Fetch Progress:' `
            -Status "Getting Installed $($SourceDefinitions[$Source].DisplayName) Packages... ($($CurrentSource + 1) of $($SourceCount))" `
            -PercentComplete ([math]::Round(($CurrentSource / $SourceCount) * 100))

        $installedPackages += Get-FuzzyPackageList `
            -Command $SourceDefinitions[$Source].InstalledQuery `
            -Formatter $SourceDefinitions[$Source].Formatter `
            -CacheFile "$($ListDirectory)\$($Source)\available.txt" `
            -MaxCacheAge $MaxCacheAge

        $CurrentSource++
    }

    Write-Progress -Activity 'Fetch Progress:' -Completed
    
    # If no packages were found, exit
    if ($installedPackages.Count -eq 0) {
        Write-Host 'No packages found.' -ForegroundColor Red # Not sure how this would happen, but just in case
        return
    } else {
        Write-Host "Found $($installedPackages.Count) packages." -ForegroundColor Green
    }

    # Invoke the helper function to uninstall the selected packages
    Invoke-FuzzyPackager -Action uninstall -Packages $installedPackages -Sources $Sources -Confirm:$Confirm
}

function Invoke-FuzzyPackageUpdate {
    [CmdletBinding()]
    param(
        # The sources to search for updates in
        [Parameter()]
        [ValidateSet('winget', 'scoop', 'choco', 'psget')] # Source names must match 
        [string[]]$Sources, # Default to all sources

        # Include packages with an unknown version - for winget only
        [Parameter()]
        [switch]$IncludeUnknown,

        # Fetch updates for each source before looking for updates
        [Parameter()]
        [switch]$UpdateSources,

        # The maximum age of the cache in minutes
        [Parameter()]
        [int]$MaxCacheAge = 0,

        # Pass the -Confirm switch to the main function
        [switch]$Confirm
    )

    if ($Sources.Count -eq 0) {
        # If no sources were specified get updates from all sources
        $Sources = $global:FuzzyWinget.ActiveSources
    }

    if ($UpdateSources) {
        # If the user specified the -UpdateSources switch, update the sources
        Update-FuzzyPackageSources -Sources $Sources
    }

    # Path to the cache directory
    $ListDirectory = "$($global:FuzzyWinget.CacheDirectory)\List"

    Write-Host "$($PSStyle.Foreground.Blue):: $($PSStyle.Reset)Querying for Updates"

    # Collect all updates
    $updates = @()

    # Used for the progress bar
    $CurrentSource = 0
    $SourceCount = $($Sources | Measure-Object).Count

    foreach ($Source in $Sources) {
        Write-Progress -Activity 'Fetch Progress:' `
            -Status "Checking $($SourceDefinitions[$Source].DisplayName) for Available Updates... ($($CurrentSource + 1) of $($SourceCount))" `
            -PercentComplete ([math]::Round(($CurrentSource / $SourceCount) * 100))

        $updates += Get-FuzzyPackageList `
            -Command $SourceDefinitions[$Source].UpdateQuery `
            -Formatter $SourceDefinitions[$Source].Formatter `
            -CacheFile "$($ListDirectory)\$($Source)\available.txt" `
            -MaxCacheAge $MaxCacheAge `
            -isUpdate

        $CurrentSource++
    }

    Write-Progress -Activity 'Fetch Progress:' -Completed

    # If there are no updates available, exit
    if ($updates.Count -eq 0) {
        Write-Host 'Everything is up to date' -ForegroundColor Green
        return
    }

    # Invoke the helper function to update the selected packages
    Invoke-FuzzyPackager -Action update -Packages $updates -Sources $Sources -Confirm:$Confirm
}

function Clear-FuzzyPackagesCache {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('winget', 'scoop', 'choco', 'psget')]
        [string[]]$Sources,

        [switch]$Preview,

        [switch]$List
    )

    if ($Sources.Count -eq 0) {
        # If no sources were specified, clear the cache for all active sources
        $Sources = $global:FuzzyWinget.ActiveSources
    }

    # If neither -List or -Preview were specified, clear both caches. 
    # The case where both are specified is handled by the individual cases below
    if (-not $List -and -not $Preview) {
        Clear-FuzzyPackagesCacheFolder -Sources $Sources -Types 'Preview', 'List'

        return # Exit the function
    }
    
    if ($Preview) {
        Clear-FuzzyPackagesCacheFolder -Sources $Sources -Types 'Preview'
    }

    if ($List) {
        Clear-FuzzyPackagesCacheFolder -Sources $Sources -Types 'List'
    }
}

function Clear-FuzzyPackagesCacheFolder {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('winget', 'scoop', 'choco', 'psget')]
        [string[]]$Sources,

        [Parameter()]
        [ValidateSet('Preview', 'List')]
        [string[]]$Types = @('Preview', 'List')
    )

    if ($Sources.Count -eq 0) {
        # If no sources were specified, clear the cache for all active sources
        $Sources = $global:FuzzyWinget.ActiveSources
    }

    foreach ($Type in $Types) {
        Write-Host '' # Newline

        # Print the type of cache being cleared
        Write-Host "$($PSStyle.Foreground.Blue):: $($PSStyle.Reset)Clearing Package $Type Cache"

        # Path to the cache directory
        $ListDirectory = "$($global:FuzzyWinget.CacheDirectory)\$Type"

        $ErrorOccured = $false

        # Clear the cache for each source specified
        foreach ($Source in $Sources) {
            Write-Host "   $($PSStyle.Foreground.BrightWhite)Clearing $($Source) cache..." -NoNewline

            try {
                # Remove the cache directory
                Remove-Item -Path "$($ListDirectory)\$($Source)\*" -Recurse -Force

                # Report that the cache was cleared
                Write-Host "`b`b`b $($PSStyle.Reset)[$($PSStyle.Foreground.Green)Cleared$($PSStyle.Reset)]"
            } catch {
                # Report that the cache could not be cleared
                Write-Host "`b`b`b $($PSStyle.Reset)[$($PSStyle.Foreground.Red)Failed$($PSStyle.Reset)]"

                $ErrorOccured = $true
            }
        }

        if ($ErrorOccured) {
            Write-Host '' # Newline

            # Report that an error occured
            Write-Host 'An error occured while clearing the cache' -ForegroundColor Red
            Write-Host "Perhaps you don't have permission to delete the cache files?" -ForegroundColor Red

            # TODO: This should be more specific, e.g. "You don't have permission to delete the cache files for the following sources: winget, scoop"
        }
    }
}



###################
# Final Setup     #
###################

# Add the source information to the global variable
$global:FuzzyWinget.Sources = @($SourceDefinitions.Keys)