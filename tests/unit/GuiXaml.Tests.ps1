BeforeAll {
    $script:UiDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..\ui\WinSetup.Pro.UI')).Path
}

Describe 'GUI XAML sanity' {

    It 'no ResourceDictionary defines the same x:Key twice (would XamlParse-crash at startup)' {
        $problems = @()
        foreach ($file in Get-ChildItem $script:UiDir -Recurse -Filter '*.xaml') {
            $keys = [regex]::Matches((Get-Content -LiteralPath $file.FullName -Raw), 'x:Key="([^"]+)"') |
                ForEach-Object { $_.Groups[1].Value }
            $dupes = $keys | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name
            foreach ($d in $dupes) { $problems += "$($file.Name): duplicate x:Key '$d'" }
        }
        $problems | Should -BeNullOrEmpty -Because ($problems -join '; ')
    }

    It 'every {StaticResource X} used in a view is defined in Styles.xaml or App.xaml' {
        $defined = @()
        foreach ($f in 'Themes\Styles.xaml', 'App.xaml') {
            $p = Join-Path $script:UiDir $f
            if (Test-Path $p) {
                $defined += [regex]::Matches((Get-Content -LiteralPath $p -Raw), 'x:Key="([^"]+)"') |
                    ForEach-Object { $_.Groups[1].Value }
            }
        }
        $defined = $defined | Select-Object -Unique

        $missing = @()
        foreach ($file in Get-ChildItem $script:UiDir -Recurse -Filter '*.xaml') {
            $raw = Get-Content -LiteralPath $file.FullName -Raw
            # keys defined locally in this file (e.g. Window.Resources) also count
            $local = [regex]::Matches($raw, 'x:Key="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
            $known = @($defined) + @($local) | Select-Object -Unique
            $used = [regex]::Matches($raw, 'StaticResource\s+([A-Za-z0-9_]+)') |
                ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
            foreach ($u in $used) {
                if ($u -notin $known -and $u -notmatch '^\{') { $missing += "$($file.Name): {StaticResource $u}" }
            }
        }
        $missing | Should -BeNullOrEmpty -Because ($missing -join '; ')
    }
}
