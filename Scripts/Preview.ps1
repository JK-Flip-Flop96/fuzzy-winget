# This script is run every time the highlighted package changes, so it should be as fast as possible.

# Take the highlighted line from the fuzzy search and get the package information from winget
$selection = $args[0]

# HACK: Strip the index from the start of the line
$selection = $selection -replace '^\d+\s+', ''

$CacheDirectory = $args[1]

# Get the source from the selected line
$source = Select-String -InputObject $selection -Pattern '^([\w\-:/]+)' | ForEach-Object { $_.Matches.Groups[1].Value }

if ($source.StartsWith('wg:')) {
    $CacheDirectory = Join-Path $CacheDirectory 'winget'

    # If the source is wg:N/A then the package is not in the winget index
    if ($source -eq 'wg:N/A') {
        # Used for manually installed/System packages
        $values = $selection -split '\t+'

        # Get the package name from the second column
        # Remove leading and trailing whitespace
        # Make the text between brackets yellow
        $name = $values[1] -replace '^\s*', '' -replace '\s*$', ''

        # Create the cache file path, replace any invalid characters with underscores
        $CacheFile = Join-Path $CacheDirectory $($($name -replace '[\\/:*?"<>|]', '_') + '.txt')

        # Style the package name
        $name = "$($PSStyle.Foreground.White)$name" -replace '\(([^\(]*?)\)$', "($($PSStyle.Foreground.Yellow)`$1$($PSStyle.Foreground.White))"

        # If the cache file does not exist then create it
        if (!(Test-Path $CacheFile)) {
            New-Item -ItemType File -Path $CacheFile -Force | Out-Null
        }

        # Check if the cache file is older than 1 day or if it is empty
        if ((Get-Date).Subtract((Get-Item $CacheFile).LastWriteTime).TotalDays -ge 1 -or (Get-Content $CacheFile).Count -eq 0) {
            # Display the name in bold. Highlight the version in cyan like the preview for winget packages
            "$($PSStyle.Bold)$name $($PSStyle.Reset)`n$($PSStyle.Foreground.Cyan)Version:$($PSStyle.Foreground.White) $($values[2])`n$($PSStyle.Foreground.BrightBlack)$($PSStyle.Italic)Cannot get more package information for manually installed or system packages.$($PSStyle.Reset)" | Tee-Object -FilePath $CacheFile
        
            # TODO: Add support for getting more information about manually installed/System packages from the registry
        } else {
            # If it is not then read the cache file
            Get-Content $CacheFile
        }

        
    } else {
        # Get the content of the last pair of brackets from the selected line, this is the package id. Accounts for the case where the package name contains brackets
        $id = Select-String -InputObject $selection -Pattern '\((.*?)\)' -AllMatches | ForEach-Object { $_.Matches.Groups[-1].Value }

        # Create the cache file path, replace any invalid characters with underscores
        $CacheFile = Join-Path $CacheDirectory $($($id -replace '[\\/:*?"<>|]', '_') + '.txt')

        # If the cache file does not exist then create it
        if (!(Test-Path $CacheFile)) {
            New-Item -ItemType File -Path $CacheFile -Force | Out-Null
        }

        # Check if the cache file is older than 1 day or if it is empty
        if ((Get-Item $CacheFile).LastWriteTime -lt (Get-Date).AddDays(-1) -or (Get-Content $CacheFile).Length -eq 0) {
            # Get the package information from winget

            # NOTE: This script avoids using the winget module so that it can avoid the overhead of loading the module and the time it takes to load the module
            # NOTE: The module also does not appear to have a way to get the package information at the moment
            # TODO: Update this if the winget CLI ever gets support for xml/json/etc output

            # Call winget show on the highlighted package and remove the word "Found" and the "Failed to update source" message from the output
            # Shift the array to the left by one to remove the first element which always a blank line
            $null, $info = $(winget show $id) -replace '^\s*Found\s*', '' -replace 'Failed in attempting to update the source.*$', ''

            # Change the name of the package to be bold and the id of the package to be bold and yellow
            $info = $info -replace '(^.*) \[(.*)\]$', "$($PSStyle.Bold)`$1 ($($PSStyle.Foreground.Yellow)`$2$($PSStyle.Foreground.BrightWhite))$($PSStyle.Reset)"

            # Change the keys to be cyan and the values to be white - not bright white to emphasise the keys and header
            $info -replace '(^[a-zA-Z0-9 ]+:(?![/0-9]))', "$($PSStyle.Foreground.Cyan)`$1$($PSStyle.Foreground.White)" | Tee-Object -FilePath $CacheFile
        } else {
            # If it is not then read the cache file
            Get-Content $CacheFile
        }
    }
} elseif ($source.StartsWith('sc:')) {
    $CacheDirectory = Join-Path $CacheDirectory 'scoop'

    # Get the name of the package from the selected line, scoop does not have package ids
    $id = Select-String -InputObject $selection -Pattern '\s([\w\-.]+)' | ForEach-Object { $_.Matches.Groups[1].Value }

    $CacheFile = Join-Path $CacheDirectory "$id.txt"

    # If the cache file does not exist then create it
    if (!(Test-Path $CacheFile)) {
        New-Item -ItemType File -Path $CacheFile -Force | Out-Null
    }

    # Check if the cache file is older than 1 day or if it is empty
    if ((Get-Date).Subtract((Get-Item $CacheFile).LastWriteTime).TotalDays -ge 1 -or (Get-Content $CacheFile).Count -eq 0) {
        # If it is then update the cache file
        scoop info $id | Tee-Object $CacheFile
    } else {
        # If it is not then read the cache file and recreate the formatting done by Format-Table
        $($(Get-Content $CacheFile) -split "`n" | ForEach-Object { $_ -replace '^([^:]*:)', "$($PSStyle.Foreground.Green)`$1$($PSStyle.Foreground.White)" }) -join "`n"
    }
} elseif ($source.StartsWith('ch:')) {
    $CacheDirectory = Join-Path $CacheDirectory 'choco'

    # Get the name of the package from the selected line, choco does not have package ids
    $id = Select-String -InputObject $selection -Pattern '\s([\w\-.]+)' | ForEach-Object { $_.Matches.Groups[1].Value }

    $CacheFile = Join-Path $CacheDirectory "$id.txt"

    # If the cache file does not exist then create it
    if (!(Test-Path $CacheFile)) {
        New-Item -ItemType File -Path $CacheFile -Force | Out-Null
    }

    # Check if the cache file is older than 1 day or if it is empty
    if ((Get-Date).Subtract((Get-Item $CacheFile).LastWriteTime).TotalDays -ge 1 -or (Get-Content $CacheFile).Count -eq 0) {
        # Remove the "Chocolatey v" message
        # Change the keys to be cyan and the values to be white - not bright white to emphasise the keys and header
        # Remove the "[x] packages found." message
        $(choco info $id) -replace 'Chocolatey v.*$', '' -replace '(^[a-zA-Z0-9 ]+:(?![/0-9]))', "$($PSStyle.Foreground.Cyan)`$1$($PSStyle.Foreground.White)" -replace '[0-9]+ packages found.$', '' | Tee-Object -FilePath $CacheFile
    } else {
        # If it is not then read the cache file
        Get-Content $CacheFile
    }

} elseif ($source.StartsWith('ps:')) {
    $CacheDirectory = Join-Path $CacheDirectory 'psget'

    # Get the name of the package from the selected line, psget does not have package ids
    $id = Select-String -InputObject $selection -Pattern '\s([\w\-.]+)' | ForEach-Object { $_.Matches.Groups[1].Value }

    $CacheFile = Join-Path $CacheDirectory "$id.txt"

    # If the cache file does not exist then create it
    if (!(Test-Path $CacheFile)) {
        New-Item -ItemType File -Path $CacheFile -Force | Out-Null
    }

    # Check if the cache file is older than 1 day or if it is empty
    if ((Get-Date).Subtract((Get-Item $CacheFile).LastWriteTime).TotalDays -ge 1 -or (Get-Content $CacheFile).Count -eq 0) {
        # If it is then update the cache file
        # TODO: Append the data contained in the "AdditionalMetadata" property to the output and hide empty fields
        Find-Module $id | Format-List | Tee-Object $CacheFile
    } else {
        # If it is not then read the cache file
        $($(Get-Content $CacheFile) -split "`n" | ForEach-Object { $_ -replace '^([^:]*:)', "$($PSStyle.Foreground.Green)`$1$($PSStyle.Foreground.White)" }) -join "`n"
    }
} else {
    # If we somehow get here then the source is not known
    "$($PSStyle.Foreground.Yellow)Cannot get package information for this source."
}