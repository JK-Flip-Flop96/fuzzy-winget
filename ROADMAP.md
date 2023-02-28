# Roadmap

## Soon (Before 1.0.0)
- Ensure that the module works on PowerShell Core 7.1 and below, may require reduced functionality depending on the version (See [issue #1](https://github.com/JK-Flip-Flop96/fuzzy-winget/issues/1))
- Add default keybindings
- Add default aliases
- Cache the list of packages to speed up subsequent invocations - especially useful for the search/install function <- #1 priority currently, install is catastrophically slow
- Offer to install fzf where required - now delayed until scoop is supported
- Detect which package managers are available

## Future (After 1.0.0)
- Add support for PowerShellGet (e.g. Install-Module, Install-Script, etc.)
  - Offer to install the winget PowerShell module if it is not installed (Only possible once the module is published to the PowerShell Gallery)
- Add support for langauge specific package managers (e.g. Rust's Cargo, Python's Pip, C++'s vcpkg, C#'s NuGet, etc.)
- Add support for using multiple package managers at once, using the package manager's name as the source

## Far Future (Extremely tentative, may never happen)
- Add support for other operating systems (e.g. Linux, macOS)
  - Add support for other package managers (e.g. apt, pacman, etc.)
  - Expose functionality of the tool so that it can be used in other shells (e.g. bash, zsh, etc.)

## Other (Anytime, preferably before first "real" release)

### PowerShell/Code stuff
- Write documentation for the functions, examples, etc.
- Release to the PowerShell Gallery? Probably dependant on the winget PowerShell module being released to the gallery
- Conform to the PowerShell style guide as much as possible

### GitHub stuff
- Write the README.md
- Write a CONTRIBUTING.md if anyone actually wants to contribute
- Releases? Maybe? I don't know how to do that yet