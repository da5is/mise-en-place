$profileDir = Join-Path $PSScriptRoot 'Profile'

Import-Module ProfileHelpers

. (Join-Path $profileDir 'prompt.ps1')
. (Join-Path $profileDir 'tools.ps1')
