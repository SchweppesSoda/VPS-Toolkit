#Requires -Version 5.1
# Run with Windows PowerShell 5.1; exercises the helper in both 5.1 and 7.
[CmdletBinding()]
param(
    [string]$BashPath = 'C:\Program Files\Git\bin\bash.exe',
    [Parameter(Mandatory = $true)][string]$PythonPath
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$tempBase = Join-Path $repo '.tmp'
$testRoot = Join-Path $tempBase ('3xui-download-test-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($testRoot)
$helper = Join-Path $repo 'scripts/vps/3x-ui/Export-3xUi.ps1'
$exporter = Join-Path $repo 'scripts/vps/3x-ui/3x-ui-node-exporter.sh'
$savedPath = $env:PATH

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Write-Utf8([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}
function Shell-Quote([string]$Value) { "'" + $Value.Replace("'", "'\''") + "'" }
function Invoke-Helper([string]$Shell, [string[]]$Arguments, [string]$Log) {
    $ErrorActionPreference = 'Continue'
    & $Shell -NoProfile -ExecutionPolicy Bypass -File $helper @Arguments *> $Log
    return $LASTEXITCODE
}

try {
    # Native SSH double: uses real stdin/stdout pipes and native argv parsing.
    Add-Type -OutputType ConsoleApplication -OutputAssembly (Join-Path $testRoot 'ssh.exe') -TypeDefinition @'
using System;
using System.IO;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
public class MockSsh {
    static string Quote(string value) {
        return "\"" + Regex.Replace(Regex.Replace(value, @"(\\*)""", "$1$1\\\""), @"(\\+)$", "$1$1") + "\"";
    }
    public static int Main(string[] args) {
        File.WriteAllLines(Environment.GetEnvironmentVariable("XUI_DOWNLOAD_TEST_ARGS"), args);
        string mode = Environment.GetEnvironmentVariable("XUI_DOWNLOAD_TEST_MODE");
        if (mode == "integration") {
            var start = new ProcessStartInfo(Environment.GetEnvironmentVariable("XUI_DOWNLOAD_TEST_BASH"));
            start.UseShellExecute = false;
            start.Arguments = "-c " + Quote(args[args.Length - 1]);
            using (var child = Process.Start(start)) { child.WaitForExit(); return child.ExitCode; }
        }
        Console.In.ReadToEnd();
        if (mode == "no-header") { Console.WriteLine("unexpected banner"); return 1; }
        byte[] data = File.ReadAllBytes(Environment.GetEnvironmentVariable("XUI_DOWNLOAD_TEST_ZIP"));
        string hash;
        using (var sha = SHA256.Create()) { hash = BitConverter.ToString(sha.ComputeHash(data)).Replace("-", "").ToLowerInvariant(); }
        if (mode == "bad-hash") hash = new string('0', 64);
        Console.WriteLine("3XUI_EXPORT_V1 " + (data.Length + (mode == "bad-size" ? 1 : 0)) + " " + hash);
        if (mode == "bad-base64") { Console.WriteLine("!!!!"); return 1; }
        for (int i = 0; i < data.Length; i += 49152) {
            Console.WriteLine(Convert.ToBase64String(data, i, Math.Min(49152, data.Length - i)));
        }
        if (mode == "truncated") return 0;
        Console.WriteLine("3XUI_EXPORT_DONE");
        if (mode == "extra-data") Console.WriteLine("extra");
        return mode == "nonzero-exit" ? 7 : 0;
    }
}
'@
    $env:PATH = $testRoot + ';' + $env:PATH
    $env:XUI_DOWNLOAD_TEST_ARGS = Join-Path $testRoot 'ssh-args.txt'
    $env:XUI_DOWNLOAD_TEST_ZIP = Join-Path $testRoot 'fixture.zip'
    Add-Type -AssemblyName System.IO.Compression
    $zipFile = [IO.File]::Create($env:XUI_DOWNLOAD_TEST_ZIP)
    $bundle = New-Object IO.Compression.ZipArchive($zipFile, ([IO.Compression.ZipArchiveMode]::Create))
    $entry = $bundle.CreateEntry('payload.bin', [IO.Compression.CompressionLevel]::NoCompression)
    $entryStream = $entry.Open()
    $payload = New-Object byte[] 180001
    $random = New-Object Random(42)
    $random.NextBytes($payload)
    $entryStream.Write($payload, 0, $payload.Length)
    $entryStream.Dispose()
    $bundle.Dispose()
    $expectedHash = (Get-FileHash -LiteralPath $env:XUI_DOWNLOAD_TEST_ZIP).Hash
    $keyPath = Join-Path $testRoot 'key with spaces'
    Write-Utf8 $keyPath 'test fixture only'
    $shells = @((Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'))
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwsh) { $shells += $pwsh.Source }

    foreach ($shell in $shells) {
        $shellName = [IO.Path]::GetFileNameWithoutExtension($shell)
        # Non-ASCII destination plus spaces and wildcard characters.
        $out = Join-Path $testRoot ($shellName + ' ' + [char]0x5bfc + [char]0x51fa + ' [backup]')
        $null = [IO.Directory]::CreateDirectory($out)
        $keep = Join-Path $out 'existing.zip'
        Write-Utf8 $keep 'keep this existing backup'
        $env:XUI_DOWNLOAD_TEST_MODE = 'valid'
        $status = Invoke-Helper $shell @('-Server', 'my-vps', '-OutDir', $out, '-Port', '2222', '-IdentityFile', $keyPath, '-Sudo', '-Address', "node's.example.test") (Join-Path $testRoot "$shellName-valid.log")
        Assert-True ($status -eq 0) "$shellName valid download failed; see .tmp logs"
        $downloads = @(Get-ChildItem -LiteralPath $out -Filter '3xui*.zip')
        Assert-True ($downloads.Count -eq 1) 'Expected exactly one downloaded ZIP'
        Assert-True ((Get-FileHash -LiteralPath $downloads[0].FullName).Hash -eq $expectedHash) 'Downloaded bytes differ'
        $actualArgs = [IO.File]::ReadAllLines($env:XUI_DOWNLOAD_TEST_ARGS)
        Assert-True ($actualArgs -contains '2222') 'SSH port was lost'
        Assert-True ($actualArgs -contains $keyPath) 'SSH key path was incorrectly quoted'
        Assert-True ($actualArgs[-2] -eq 'my-vps') 'SSH alias was lost'
        Assert-True ($actualArgs[-1].StartsWith('sudo -n bash -c ')) 'sudo remote command is incorrect'

        foreach ($mode in @('no-header', 'bad-hash', 'bad-size', 'bad-base64', 'truncated', 'nonzero-exit', 'extra-data')) {
            $env:XUI_DOWNLOAD_TEST_MODE = $mode
            $status = Invoke-Helper $shell @('-Server', 'my-vps', '-OutDir', $out) (Join-Path $testRoot "$shellName-$mode.log")
            Assert-True ($status -ne 0) "$shellName unexpectedly accepted $mode"
            Assert-True (@(Get-ChildItem -LiteralPath $out -Filter '*.partial').Count -eq 0) "$mode left a partial file"
            Assert-True (@(Get-ChildItem -LiteralPath $out -Filter '*.zip').Count -eq 2) "$mode changed existing backups"
        }
        Assert-True ([IO.File]::ReadAllText($keep) -eq 'keep this existing backup') 'Existing backup was modified'
        Write-Output "[OK] $shellName download, quoting, checksum, truncation and failure cleanup"
    }

    # Run the actual exporter against a disposable SQLite database via the SSH
    # double. Only the Linux root check is bypassed on this Windows test host.
    $env:XUI_DOWNLOAD_TEST_MODE = 'integration'
    $env:XUI_DOWNLOAD_TEST_BASH = $BashPath
    $sessions = Join-Path $testRoot 'remote-sessions'
    $null = [IO.Directory]::CreateDirectory($sessions)
    $dbPath = Join-Path $testRoot "db with 'quotes'.db"
    $fixtureScript = Join-Path $testRoot 'fixture.py'
    Write-Utf8 $fixtureScript @'
import sqlite3
import sys
con = sqlite3.connect(sys.argv[1])
con.execute("CREATE TABLE settings (key TEXT, value TEXT)")
con.execute("INSERT INTO settings VALUES (?,?)", ("subDomain", "nodes.example.test"))
con.execute("CREATE TABLE inbounds (id INTEGER, settings TEXT)")
con.commit()
con.close()
'@
    & $PythonPath $fixtureScript $dbPath
    Assert-True ($LASTEXITCODE -eq 0) 'Could not create the SQLite fixture'
    $posixDb = $dbPath.Replace('\', '/')
    $posixPython = $PythonPath.Replace('\', '/')
    $prefix = 'export PATH="/usr/bin:/bin:$PATH"' + "`n" +
        'export TMPDIR=' + (Shell-Quote $sessions.Replace('\', '/')) + "`n" +
        'python3() { ' + (Shell-Quote $posixPython) + ' "$@"; }' + "`n"
    # Windows paths need to be resolved by MSYS before the POSIX safety checks.
    $prefix += 'export TMPDIR="$(cd -- "$TMPDIR" && pwd -P)"' + "`n"
    $testExporter = Join-Path $testRoot 'test-exporter.sh'
    $scriptText = [IO.File]::ReadAllText($exporter).Replace('if [[ "${EUID}" -ne 0 ]]; then', 'if false; then')
    Write-Utf8 $testExporter ($prefix + $scriptText)
    $integrationOut = Join-Path $testRoot 'integration-output'
    $status = Invoke-Helper $shells[0] @('-Server', 'test-only', '-OutDir', $integrationOut, '-RawOnly', '-Database', $posixDb, '-ExporterPath', $testExporter) (Join-Path $testRoot 'integration.log')
    Assert-True ($status -eq 0) 'Real exporter stream integration failed; see .tmp logs'
    $download = @(Get-ChildItem -LiteralPath $integrationOut -Filter '*.zip')
    Assert-True ($download.Count -eq 1) 'Integration ZIP missing'
    $verifyScript = Join-Path $testRoot 'verify.py'
    Write-Utf8 $verifyScript @'
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1]) as bundle:
    assert bundle.testzip() is None
    assert "raw_inbounds.json" in bundle.namelist()
    assert "x-ui.snapshot.db" in bundle.namelist()
'@
    & $PythonPath $verifyScript $download[0].FullName
    Assert-True ($LASTEXITCODE -eq 0) 'Integration ZIP contents invalid'
    Assert-True (@(Get-ChildItem -LiteralPath $sessions -Force).Count -eq 0) 'Remote temporary files were not cleaned'
    Write-Output '[OK] Real Bash/SQLite export through native pipes to Windows, including remote cleanup'
}
finally {
    $env:PATH = $savedPath
    foreach ($name in @('ARGS', 'ZIP', 'MODE', 'BASH')) {
        [Environment]::SetEnvironmentVariable('XUI_DOWNLOAD_TEST_' + $name, $null, 'Process')
    }
}

# Remove only this test's verified absolute directory after successful checks.
$resolved = [IO.Path]::GetFullPath($testRoot)
$expectedBase = [IO.Path]::GetFullPath($tempBase).TrimEnd('\') + '\'
Assert-True ($resolved.StartsWith($expectedBase, [StringComparison]::OrdinalIgnoreCase)) 'Unsafe test cleanup path'
Assert-True ([IO.Path]::GetFileName($resolved) -match '^3xui-download-test-[a-f0-9]{32}$') 'Unsafe test directory name'
Remove-Item -LiteralPath $resolved -Recurse -Force
Write-Output '3x-ui Windows download tests passed.'
