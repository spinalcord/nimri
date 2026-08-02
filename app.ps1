[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Mode = "run",

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot

$validModes = @("serialize", "generate", "run", "dev", "build", "test")
if ($RemainingArguments -or $Mode -notin $validModes) {
    [Console]::Error.WriteLine(
        "Usage: .\app.ps1 [serialize|generate|run|dev|build|test]"
    )
    exit 2
}

function Invoke-Native {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

$runtimeDlls = @(
    "libgcc_s_seh-1.dll",
    "libstdc++-6.dll",
    "libwinpthread-1.dll"
)

switch ($Mode) {
    { $_ -in @("serialize", "generate", "run") } {
        Invoke-Native "nim" @("c", "--threads:on", "main.nim")
        Invoke-Native ".\main.exe" @($Mode)
    }

    "dev" {
        Invoke-Native "nim" @("c", "--threads:on", "main.nim")
        Invoke-Native ".\main.exe" @("run")
    }

    "test" {
        $testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) `
            ("nimri-test-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $testDirectory | Out-Null

        try {
            foreach ($testSource in @(
                "tests/test_nimri_rpc.nim",
                "tests/test_frontend_bindings.nim"
            )) {
                $testName = [System.IO.Path]::GetFileNameWithoutExtension($testSource)
                $testBinary = Join-Path $testDirectory "$testName.exe"
                $testCache = Join-Path $testDirectory "nimcache\$testName"

                Invoke-Native "nim" @(
                    "c", "--threads:on", "--nimcache:$testCache",
                    "-o:$testBinary", $testSource
                )
                Invoke-Native $testBinary
            }
        }
        finally {
            Remove-Item -Recurse -Force -LiteralPath $testDirectory
        }
    }

    "build" {
        $nimDump = Invoke-Native "nim" @(
            "dump", "--dump.format:json", "main.nim"
        )
        $nimInfo = $nimDump | ConvertFrom-Json
        if (-not $nimInfo.prefixdir) {
            throw "Nim did not report its prefixdir."
        }

        $runtimeDirectory = Join-Path $nimInfo.prefixdir "dist\mingw64\bin"
        foreach ($runtimeDll in $runtimeDlls) {
            $runtimePath = Join-Path $runtimeDirectory $runtimeDll
            if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
                throw "Required MinGW runtime DLL was not found: $runtimePath"
            }
        }
        $env:Path = $runtimeDirectory + [System.IO.Path]::PathSeparator + $env:Path

        New-Item -ItemType Directory -Force -Path "bin" | Out-Null
        if (Test-Path -LiteralPath "bin\frontend") {
            Remove-Item -Recurse -Force -LiteralPath "bin\frontend"
        }

        $buildDirectory = Join-Path ([System.IO.Path]::GetTempPath()) `
            ("nimri-build-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $buildDirectory | Out-Null

        try {
            $bootstrapBinary = Join-Path $buildDirectory "main.exe"
            Invoke-Native "nim" @(
                "c", "--threads:on",
                "--nimcache:$(Join-Path $buildDirectory 'nimcache-bootstrap')",
                "-o:$bootstrapBinary", "main.nim"
            )
            Invoke-Native $bootstrapBinary @("generate")
            Invoke-Native "npm.cmd" @("--prefix", "frontend", "run", "build")
            Invoke-Native "nim" @(
                "c", "--threads:on", "-d:release",
                "--nimcache:$(Join-Path $buildDirectory 'nimcache-release')",
                "-o:bin\main.exe", "main.nim"
            )

            foreach ($runtimeDll in $runtimeDlls) {
                Copy-Item -LiteralPath (Join-Path $runtimeDirectory $runtimeDll) `
                    -Destination (Join-Path "bin" $runtimeDll)
            }
        }
        finally {
            Remove-Item -Recurse -Force -LiteralPath $buildDirectory
        }
    }
}
