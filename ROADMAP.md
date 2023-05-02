# Roadmap

## Soon (Before 1.0.0)
- Add default keybindings
- Offer to update fzf where required 
  - Installation is now handled (Think it might be broken :/)

## Future (After 1.0.0)
- Offer to install the winget PowerShell module if it is not installed (Only possible once the module is published to the PowerShell Gallery)
- Add support for langauge specific package managers (e.g. Rust's Cargo, Python's Pip, C++'s vcpkg, C#'s NuGet, etc.)

## Far Future (Extremely tentative, may never happen)
- Add support for other operating systems (e.g. Linux, macOS)
  - Add support for other OS-specific package managers (e.g. apt, pacman, homebrew etc.)
  - Expose functionality of the tool so that it can be used in other shells (e.g. bash, zsh, etc.)

## Issues
- [ ] Check if the module works on PowerShell Core 7.1 and below, may require reduced functionality depending on the version (See [issue #1](https://github.com/JK-Flip-Flop96/fuzzy-winget/issues/1))
- [ ] Ensure that the module works on Windows PowerShell 5.1, may require reduced functionality (See [issue #1](https://github.com/JK-Flip-Flop96/fuzzy-winget/issues/1))
- [ ] Weird line wrapping issue after the tool is run. Seen with PSReadLine's ListView mode. 

## Other (Anytime, preferably before first "real" release)

### PowerShell/Code stuff
- Write documentation for the functions, examples, etc.
- Release to the PowerShell Gallery? Probably dependant on the winget PowerShell module being released to the gallery
- Conform to the PowerShell style guide as much as possible

### GitHub stuff
- Write the README.md
- Write a CONTRIBUTING.md if anyone actually wants to contribute
- Releases? Maybe? I don't know how to do that yet
