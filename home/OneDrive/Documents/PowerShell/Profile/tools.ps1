# Dot-sourced by the profile: third-party modules and tool activation.
Import-OrInstallModule 'Terminal-Icons'

if (Get-Command git -ErrorAction SilentlyContinue) {
    Import-OrInstallModule 'posh-git'
}

if (Get-Command mise -ErrorAction SilentlyContinue) {
    mise activate pwsh | Out-String | Invoke-Expression
}
