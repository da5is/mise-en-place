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

    # Keep mise's prompt wrapper intact when posh-git loads or the profile is reloaded.
    function global:prompt {
        $gitPrompt = $ExecutionContext.SessionState.PSVariable.GetValue('GitPromptScriptBlock')
        if ($gitPrompt) {
            & $gitPrompt
        }
        else {
            & $global:__profileOriginalPrompt
        }
    }
}

Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -SupportEvent -Action {
    $previousExitCode = $global:LASTEXITCODE
    try {
        foreach ($moduleName in @('Terminal-Icons', 'posh-git')) {
            if ($moduleName -eq 'posh-git' -and -not (Get-Command git -CommandType Application -ErrorAction Ignore)) {
                continue
            }

            try {
                Import-OrInstallModule $moduleName

                if ($moduleName -eq 'Terminal-Icons') {
                    Get-Item -LiteralPath $HOME, $PROFILE.CurrentUserCurrentHost |
                        Out-String |
                        Out-Null
                }
                elseif ($moduleName -eq 'posh-git') {
                    # Cache posh-git's native helper instead of compiling C# on the first prompt.
                    if (-not ('NativeConsoleMethods' -as [type])) {
                        $poshGit = Get-Module posh-git
                        $consoleSource = & $poshGit { $consoleModeSource }
                        if ([string]::IsNullOrWhiteSpace($consoleSource)) {
                            throw 'posh-git console helper source was not found.'
                        }

                        $keySource = "$([Environment]::Version)|$([Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture)|$consoleSource"
                        $key = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($keySource)))
                        $cacheDirectory = Join-Path $env:LOCALAPPDATA 'PowerShell\Cache\posh-git'
                        $cachePath = Join-Path $cacheDirectory "NativeConsoleMethods-$key.dll"

                        if (-not [IO.File]::Exists($cachePath)) {
                            [void][IO.Directory]::CreateDirectory($cacheDirectory)
                            $temporaryPath = Join-Path $cacheDirectory "$([guid]::NewGuid().ToString('N')).dll"
                            try {
                                Add-Type -TypeDefinition $consoleSource -OutputAssembly $temporaryPath -ErrorAction Stop
                                try {
                                    [IO.File]::Move($temporaryPath, $cachePath)
                                }
                                catch [IO.IOException] {
                                    if (-not [IO.File]::Exists($cachePath)) {
                                        throw
                                    }
                                }
                            }
                            finally {
                                if ([IO.File]::Exists($temporaryPath)) {
                                    [IO.File]::Delete($temporaryPath)
                                }
                            }
                        }

                        [void][Reflection.Assembly]::LoadFrom($cachePath)
                    }

                    if ($global:GitPromptSettings.AnsiConsole) {
                        & $global:GitPromptScriptBlock | Out-Null
                    }
                }
            }
            catch {
                $Host.UI.WriteWarningLine("Failed to initialize '$moduleName': $($_.Exception.Message)")
            }
        }
    }
    finally {
        $global:LASTEXITCODE = $previousExitCode
    }
} | Out-Null

$mise = Join-Path $HOME '.local\bin\mise.exe'
if (Test-Path -LiteralPath $mise) {
    (& $mise activate pwsh) | Out-String | Invoke-Expression
}
