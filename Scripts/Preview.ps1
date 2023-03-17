# This script is run every time the highlighted package changes, so it should be as fast as possible.

# Take the highlighted line from the fuzzy search and get the package information from winget
$selection = $args[0]

# Get the source from the selected line
$source = Select-String -InputObject $selection -Pattern "^([\w\-:/]+)" | ForEach-Object { $_.Matches.Groups[1].Value }

if ($source.StartsWith("wg:")) {

    

    if ($source -eq "wg:N/A") { # Used for manually installed/System packages
        $values = $selection -split "\t+"

        # Get the package name from the second column
        $name = $values[1] -replace "^\s*", ""
        $name = $name -replace "\s*$", ""

        # Make text inside the last pair of brackets yellow
        $name = $name -replace "\(([^\(]*?)\)$", "($($PSStyle.Foreground.Yellow)`$1$($PSStyle.Foreground.BrightWhite))"

        # Get the package version from the third column
        $version = $values[2]

        Write-Host "$($PSStyle.Bold)$name $($PSStyle.Reset)`n$($PSStyle.Foreground.Cyan)Version:$($PSStyle.Foreground.BrightWhite) $version"

        "$($PSStyle.Foreground.BrightBlack)$($PSStyle.Italic)Cannot get more package information for manually installed or system packages.$($PSStyle.Reset)"
    } else {
        # Get the content of the last pair of brackets from the selected line, this is the package id. Accounts for the case where the package name contains brackets
        $id = Select-String -InputObject $selection -Pattern "\((.*?)\)" -AllMatches | ForEach-Object { $_.Matches.Groups[-1].Value }

        # Get the package information from winget

        # NOTE: This script avoids using the winget module so that it can avoid the overhead of loading the module and the time it takes to load the module
        # TODO: Update this if the winget CLI ever gets support for xml/json/etc output

        # Call winget show on the highlighted package and remove the word "Found" from the output 
        $info = $(winget show $id) -replace "^\s*Found\s*", ""

        # Remove the "Failed to update source" message
        $info = $info -replace "Failed to update source.*$", ""

        # Change the name of the package to be bold and the id of the package to be bold and yellow
        $info = $info -replace "(^.*) \[(.*)\]$", "$($PSStyle.Bold)`$1 ($($PSStyle.Foreground.Yellow)`$2$($PSStyle.Foreground.BrightWhite))$($PSStyle.BoldOff)"

        # Change the keys to be cyan and the values to be white - not bright white to emphasise the keys and header
        $info -replace "(^[a-zA-Z0-9 ]+:(?![/0-9]))", "$($PSStyle.Foreground.Cyan)`$1$($PSStyle.Foreground.White)"
    }
} elseif ($source.StartsWith("sc:")) {
    # Get the name of the package from the selected line, scoop does not have package ids
    $id = Select-String -InputObject $selection -Pattern "\s([\w\-]+)" | ForEach-Object { $_.Matches.Groups[1].Value }

    # Scoop's info command returns a nice powershell hashtable so we can use Format-List to display it
    scoop info $id | Format-List
} elseif ($source.StartsWith("ch:")) {
    # Get the name of the package from the selected line, choco does not have package ids
    $id = Select-String -InputObject $selection -Pattern "\s([\w\-.]+)" | ForEach-Object { $_.Matches.Groups[1].Value }

    $info = $(choco info $id)

    # Remove the "Chocolatey v" message
    $info = $info -replace "Chocolatey v.*$", ""

    # Change the keys to be cyan and the values to be white - not bright white to emphasise the keys and header
    $info = $info -replace "(^[a-zA-Z0-9 ]+:(?![/0-9]))", "$($PSStyle.Foreground.Cyan)`$1$($PSStyle.Foreground.White)"

    # Remove the "[x] packages found." message
    $info -replace "[0-9]+ packages found.$", ""

} else {
    # If we somehow get here then the source is not known
    "$($PSStyle.Foreground.Yellow)Cannot get package information for this source."
}