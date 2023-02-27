# *** FuzzyWinget ***
# Author: Stuart Miller
# Version: 0.1.0
# Description: A module of functions to interact with WinGet using fzf
# License: MIT
# Repository: https://github.com/JK-Flip-Flop96/Fuzzy-Winget

# Helper function to handle the actual running of winget commands for the other functions in this module
# NOTE: This function is not exported and should not be called directly
function Invoke-FuzzyPackager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("install", "uninstall", "update")] # Confirms that the action is one of the three supported actions
        [string]$Action,

        [Parameter(Mandatory=$true)]
        [ValidateSet("winget", "scoop")] # Confirms that the source is one of the supported sources
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
        $source = $package | Select-String -Pattern "^([\w\-:]+)" | ForEach-Object { $_.Matches.Groups[1].Value } # All text before the first space

        if ($source.StartsWith("wg:")) { # If the source is a winget source
            $source = "winget" # Set the source to winget
        } elseif ($source.StartsWith("sc:")) { # If the source is a scoop bucket
            $source = "scoop" # Set the source to scoop
        } else {
            Write-Host "Unknown source." -ForegroundColor Red # This should never happen, but just in case
        }

        if ($source -eq "winget"){
            $name = $package | Select-String -Pattern "\s(.*) \(" -AllMatches | ForEach-Object { $_.Matches.Groups[-1].Value } # All text between the first space and the last opening bracket
            $id = $package | Select-String -Pattern "\((.*?)\)" -AllMatches | ForEach-Object { $_.Matches.Groups[-1].Value } # All text between the last opening bracket and the last closing bracket
        } elseif ($source -eq "scoop") {
            # Get the name of the package from the selected line, scoop does not have package ids
            $id = $($package -split "\s+")[1] # Scoop packages never have spaces in their names so this should always work
            $name = $id
        }

        # If the ID is empty return
        if(-not $id){
            Write-Host "No ID found." -ForegroundColor Red # This should never happen, but just in case
        }

        # Define the package title for use in when reporting the action to the user  
        if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 2) {
            if ($name -eq $id) { # If the name and id are the same (scoop packages)
                $packageTitle = "$($PSStyle.Foreground.Yellow)$id$($PSStyle.Foreground.BrightWhite)" 
            } else {
                $packageTitle = "$name ($($PSStyle.Foreground.Yellow)$id$($PSStyle.Foreground.BrightWhite))" # Use PSStyle to make the ID yellow if the user is running PS 7.2 or newer
            }
        } else {
            if ($name -eq $id) { # If the name and id are the same (scoop packages)
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
                }
            }
        }

        # Report the result to the user
        if ($source -eq "winget"){
            
            if($result.status -eq "Ok"){
                Write-Host (Get-Culture).TextInfo.ToTitleCase("$action succeeded") -ForegroundColor Green # Convert the action to title case for display
            }else{
                Write-Host (Get-Culture).TextInfo.ToTitleCase("$action failed") -ForegroundColor Red

                # Output the full status if the update failed
                $result | Format-List | Out-String | Write-Host
            }
        } elseif ($source -eq "scoop"){
            # Do Nothing atm, scoop's own output is sufficient
        }
    }
}

# Function to allow the user to select a winget package and install it
function Invoke-FuzzyWingetInstall {
    [CmdletBinding()]
    param(
        # No parameters yet
        # TODO: Add parameters to allow the user to specify a source, version, etc.
    )

    # Get all packages from WinGet and format them for fzf
    $availablePackages = Find-WinGetPackage | # Get all packages
    ForEach-Object { # Format the output so that it can be used by fzf
        $source = "$($PSStyle.Foreground.Magenta)wg:$($_.Source)"
        $name = "$($PSStyle.Foreground.White)$($_.Name)"
        $id = "$($PSStyle.Foreground.Yellow)$($_.Id)$($PSStyle.Foreground.BrightWhite)" # Ensure the closing bracket is white
        $version = "$($PSStyle.Foreground.Green)$($_.Version)"

        # Output the formatted string - these strings are the ones that will be displayed in fzf
        "$source `t $name ($id) `t $version"
    }

    # Cache the available packages so that we can use them in the preview window
    $availablePackages | Out-String | Set-Content -Path $env:TEMP\fuzzywinget\availablePackages.txt

    # Call the helper function to install the selected packages
    Invoke-FuzzyPackager -Action install -Packages $availablePackages -Sources "winget"
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
            $source = "$($PSStyle.Foreground.BrightBlack)wg:N/A" # Make the source grey to make other sources stand out
        }else{
            $source = "$($PSStyle.Foreground.Magenta)wg:$($_.Source)"
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
    Invoke-FuzzyPackager -Action uninstall -Packages $installedPackages -Sources "winget"
}

# Allow the user to select a winget package and update it
function Invoke-FuzzyWingetUpdate{
    [CmdletBinding()]
    param(
        # No parameters yet
        # TODO: Same as Invoke-FuzzyWingetInstall
        
        # True if installed packages with unknown versions should be included 
        [switch]$IncludeUnknown
    )

    # Get all updates available from WinGet and format them for fzf
    $updates = Get-WinGetPackage | Where-Object {(($_.Version -ne "Unknown") -or $IncludeUnknown) -and $_.IsUpdateAvailable} |
    ForEach-Object { # Format the output so that it can be used by fzf
        $source = "$($PSStyle.Foreground.Magenta)wg:$($_.Source)"
        $name = "$($PSStyle.Foreground.White)$($_.Name)"
        $id = "$($PSStyle.Foreground.Yellow)$($_.Id)$($PSStyle.Foreground.BrightWhite)" # Ensure the closing bracket is white
        $version = "$($PSStyle.Foreground.Red)$($_.Version)"
        $latest_version = "$($PSStyle.Foreground.Green)$($_.AvailableVersions[0])" # Get the latest version from the array - this is the first element

        # Output the formatted string - these strings are the ones that will be displayed in fzf
        "$source `t $name ($id) `t $version $($PSStyle.Foreground.Cyan)-> $latest_version"
    }

    # Invoke the helper function to update the selected packages
    Invoke-FuzzyPackager -Action update -Packages $updates -Sources "winget"
}

function Invoke-FuzzyScoopInstall {
    [CmdletBinding()]
    param(
        # No parameters yet
    )

    # Get all packages from Scoop and format them for fzf
    $availablePackages = scoop search | # Get all packages
    ForEach-Object { # Format the output so that it can be used by fzf
        $source = "$($PSStyle.Foreground.Magenta)sc:$($_.Source)"
        $name = "$($PSStyle.Foreground.White)$($_.Name)"
        $version = "$($PSStyle.Foreground.Green)$($_.Version)"

        # Output the formatted string - these strings are the ones that will be displayed in fzf
        "$source `t $name `t $version"
    }

    # Invoke the helper function to install the selected packages
    Invoke-FuzzyPackager -Action install -Packages $availablePackages -Sources "scoop"
}

function Invoke-FuzzyScoopUninstall {
    [CmdletBinding()]
    param(
        # No parameters yet
    )

    # Get all packages from Scoop and format them for fzf
    $installedPackages = scoop list | # Get all installed packages
    ForEach-Object { # Format the output so that it can be used by fzf
        $source = "$($PSStyle.Foreground.Magenta)sc:$($_.Source)"
        $name = "$($PSStyle.Foreground.White)$($_.Name)"
        $version = "$($PSStyle.Foreground.Green)$($_.Version)"

        # Output the formatted string - these strings are the ones that will be displayed in fzf
        "$source `t $name `t $version"
    }

    # Invoke the helper function to uninstall the selected packages
    Invoke-FuzzyPackager -Action uninstall -Packages $installedPackages -Sources "scoop"
}

function Invoke-FuzzyScoopUpdate {
    param (
        # No parameters yet
    )
    
    # Get all packages from Scoop and format them for fzf
    $packages = scoop status 

    # Return if there are no packages
    if($packages.Count -eq 0){
        return # Just return - no need to print anything as scoop status will do that
    }
    
    # WARNING: This is totally untested as I don't have any packages that need updating to test with

    $updates = $packages | Where-Object {$_.'Latest version' -ne ""} | # Other packages are returned with info in other fields - ignore them
    ForEach-Object { # Format the output so that it can be used by fzf
        $source = "$($PSStyle.Foreground.Magenta)sc:scoop" # Bucket name is not returned by scoop status
        $name = "$($PSStyle.Foreground.White)$($_.Name)"
        $version = "$($PSStyle.Foreground.Red)$($_.'Installed version')"
        $latest_version = "$($PSStyle.Foreground.Green)$($_.'Latest version')"

        # Output the formatted string - these strings are the ones that will be displayed in fzf
        "$source `t $name `t $version $($PSStyle.Foreground.Cyan)-> $latest_version"
    }

    # Invoke the helper function to update the selected packages
    Invoke-FuzzyPackager -Action update -Packages $updates -Sources "scoop"
}