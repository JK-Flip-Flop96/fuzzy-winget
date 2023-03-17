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
if (-not (Test-Path $global:FuzzyWinget.CacheDirectory)) {
    New-Item -ItemType Directory -Path $global:FuzzyWinget.CacheDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path "$($global:FuzzyWinget.CacheDirectory)\List" -Force | Out-Null
    New-Item -ItemType Directory -Path "$($global:FuzzyWinget.CacheDirectory)\Preview" -Force | Out-Null

    New-Item -ItemType Directory -Path "$($global:FuzzyWinget.CacheDirectory)\List\winget" -Force | Out-Null
    New-Item -ItemType Directory -Path "$($global:FuzzyWinget.CacheDirectory)\List\scoop" -Force | Out-Null
    New-Item -ItemType Directory -Path "$($global:FuzzyWinget.CacheDirectory)\List\choco" -Force | Out-Null

    New-Item -ItemType Directory -Path "$($global:FuzzyWinget.CacheDirectory)\Preview\winget" -Force | Out-Null
    New-Item -ItemType Directory -Path "$($global:FuzzyWinget.CacheDirectory)\Preview\scoop" -Force | Out-Null
    New-Item -ItemType Directory -Path "$($global:FuzzyWinget.CacheDirectory)\Preview\choco" -Force | Out-Null
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
        [ValidateSet("winget", "scoop", "choco")] # Confirms that the source is one of the supported sources
        [string[]]$Sources, 

        [Parameter(Mandatory=$true, ValueFromPipeline=$true)] # Confirms that there is at least one package to act on
        [string[]]$Packages
    )

    # Define the ps executable to use for the preview command, pwsh for core and powershell for desktop
    $PSExecutable = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh" } else { "powershell" } 

    $WindowTitle = (Get-Culture).TextInfo.ToTitleCase(" $Action Packages ") # Set the title of the fzf window to the action being performed
    
    # Set the colour of the tile based on the action being performed
    $TitleColour = switch ($Action) {
        "install" { "green" }
        "uninstall" { "red" }
        "update" { "yellow" }
    }

    # Format the packages for fzf and pipe them to fzf for selection
    $selectedPackages = $Packages | Format-Table -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") } |
        fzf --ansi `
            --multi `
            --cycle `
            --border "bold" `
            --border-label "$WindowTitle" `
            --border-label-pos=3 `
            --color=label:$TitleColour `
            --preview "$PSExecutable -noLogo -noProfile -nonInteractive -File `"$PSScriptRoot\Scripts\Preview.ps1`" {}" `
            --preview-window '50%,border-left,wrap' `
            --prompt=' >'

    # FZF Arguments:
    # --ansi: Enable ANSI color support
    # --multi: Allow multiple selections
    # --cycle: Allow cycling through the list
    # --border: Enable a border around the fzf window
    #   "bold": Set the border use heavy line drawing characters
    # --border-label: Set the label for the border
    # --border-label-pos: Set the position of the border label
    # --color: Set the color of the border label
    # --preview: Set the command to run for the preview window
    # --preview-window: Set the size and position of the preview window
    # --prompt: Set the prompt for the fzf window

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
                    # TODO: Different sources have different ways of installing packages
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

#########################
# User-facing functions #
#########################

function Invoke-FuzzyPackageInstall {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet("winget", "scoop", "choco")]
        [string[]]$Sources=@("winget", "scoop", "choco"),

        [switch]$UpdateSources
    )

    # Collect all available packages
    $availablePackages = @()

    if($Sources.Contains("winget")){
        # Update the WinGet package index if the user specified the -UpdateSources switch
        if($UpdateSources){
            Write-Host "Updating WinGet sources..." -NoNewline
            
            winget source update *> $null 

            Write-Host " [Done]" -ForegroundColor Green
        }

        Write-Host "Fetching WinGet packages..." -NoNewline

        # Get all packages from WinGet and format them for fzf
        $availablePackages += Find-WinGetPackage | Format-WingetPackage

        Write-Host " [Done]" -ForegroundColor Green
    }
    
    if($Sources.Contains("scoop")){
        # Update the Scoop package index if the user specified the -UpdateSources switch
        if($UpdateSources){
            Write-Host "Updating Scoop sources..." -NoNewline

            scoop update *> $null

            Write-Host " [Done]" -ForegroundColor Green
        }

        Write-Host "Fetching Scoop packages..." -NoNewline

        # Get all packages from Scoop and format them for fzf
        $availablePackages += scoop search 6> $null | Format-ScoopPackage

        Write-Host " [Done]" -ForegroundColor Green
    }

    if($Sources.Contains("choco")){
        # Chocolatey doesn't have a way to update the package index, so we just fetch the packages
        Write-Host "Fetching Chocolatey packages..." -NoNewline

        # Get all packages from Chocolatey and format them for fzf
        $availablePackages += choco search -r | Format-ChocoPackage

        Write-Host " [Done]" -ForegroundColor Green
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
        [ValidateSet("winget", "scoop", "choco")]
        [string[]]$Sources=@("winget", "scoop", "choco"),

        [Parameter()]
        [int]$MaxCacheAge = 0
    )

    # Collect all installed packages
    $installedPackages = @()

    if($Sources.Contains("winget")){
        # Check if the cache exists
        if(!(Test-Path "$($global:FuzzyWinget.CacheDirectory)\List\winget\installed.txt")){
            # If it doesn't exist, create it
            New-Item -ItemType File -Path "$($global:FuzzyWinget.CacheDirectory)\List\winget\installed.txt" -Force | Out-Null
        }

        # Check if the cache is older than the specified max age
        if ((Get-Date).Subtract((Get-Item "$($global:FuzzyWinget.CacheDirectory)\List\winget\installed.txt").LastWriteTime).TotalMinutes -gt $MaxCacheAge){
            Write-Host "Getting Installed Winget packages..." -NoNewline

            # Get all packages from WinGet and format them for fzf
            $installedWingetPackages += Get-WinGetPackage | Format-WingetPackage

            # Save the list to the cache
            $installedWingetPackages | Out-File "$($global:FuzzyWinget.CacheDirectory)\List\winget\installed.txt" -Encoding UTF8 -Force

            # Add the packages to the list of installed packages
            $installedPackages += $installedWingetPackages

            Write-Host " [Done]" -ForegroundColor Green
        }else{
            # If the cache is still valid, use it
            $installedPackages += Get-Content "$($global:FuzzyWinget.CacheDirectory)\List\winget\installed.txt"
        }
    }
        
    if($Sources.Contains("scoop")){

        if (!(Test-Path "$($global:FuzzyWinget.CacheDirectory)\List\scoop\installed.txt")){
            # If it doesn't exist, create it
            New-Item -ItemType File -Path "$($global:FuzzyWinget.CacheDirectory)\List\scoop\installed.txt" -Force | Out-Null
        }

        # Check if the cache is older than the specified max age
        if ((Get-Date).Subtract((Get-Item "$($global:FuzzyWinget.CacheDirectory)\List\scoop\installed.txt").LastWriteTime).TotalMinutes -gt $MaxCacheAge){
            Write-Host "Getting Installed Scoop packages..." -NoNewline

            # Get all packages from Scoop and format them for fzf
            $installedScoopPackages += scoop list 6> $null | Format-ScoopPackage

            # Save the list to the cache
            $installedScoopPackages | Out-File "$($global:FuzzyWinget.CacheDirectory)\List\scoop\installed.txt" -Encoding UTF8 -Force

            # Add the packages to the list of installed packages
            $installedPackages += $installedScoopPackages

            Write-Host " [Done]" -ForegroundColor Green
        } else {
            # If the cache is still valid, use it
            $installedPackages += Get-Content "$($global:FuzzyWinget.CacheDirectory)\List\scoop\installed.txt"
        }
    }

    if($Sources.Contains("choco")){
        if (!(Test-Path "$($global:FuzzyWinget.CacheDirectory)\List\choco\installed.txt")){
            # If it doesn't exist, create it
            New-Item -ItemType File -Path "$($global:FuzzyWinget.CacheDirectory)\List\choco\installed.txt" -Force | Out-Null
        }

        # Check if the cache is older than the specified max age
        if ((Get-Date).Subtract((Get-Item "$($global:FuzzyWinget.CacheDirectory)\List\choco\installed.txt").LastWriteTime).TotalMinutes -gt $MaxCacheAge){
            Write-Host "Getting Installed Chocolatey packages..." -NoNewline

            # TODO: Remove the --local-only flag once choco v2.0 is released
            # Get all packages from Chocolatey and format them for fzf
            $installedChocoPackages += choco list --local-only -r | Format-ChocoPackage

            # Save the list to the cache
            $installedChocoPackages | Out-File "$($global:FuzzyWinget.CacheDirectory)\List\choco\installed.txt" -Encoding UTF8 -Force

            # Add the packages to the list of installed packages
            $installedPackages += $installedChocoPackages

            Write-Host " [Done]" -ForegroundColor Green
        } else {
            # If the cache is still valid, use it
            $installedPackages += Get-Content "$($global:FuzzyWinget.CacheDirectory)\List\choco\installed.txt"
        }
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
        [switch]$IncludeUnknown,

        # Fetch updates for each source before looking for updates
        [switch]$UpdateSources
    )

    # Collect all updates
    $updates = @()

    if($Sources.Contains("winget")){
        if ($UpdateSources){
            Write-Host "Updating WinGet sources..." -NoNewline

            # Update the WinGet source list
            winget source update *> $null

            Write-Host " [Done]" -ForegroundColor Green
        }

        Write-Host "Fetching WinGet updates..." -NoNewline

        # Get all updates available from WinGet and format them for fzf
        $updates += Get-WinGetPackage | Where-Object {(($_.Version -ne "Unknown") -or $IncludeUnknown) -and $_.IsUpdateAvailable} | Format-WingetPackage -isUpdate

        Write-Host " [Done]" -ForegroundColor Green
    }
    
    if($Sources.Contains("scoop")){

        if ($UpdateSources){
            Write-Host "Updating Scoop buckets..." -NoNewline

            # Update the Scoop source list
            scoop update *> $null

            Write-Host " [Done]" -ForegroundColor Green
        }

        Write-Host "Fetching Scoop updates..." -NoNewline

        # Get all packages from Scoop and format them for fzf
        $updates += scoop status 6> $null | Format-ScoopPackage -isUpdate

        Write-Host " [Done]" -ForegroundColor Green
    }

    if ($Sources.Contains("choco")){

        # I don't think there's a way to update the source list for choco, so we'll just skip it

        Write-Host "Fetching Chocolatey updates..." -NoNewline

        # Get all packages from Chocolatey and format them for fzf
        $updates += choco outdated -r | Format-ChocoPackage -isUpdate

        Write-Host " [Done]" -ForegroundColor Green
    }

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
        $source = "$($PSStyle.Foreground.Blue)ch:choco" # Choco doesn't report the source so just use choco

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