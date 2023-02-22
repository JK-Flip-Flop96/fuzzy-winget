# *** FuzzyWinget ***
# Author: Stuart Miller
# Version: 0.1.0
# Description: A module of functions to interact with WinGet using fzf
# License: MIT
# Repository: https://github.com/JK-Flip-Flop96/Fuzzy-Winget

<# -- TODO --
Dependant todo items are indented.
Other todo items are contained within the code if they are specific to a function or block of code.
The TODOs are grouped by priority, with the most important items at the top.
TODOs are removed once they are completed.

-- IMMEDIATE -- (For 0.1.0)
TODO: Verify that the installed fzf version has all of the required features
-   TODO: Offer to install the latest version of fzf if the installed version is too old
TODO: Offer to install the latest version of fzf if it is not installed

-- SOON -- (Before 0.2.0)
TODO: Ensure that the module works on PowerShell Core 7.1 and below, may require reduced functionality depending on the version (See issue #1)
TODO: Add a function to search for package details (winget search) and display them (winget show). This should be a wrapper around the Invoke-FuzzyWinget function
-   TODO: Add keybindings for this function, e.g. Ctrl+Shift+I for install, Ctrl+Shift+U for uninstall, Ctrl+Shift+Y for update
TODO: Add default aliases

-- FUTURE -- (Before 1.0.0)
TODO: Cache the list of packages to speed up subsequent invocations - especially useful for the search/install function
TODO: Allow more than one package to be selected, using the --multi flag
TODO: Add support for other Windows package managers (e.g. Chocolatey, Scoop)
-   TODO: Offer to install fzf with a different package manager where required
-   TODO: Allow the user to specify which package managers to use during invocation
-   TODO: Detect which package managers are available
TODO: Add support for PowerShellGet (e.g. Install-Module, Install-Script, etc.)
-   TODO: Offer to install the winget PowerShell module if it is not installed (Only possible once the module is published to the PowerShell Gallery)
TODO: Add support for langauge specific package managers (e.g. Rust's Cargo, Python's Pip, C++'s vcpkg, C#'s NuGet, etc.)
TODO: Add support for using multiple package managers at once, using the package manager's name as the source

-- FAR FUTURE -- (1.1.0 or beyond, maybe never)
TODO: Add support for other operating systems (e.g. Linux, macOS)
-   TODO: Add support for other package managers (e.g. apt, pacman, etc.)

-- CHORES -- (Anytime, preferably before major/minor release)
- Powershell stuff -
TODO: Create a module manifest
TODO: Write documentation for the functions, examples, etc.
TODO: Release to the PowerShell Gallery? - only once the module is in a known working state

- GitHub stuff -
TODO: Write the README.md
TODO: Write a CONTRIBUTING.md if anyone actually wants to contribute
TODO: Releases? Maybe? I don't know how to do that yet

- Meta stuff -
TODO: Move the TODOs to a separate file? ROADMAP.md? This block is getting a bit long.
#>

# Helper function to handle the actual running of winget commands for the other functions in this module
function Invoke-FuzzyWinget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("install", "uninstall", "update")] # Confirms that the action is one of the three supported actions
        [string]$Action,

        [Parameter(Mandatory=$true, ValueFromPipeline=$true)] # Confirms that there is at least one package to act on
        [string[]]$Packages
    )

    # Return if the function was invoked by the user and not by another function
    if($PSCmdlet.MyInvocation.CommandOrigin -ne "Internal"){
        Write-Host "This function is not intended to be called directly. Call the other functions in this module instead." -ForegroundColor Red
        return
    }

    # FIXME: Remove this when the cmdlet is supported in WindowsPowerShell (See issue #1)
    # Exit if this cmdlet was run from WindowsPowerShell
    if($PSVersionTable.PSEdition -eq "Desktop"){
        Write-Host "This cmdlet is only supported in PowerShell Core currently." -ForegroundColor Red
        return
    }

    # FIXME: Remove this when the cmdlet is supported in PowerShell Core < 7.2 (See issue #1)
    # Exit if the powershell version is less than 7.2 (See issue #1)
    if($PSVersionTable.PSVersion.Major -lt 7 -or ($PSVersionTable.PSVersion.Major -eq 7 -and $PSVersionTable.PSVersion.Minor -lt 2)){
        Write-Host "This cmdlet is only supported in PowerShell Core 7.2 or higher currently." -ForegroundColor Red
        return
    }

    # TODO: Can I differentiate between pwsh and pwsh-preview?
    # Define the ps executable to use for the preview command, pwsh for core and powershell for desktop
    $PSExecutable = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh" } else { "powershell" } 

    # TODO: Somehow convert this to a call to a function so that the preview command can be changed by the user/developer in one place
    # TODO: Define an alternate preview command for when the user is running an older versions of powershell, PSStyle doesn't work in WindowsPowerShell or Powershell Core < 7.2 (See issue #1)
    # Define the preview command for fzf to use - Better to define it here for readability, defined as an array to make it easier to read
    $fzfPreviewArgs = @(
        # Launch a new PowerShell instance to run the preview command in and pipe the selected line to it
        "echo {} | $PSExecutable -noLogo -noProfile -Command `"" 

        # Get the ID from the selected line
        '$id = $input | Select-String -Pattern \"\((.*?)\)\" | ForEach-Object { $_.Matches.Groups[1].Value };'
        
        # Call winget show on the highlighted package and remove the word "Found" from the output 
        '$info = $(winget show $id) -replace \"^\s*Found\s*\", \"\";'
        
        # Change the name of the package to be bold and the id of the package to be bold and yellow
        '$info = $info -replace \"(^.*) \[(.*)\]$\", \"$($PSStyle.Bold)`$1 ($($PSStyle.Foreground.Yellow)`$2$($PSStyle.Foreground.BrightWhite))$($PSStyle.BoldOff)\";'

        # Change the keys to be cyan and the values to be white - not bright white to emphasise the keys and header
        '$info -replace \"(^\S[a-zA-Z0-9 ]+:(?!/))\", \"$($PSStyle.Foreground.Cyan)`$1$($PSStyle.Foreground.White)\""'
    ) -join "" # Join the array into a single string

    

    # Format the packages for fzf and pipe them to fzf for selection
    $package = $Packages | Format-Table -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") } |
        fzf --ansi --reverse --preview "$fzfPreviewArgs" --preview-window '50%,border-left' --prompt=' WinGet >'

    # If the user didn't select anything return
    if(-not $package){
        return
    }

    # TODO: Allow the user to select multiple packages

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
            $result = Install-WinGetPackage $id # Cmdlet will report its own progress
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
        Write-Host (Get-Culture).TextInfo.ToTitleCase("$action succeeded") -ForegroundColor Green # Convert the action to title case for display
    }else{
        Write-Host (Get-Culture).TextInfo.ToTitleCase("$action failed") -ForegroundColor Red

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
        # TODO: Add a parameter to allow the user to specify a custom preview command, maybe in an eviroment variable?
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
        # Source may be null if the package was installed manually or by the OS
        if(-not $_.Source){
            $_.Source = "N/A" # Set the source to N/A if it is null, mainly for formatting
            $source = "$($PSStyle.Foreground.BrightBlack)$($_.Source)" # Make the source grey to make other sources stand out
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