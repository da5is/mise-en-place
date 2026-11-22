PSReadLine loaded: $([bool](Get-Module PSReadLine))
# =====================================================================================
#  Warp-style PowerShell profile (Windows Terminal / Rio), backed by GitHub Copilot CLI
#  Requires: PowerShell 7.2+, Copilot CLI (winget install GitHub.Copilot, run `copilot`
#  once and /login). Optional: psmux for persistent sessions.
#  Put oh-my-posh / starship / your own prompt setup ABOVE the "AI error correction"
#  section so it gets wrapped rather than replaced.
# =====================================================================================

# ---- Scripts: behave like -NoProfile from here down -----------------------------------
# PowerShell only loads PSReadLine for an interactive prompt, so no PSReadLine = a script
# (pwsh -File, pwsh -Command without -NoExit, -NonInteractive, piped input).
# Anything placed ABOVE this line still runs for scripts.
if (-not (Get-Module PSReadLine)) { return }

# ---- Settings (override any of these before this point) ------------------------------
$env:POSHCOPILOT_MODEL  = $env:POSHCOPILOT_MODEL  ?? 'mai-code-1.1-flash'
$env:POSHCOPILOT_EFFORT = $env:POSHCOPILOT_EFFORT ?? 'low'   # use 'none' if the model rejects 'low'
$env:POSHCOPILOT_FIX    = $env:POSHCOPILOT_FIX    ?? '1'     # '0' turns off AI error correction

# ---- History ghost text --------------------------------------------------------------
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle InlineView

# Right arrow: at the end of the line, accept the next word of the suggestion; otherwise move normally
Set-PSReadLineKeyHandler -Chord RightArrow -BriefDescription 'SmartForwardChar' -ScriptBlock {
    $line = $null; $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($cursor -lt $line.Length) { [Microsoft.PowerShell.PSConsoleReadLine]::ForwardChar() }
    else { [Microsoft.PowerShell.PSConsoleReadLine]::AcceptNextSuggestionWord() }
}
# End: at the end of the line, accept the whole suggestion; otherwise jump to the end
Set-PSReadLineKeyHandler -Chord End -BriefDescription 'SmartEnd' -ScriptBlock {
    $line = $null; $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($cursor -lt $line.Length) { [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine() }
    else { [Microsoft.PowerShell.PSConsoleReadLine]::AcceptSuggestion() }
}

# ---- Copilot CLI helpers -------------------------------------------------------------
function Get-PoshCopilotArgs {
    '-s', '--no-color',
    '--model', $env:POSHCOPILOT_MODEL,
    '--reasoning-effort', $env:POSHCOPILOT_EFFORT,
    '--available-tools',            # empty list = no tools: it can only answer, never run anything
    '--disable-builtin-mcps', '--no-custom-instructions', '--no-ask-user'
}

# ---- Ctrl+Shift+O (and Alt+O fallback): turn the current line into a command ---------
# Alt+O is there because Rio and psmux may deliver Ctrl+Shift+O as plain Ctrl+O.
foreach ($_chord in 'Ctrl+Shift+o', 'Alt+o') {
Set-PSReadLineKeyHandler -Chord $_chord -BriefDescription 'CopilotComplete' `
    -Description 'Turn the current line into a PowerShell command using GitHub Copilot CLI' -ScriptBlock {

    $rl = [Microsoft.PowerShell.PSConsoleReadLine]
    $line = $null; $cursor = $null
    $rl::GetBufferState([ref]$line, [ref]$cursor)
    if ([string]::IsNullOrWhiteSpace($line)) { return }

    $exe = Get-Command copilot -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) { $global:PoshCopilotLastError = 'copilot CLI not found on PATH'; $rl::Ding(); return }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    if ($exe.Extension -match '^\.(cmd|bat)$') {
        $psi.FileName = $env:ComSpec
        '/d', '/c', $exe.Source | ForEach-Object { $psi.ArgumentList.Add($_) }
    } else { $psi.FileName = $exe.Source }
    Get-PoshCopilotArgs | ForEach-Object { $psi.ArgumentList.Add($_) }

    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardInputEncoding  = [System.Text.UTF8Encoding]::new($false)
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

    $prompt = @"
You convert requests into PowerShell 7 commands for Windows.
Reply with exactly one command line and nothing else: no explanation, no markdown, no code fences.
If the input is already a partial or broken command, complete or fix it.
Input: $line
"@

    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($prompt); $p.StandardInput.Close()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()

    $frames = [char[]]'⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'; $i = 0
    $shownLen = $line.Length; $cancelled = $false
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        while (-not $outTask.IsCompleted) {
            if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq 'Escape') { $cancelled = $true; break }
            if ($sw.Elapsed.TotalSeconds -gt 90) { $cancelled = $true; break }
            $status = '  {0} thinking {1:0.0}s (Esc to cancel)' -f $frames[$i++ % $frames.Length], $sw.Elapsed.TotalSeconds
            $rl::Replace(0, $shownLen, $line + $status)
            $shownLen = $line.Length + $status.Length
            Start-Sleep -Milliseconds 80
        }
    } finally {
        if (-not $p.HasExited) { try { $p.Kill($true) } catch {} }
        $rl::Replace(0, $shownLen, $line)
    }
    if ($cancelled) { $rl::Ding(); return }

    $out = $outTask.Result
    $cmd = $out -split "`r?`n" | Where-Object { $_.Trim() -and $_ -notmatch '^\s*```' } | Select-Object -First 1
    if (-not $cmd) {
        $global:PoshCopilotLastError = ($errTask.Result, $out | Where-Object { $_ }) -join "`n"
        $rl::Ding(); return
    }
    $rl::Replace(0, $line.Length, $cmd.Trim())   # review, then press Enter
}
}
Remove-Variable _chord -ErrorAction SilentlyContinue

# ---- AI error correction: when a command fails, a fix appears as ghost text ----------
# The fix is offered for the next command line only. Start typing it (or press End/→ on
# an empty line if your PSReadLine shows it there) to accept; anything else dismisses it.
if (-not ('AICorrector' -as [type])) {
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Management.Automation.Subsystem;
using System.Management.Automation.Subsystem.Prediction;
using System.Threading;

public sealed class AICorrector : ICommandPredictor {
    public static volatile string Suggestion = string.Empty;
    public static volatile int Generation = 0;

    private static readonly Guid _id = new Guid("6f2a8c41-3d7e-4b9a-9c15-2e8d0f7a4b63");
    public Guid Id => _id;
    public string Name => "AICorrector";
    public string Description => "Copilot fix for the last failed command";

    public bool CanAcceptFeedback(PredictionClient client, PredictorFeedbackKind feedback) => false;

    public SuggestionPackage GetSuggestion(PredictionClient client, PredictionContext context, CancellationToken ct) {
        var s = Suggestion;
        if (string.IsNullOrWhiteSpace(s)) return default;
        var input = context.InputAst.Extent.Text;
        if (input.Length > 0 && !s.StartsWith(input, StringComparison.OrdinalIgnoreCase)) return default;
        return new SuggestionPackage(new List<PredictiveSuggestion> { new PredictiveSuggestion(s) });
    }

    public void OnSuggestionDisplayed(PredictionClient client, uint session, int countOrIndex) { }
    public void OnSuggestionAccepted(PredictionClient client, uint session, string acceptedSuggestion) { }
    public void OnCommandLineAccepted(PredictionClient client, IReadOnlyList<string> history) { }
    public void OnCommandLineExecuted(PredictionClient client, string commandLine, bool success) { }
}
'@
        [System.Management.Automation.Subsystem.SubsystemManager]::RegisterSubsystem(
            [System.Management.Automation.Subsystem.SubsystemKind]::CommandPredictor, [AICorrector]::new())
    } catch {
        Write-Warning "AI error correction disabled: $($_.Exception.Message)"
        $env:POSHCOPILOT_FIX = '0'
    }
}

if (-not $global:PoshCopilotFixState) {
    $global:PoshCopilotFixState = @{
        OrigPrompt = $function:prompt          # wrap whatever prompt you already have
        LastId     = (Get-History -Count 1).Id
        LastErr    = $global:Error[0]
        PluginOn   = $false
    }
}

function global:prompt {
    $ok   = $?
    $exit = $global:LASTEXITCODE
    $st   = $global:PoshCopilotFixState

    if ($env:POSHCOPILOT_FIX -ne '0' -and ('AICorrector' -as [type])) {
        # Any fix from the previous failure only lives for one command line
        if ($st.PluginOn) {
            [AICorrector]::Generation = [AICorrector]::Generation + 1
            [AICorrector]::Suggestion = ''
            Set-PSReadLineOption -PredictionSource History
            $st.PluginOn = $false
        }
        Get-Job -Name PoshCopilotFix -ErrorAction SilentlyContinue |
            Where-Object State -ne 'Running' | Remove-Job -Force

        $last = Get-History -Count 1
        if ($last -and $last.Id -ne $st.LastId) {            # a real command ran (not an empty Enter)
            $st.LastId = $last.Id
            $newErr = if ($global:Error.Count -and -not [object]::ReferenceEquals($global:Error[0], $st.LastErr)) { "$($global:Error[0])" }
            $st.LastErr = $global:Error[0]

            # $? covers cmdlet failures and non-zero exit codes; skip Ctrl+C (0xC000013A)
            $copilot = Get-Command copilot -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $ok -and $exit -ne -1073741510 -and $copilot) {
                $detail = if ($newErr) { "Error: $newErr" } else { "Exit code: $exit" }
                $prompt = @"
You are a PowerShell 7 expert on Windows. A command failed.
Reply with exactly one line: the corrected command. No markdown, no code fences, no explanation.
Command: $($last.CommandLine)
$detail
Directory: $($PWD.Path)
"@
                [AICorrector]::Generation = [AICorrector]::Generation + 1
                [AICorrector]::Suggestion = ''
                Set-PSReadLineOption -PredictionSource Plugin
                $st.PluginOn = $true

                $null = Start-ThreadJob -Name PoshCopilotFix -ArgumentList @(
                    $copilot.Source, (Get-PoshCopilotArgs), $prompt, [AICorrector]::Generation
                ) -ScriptBlock {
                    param($exe, $copilotArgs, $prompt, $gen)
                    try {
                        $out = $prompt | & $exe @copilotArgs 2>$null
                        $fix = $out | Where-Object { $_.Trim() -and $_ -notmatch '^\s*```' } | Select-Object -First 1
                        # Only publish if no newer command has run since this job started
                        if ($fix -and [AICorrector]::Generation -eq $gen) { [AICorrector]::Suggestion = $fix.Trim() }
                    } catch { }
                }
            }
        }
    }

    $global:LASTEXITCODE = $exit
    if ($st.OrigPrompt) { & $st.OrigPrompt } else { "PS $($PWD.Path)$('>' * ($NestedPromptLevel + 1)) " }
}

# ---- psmux auto-start: keep this at the very bottom ----------------------------------
# Only for a plain interactive pwsh: skipped inside psmux, with -NoExit -Command, in VS Code,
# and when NO_MUX is set. (Scripts never get this far.)
$_hasCommand = [Environment]::GetCommandLineArgs() -match '^(-|/)(c|com\w*|cwa|commandwithargs)$'
if (-not $_hasCommand -and -not $env:TMUX -and -not $env:NO_MUX -and
    $Host.Name -eq 'ConsoleHost' -and $env:TERM_PROGRAM -ne 'vscode' -and
    (Get-Command psmux -ErrorAction SilentlyContinue)) {

    psmux attach 2>$null || psmux
    exit $LASTEXITCODE    # close the outer shell when you detach/quit; remove to drop back to pwsh
}
Remove-Variable _hasCommand -ErrorAction SilentlyContinue
