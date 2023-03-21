# *** FuzzyWinget ***
# Author: Stuart Miller
# Version: 0.1.0
# Description: A module of functions to interact with WinGet using fzf
# License: MIT
# Repository: https://github.com/JK-Flip-Flop96/Fuzzy-Winget
##########################################################################################

# Global Variables
$global:FuzzyWinget = @{ # Create a global variable to store the module's data in
    CacheDirectory = "$env:tmp\FuzzyPackages" # Set the default cache directory to the temp directory
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
        [Parameter(Mandatory=$true)]
        [ValidateSet("install", "uninstall", "update")] # Confirms that the action is one of the three supported actions
        [string]$Action,

        [Parameter(Mandatory=$true)]
        [ValidateSet("winget", "scoop", "choco", "psget")] # Confirms that the source is one of the supported sources
        [string[]]$Sources, 

        [Parameter(Mandatory=$true, ValueFromPipeline=$true)] # Confirms that there is at least one package to act on
        [string[]]$Packages
    )

    # --- Setup for fzf ---

    # Define the ps executable to use for the preview command, pwsh for core and powershell for desktop
    $PSExecutable = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh" } else { "powershell" } 

    $WindowTitle = (Get-Culture).TextInfo.ToTitleCase(" $Action Packages ") # Set the title of the fzf window to the action being performed
    
    # Set the colour of the tile based on the action being performed
    $TitleColour = switch ($Action) {
        "install" { "green" }
        "uninstall" { "red" }
        "update" { "yellow" }
    }

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
     --prompt: Set the prompt for the fzf window #>

    # Call fzf to select the packages to act on
    $selectedPackages = $Packages |
        fzf --ansi `
            --multi `
            --cycle `
            --border "bold" `
            --border-label "$WindowTitle" `
            --border-label-pos=3 `
            --color=label:$TitleColour `
            --preview "$PSExecutable -noLogo -noProfile -nonInteractive -File `"$PSScriptRoot\Scripts\Preview.ps1`" {} `"$($global:FuzzyWinget.CacheDirectory)\Preview`"" `
            --preview-window '50%,border-left,wrap' `
            --prompt=' >'

    # If the user didn't select anything return
    if(-not $selectedPackages){
        # Reset the lastexitcode to 0 then return
        $global:LASTEXITCODE = 0
        return
    }

    # Loop through the selected packages
    foreach ($package in $selectedPackages) {

        # Extract the pertinent information from the selected package
        $source = $package | Select-String -Pattern "^([\w\-:]+)" | ForEach-Object { $_.Matches.Groups[1].Value } # All text before the first space

        if ($source.StartsWith("wg:")) { # If the source is a winget source
            $source = "winget" # Set the source to winget
        } elseif ($source.StartsWith("sc:")) { # If the source is a scoop bucket
            $source = "scoop" # Set the source to scoop
        } elseif ($source.StartsWith("ch:")) { # If the source is a chocolatey source
            $source = "choco" # Set the source to choco
        } else {
            Write-Host "Unknown source." -ForegroundColor Red # This should never happen, but just in case
        }

        if ($source -eq "winget"){
            $name = $package | Select-String -Pattern "\s(.*) \(" -AllMatches | ForEach-Object { $_.Matches.Groups[-1].Value } # All text between the first space and the last opening bracket
            $id = $package | Select-String -Pattern "\((.*?)\)" -AllMatches | ForEach-Object { $_.Matches.Groups[-1].Value } # All text between the last opening bracket and the last closing bracket
        } elseif ($source -eq "scoop" -or $source -eq "choco") {
            # Get the name of the package from the selected line, scoop and choco don't have package ids
            $id = $($package -split "\s+")[1] # Scoop packages never have spaces in their names so this should always work
            $name = $id
        }

        # If the ID is empty return
        if(-not $id){
            Write-Host "No ID found." -ForegroundColor Red # This should never happen, but just in case
        }

        # Define the package title for use in when reporting the action to the user  
        if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 2) {
            if ($name -eq $id) { # If the name and id are the same (scoop/choco packages)
                $packageTitle = "$($PSStyle.Foreground.Yellow)$id$($PSStyle.Foreground.BrightWhite)" 
            } else {
                $packageTitle = "$name ($($PSStyle.Foreground.Yellow)$id$($PSStyle.Foreground.BrightWhite))" # Use PSStyle to make the ID yellow if the user is running PS 7.2 or newer
            }
        } else {
            if ($name -eq $id) { # If the name and id are the same (scoop/choco packages)
                $packageTitle = "$id" 
            } else {
                $packageTitle = "$name ($id)" # If the user is running an older version of PS just use the default color
            }
        }

        # Remove any remaining whitespace
        $packageTitle = $packageTitle.Trim() 

        # Run the selected action
        switch($Action){
            "install" { 
                # Prefix the source so that the user knows where the package is coming from
                Write-Host "[$source] Installing $packageTitle"

                if ($source -eq "winget"){
                    $result = Install-WinGetPackage $id # Cmdlet will report its own progress

                    # Add the command to the history file so that the user can easily rerun it - works but requires a restart of the shell to take effect
                    Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "Install-WinGetPackage $id"
                } elseif ($source -eq "scoop"){
                    $result = scoop install $id 
                    Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "scoop install $id"
                } elseif ($source -eq "choco"){
                    choco install $id -y # Don't capture output, needs -y flag to install without prompting
                    Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "choco install $id -y"
                }
            }
            "uninstall" {
                Write-Host "[$source] Uninstalling $packageTitle"
                if ($source -eq "winget"){
                    $result = Uninstall-WinGetPackage $id
                    Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "Uninstall-WinGetPackage $id"
                } elseif ($source -eq "scoop"){
                    $result = scoop uninstall $id
                    Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "scoop uninstall $id"
                } elseif ($source -eq "choco"){
                    choco uninstall $id -y
                    Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "choco uninstall $id -y"
                }
            }
            "update" {
                Write-Host "[$source] Updating $packageTitle"
                if ($source -eq "winget"){
                    $result = Update-WinGetPackage $id
                    Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "Update-WinGetPackage $id"
                } elseif ($source -eq "scoop"){
                    $result = scoop update $id
                    Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "scoop update $id"
                } elseif ($source -eq "choco"){
                    choco upgrade $id -y
                    Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "choco upgrade $id -y"
                }
            }
        }

        # Report the result to the user
        if ($source -eq "winget"){
            # The WinGet cmdlets return a hashtable with a status key
            if($result.status -eq "Ok"){
                Write-Host (Get-Culture).TextInfo.ToTitleCase("$action succeeded") -ForegroundColor Green # Convert the action to title case for display
            }else{
                Write-Host (Get-Culture).TextInfo.ToTitleCase("$action failed") -ForegroundColor Red

                # Output the full status if the update failed
                $result | Format-List | Out-String | Write-Host
            }
        } elseif ($source -eq "scoop"){
            # Do Nothing atm, scoop's own output is sufficient
        } elseif ($source -eq "choco"){
            # Do Nothing atm, choco's own output is sufficient
        }
    }
}

function Update-FuzzyPackageSources{
    [CmdletBinding()]
    param(
        # The sources to update
        [Parameter()]
        [ValidateSet("winget", "scoop", "choco", "psget")] # Source names must match 
        [string[]]$Sources=@("winget", "scoop", "choco", "psget") # Default to all sources
    )

    Write-Host "$($PSStyle.Foreground.Blue):: $($PSStyle.Foreground.White)Updating Packages Sources"

    foreach($source in $Sources){
        Write-Host "   $($PSStyle.Foreground.BrightWhite)Updating $($source)..." -NoNewline

        Invoke-Command $SourceInfo[$source].RefreshCommand

        Write-Host "`b`b`b $($PSStyle.Foreground.BrightWhite)[$($PSStyle.Foreground.Green)OK$($PSStyle.Foreground.BrightWhite)]"
    }

    Write-Host "" # Newline
}

function Get-FuzzyPackageList{
    [CmdletBinding()]
    param(
        # The action that will on the selected packages
        [Parameter(Mandatory=$true)]
        [scriptblock]$Command,

        # The formatter that will be used to format the packages into strings for fzf
        [Parameter(Mandatory=$true)]
        [scriptblock]$Formatter,

        # Path to the cache file
        [Parameter(Mandatory=$true)]
        [string]$CacheFile,

        # The maximum age of the cache in minutes
        [Parameter(Mandatory=$true)]
        [int]$MaxCacheAge,

        # Argument to pass to the formatter
        [switch]$isUpdate
    )

    # Check if the cache exists
    if(!(Test-Path $CacheFile)){
        # If it doesn't exist, create it
        New-Item -ItemType File -Path $CacheFile -Force | Out-Null
    }

    # Check if the cache is older than the specified max age
    if ((Get-Date).Subtract((Get-Item $CacheFile).LastWriteTime).TotalMinutes -gt $MaxCacheAge){
        # Get all packages from WinGet and format them for fzf
        &$Command | & $Formatter -isUpdate:$isUpdate | Tee-Object -FilePath $CacheFile
    }else{
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
        [ValidateSet("winget", "scoop", "choco", "psget")]
        [string[]]$Sources=@("winget", "scoop", "choco", "psget"),

        [Parameter()]
        [switch]$UpdateSources,

        # The maximum age of the cache in minutes
        [Parameter()]
        [int]$MaxCacheAge = 0
    )

    if($UpdateSources){
        # If the user specified the -UpdateSources switch, update the sources
        Update-FuzzyPackageSources -Sources $Sources
    }

    $ListDirectory = "$($global:FuzzyWinget.CacheDirectory)\List"

    Write-Host "$($PSStyle.Foreground.Blue):: $($PSStyle.Foreground.White)Getting Available Packages"

    # Collect all available packages
    $availablePackages = @()

    foreach($source in $Sources){
        Write-Host "   $($PSStyle.Foreground.BrightWhite)Getting $source package list..." -NoNewline

        $availablePackages += Get-FuzzyPackageList `
            -Command $SourceInfo[$source].InstallQuery `
            -Formatter $SourceInfo[$source].Formatter `
            -CacheFile "$($ListDirectory)\$($source)\available.txt" `
            -MaxCacheAge $MaxCacheAge

        Write-Host "`b`b`b $($PSStyle.Foreground.BrightWhite)[$($PSStyle.Foreground.Green)OK$($PSStyle.Foreground.BrightWhite)]"
    }

    # If no packages were found, exit
    if($availablePackages.Count -eq 0){
        Write-Host "No packages found." -ForegroundColor Red
        return
    }

    # Invoke the helper function to install the selected packages
    Invoke-FuzzyPackager -Action install -Packages $availablePackages -Sources $Sources
}

function Invoke-FuzzyPackageUninstall {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet("winget", "scoop", "choco", "psget")]
        [string[]]$Sources=@("winget", "scoop", "choco", "psget"),

        # The max age of the cache in minutes
        [Parameter()]
        [int]$MaxCacheAge = 0
    )

    $ListDirectory = "$($global:FuzzyWinget.CacheDirectory)\List"

    Write-Host "$($PSStyle.Foreground.Blue):: $($PSStyle.Foreground.White)Getting Installed Packages"

    # Collect all installed packages
    $installedPackages = @()

    foreach($source in $Sources){
        Write-Host "   $($PSStyle.Foreground.BrightWhite)Getting $($source) packages..." -NoNewline

        $installedPackages += Get-FuzzyPackageList `
            -Command $SourceInfo[$source].UninstallQuery `
            -Formatter $SourceInfo[$source].Formatter `
            -CacheFile "$($ListDirectory)\$($source)\installed.txt" `
            -MaxCacheAge $MaxCacheAge

        Write-Host "`b`b`b $($PSStyle.Foreground.BrightWhite)[$($PSStyle.Foreground.Green)OK$($PSStyle.Foreground.BrightWhite)]"
    }
    
    # If no packages were found, exit
    if($installedPackages.Count -eq 0){
        Write-Host "No packages found." -ForegroundColor Red # Not sure how this would happen, but just in case
        return
    }

    # Invoke the helper function to uninstall the selected packages
    Invoke-FuzzyPackager -Action uninstall -Packages $installedPackages -Sources $Sources
}

function Invoke-FuzzyPackageUpdate {
    [CmdletBinding()]
    param(
        # The sources to search for updates in
        [Parameter()]
        [ValidateSet("winget", "scoop", "choco")] # Source names must match 
        [string[]]$Sources=@("winget", "scoop", "choco"), # Default to all sources

        # Include packages with an unknown version - for winget only
        [Parameter()]
        [switch]$IncludeUnknown,

        # Fetch updates for each source before looking for updates
        [Parameter()]
        [switch]$UpdateSources,

        # The maximum age of the cache in minutes
        [Parameter()]
        [int]$MaxCacheAge = 0
    )

    if($UpdateSources){
        # If the user specified the -UpdateSources switch, update the sources
        Update-FuzzyPackageSources -Sources $Sources
    }

    # Path to the cache directory
    $ListDirectory = "$($global:FuzzyWinget.CacheDirectory)\List"

    Write-Host "$($PSStyle.Foreground.Blue):: $($PSStyle.Foreground.White)Querying for Updates"

    # Collect all updates
    $updates = @()

    foreach($source in $Sources){
        Write-Host "   $($PSStyle.Foreground.BrightWhite)Fetching $($source) updates..." -NoNewline

        $updates += Get-FuzzyPackageList `
            -Command $SourceInfo[$source].UpdateQuery `
            -Formatter $SourceInfo[$source].Formatter `
            -CacheFile "$($ListDirectory)\$($source)\updates.txt" `
            -MaxCacheAge $MaxCacheAge `
            -isUpdate `

        Write-Host "`b`b`b [$($PSStyle.Foreground.Green)OK$($PSStyle.Foreground.BrightWhite)]"
    }

    Write-Host "" # Newline

    # If there are no updates available, exit
    if($updates.Count -eq 0){
        Write-Host "Everything is up to date" -ForegroundColor Green
        return
    }

    # Invoke the helper function to update the selected packages
    Invoke-FuzzyPackager -Action update -Packages $updates -Sources $Sources
}

####################
# Format Functions #
####################

# Formatter for all winget packages
function Format-WingetPackage {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [object]$Package,

        [switch]$isUpdate
    )

    process {
        # Source may be null if the package was installed manually or by the OS
        if(-not $Package.Source){
            $source = "$($PSStyle.Foreground.Magenta)wg:$($PSStyle.Foreground.BrightBlack)N/A   " # Make the source grey to make other sources stand out, pad with spaces to align with other sources
        }else{
            $source = "$($PSStyle.Foreground.Magenta)wg:$($Package.Source)" # e.g. wg:winget, wg:msstore
        }
        
        $name = "$($PSStyle.Foreground.White)$($Package.Name)"
        $id = "$($PSStyle.Foreground.Yellow)$($Package.Id)$($PSStyle.Foreground.BrightWhite)" # Ensure the closing bracket is white

        if ($isUpdate){
            # For packages with updates, show the version change that will occur - e.g. 1.0.0 -> 1.0.1
            $version = "$($PSStyle.Foreground.Red)$($Package.Version) $($PSStyle.Foreground.Cyan)-> $($PSStyle.Foreground.Green)$($Package.AvailableVersions[0])"
        }else{
            # For packages without updates, show the current version - e.g. 1.0.0
            $version = "$($PSStyle.Foreground.Green)$($Package.Version)"
        }

        # Output the formatted string - these strings are the ones that will be displayed in fzf
        "$source `t $name ($id) `t $version"
    }
}

# Formatter for scoop packages without updates
function Format-ScoopPackage {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [object]$Package,

        [switch]$isUpdate
    )

    process {
        $name = "$($PSStyle.Foreground.White)$($Package.Name)"

        if ($isUpdate){
            $source = "$($PSStyle.Foreground.Cyan)sc:scoop" # Bucket name is not returned by scoop status

            # For packages with updates, show the version change that will occur - e.g. 1.0.0 -> 1.0.1
            $version = "$($PSStyle.Foreground.Red)$($Package.'Installed version') $($PSStyle.Foreground.Cyan)-> $($PSStyle.Foreground.Green)$($Package.'Latest version')"
        }else{
            $source = "$($PSStyle.Foreground.Cyan)sc:$($Package.Source)" # e.g. sc:extras, sc:main

            # For packages without updates, show the current version - e.g. 1.0.0
            $version = "$($PSStyle.Foreground.Green)$($Package.Version)"
        }

        # Output the formatted string - these strings are the ones that will be displayed in fzf
        "$source `t $name `t $version"
    }
}

# Formatter for choco packages
function Format-ChocoPackage {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [string]$Package,

        # Tells the function to append the version change
        [switch]$isUpdate
    )

    process {
        # Split the package name and version
        # e.g. 7zip|19.0|20.0 -> 7zip, 19.0, 20.0. name|currentVersion|newVersion
        $PackageDetails = $Package -split '\|'

        $name = "$($PSStyle.Foreground.White)$($PackageDetails[0])"
        $source = "$($PSStyle.Foreground.Yellow)ch:choco" # Choco doesn't report the source so just use choco

        if ($isUpdate){
            # For packages with updates, show the version change that will occur - e.g. 1.0.0 -> 1.0.1
            $version = "$($PSStyle.Foreground.Red)$($PackageDetails[1]) $($PSStyle.Foreground.Cyan)-> $($PSStyle.Foreground.Green)$($PackageDetails[2])"
        } else {
            # For packages without updates, show the current version - e.g. 1.0.0
            $version = "$($PSStyle.Foreground.Green)$($PackageDetails[1])"
        }

        # Output the formatted string - these strings are the ones that will scbe displayed in fzf
        "$source `t $name `t $version"
    }
}

function Format-PSGetPackage {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [object]$Package,

        [switch]$isUpdate
    )

    process {
        $source = "$($PSStyle.Foreground.Blue)ps:$($Package.Repository)" # e.g. ps:PSGallery
        
        $name = "$($PSStyle.Foreground.White)$($Package.Name)"

        # For packages without updates, show the current version - e.g. 1.0.0
        $version = "$($PSStyle.Foreground.Green)$($Package.Version)"

        # Output the formatted string - these strings are the ones that will be displayed in fzf
        "$source `t $name `t $version"
    }
}

#######################
# Source Configuraton #
#######################

# The following hash table contains the configuration for each package source
# This section must be run last so that the functions are defined

$SourceInfo = @{
    winget = @{
        # Source information
        Name = "winget"
        DisplayName = "Windows Package Manager"

        # Package queries
        InstallQuery = { Find-WinGetPackage }
        UninstallQuery = { Get-WinGetPackage }
        UpdateQuery = { Get-WinGetPackage | Where-Object {($IncludeUnknown -or ($_.Version -ne "Unknown")) -and $_.IsUpdateAvailable} }

        # Package commands
        InstallCommand = { Install-WinGetPackage }
        UninstallCommand = { Uninstall-WinGetPackage }
        UpdateCommand = { Update-WinGetPackage }

        # Source commands
        RefreshCommand = { winget source update *> $null }

        # Package formatters
        Formatter = ${function:Format-WingetPackage}

        Status = {
            # Check if winget is installed
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                return $true
            } else {
                return $false
            }
        }
    }
    scoop = @{
        # Source information
        Name = "scoop"
        DisplayName = "Scoop"

        # Package queries 
        InstallQuery = { scoop search 6> $null }
        UninstallQuery = { scoop list 6> $null }
        UpdateQuery = { scoop status 6> $null }

        # Package commands
        InstallCommand = { scoop install }
        UninstallCommand = { scoop uninstall }
        UpdateCommand = { scoop update }

        # Source commands
        RefreshCommand = { scoop update *> $null }

        # Package formatters
        Formatter = ${function:Format-ScoopPackage}

        Status = {
            # Check if scoop is installed
            if (Get-Command scoop -ErrorAction SilentlyContinue) {
                return $true
            } else {
                return $false
            }
        }
    }
    choco = @{
        # Source information
        Name = "choco"
        DisplayName = "Chocolatey"

        # Package queries
        InstallQuery = { choco search -r }
        UninstallQuery = { choco list --local-only -r }
        UpdateQuery = { choco outdated -r }

        # Package commands
        InstallCommand = { choco install }
        UninstallCommand = { choco uninstall }
        UpdateCommand = { choco upgrade }

        # Source commands
        RefreshCommand = { } # Choco doesn't have a refresh command

        # Package formatters
        Formatter = ${function:Format-ChocoPackage}

        Status = {
            # Check if choco is installed
            if (Get-Command choco -ErrorAction SilentlyContinue) {
                return $true
            } else {
                return $false
            }
        }
    }
    psget = @{
        # Source information
        Name = "psget"
        DisplayName = "PowerShellGet"

        # Package queries
        InstallQuery = { Find-Module }
        UninstallQuery = { Get-InstalledModule }
        UpdateQuery = { } # PSGet doesn't have an update query
        # TODO: Make a custom update query maybe check the version of the installed module and the latest version on the gallery? 

        # Package commands
        InstallCommand = { Install-Module }
        UninstallCommand = { Uninstall-Module }
        UpdateCommand = { Update-Module } # This is redundant until I can jerry-rig an update query

        # Source commands
        RefreshCommand = { } # PSGet doesn't have a refresh command

        # Package formatters
        Formatter = ${function:Format-PSGetPackage}

        Status = {
            # TODO: Check if PSGet is installed
        }
    }
}