# Scoop: home-only migration

`config.windows.toml` is shared by all Windows machines. Scoop's `which`
package, pre-packages install hook, and `install-scoop` task now live only in
`config.windowshome.toml`. Removing those declarations does **not** uninstall
an existing Scoop installation.

## Work: stop provisioning Scoop

1. Bring the updated configs onto the work machine before running bootstrap.
2. In `~\.config\mise\miserc.local.toml`, set:

   ```toml
   env = ["windows", "windowswork"]
   ```

   Preserve other keys and any existing `work` environment (which configures
   work package registries). Remove `windowshome` from the list. Also remove
   `windowshome` from any `MISE_ENV` override in the shell, user/machine
   environment variables, or shell profile.
3. Open a new PowerShell window and check:

   ```powershell
   mise config ls
   mise tasks ls --name-only
   ```

   The config list must include `config.windows.toml` and
   `config.windowswork.toml`, but not `config.windowshome.toml`. The task list
   must not include `install-scoop`. No replacement package manager is added.

## Work: uninstall existing Scoop

**If work policy blocks running Scoop, ask IT to perform the cleanup. Do not
bypass policy or execution restrictions to run these commands.** Run the
following only where approved.

1. Inventory the installation before removing it:

   ```powershell
   scoop list
   scoop config
   $scoopRoot = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $HOME 'scoop' }
   $scoopGlobalRoot = if ($env:SCOOP_GLOBAL) { $env:SCOOP_GLOBAL } else { Join-Path $env:ProgramData 'scoop' }
   $scoopRoot
   $scoopGlobalRoot
   ```

   Inspect both roots, including any globally installed apps. Install needed,
   approved replacements through your organization's supported channel and
   verify their executable paths before uninstalling. Shared mise tools are
   unchanged, but other Scoop-installed apps will be removed too.

2. Save an inventory outside either Scoop root, in an approved local location:

   ```powershell
   scoop export | Set-Content -LiteralPath (Join-Path $HOME 'scoop-work-export.json') -Encoding utf8
   ```

   The export is an inventory, **not an app-data backup**. Separately back up
   needed data from `<Scoop root>\persist`, app directories, and any external
   data locations. Review the export for private bucket URLs; keep work
   inventories and data on approved work storage, not in this config directory
   or on a home machine.

3. Close Scoop-installed applications and terminals using them. From an
   approved PowerShell not running inside a Scoop directory, choose **one**
   uninstall command:

   ```powershell
   # Current-user installation only:
   scoop uninstall scoop
   ```

   If global apps also need removal, use this **instead**, in an approved
   elevated PowerShell under the same user account:

   ```powershell
   scoop uninstall scoop --global
   ```

   Both commands remove Scoop and all current-user Scoop apps; `--global`
   additionally removes global apps. Persisted data is retained by default.
   To remove it too, append `--purge` to the chosen command **only after
   verifying backups**. This is destructive. Read the confirmation carefully.
   If removal fails because files are in use, close the identified apps or
   restart and retry; do not simply delete the installation directory first.

4. Review leftovers after a successful uninstall:

   - Retained `persist` directories are expected without `--purge`. Remove only
     confirmed Scoop-owned leftovers after backup and according to work policy.
   - Inspect user and, if applicable, machine `PATH` in Windows Environment
     Variables. Remove only entries pointing into the removed Scoop roots
     (including shims and app-specific paths), preserving all unrelated entries.
   - Remove obsolete `SCOOP`, `SCOOP_GLOBAL`, and `SCOOP_CACHE` environment
     variables and any custom Scoop cache after checking ownership and backups.
   - Check Scoop's config file (normally `~\.config\scoop\config.json`, or
     `$env:XDG_CONFIG_HOME\scoop\config.json`), Scoop-created Start Menu
     shortcuts, and shell-profile Scoop imports or PATH edits. Remove only
     stale Scoop-owned entries. App-specific integrations may need separate
     cleanup through the app's documented uninstall steps.

5. Close all terminal windows and open a fresh PowerShell:

   ```powershell
   Get-Command scoop -All -ErrorAction SilentlyContinue
   mise config ls
   mise tasks ls --name-only
   ```

   `scoop` should not resolve, `windowshome` must not load, and `install-scoop`
   must not be listed. Verify needed replacement applications still resolve
   outside the removed Scoop roots. Do not use `mise bootstrap unapply` for
   this migration: that could remove unrelated managed resources.

## Home: cut over without reinstalling

1. Bring the updated configs onto the home machine.
2. In `~\.config\mise\miserc.local.toml`, preserve other keys and set:

   ```toml
   env = ["windows", "windowshome"]
   ```

   Keep both environments: `windowshome` adds to, rather than replaces,
   shared Windows configuration. Ensure any `MISE_ENV` override agrees.
3. Open a fresh PowerShell and verify `mise config ls` includes both
   `config.windows.toml` and `config.windowshome.toml`, and excludes
   `config.windowswork.toml`. Preview package changes, then apply them:

   ```powershell
   mise bootstrap --only packages --dry-run
   mise bootstrap --only packages
   ```

   This also applies other configured bootstrap packages. The home
   pre-packages hook installs Scoop if absent and keeps an existing
   installation (including a custom `$env:SCOOP` root). Existing apps,
   buckets, and persisted data stay in place; no export/import, directory
   move, or uninstall is needed. A partial/broken Scoop directory is not
   repaired by this hook; repair it before bootstrap if necessary.
4. Open another PowerShell window if Scoop was newly installed, then check:

   ```powershell
   scoop --version
   scoop list
   Get-Command which -All
   ```

   Scoop and its `which` package should be available. Future home bootstrap
   runs continue to manage them; shared Windows and work bootstrap runs do not.

Uninstall behavior: [Scoop uninstall command](https://github.com/ScoopInstaller/Scoop/blob/master/libexec/scoop-uninstall.ps1)
and [Scoop self-uninstaller](https://github.com/ScoopInstaller/Scoop/blob/master/bin/uninstall.ps1).
