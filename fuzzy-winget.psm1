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
    [string]$Source # The source of the package. This is the key of the $SourceDefinitions hashtable
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

# Hash table to store the source definitions
$global:SourceDefinitions = @{}

# Load sources from the Sources folder
Get-ChildItem -Path "$PSScriptRoot\Sources" -Filter '*.ps1' -Recurse | ForEach-Object {
    $SourceDefinitions[$_.BaseName] = [FuzzySource]$(. $_.FullName)
}

# Check the status of each source
$global:SourceDefinitions.Keys | ForEach-Object {
    if ($SourceDefinitions[$_].CheckStatus.Invoke()){
        Write-Verbose "Source $($_) is installed and working" 
    } else {
        Write-Warning "Source $($_) is not installed or is not working"
    }
}

########################
# Module Configuration #
########################

# This hashtable stores the default configuration options for the module
# TODO: Function to set these variables, like Set-PSReadLineOption
$global:FuzzyPackagesOptions = @{
    # Directory to store the cache files in
    CacheDirectory = "$env:tmp\FuzzyPackages" 

    # All of the sources that can be used
    Sources        = $global:SourceDefinitions.Keys

    # The default sources to use when no sources are specified - this should be a subset of the Sources variable
    ActiveSources  = $global:SourceDefinitions.Keys

    # Allow the use of Nerd Fonts
    # If this is set to $true, the module will use the Nerd Font symbols
    # Currently only used in one location, not sure if that will ever change
    UseNerdFonts   = $true
}

# Create the cache directory if it doesn't exist
if (-not (Test-Path $global:FuzzyPackagesOptions.CacheDirectory)) {
    New-Item -ItemType Directory -Path $global:FuzzyPackagesOptions.CacheDirectory -Force | Out-Null
}

#################
# Main Function #
#################

# The main function of the module, this function cannot be called directly. 
# It is interfaced via the Invoke-[Install/Uninstall/Update] functions.
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
    $PromptText = if ($global:FuzzyPackagesOptions.UseNerdFonts) { ' >' } else { '>' }
    

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
        --preview "$PSExecutable -noLogo -noProfile -nonInteractive -File `"$PSScriptRoot\Scripts\Preview.ps1`" {} `"$($global:FuzzyPackagesOptions.CacheDirectory)\Preview`"" `
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

    # Get the package objects from the selected packages by index, then sort them by source
    $PackageGroups = $SelectedPackages | ForEach-Object { 
        $Index = $_ | Select-String -Pattern '^\d+' | ForEach-Object { $_.Matches.Groups[0].Value }
        $Packages[$Index]
    } | Group-Object -Property Source 

    # Display the packages to be acted on
    Write-Host "[$($PSStyle.Foreground.Yellow)FuzzyPackages$($PSStyle.Reset)] Packages to $($Action):"
    # Iterate through the package groups and display the packages to be acted on in each group
    foreach ($PackageGroup in $PackageGroups) {
        # Get the source definition using the key from the package
        $SourceDefinition = $global:SourceDefinitions[$PackageGroup.Name]

        # Display the packages to be acted on
        Write-Host "[$($SourceDefinition.Color)$($SourceDefinition.DisplayName)$($PSStyle.Reset)]" -NoNewline
        Write-Host " $($PackageGroup.Group.Count) $(if ($PackageGroup.Group.Count -eq 1) { 'package' } else { 'packages' })"
        
        $PackageGroup.Group | ForEach-Object { 
            Write-Host "  - $($_.Title()) Version $($_.Version)"
        }
    }

    # If the user wants to confirm the action prompt them
    if ($Confirm) {
        $UserChoice = Read-Host -Prompt "Are you sure you want to $($Action) the selected packages? (y/n)"
        if (($UserChoice -ne 'y') -and ($UserChoice -ne 'Y')) {
            Write-Host 'Exiting...'
            return
        }
    }

    # Loop through each package group
    foreach ($PackageGroup in $PackageGroups) {

        # Get the source definition using name from the group
        $SourceDefinition = $SourceDefinitions[$PackageGroup.Name]

        # Loop through each package in the group
        foreach ($Package in $PackageGroup.Group) {
            # Run the selected action
            switch ($Action) {
                'install' { 
                    Write-Host "[$($SourceDefinition.Color)$($SourceDefinition.DisplayName)$($PSStyle.Reset)] " + 
                    "Installing $($Package.Title()) Version $($Package.Version)"

                    & $SourceDefinition.InstallCommand -Package $Package
                }
                'uninstall' {
                    Write-Host "[$($SourceDefinition.Color)$($SourceDefinition.DisplayName)$($PSStyle.Reset)] " + 
                    "Uninstalling $($Package.Title()) Version $($Package.Version)"

                    & $SourceDefinition.UninstallCommand -Package $Package
                }
                'update' {
                    Write-Host "[$($SourceDefinition.Color)$($SourceDefinition.DisplayName)$($PSStyle.Reset)] " + 
                    "Updating $($Package.Title()) to Version $($Package.AvailableVersion)"

                    & $SourceDefinition.UpdateCommand -Package $Package
                }
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
        $Sources = $global:FuzzyPackagesOptions.ActiveSources
    }

    Write-Host "$($PSStyle.Foreground.Blue):: $($PSStyle.Reset)Refreshing Packages Sources"

    # Used for the progress bar
    $CurrentSource = 0
    $SourceCount = $Sources.Count

    # Start a stopwatch to time the refresh
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Progress -Activity 'Refresh Progress:' -Status "Refreshing $($SourceDefinitions[$Sources[0]].DisplayName) Packages... (1 of $SourceCount)" -PercentComplete 0 -Id 0

    foreach ($Source in $Sources) {
        Write-Progress -Activity 'Refresh Progress:' `
            -Status "Refreshing $($SourceDefinitions[$Source].DisplayName) Packages... ($($CurrentSource + 1) of $SourceCount)" `
            -PercentComplete (($CurrentSource / $SourceCount) * 100) -Id 0

        Invoke-Command $SourceDefinitions[$Source].RefreshCommand

        $CurrentSource++
    }

    Write-Progress -Activity 'Refresh Progress:' -Completed -Id 0

    Write-Host "   $($PSStyle.Foreground.Green)Refresh Complete! Took $($Stopwatch.Elapsed.TotalSeconds) seconds`n"
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
        # Get all packages from WinGet and format them for fzf, export the packages to the cache file in xml format
        &$Command | & $Formatter -isUpdate:$isUpdate | Tee-Object -Variable Packages | Export-Clixml -Path $CacheFile
        $Packages
    } else {
        # If the cache is still valid, use it
        Import-Clixml -Path $CacheFile
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
        $Sources = $global:FuzzyPackagesOptions.ActiveSources
    }

    if ($UpdateSources) {
        # If the user specified the -UpdateSources switch, update the sources
        Update-FuzzyPackageSources -Sources $Sources
    }

    $ListDirectory = "$($global:FuzzyPackagesOptions.CacheDirectory)\List"

    Write-Host "$($PSStyle.Foreground.Blue):: $($PSStyle.Reset)Getting Available Packages"

    # Collect all available packagesbr
    $availablePackages = @()

    # Used for the progress bar
    $CurrentSource = 0 
    $SourceCount = $Sources.Count

    Write-Progress -Activity 'Fetch Progress:' `
        -Status "Getting $($SourceDefinitions[$Sources[0]].DisplayName) Package List..." `
        -PercentComplete 0 -Id 1

    foreach ($Source in $Sources) {
        Write-Progress -Activity 'Fetch Progress:' `
            -Status "Getting $($SourceDefinitions[$Source].DisplayName) Package List... ($($CurrentSource + 1) of $($SourceCount))" `
            -PercentComplete ([math]::Round(($CurrentSource / $SourceCount) * 100)) -Id 1

        $availablePackages += Get-FuzzyPackageList `
            -Command $SourceDefinitions[$Source].AvailableQuery `
            -Formatter $SourceDefinitions[$Source].Formatter `
            -CacheFile "$($ListDirectory)\$($Source)\available.txt" `
            -MaxCacheAge $MaxCacheAge

        $CurrentSource++
    }

    Write-Progress -Activity 'Fetch Progress:' -Completed -Id 1

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
        $Sources = $global:FuzzyPackagesOptions.ActiveSources
    }

    $ListDirectory = "$($global:FuzzyPackagesOptions.CacheDirectory)\List"

    Write-Host "$($PSStyle.Foreground.Blue):: $($PSStyle.Reset)Getting Installed Packages"

    # Collect all installed packages
    $installedPackages = @()

    # Used for the progress bar
    $CurrentSource = 0 
    $SourceCount = $($Sources | Measure-Object).Count

    # Used for the progress bar
    $CurrentSource = 0 
    $SourceCount = $($Sources | Measure-Object).Count

    Write-Progress -Activity 'Fetch Progress:' `
        -Status "Getting Installed $($SourceDefinitions[$Sources[0]].DisplayName) Packages..." `
        -PercentComplete 0 -Id 2

    foreach ($Source in $Sources) {
        Write-Progress -Activity 'Fetch Progress:' `
            -Status "Getting Installed $($SourceDefinitions[$Source].DisplayName) Packages... ($($CurrentSource + 1) of $($SourceCount))" `
            -PercentComplete ([math]::Round(($CurrentSource / $SourceCount) * 100)) -Id 2

        $installedPackages += Get-FuzzyPackageList `
            -Command $SourceDefinitions[$Source].InstalledQuery `
            -Formatter $SourceDefinitions[$Source].Formatter `
            -CacheFile "$($ListDirectory)\$($Source)\installed.txt" `
            -MaxCacheAge $MaxCacheAge

        $CurrentSource++
    }

    Write-Progress -Activity 'Fetch Progress:' -Completed -Id 2
    
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
        $Sources = $global:FuzzyPackagesOptions.ActiveSources
    }

    if ($UpdateSources) {
        # If the user specified the -UpdateSources switch, update the sources
        Update-FuzzyPackageSources -Sources $Sources
    }

    # Path to the cache directory
    $ListDirectory = "$($global:FuzzyPackagesOptions.CacheDirectory)\List"

    Write-Host "$($PSStyle.Foreground.Blue):: $($PSStyle.Reset)Querying for Updates"

    # Collect all updates
    $updates = @()

    # Used for the progress bar
    $CurrentSource = 0
    $SourceCount = $($Sources | Measure-Object).Count

    Write-Progress -Activity 'Fetch Progress:' `
        -Status "Checking $($SourceDefinitions[$Sources[0]].DisplayName) for Available Updates..." `
        -PercentComplete 0 -Id 3

    foreach ($Source in $Sources) {
        Write-Progress -Activity 'Fetch Progress:' `
            -Status "Checking $($SourceDefinitions[$Source].DisplayName) for Available Updates... ($($CurrentSource + 1) of $($SourceCount))" `
            -PercentComplete ([math]::Round(($CurrentSource / $SourceCount) * 100)) -Id 3

        $updates += Get-FuzzyPackageList `
            -Command $SourceDefinitions[$Source].UpdateQuery `
            -Formatter $SourceDefinitions[$Source].Formatter `
            -CacheFile "$($ListDirectory)\$($Source)\updates.txt" `
            -MaxCacheAge $MaxCacheAge `
            -isUpdate

        $CurrentSource++
    }

    Write-Progress -Activity 'Fetch Progress:' -Completed -Id 3

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
        $Sources = $global:FuzzyPackagesOptions.ActiveSources
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
        $Sources = $global:FuzzyPackagesOptions.ActiveSources
    }

    foreach ($Type in $Types) {
        Write-Host '' # Newline

        # Print the type of cache being cleared
        Write-Host "$($PSStyle.Foreground.Blue):: $($PSStyle.Reset)Clearing Package $Type Cache"

        # Path to the cache directory
        $ListDirectory = "$($global:FuzzyPackagesOptions.CacheDirectory)\$Type"

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

            # TODO: This should be more specific, 
            # e.g. "You don't have permission to delete the cache files for the following sources: winget, scoop"
        }
    }
}



###################
# Final Setup     #
###################

# Space for additional setup code that needs to be run after the rest of the script has been loaded
# None currently required