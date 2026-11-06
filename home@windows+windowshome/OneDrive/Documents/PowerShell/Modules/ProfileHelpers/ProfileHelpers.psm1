function Import-OrInstallModule {
    <#
    .SYNOPSIS
    Imports a module, installing it for the current user first if missing.
    #>
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
        # Global so the module stays visible outside this module's scope
        Import-Module $Name -Global -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Import-OrInstallModule
