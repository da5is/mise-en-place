# ---- PoshCopilot: Ctrl+Shift+O turns the current line into a PowerShell command via GitHub Copilot CLI ----
# Requires: winget install GitHub.Copilot  (then run `copilot` once and /login). Esc cancels.
$env:POSHCOPILOT_MODEL  = $env:POSHCOPILOT_MODEL  ?? 'mai-code-1.1-flash'
$env:POSHCOPILOT_EFFORT = $env:POSHCOPILOT_EFFORT ?? 'low'

Set-PSReadLineKeyHandler -Chord 'Ctrl+Shift+o' -BriefDescription 'CopilotComplete' `
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

    @('-s', '--no-color',
      '--model', $env:POSHCOPILOT_MODEL,
      '--reasoning-effort', $env:POSHCOPILOT_EFFORT,
      '--available-tools',            # no tools: answer only, never runs anything
      '--disable-builtin-mcps', '--no-custom-instructions', '--no-ask-user'
    ) | ForEach-Object { $psi.ArgumentList.Add($_) }

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
# ---- end PoshCopilot ----