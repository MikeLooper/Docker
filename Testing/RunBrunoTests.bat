@echo off
rem ===========================================================================
rem  RunBrunoTests.bat
rem
rem  Runs the Bruno test collections for the Pilot APIs against each Docker
rem  environment and writes a combined HTML report (plus per-run
rem  HTML/JSON/JUnit reports).
rem
rem  Environments (run in this order):
rem    1. Docker - PostgreSQL
rem    2. Docker - SQL Server
rem
rem  Requires Node.js. Uses the Bruno CLI ("bru") if installed globally,
rem  otherwise runs it through npx (@usebruno/cli).
rem  Secrets (e.g. IDP_HOST_PASSWORD) are read by Bruno from the .env file in
rem  each collection folder.
rem ===========================================================================
setlocal EnableExtensions

set "GITHUB_ROOT=C:\Working\Storage\Dev\GitHub"

for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"`) do set "STAMP=%%T"
set "REPORT_DIR=%~dp0BrunoReports\%STAMP%"
set "MANIFEST=%REPORT_DIR%\runs.txt"
mkdir "%REPORT_DIR%" >nul 2>&1

where bru >nul 2>&1
if %ERRORLEVEL%==0 (
    set "BRU_CMD=bru"
) else (
    where npx >nul 2>&1 || (
        echo ERROR: Neither "bru" nor "npx" was found. Install Node.js, then run: npm install -g @usebruno/cli
        exit /b 2
    )
    set "BRU_CMD=npx --yes @usebruno/cli"
)

echo Report folder : %REPORT_DIR%
echo.

set "OVERALL=0"
call :RunEnvironment "Docker - PostgreSQL" "PostgreSQL"
call :RunEnvironment "Docker - SQL Server" "SqlServer"

echo.
echo Building summary report...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-Content -LiteralPath '%~f0' -Raw; $s = $s.Substring($s.LastIndexOf('#==POWERSHELL==#')); & ([scriptblock]::Create($s)) -ReportDir '%REPORT_DIR%'"

echo.
echo Summary report: %REPORT_DIR%\Summary.html
if exist "%REPORT_DIR%\Summary.html" start "" "%REPORT_DIR%\Summary.html"

if "%OVERALL%"=="0" (echo RESULT: ALL COLLECTIONS PASSED) else (echo RESULT: ONE OR MORE COLLECTIONS FAILED)
endlocal & exit /b %OVERALL%

rem ---------------------------------------------------------------------------
rem  :RunEnvironment <BrunoEnvironmentName> <ShortTag>
rem ---------------------------------------------------------------------------
:RunEnvironment
set "BRU_ENV=%~1"
set "TAG=%~2"
echo ###########################################################################
echo  Environment: %BRU_ENV%
echo ###########################################################################
call :RunCollection "PilotApiDotNet"  "%GITHUB_ROOT%\PilotApiDotNet\test\Bruno\PilotApiDotNet"
call :RunCollection "PilotApiJava"    "%GITHUB_ROOT%\PilotApiJava\test\Bruno\PilotApiJava"
call :RunCollection "PilotApiPython"  "%GITHUB_ROOT%\PilotApiPython\tests\Bruno\PilotApiPython"
call :RunCollection "PilotUtilityApi" "%GITHUB_ROOT%\PilotUtilityApi\test\Bruno\PilotUtilityApi"
call :RunCollection "PilotApiMsDab"   "%~dp0MsDab\PilotApiMsDab"
goto :eof

rem ---------------------------------------------------------------------------
rem  :RunCollection <Name> <CollectionPath>   (uses BRU_ENV and TAG)
rem ---------------------------------------------------------------------------
:RunCollection
set "NAME=%~1"
set "COLL=%~2"
set "OUT=%REPORT_DIR%\%NAME%_%TAG%"
echo ===========================================================================
echo  %NAME%  [%BRU_ENV%]
echo  %COLL%
echo ===========================================================================
call :Now START_TS
if not exist "%COLL%\opencollection.yml" (
    echo ERROR: Collection not found.
    >> "%MANIFEST%" echo %TAG%;%BRU_ENV%;%NAME%;NOT_FOUND;%START_TS%;%START_TS%
    set "OVERALL=1"
    goto :eof
)
pushd "%COLL%"
call %BRU_CMD% run -r --env "%BRU_ENV%" ^
    --reporter-json  "%OUT%.json" ^
    --reporter-html  "%OUT%.html" ^
    --reporter-junit "%OUT%.xml"
set "RC=%ERRORLEVEL%"
popd
call :Now END_TS
>> "%MANIFEST%" echo %TAG%;%BRU_ENV%;%NAME%;%RC%;%START_TS%;%END_TS%
if not "%RC%"=="0" set "OVERALL=1"
echo.
goto :eof

rem ---------------------------------------------------------------------------
rem  :Now <VariableName>   Sets the variable to the current ISO 8601 timestamp.
rem ---------------------------------------------------------------------------
:Now
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format o"`) do set "%~1=%%T"
goto :eof

rem ---------------------------------------------------------------------------
rem  Everything below is PowerShell that builds Summary.html from the JSON
rem  results. It is never executed by cmd (the script exits above).
rem ---------------------------------------------------------------------------
#==POWERSHELL==#
param([string]$ReportDir)

function Enc([object]$v) { [System.Net.WebUtility]::HtmlEncode([string]$v) }
function FormatDuration([TimeSpan]$t) {
    if ($t.TotalSeconds -lt 60) { '{0:N1} s' -f $t.TotalSeconds } else { '{0}:{1:mm\:ss}' -f [int][Math]::Floor($t.TotalHours), $t }
}

$manifest = Join-Path $ReportDir 'runs.txt'
$runs = if (Test-Path $manifest) { @(Get-Content $manifest | Where-Object { $_.Trim() }) } else { @() }
$summaryRows = New-Object System.Text.StringBuilder
$detailHtml  = New-Object System.Text.StringBuilder
$tot = @{ Req = 0; ReqPass = 0; ReqFail = 0; Tests = 0; TestPass = 0; Asserts = 0; AssertPass = 0; Duration = [TimeSpan]::Zero }
$firstStart = $null; $lastEnd = $null

foreach ($line in $runs) {
    $tag, $envName, $name, $status, $startTs, $endTs = $line.Split(';') | ForEach-Object { $_.Trim() }
    $id       = "${name}_$tag"
    $jsonFile = Join-Path $ReportDir "$id.json"

    $started  = [DateTime]::Parse($startTs, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    $ended    = [DateTime]::Parse($endTs,   [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    $duration = $ended - $started
    $tot.Duration += $duration
    if (-not $firstStart -or $started -lt $firstStart) { $firstStart = $started }
    if (-not $lastEnd -or $ended -gt $lastEnd) { $lastEnd = $ended }
    $timeCells = "<td>$($started.ToString('yyyy-MM-dd HH:mm:ss'))</td><td>$(FormatDuration $duration)</td>"

    if (-not (Test-Path $jsonFile)) {
        [void]$summaryRows.Append("<tr class='fail'><td>$(Enc $envName)</td><td>$name</td>$timeCells<td colspan='4'>No results (exit/status: $(Enc $status))</td><td>FAIL</td><td></td></tr>")
        continue
    }

    $data = Get-Content $jsonFile -Raw | ConvertFrom-Json
    $iterations = @($data)
    $req = 0; $reqPass = 0; $reqFail = 0; $tests = 0; $testPass = 0; $asserts = 0; $assertPass = 0
    $rows = New-Object System.Text.StringBuilder

    foreach ($it in $iterations) {
        $s = $it.summary
        $req += [int]$s.totalRequests; $reqPass += [int]$s.passedRequests; $reqFail += [int]$s.failedRequests + [int]$s.errorRequests
        $tests += [int]$s.totalTests;  $testPass += [int]$s.passedTests
        $asserts += [int]$s.totalAssertions; $assertPass += [int]$s.passedAssertions

        foreach ($r in @($it.results)) {
            $failed = @(@($r.testResults) + @($r.assertionResults) | Where-Object { $_ -and $_.status -ne 'pass' })
            $ok = (-not $r.error) -and ($failed.Count -eq 0) -and ($r.status -ne 'error')
            $cls = if ($r.skipped -or $r.status -eq 'skipped') { 'skip' } elseif ($ok) { 'pass' } else { 'fail' }
            $msgs = @()
            if ($r.error) { $msgs += "Error: $($r.error)" }
            foreach ($f in $failed) {
                $label = if ($f.description) { $f.description } else { "$($f.lhsExpr) $($f.rhsExpr)" }
                $msgs += "$label -> $($f.error)"
            }
            [void]$rows.Append("<tr class='$cls'><td>$(Enc $r.test.filename)</td><td>$(Enc $r.request.method)</td><td>$(Enc $r.response.status)</td><td>$(Enc $r.response.responseTime)</td><td>$(($msgs | ForEach-Object { Enc $_ }) -join '<br>')</td></tr>`n")
        }
    }

    $pass = ($status -eq '0') -and ($reqFail -eq 0) -and ($tests -eq $testPass) -and ($asserts -eq $assertPass)
    $cls  = if ($pass) { 'pass' } else { 'fail' }
    $word = if ($pass) { 'PASS' } else { 'FAIL' }
    [void]$summaryRows.Append("<tr class='$cls'><td>$(Enc $envName)</td><td><a href='#$id'>$name</a></td>$timeCells<td>$reqPass / $req</td><td>$reqFail</td><td>$testPass / $tests</td><td>$assertPass / $asserts</td><td>$word</td><td><a href='$id.html'>Bruno report</a></td></tr>`n")
    [void]$detailHtml.Append("<h2 id='$id'>$name &mdash; $(Enc $envName) <span class='badge $cls'>$word</span></h2>`n<table><tr><th>Request</th><th>Method</th><th>Status</th><th>Time (ms)</th><th>Failures</th></tr>`n$rows</table>`n")

    $tot.Req += $req; $tot.ReqPass += $reqPass; $tot.ReqFail += $reqFail
    $tot.Tests += $tests; $tot.TestPass += $testPass; $tot.Asserts += $asserts; $tot.AssertPass += $assertPass
}

$generated   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$startedText = if ($firstStart) { $firstStart.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
$elapsed     = if ($firstStart) { FormatDuration ($lastEnd - $firstStart) } else { 'n/a' }
$html = @"
<!DOCTYPE html>
<html><head><meta charset='utf-8'><title>Bruno Test Summary</title>
<style>
 body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #222; }
 table { border-collapse: collapse; width: 100%; margin-bottom: 24px; font-size: 14px; }
 th, td { border: 1px solid #ccc; padding: 6px 8px; text-align: left; vertical-align: top; }
 th { background: #f0f0f0; }
 tr.pass td:first-child { border-left: 6px solid #2e7d32; }
 tr.fail td:first-child { border-left: 6px solid #c62828; }
 tr.fail { background: #fdecea; }
 tr.skip { color: #888; }
 .badge { font-size: 12px; padding: 2px 8px; border-radius: 10px; color: #fff; vertical-align: middle; }
 .badge.pass { background: #2e7d32; } .badge.fail { background: #c62828; }
 tfoot td { font-weight: bold; background: #fafafa; }
</style></head><body>
<h1>Bruno Test Summary</h1>
<p>Generated: $generated &nbsp;|&nbsp; Total elapsed: $elapsed</p>
<table>
<tr><th>Environment</th><th>Collection</th><th>Started</th><th>Duration</th><th>Requests passed</th><th>Requests failed</th><th>Tests passed</th><th>Assertions passed</th><th>Result</th><th>Details</th></tr>
$summaryRows
<tfoot><tr><td colspan='2'>Total</td><td>$startedText</td><td>$(FormatDuration $tot.Duration)</td><td>$($tot.ReqPass) / $($tot.Req)</td><td>$($tot.ReqFail)</td><td>$($tot.TestPass) / $($tot.Tests)</td><td>$($tot.AssertPass) / $($tot.Asserts)</td><td colspan='2'></td></tr></tfoot>
</table>
$detailHtml
</body></html>
"@
Set-Content -LiteralPath (Join-Path $ReportDir 'Summary.html') -Value $html -Encoding UTF8
Write-Host "Totals: requests $($tot.ReqPass)/$($tot.Req) passed, tests $($tot.TestPass)/$($tot.Tests), assertions $($tot.AssertPass)/$($tot.Asserts)"
