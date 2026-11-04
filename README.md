# Mise-En-Place Configuration and Bootstrap

1. Create local rc file - `notepad ~\.config\mise\miserc.local.toml`
2. Add environment settings - `env= ["work", "windows", "windowswork"]`
3. If an existing deployment, run PowerShell from conhost.exe - `conhost pwsh.exe` and delete `C:\Users\matdavi\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` while no Windows Terminals are loaded.
4. `mise bootstrap --adopt da5is/mise-en-place --take-remote-all --replace-history --yes`

