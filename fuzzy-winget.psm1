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
<#
.SYNOPSIS
    Class to store information about a package manager source

.DESCRIPTION
    Class to store information about a package manager source. This class is used to store information about a 
    package manager source, such as the name, short name, display name, color, and functions to get information 
    about packages and perform actions on packages

.PARAMETER Name
    The name of the source. This is the key of the $SourceDefinitions hashtable

.PARAMETER ShortName
    The short name of the source. This is used to display the source name in the fzf menu without taking up too
    much space

.PARAMETER DisplayName
    The display name of the source. This is used to display where space is not an issue, e.g in the installation 
    progress updates

.PARAMETER Color
    The color of the source. This is used to color the source name in the fzf menu. The string should contain a
    valid ANSI escape sequence.

.PARAMETER GetAvailablePackages
    A scriptblock that returns a list of available packages. The scriptblock should return an array of 
    FuzzyPackage objects

.PARAMETER GetInstalledPackages
    A scriptblock that returns a list of installed packages. The scriptblock should return an array of 
    FuzzyPackage objects

.PARAMETER GetPackageUpdates
    A scriptblock that returns a list of packages that have updates available. The scriptblock should return an 
    array of FuzzyPackage objects

.PARAMETER InstallPackage
    A scriptblock that installs a package. The scriptblock should take a FuzzyPackage object as a parameter.

.PARAMETER UninstallPackage
    A scriptblock that uninstalls a package. The scriptblock should take a FuzzyPackage object as a parameter.

.PARAMETER UpdatePackage
    A scriptblock that updates a package. The scriptblock should take a FuzzyPackage object as a parameter.

.PARAMETER UpdateSources
    A scriptblock that updates the sources of the package manager. 
    Note: Not all packages will have/need this

.PARAMETER PackageFormatter
    A scriptblock that formats the output of the package queries. The scriptblock should take an object (Dependant 
    on the result of the query) as a parameter and return a FuzzyPackage object. 
    
    The scriptblock should also have a isUpdate parameter that is a switch;
    If the scriptblock is used to format the output of the GetPackageUpdates query, the isUpdate parameter should 
    be set to $true. If the scriptblock is used to format the output of the GetAvailablePackages or 
    GetInstalledPackages queries, the isUpdate parameter should be set to $false.

.PARAMETER SourceCheck
    A scriptblock that checks if the source is available. The scriptblock should return a boolean value. If the 
    value is $true, the source is available. If the value is $false, the source is unavailable.

    This can be implemented in any way you want as each package manager will have a different way of checking if 
    the source is available. 
    
    For example, winget checks if the winget.exe file exists in the path and if the winget PowerShell module is 
    installed. If both of these are true, the source is available. If either of these are false, 
    the source is unavailable.

.PARAMETER ResultCheck
    A scriptblock that checks if the result of the previous action. The scriptblock should take an object the
    result of the previous action as a parameter and return a boolean value. If the value is $true, the action was
    successful. If the value is $false, the action was unsuccessful.

    Note: It is not necessary to use the passed in object to check if the action was successful. You can use any
    method you want to check if the action was successful. For example, PowerShellGet checks the automatic variable
    $? to check if the action was successful. Or, chocolatey checks if the exit code of the previous command was 0.
#>
class FuzzySource {
    # Source information
    [string]$Name
    [string]$ShortName
    [string]$DisplayName 
    [string]$Color

    # Package list queries
    [scriptblock]$GetAvailablePackages 
    [scriptblock]$GetInstalledPackages 
    [scriptblock]$GetPackageUpdates

    # Actions
    [scriptblock]$InstallPackage 
    [scriptblock]$UninstallPackage
    [scriptblock]$UpdatePackage

    # Source Actions
    [scriptblock]$UpdateSources
    [scriptblock]$PackageFormatter

    # Checks
    [scriptblock]$SourceCheck
    [scriptblock]$ResultCheck
}

# Class to stort information about a package
class FuzzyPackage {
    [string]$Name # The name of the package
    [string]$Id # The ID of the package (if applicable)
    [string]$Version # The version of the package
    [string]$AvailableVersion # The latest available version of the package (if applicable)
    [string]$Source # The source of the package. This is the key of the $SourceDefinitions hashtable
    [string]$Repo # The repository of the package

    <#
    .SYNOPSIS
        Returns the string representation of the package

    .DESCRIPTION
        Returns the string representation of the package. The string is formatted as follows:
        <Source color><Source short name>:<Repo><Reset><tab><Name><tab><Version>
        If the package has an ID, it is appended to the name in yellow
        If the package has an available version, it is appended to the version in green, with the current version 
        in red
    #>
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

    <#
    .SYNOPSIS
        Returns the title of the package, used for printing the package name during actions
    #>
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
    if ($SourceDefinitions[$_].SourceCheck.Invoke()){
        Write-Verbose "Source $($_) is installed and working" 
    } else {
        Write-Warning "Source $($_) is not installed or is not working"
    }
}

# TODO: Probably need to add some error handling here, e.g.:
#   - Sources with the same name
#   - Sources with the same short name
#   - Sources with the same color (Not that this is a problem, but it might be confusing)

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

<#
.SYNOPSIS
    Installs, uninstalls or updates packages from various package managers using fzf

.DESCRIPTION
    Installs, uninstalls or updates packages from various package managers using fzf, with support for multiple
    package managers and multiple sources for each package manager. 
    
    The package managers currently supported are:
        - winget
        - scoop
        - choco
        - psget

    The sources for each package manager are defined in the Sources folder. Each source is defined in a separate
    file, and the file name is used as the key for the source. The source files are dot sourced into the main
    script, so they can be used to define functions and variables that are used by the source.

.PARAMETER Action
    The action to perform. This can be one of the following:
        - install
        - uninstall
        - update

.PARAMETER Sources
    The sources to use for the action. This can be one or more of the following:
        - winget
        - scoop
        - choco
        - psget

.PARAMETER Confirm
    If this switch is specified, the user will be prompted to confirm the action before it is performed

.PARAMETER Packages
    The packages to act on. This can be one or more packages. The packages must be of type FuzzyPackage, which
    is defined in this script. The FuzzyPackage class is used to store information about a package, and provices 
    methods toconvert the package to a string for display in fzf.

.EXAMPLE
    Invoke-FuzzyPackager -Action install -Sources winget, scoop -Packages $Packages

    The above will list all of the packages from the winget and scoop sources, and allow the user to select one or
    more packages to install. 

    Note: This is not the intended usage of this Cmdlet, but it is possible to use it this way.

.INPUTS
    FuzzyPackage

.OUTPUTS
    None

.NOTES
    This Cmdlet requires fzf to be installed and available in the path.

    The fzf executable can be downloaded from GitHub, or installed using a package manager. The following are
    some examples of how to install fzf using various package managers:

    winget install fzf
    scoop install fzf
    choco install fzf
#>
function Invoke-FuzzyPackager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('install', 'uninstall', 'update')]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [ValidateSet('winget', 'scoop', 'choco', 'psget')]
        [string[]]$Sources, 

        [switch]$Confirm,

        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
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

                    & $SourceDefinition.InstallPackage -Package $Package
                }
                'uninstall' {
                    Write-Host "[$($SourceDefinition.Color)$($SourceDefinition.DisplayName)$($PSStyle.Reset)] " + 
                    "Uninstalling $($Package.Title()) Version $($Package.Version)"

                    & $SourceDefinition.UninstallPackage -Package $Package
                }
                'update' {
                    Write-Host "[$($SourceDefinition.Color)$($SourceDefinition.DisplayName)$($PSStyle.Reset)] " + 
                    "Updating $($Package.Title()) to Version $($Package.AvailableVersion)"

                    & $SourceDefinition.UpdatePackage -Package $Package
                }
            }
        }
    }
}

<#
.SYNOPSIS
    Update the package sources

.DESCRIPTION
    Update the package sources, if no sources are specified all active sources will be updated.

.PARAMETER Sources
    The sources to update

.EXAMPLE
    Update-FuzzyPackageSources -Sources 'winget', 'scoop'
    Update the winget and scoop sources

    Note: This Cmdlet is not exported by default, the recommended way to use it is via the -UpdateSources switch 
    available on the Invoke-FuzzyPackage[Install|Uninstall|Update] Cmdlets
#>
function Update-FuzzyPackageSources {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('winget', 'scoop', 'choco', 'psget')]
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

        Invoke-Command $SourceDefinitions[$Source].UpdateSources

        $CurrentSource++
    }

    Write-Progress -Activity 'Refresh Progress:' -Completed -Id 0

    Write-Host "   $($PSStyle.Foreground.Green)Refresh Complete! Took $($Stopwatch.Elapsed.TotalSeconds) seconds`n"
}

<#
.SYNOPSIS
    Get a list of packages from a source

.DESCRIPTION
    Get a list of packages from a source. This function will retrieve the packages from the cache if it is not 
    older than the MaxCacheAge.

.PARAMETER Command
    The command that will be used to get the packages. This is a scriptblock defined in the source definition.

.PARAMETER PackageFormatter
    The PackageFormatter that will be used to format the packages into FuzzyPackage Objects. This is a scriptblock defined
    in the source definition.

.PARAMETER CacheFile
    Path to the cache file that will be used to store the packages.

.PARAMETER MaxCacheAge
    The maximum age of the cache in minutes.

.PARAMETER isUpdate
    Argument to pass to the PackageFormatter. This is used to determine if the packages are being retrieved for an update
    or not. Ultimately this is used to know how the package objects should be formatted.

.EXAMPLE
    Get-FuzzyPackageList -Command $SourceDefinitions['winget'].GetAvailablePackages `
        -Formatter $SourceDefinitions['winget'].PackageFormatter `
        -CacheFile [Some file path] `
        -MaxCacheAge 60 `
        -isUpdate
    Get a list of packages from the winget source

    Note: This Cmdlet is not exported by default, this function is invoked by the 
    Invoke-FuzzyPackage[Install|Uninstall|Update] Cmdlets as required. The above example is roughly what the 
    Invoke-FuzzyPackageInstall Cmdlet does.
#>
function Get-FuzzyPackageList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$PackageFormatter,
        
        [Parameter(Mandatory = $true)]
        [string]$CacheFile,

        [Parameter(Mandatory = $true)]
        [int]$MaxCacheAge,

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
        &$Command | & $PackageFormatter -isUpdate:$isUpdate | Tee-Object -Variable Packages | Export-Clixml -Path $CacheFile
        if ($null -ne $Packages) {
            $Packages # Only output the packages if there are any   
        }
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
        [switch]$UpdateSourcess,

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

    if ($UpdateSourcess) {
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
            -Command $SourceDefinitions[$Source].GetAvailablePackages `
            -PackageFormatter $SourceDefinitions[$Source].PackageFormatter `
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
            -Command $SourceDefinitions[$Source].GetInstalledPackages `
            -PackageFormatter $SourceDefinitions[$Source].PackageFormatter `
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
        [switch]$UpdateSourcess,

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

    if ($UpdateSourcess) {
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
            -Command $SourceDefinitions[$Source].GetPackageUpdates `
            -PackageFormatter $SourceDefinitions[$Source].PackageFormatter `
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

    foreach ($update in $updates) {
        Write-Host if ($null -eq $update) { 'null' } else { $update.Name } -ForegroundColor Yellow
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