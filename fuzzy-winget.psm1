# *** FuzzyWinget ***
# Author: Stuart Miller
# Version: 0.1.0
# Description: A module of functions to interact with WinGet using fzf
# License: MIT
# Repository: https://github.com/JK-Flip-Flop96/Fuzzy-Winget

# Helper function to handle the actual running of winget commands for the other functions in this module
function Invoke-FuzzyWinget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("install", "uninstall", "update")] # Confirms that the action is one of the three supported actions
        [string]$Action,

        [Parameter(Mandatory=$true)]
        [ValidateSet("winget")] # Confirms that the source is one of the supported sources
        [string[]]$Sources, 

        [Parameter(Mandatory=$true, ValueFromPipeline=$true)] # Confirms that there is at least one package to act on
        [string[]]$Packages
    )

    # Define the ps executable to use for the preview command, pwsh for core and powershell for desktop
    $PSExecutable = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh" } else { "powershell" } 

    # Format the packages for fzf and pipe them to fzf for selection
    $selectedPackages = $Packages | Format-Table -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") } |
        fzf --ansi --reverse --multi --preview "$PSExecutable -noLogo -noProfile -nonInteractive -File `"$PSScriptRoot\Scripts\Preview.ps1`" {}" --preview-window '50%,border-left' --prompt=' >'

    # If the user didn't select anything return
    if(-not $selectedPackages){
        return
    }

    # Loop through the selected packages
    foreach ($package in $selectedPackages) {

        # Extract the pertinent information from the selected package
        $source = $package | Select-String -Pattern "^([\w\-]+)" | ForEach-Object { $_.Matches.Groups[1].Value } # All text before the first space
        $name = $package | Select-String -Pattern "\s(.*) \(" -AllMatches | ForEach-Object { $_.Matches.Groups[-1].Value } # All text between the first space and the last opening bracket
        $id = $package | Select-String -Pattern "\((.*?)\)" -AllMatches | ForEach-Object { $_.Matches.Groups[-1].Value } # All text between the last opening bracket and the last closing bracket

        # If the ID is empty return
        if(-not $id){
            Write-Host "No ID found." -ForegroundColor Red # This should never happen, but just in case
        }

        # Define the package title for use in when reporting the action to the user  
        if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 2) {
            $packageTitle = "$name ($($PSStyle.Foreground.Yellow)$id$($PSStyle.Foreground.BrightWhite))" # Use PSStyle to make the ID yellow if the user is running PS 7.2 or newer
        } else {
            $packageTitle = "$name ($id)"  # Otherwise leave it as normal
        }

        # Remove any remaining whitespace
        $packageTitle = $packageTitle.Trim() 

        # Run the selected action
        switch($Action){
            "install" { 
                Write-Host "[$source] Installing $packageTitle"

                # TODO: Different sources have different ways of installing packages
                $result = Install-WinGetPackage $id # Cmdlet will report its own progress

                # Add the command to the history file so that the user can easily rerun it - works but requires a restart of the shell to take effect
                Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "Install-WinGetPackage $id"
            }
            "uninstall" {
                Write-Host "[$source] Uninstalling $packageTitle"
                $result = Uninstall-WinGetPackage $id
                Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "Uninstall-WinGetPackage $id"
            }
            "update" {
                Write-Host "[$source] Updating $packageTitle"
                $result = Update-WinGetPackage $id
                Add-Content -Path (Get-PSReadLineOption).HistorySavePath -Value "Update-WinGetPackage $id"
            }
        }

        # TODO: Different sources have different ways of reporting the result of the action
        # Report the result to the user
        if($result.status -eq "Ok"){
            Write-Host (Get-Culture).TextInfo.ToTitleCase("$action succeeded") -ForegroundColor Green # Convert the action to title case for display
        }else{
            Write-Host (Get-Culture).TextInfo.ToTitleCase("$action failed") -ForegroundColor Red

            # Output the full status if the update failed
            $result | Format-List | Out-String | Write-Host
        }
    }
}

# Function to allow the user to select a winget package and install it
function Invoke-FuzzyWingetInstall {
    [CmdletBinding()]
    param(
        # No parameters yet
        # TODO: Add parameters to allow the user to specify a source, version, etc.
        # TODO: Add a parameter to allow the user to pre-filter the packages
        # TODO: Add a parameter to allow the user to specify a custom preview command, maybe in an eviroment variable?
    )

    # Get all packages from WinGet and format them for fzf
    $availablePackages = Find-WinGetPackage | # Get all packages
    ForEach-Object { # Format the output so that it can be used by fzf
        $source = "$($PSStyle.Foreground.Magenta)$($_.Source)"
        $name = "$($PSStyle.Foreground.White)$($_.Name)"
        $id = "$($PSStyle.Foreground.Yellow)$($_.Id)$($PSStyle.Foreground.BrightWhite)" # Ensure the closing bracket is white
        $version = "$($PSStyle.Foreground.Green)$($_.Version)"

        # Output the formatted string - these strings are the ones that will be displayed in fzf
        "$source `t $name ($id) `t $version"
    }

    # Cache the available packages so that we can use them in the preview window
    $availablePackages | Out-String | Set-Content -Path $env:TEMP\fuzzywinget\availablePackages.txt

    # Call the helper function to install the selected packages
    Invoke-FuzzyWinget -Action install -Packages $availablePackages -Sources "winget"
}

# Allow the user to select a winget package and install it
function Invoke-FuzzyWingetUninstall{
    [CmdletBinding()]
    param(
        # No parameters yet
        # TODO: Same as Invoke-FuzzyWingetInstall
    )

    # Get all packages from WinGet and format them for fzf
    $installedPackages = Get-WinGetPackage | # Get all installed packages
    ForEach-Object { # Format the output so that it can be used by fzf
        # Source may be null if the package was installed manually or by the OS
        if(-not $_.Source){
            $source = "$($PSStyle.Foreground.BrightBlack)N/A" # Make the source grey to make other sources stand out
        }else{
            $source = "$($PSStyle.Foreground.Magenta)$($_.Source)"
        }
        
        $name = "$($PSStyle.Foreground.White)$($_.Name)"
        $id = "$($PSStyle.Foreground.Yellow)$($_.Id)$($PSStyle.Foreground.BrightWhite)" # Ensure the closing bracket is white
        $version = "$($PSStyle.Foreground.Green)$($_.Version)"

        # Output the formatted string - these strings are the ones that will be displayed in fzf
        "$source `t $name ($id) `t $version"
    }

    # If there are no packages then exit - This should never happen
    if($installedPackages.Count -eq 0){
        Write-Host "No packages found" -ForegroundColor Yellow
        return
    }

    # Invoke the helper function to uninstall the selected packages
    Invoke-FuzzyWinget -Action uninstall -Packages $installedPackages -Sources "winget"
}

# Allow the user to select a winget package and update it
function Invoke-FuzzyWingetUpdate{
    [CmdletBinding()]
    param(
        # No parameters yet
        # TODO: Same as Invoke-FuzzyWingetInstall
        # TODO: Add a parameter to allow the user to see updates for package with unknown versions, like --include-unknown from winget CLI
    )

    # Get all updates available from WinGet and format them for fzf
    $updates = Get-WinGetPackage | Where-Object {($_.Version -ne "Unknown") -and $_.IsUpdateAvailable} | # Get all packages that have an update available and don't have an unknown version
    ForEach-Object { # Format the output so that it can be used by fzf
        $source = "$($PSStyle.Foreground.Magenta)$($_.Source)"
        $name = "$($PSStyle.Foreground.White)$($_.Name)"
        $id = "$($PSStyle.Foreground.Yellow)$($_.Id)$($PSStyle.Foreground.BrightWhite)" # Ensure the closing bracket is white
        $version = "$($PSStyle.Foreground.Red)$($_.Version)"
        $latest_version = "$($PSStyle.Foreground.Green)$($_.AvailableVersions[0])" # Get the latest version from the array - this is the first element

        # Output the formatted string - these strings are the ones that will be displayed in fzf
        "$source `t $name ($id) `t $version $($PSStyle.Foreground.Cyan)-> $latest_version"
    }

    # Invoke the helper function to update the selected packages
    Invoke-FuzzyWinget -Action update -Packages $updates -Sources "winget"
}