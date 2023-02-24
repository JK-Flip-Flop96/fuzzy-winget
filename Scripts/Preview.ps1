# Take the highlighted line from the fuzzy search and get the package information from winget
$selection = $args[0]

# Get the ID and source from the selected line
$id = Select-String -InputObject $selection -Pattern "\((.*?)\)" -AllMatches | ForEach-Object { $_.Matches.Groups[-1].Value };
$source = Select-String -InputObject $selection -Pattern "^([\w\-]+)" | ForEach-Object { $_.Matches.Groups[1].Value };

# Different sources have different ways of getting the package information
if ($source -eq "winget" -or $source -eq "msstore") { 
    # Call winget show on the highlighted package and remove the word "Found" from the output 
    $info = $(winget show $id) -replace "^\s*Found\s*", ""

    # Change the name of the package to be bold and the id of the package to be bold and yellow
    $info = $info -replace "(^.*) \[(.*)\]$", "$($PSStyle.Bold)`$1 ($($PSStyle.Foreground.Yellow)`$2$($PSStyle.Foreground.BrightWhite))$($PSStyle.BoldOff)"

    # Change the keys to be cyan and the values to be white - not bright white to emphasise the keys and header
    $info -replace "(^[a-zA-Z0-9 ]+:(?!/))", "$($PSStyle.Foreground.Cyan)`$1$($PSStyle.Foreground.White)"
    # $info is written to the preview window here
} else {
    # If the package is not from a known source then display an error message
    "$($PSStyle.Foreground.Yellow)Cannot get package information for this source."
}