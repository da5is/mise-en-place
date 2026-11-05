function Import-OrInstallModule {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [int] $TimeoutSeconds = 15
    )

    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Write-Host "Installing PowerShell module '$Name'..." -ForegroundColor DarkGray

        $job = Start-Job {
            param($ModuleName)

            Install-Module `
                -Name $ModuleName `
                -Scope CurrentUser `
                -Force `
                -AllowClobber `
                -ErrorAction Stop
        } -ArgumentList $Name

        if (Wait-Job $job -Timeout $TimeoutSeconds) {
            try {
                Receive-Job $job -ErrorAction Stop
            }
            catch {
                Write-Warning "Failed to install '$Name': $_"
            }
        }
        else {
            Write-Warning "Installation of '$Name' timed out after $TimeoutSeconds seconds."
            Stop-Job $job
        }

        Remove-Job $job -Force
    }

    if (Get-Module -ListAvailable -Name $Name) {
        Import-Module $Name -ErrorAction SilentlyContinue
    }
}

Import-OrInstallModule 'Terminal-Icons'

if (Get-Command git -ErrorAction SilentlyContinue) {
    Import-OrInstallModule 'posh-git'
}

if (Get-Command mise -ErrorAction SilentlyContinue) {
    mise activate pwsh | Out-String | Invoke-Expression
}
