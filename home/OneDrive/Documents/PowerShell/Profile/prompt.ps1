# Dot-sourced by the profile; prompt must live in the global scope.
function prompt {
    $p = $executionContext.SessionState.Path.CurrentLocation

    if ($p.Provider.Name -eq "FileSystem") {
        # Tell Rio the working directory
        $uri = [System.Uri]::new($p.ProviderPath).AbsoluteUri
        [Console]::Write("`e]7;$uri`a")

        # Set the displayed title using Windows-style backslashes
        [Console]::Write("`e]2;$($p.ProviderPath)`a")
    }

    "PS $p$('>' * ($nestedPromptLevel + 1)) "
}
