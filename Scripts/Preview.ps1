# This script is run every time the highlighted package changes, so it should be as fast as possible.

# Take the highlighted line from the fuzzy search and get the package information from winget
$selection = $args[0]

# Get the source from the selected line
$source = Select-String -InputObject $selection -Pattern "^([\w\-:]+)" | ForEach-Object { $_.Matches.Groups[1].Value };

if ($source.StartsWith("wg:")) {
    if ($source -eq "wg:N/A") { # Used for manually installed/System packages
        $source = "unknown" # Jump to the else statement in the if statement below
    } else {
        $source = "winget"

        # Get the content of the last pair of brackets from the selected line, this is the package id. Accounts for the case where the package name contains brackets
        $id = Select-String -InputObject $selection -Pattern "\((.*?)\)" -AllMatches | ForEach-Object { $_.Matches.Groups[-1].Value };
    }
} elseif ($source.StartsWith("sc:")) {
    $source = "scoop"

    # Get the name of the package from the selected line, scoop does not have package ids
    $id = Select-String -InputObject $selection -Pattern "\s([\w\-]+)" | ForEach-Object { $_.Matches.Groups[1].Value };
} else {
    # If we somehow get here then the source is not known - this will jump to the else statement in the if statement below
    $source = "unknown"
}

# Different sources have different ways of getting the package information
if ($source -eq "winget") { 
    # NOTE: This script avoids using the winget module so that it can avoid the overhead of loading the module and the time it takes to load the module
    # TODO: Update this if the winget CLI ever gets support for xml/json/etc output

    # Call winget show on the highlighted package and remove the word "Found" from the output 
    $info = $(winget show $id) -replace "^\s*Found\s*", ""

    # Remove the "Failed to update source" message
    $info = $info -replace "Failed to update source.*$", ""

    # Change the name of the package to be bold and the id of the package to be bold and yellow
    $info = $info -replace "(^.*) \[(.*)\]$", "$($PSStyle.Bold)`$1 ($($PSStyle.Foreground.Yellow)`$2$($PSStyle.Foreground.BrightWhite))$($PSStyle.BoldOff)"

    # Change the keys to be cyan and the values to be white - not bright white to emphasise the keys and header
    $info -replace "(^[a-zA-Z0-9 ]+:(?!/))", "$($PSStyle.Foreground.Cyan)`$1$($PSStyle.Foreground.White)"
    # $info is written to the preview window here
} elseif ($source -eq "scoop") {
    # TODO: Write a nice preview for scoop packages, format-list is a good start
    scoop info $id | Format-List
} else {
    # If the package is not from a known source then display an error message
    "$($PSStyle.Foreground.Yellow)Cannot get package information for this source."
}