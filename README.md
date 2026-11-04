# Mise-En-Place Configuration and Bootstrap

- Install mise via `curl -fsSL https://mise.run | sh` or `winget install jdx.mise`
- Configure GH authentication

```
mise exec gh@latest -- gh auth login --hostname github.com --git-protocol https --web
mise exec gh@latest -- gh auth setup-git --hostname github.com
mise bootstrap --adopt da5is/mise-en-place
```

- Create local rc file - `~\.config\mise\miserc.local.toml` or `~/.config/mise/miserc.local.toml`
- Add environment settings - `env= ["work", "windows", "windowswork"]`
- If an existing deployment, run PowerShell from conhost.exe - `conhost pwsh.exe` and delete `C:\Users\matdavi\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` while no Windows Terminals are loaded.
- `mise bootstrap --adopt da5is/mise-en-place --take-remote-all --replace-history --yes`

