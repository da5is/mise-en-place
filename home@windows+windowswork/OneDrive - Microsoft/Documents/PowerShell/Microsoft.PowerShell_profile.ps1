function Import-OrInstallModule {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [int] $TimeoutSeconds = 15
    )

    try {
        Import-Module $Name -Global -ErrorAction Stop
        return
    }
    catch [System.IO.FileNotFoundException] {
        if ($_.FullyQualifiedErrorId -notlike 'Modules_ModuleNotFound,*') {
            throw
        }
    }

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
        Import-Module $Name -Global -ErrorAction Stop
    }
}

if (-not (Test-Path Variable:\global:__profileOriginalPrompt)) {
    $global:__profileOriginalPrompt = $function:prompt
}

# Keep mise's prompt wrapper intact when posh-git loads after the first prompt.
function global:prompt {
    $gitPrompt = $ExecutionContext.SessionState.PSVariable.GetValue('GitPromptScriptBlock')
    if ($gitPrompt) {
        & $gitPrompt
    }
    else {
        & $global:__profileOriginalPrompt
    }
}

Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -SupportEvent -Action {
    foreach ($moduleName in @('Terminal-Icons', 'posh-git')) {
        if ($moduleName -eq 'posh-git' -and -not (Get-Command git -CommandType Application -ErrorAction Ignore)) {
            continue
        }

        try {
            Import-OrInstallModule $moduleName
        }
        catch {
            $Host.UI.WriteWarningLine("Failed to load '$moduleName': $($_.Exception.Message)")
        }
    }
    if ($env:__COPILOT_STARTUP_PROBE) {
        $completion = TabExpansion2 -InputScript 'git che' -CursorColumn 7
        $result = @{
            Modules = @(Get-Module Terminal-Icons, posh-git).Name
            GitCheckoutCompletion = 'checkout' -in $completion.CompletionMatches.CompletionText
            MisePromptPreserved = $function:prompt.ToString().Contains('_mise_hook')
            PSReadLineLoaded = [bool](Get-Module PSReadLine)
        }
        [IO.File]::WriteAllText($env:__COPILOT_STARTUP_PROBE, ($result | ConvertTo-Json -Compress))
    }
} | Out-Null

$mise = Join-Path $HOME '.local\bin\mise.exe'
if (Test-Path -LiteralPath $mise) {
    (& $mise activate pwsh) | Out-String | Invoke-Expression
}
