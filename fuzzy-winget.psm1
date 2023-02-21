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
        [ValidateSet("install", "uninstall", "update")]
        [string]$Action,

        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string[]]$Packages
    )

    # Return if the function was invoked by the user and not by another function
    if($PSCmdlet.MyInvocation.InvocationName -ne "Invoke-FuzzyWinget"){
        Write-Host "This function is not intended to be called directly." -ForegroundColor Red
        return
    }

    # If the packages array is empty then exit
    if($Packages.Count -eq 0){
        Write-Host "No packages specified" -ForegroundColor Yellow
        return
    }

    # Define the preview command for fzf to use - Better to define it here for readability
    $fzfPreviewArgs = ('echo {} | ' + # Pipe the selected line to the command
        'pwsh -noLogo -noProfile -Command "' + # Preview command is run by cmd.exe so we need to start a new session
        '$id = $input | Select-String -Pattern \"\((.*?)\)\" | ForEach-Object { $_.Matches.Groups[1].Value }; ' +  # Get the ID from the selected line
        '$info = $(winget show $id) -replace \"^\s*Found\s*\", \"\"; ' + # Call the winget show command and remove the "Found" text from the output
        '$info = $info -replace \"(^.*) \[(.*)\]$\", \"$($PSStyle.Bold)`$1 ($($PSStyle.Foreground.Yellow)`$2$($PSStyle.Foreground.BrightWhite))$($PSStyle.BoldOff)\"; ' + # Colour the ID and make the whole header bold
        '$info -replace \"(^\S[a-zA-Z0-9 ]+:(?!/))\", \"$($PSStyle.Foreground.Cyan)`$1$($PSStyle.Foreground.White)\""' # Colour the keys, close the quotes and end the command
    ) # Will print $info in the preview window

    # Format the packages for fzf and pipe them to fzf for selection
    $package = $Packages | Format-Table -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") } |
        fzf --ansi --reverse --preview "$fzfPreviewArgs" --preview-window '50%,border-left' --prompt=' WinGet >'

    # If the user didn't select anything return
    if(-not $package){
        return
    }

    # Get the ID from the selected line
    $id = $package | Select-String -Pattern "\((.*?)\)" | ForEach-Object { $_.Matches.Groups[1].Value }

    # If the ID is empty return
    if(-not $id){
        Write-Host "No ID found." -ForegroundColor Red # This should never happen, but just in case
    }

    # Capture the result of the action
    $result = $null

    # Run the selected action
    switch($Action){
        "install" { 
            Write-Host "Installing $id..."
            $result = Install-WinGetPackage $id 
        }
        "uninstall" {
            Write-Host "Uninstalling $id..."
            $result = Uninstall-WinGetPackage $id 
        }
        "update" {
            Write-Host "Updating $id..."
            $result = Update-WinGetPackage $id 
        }
    }

    # Report the result to the user
    if($result.status -eq "Ok"){
        switch ($Action) {
            "install" { Write-Host "Successfully installed $id" -ForegroundColor Green }
            "uninstall" { Write-Host "Successfully uninstalled $id" -ForegroundColor Green }
            "update" { Write-Host "Successfully updated $id" -ForegroundColor Green }
        }
    }else{
        switch ($Action) {
            "install" { Write-Host "Failed to install $id" -ForegroundColor Red }
            "uninstall" { Write-Host "Failed to uninstall $id" -ForegroundColor Red }
            "update" { Write-Host "Failed to update $id" -ForegroundColor Red }
        }

        # Output the full status if the update failed
        $result | Format-List | Out-String | Write-Host
    }
}

# Function to allow the user to select a winget package and install it
function Invoke-FuzzyWingetInstall {
    [CmdletBinding()]
    param(
        # No parameters yet
        # TODO: Add parameters to allow the user to specify a source, version, etc.
        # TODO: Add a parameter to allow the user to pre-filter the packages
        # TODO: Add a parameter to allow the user to specify a custom preview command
    )

    # Get all packages from WinGet and format them for fzf
    $availablePackages = Find-WinGetPackage | # Get all packages 
    Select-Object -Property Source, Name, Id, Version | # Select only the properties we need
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
    Invoke-FuzzyWinget -Action install -Packages $availablePackages
}

# Allow the user to select a winget package and install it
function Invoke-FuzzyWingetUninstall{
    [CmdletBinding()]
    param(
        # No parameters yet
        # TODO: Same as Invoke-FuzzyWingetInstall
    )

    # Get all packages from WinGet and format them for fzf
    $installedPackages = Get-WinGetPackage | # Get all packages that don't have an unknown version
    Select-Object -Property Source, Name, Id, Version | # Select only the properties we need
    ForEach-Object { # Format the output so that it can be used by fzf
        $source = "$($PSStyle.Foreground.Magenta)$($_.Source)"
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
    Invoke-FuzzyWinget -Action uninstall -Packages $installedPackages
}

# Allow the user to select a winget package and update it
function Invoke-FuzzyWingetUpdate{
    [CmdletBinding()]
    param(
        # No parameters yet
        # TODO: Same as Invoke-FuzzyWingetInstall
    )

    # Get all updates available from WinGet and format them for fzf
    $updates = Get-WinGetPackage | Where-Object {($_.Version -ne "Unknown") -and $_.IsUpdateAvailable} | # Get all packages that have an update available and don't have an unknown version
    Select-Object -Property Source, Name, Id, Version, AvailableVersions | # Select only the properties we need
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
    Invoke-FuzzyWinget -Action update -Packages $updates
}