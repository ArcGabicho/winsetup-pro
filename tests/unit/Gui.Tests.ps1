BeforeDiscovery {
    $script:HasDotnet = [bool](Get-Command dotnet -ErrorAction SilentlyContinue)
}

BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:Csproj = Join-Path $script:Root 'ui\WinSetup.Pro.UI\WinSetup.Pro.UI.csproj'
    Import-Module (Join-Path $script:Root 'launcher\WinSetupPro\WinSetupPro.psd1') -Force
}
AfterAll { Remove-Module WinSetupPro -Force -ErrorAction SilentlyContinue }

Describe 'GUI project' {

    It 'the csproj exists and targets net10.0-windows WPF with no NuGet dependencies' {
        Test-Path $script:Csproj | Should -BeTrue
        $xml = [xml](Get-Content -LiteralPath $script:Csproj -Raw)
        $xml.Project.PropertyGroup.TargetFramework | Should -Contain 'net10.0-windows'
        ($xml.Project.PropertyGroup.UseWPF | Where-Object { $_ }) | Should -Be 'true'
        $xml.SelectNodes('//PackageReference').Count | Should -Be 0
    }

    It 'builds with dotnet (Debug)' -Skip:(-not $script:HasDotnet) {
        $out = & dotnet build $script:Csproj -c Debug -v q --nologo 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($out -join "`n")
        (Join-Path (Split-Path $script:Csproj) 'bin\Debug\net10.0-windows\WinSetup.Pro.UI.dll') | Should -Exist
    }

    It 'the launcher locates the built GUI executable' -Skip:(-not $script:HasDotnet) {
        $m = Get-Module WinSetupPro
        $exe = & $m { param($h) Get-WinSetupGuiExe -RepoHome $h } $script:Root
        $exe | Should -Not -BeNullOrEmpty
        Test-Path $exe | Should -BeTrue
        $exe | Should -Match 'WinSetup\.Pro\.UI\.exe$'
    }

    It 'app.manifest asks for asInvoker (the GUI is not elevated)' {
        (Get-Content -LiteralPath (Join-Path (Split-Path $script:Csproj) 'app.manifest') -Raw) |
            Should -Match 'requestedExecutionLevel level="asInvoker"'
    }
}
