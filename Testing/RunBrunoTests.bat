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
rem    3. Docker              (database-independent APIs, e.g. PythonAPIWithClaude)
rem
rem  Usage:
rem    RunBrunoTests.bat                            run everything
rem    RunBrunoTests.bat PostgreSQL                 run one environment (ShortTag:
rem                                                 PostgreSQL, SqlServer or Docker)
rem    RunBrunoTests.bat PostgreSQL PilotApiDotNet  run one collection in one
rem                                                 environment ("" = any environment)
rem
rem  Requires Node.js. Uses the Bruno CLI ("bru") if installed globally,
rem  otherwise runs it through npx (@usebruno/cli).
rem  Secrets (e.g. IDP_HOST_PASSWORD) are read by Bruno from the .env file in
rem  each collection folder.
rem ===========================================================================
setlocal EnableExtensions

set "FILTER_TAG=%~1"
set "FILTER_NAME=%~2"

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
if defined FILTER_TAG  echo Environment   : %FILTER_TAG%
if defined FILTER_NAME echo Collection    : %FILTER_NAME%
echo.

set "OVERALL=0"
set "RUN_COUNT=0"
call :RunEnvironment "Docker - PostgreSQL" "PostgreSQL"
call :RunEnvironment "Docker - SQL Server" "SqlServer"
call :RunStandalone   "Docker"              "Docker"

if "%RUN_COUNT%"=="0" (
    echo ERROR: No collections matched the requested filter(s).
    set "OVERALL=1"
)

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
if defined FILTER_TAG if /i not "%FILTER_TAG%"=="%~2" goto :eof
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
rem  :RunStandalone <BrunoEnvironmentName> <ShortTag>
rem  Collections that do not use a database; run once rather than per database.
rem ---------------------------------------------------------------------------
:RunStandalone
if defined FILTER_TAG if /i not "%FILTER_TAG%"=="%~2" goto :eof
set "BRU_ENV=%~1"
set "TAG=%~2"
echo ###########################################################################
echo  Environment: %BRU_ENV%
echo ###########################################################################
call :RunCollection "PythonAPIWithClaude" "%GITHUB_ROOT%\PythonAPIWithClaude\tests\Bruno\PythonAPIWithClaude"
goto :eof

rem ---------------------------------------------------------------------------
rem  :RunCollection <Name> <CollectionPath>   (uses BRU_ENV and TAG)
rem ---------------------------------------------------------------------------
:RunCollection
if defined FILTER_NAME if /i not "%FILTER_NAME%"=="%~1" goto :eof
set /a RUN_COUNT+=1
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
# Percentage rounded down to one decimal, so 99.96% never displays as 100%.
function Pct([int]$n, [int]$d) { [Math]::Floor(1000.0 * $n / $d) / 10 }

$svgPass = "<svg class='ico' viewBox='0 0 16 16' aria-hidden='true'><path d='M3.5 8.5l3 3 6-7' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/></svg>"
$svgFail = "<svg class='ico' viewBox='0 0 16 16' aria-hidden='true'><path d='M4.5 4.5l7 7M11.5 4.5l-7 7' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round'/></svg>"
$svgSkip = "<svg class='ico' viewBox='0 0 16 16' aria-hidden='true'><path d='M4 8h8' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round'/></svg>"
# Date over time, so the Started column stays narrow.
function StampCell([DateTime]$t) { "<td class='stamp'><span>$($t.ToString('yyyy-MM-dd'))</span><span class='time'>$($t.ToString('HH:mm:ss'))</span></td>" }
function Badge([string]$cls) {
    $icon = switch ($cls) { 'pass' { $svgPass } 'fail' { $svgFail } default { $svgSkip } }
    "<span class='badge $cls'>$icon$($cls.ToUpper())</span>"
}
function Kpi([string]$label, [string]$value, [string]$sub, [int]$n, [int]$d) {
    if ($d -eq 0) {
        $p = 'N/A'
        $cls = 'skip'
    } else {
        $p = '{0:0.#}%' -f (Pct $n $d)
        $cls = if ($n -eq $d) { 'pass' } else { 'fail' }
    }
    "<div class='kpi'><div class='kpi-label'>$label</div><div class='kpi-value'>$value</div><div class='kpi-foot'><span class='pill $cls'>$p</span><span class='kpi-sub'>$sub</span></div></div>"
}

$manifest = Join-Path $ReportDir 'runs.txt'
$runs = if (Test-Path $manifest) { @(Get-Content $manifest | Where-Object { $_.Trim() }) } else { @() }
$summaryRows = New-Object System.Text.StringBuilder
$detailHtml  = New-Object System.Text.StringBuilder
$tot = @{ Req = 0; ReqPass = 0; ReqFail = 0; Tests = 0; TestPass = 0; Asserts = 0; AssertPass = 0; Duration = [TimeSpan]::Zero; Coll = 0; CollPass = 0 }
$firstStart = $null; $lastEnd = $null

foreach ($line in $runs) {
    $tag, $envName, $name, $status, $startTs, $endTs = $line.Split(';') | ForEach-Object { $_.Trim() }
    $id       = "${name}_$tag"
    $jsonFile = Join-Path $ReportDir "$id.json"
    $tot.Coll++

    $started  = [DateTime]::Parse($startTs, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    $ended    = [DateTime]::Parse($endTs,   [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    $duration = $ended - $started
    $tot.Duration += $duration
    if (-not $firstStart -or $started -lt $firstStart) { $firstStart = $started }
    if (-not $lastEnd -or $ended -gt $lastEnd) { $lastEnd = $ended }
    $timeCells = "$(StampCell $started)<td class='num'>$(FormatDuration $duration)</td>"
    $collCell  = "<td><span class='env'>$(Enc $envName)</span></td>"

    if (-not (Test-Path $jsonFile)) {
        [void]$summaryRows.Append("<tr class='fail'>$collCell<td class='strong'>$name</td>$timeCells<td colspan='4' class='muted'>No results (exit/status: $(Enc $status))</td><td>$(Badge 'fail')</td><td></td></tr>`n")
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
            $checks = @(@($r.testResults) + @($r.assertionResults) | Where-Object { $_ })
            $failed = @($checks | Where-Object { $_.status -ne 'pass' })
            $ok = (-not $r.error) -and ($failed.Count -eq 0) -and ($r.status -ne 'error')
            $cls = if ($r.skipped -or $r.status -eq 'skipped') { 'skip' } elseif ($ok) { 'pass' } else { 'fail' }
            $msgs = @()
            if ($r.error) { $msgs += "Error: $($r.error)" }
            foreach ($f in $failed) {
                $label = if ($f.description) { $f.description } else { "$($f.lhsExpr) $($f.rhsExpr)" }
                $msgs += "$label -> $($f.error)"
            }
            $file   = [string]$r.test.filename
            $folder = Split-Path $file -Parent
            $leaf   = [IO.Path]::GetFileNameWithoutExtension($file)
            $reqCell = if ($folder) { "<span class='folder'>$(Enc $folder)</span><span class='leaf'>$(Enc $leaf)</span>" } else { "<span class='leaf'>$(Enc $leaf)</span>" }
            $failCell = if ($msgs) { "<div class='failures'>$(($msgs | ForEach-Object { Enc $_ }) -join '<br>')</div>" } else { "<span class='muted'>&mdash;</span>" }
            [void]$rows.Append("<tr class='$cls'><td>$reqCell</td><td><span class='method m-$(([string]$r.request.method).ToLower())'>$(Enc $r.request.method)</span></td><td class='num'>$(Enc $r.response.status)</td><td class='num'>$(Enc $r.response.responseTime)</td><td class='num'>$($checks.Count - $failed.Count) / $($checks.Count)</td><td>$failCell</td><td>$(Badge $cls)</td></tr>`n")
        }
    }

    $pass = ($status -eq '0') -and ($reqFail -eq 0) -and ($tests -eq $testPass) -and ($asserts -eq $assertPass)
    $cls  = if ($pass) { 'pass' } else { 'fail' }
    if ($pass) { $tot.CollPass++ }
    [void]$summaryRows.Append("<tr class='$cls'>$collCell<td class='strong'><a href='#$id'>$name</a></td>$timeCells<td class='num'>$reqPass / $req</td><td class='num'>$reqFail</td><td class='num'>$testPass / $tests</td><td class='num'>$assertPass / $asserts</td><td>$(Badge $cls)</td><td><a class='ext' href='$id.html'>Bruno report</a></td></tr>`n")
    [void]$detailHtml.Append(@"
<details class='card detail' id='$id' open>
<summary><span class='detail-title'><span class='detail-name'>$name</span><span class='env'>$(Enc $envName)</span></span><span class='detail-meta'><span class='muted'>$reqPass / $req requests &middot; $testPass / $tests tests &middot; $(FormatDuration $duration)</span>$(Badge $cls)</span></summary>
<div class='table-wrap'><table>
<thead><tr><th>Request</th><th>Method</th><th class='num'>Status</th><th class='num'>Time (ms)</th><th class='num'>Checks</th><th>Failures</th><th>Result</th></tr></thead>
<tbody>
$rows</tbody></table></div>
</details>

"@)

    $tot.Req += $req; $tot.ReqPass += $reqPass; $tot.ReqFail += $reqFail
    $tot.Tests += $tests; $tot.TestPass += $testPass; $tot.Asserts += $asserts; $tot.AssertPass += $assertPass
}

$generated   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$startedText = if ($firstStart) { $firstStart.ToString('yyyy-MM-dd HH:mm:ss') } else { 'n/a' }
$elapsed     = if ($firstStart) { FormatDuration ($lastEnd - $firstStart) } else { 'n/a' }
$allPass     = ($tot.Coll -gt 0) -and ($tot.CollPass -eq $tot.Coll)
$bannerCls   = if ($allPass) { 'pass' } else { 'fail' }
$bannerIcon  = if ($allPass) { $svgPass } else { $svgFail }
$bannerText  = if ($tot.Coll -eq 0) { 'No collections were run' } elseif ($allPass) { "All $($tot.Coll) collection(s) passed" } else { "$($tot.Coll - $tot.CollPass) of $($tot.Coll) collection(s) failed" }
$kpis = (Kpi 'Collections' "$($tot.CollPass)<span class='of'>/ $($tot.Coll)</span>" 'passed' $tot.CollPass $tot.Coll) +
        (Kpi 'Requests' "$($tot.ReqPass)<span class='of'>/ $($tot.Req)</span>" "$($tot.ReqFail) failed" $tot.ReqPass $tot.Req) +
        (Kpi 'Tests' "$($tot.TestPass)<span class='of'>/ $($tot.Tests)</span>" "$($tot.Tests - $tot.TestPass) failed" $tot.TestPass $tot.Tests) +
        (Kpi 'Assertions' "$($tot.AssertPass)<span class='of'>/ $($tot.Asserts)</span>" "$($tot.Asserts - $tot.AssertPass) failed" $tot.AssertPass $tot.Asserts)
$html = @"
<!DOCTYPE html>
<html lang='en'><head><meta charset='utf-8'>
<meta name='viewport' content='width=device-width, initial-scale=1'>
<title>Bruno Test Summary</title>
<link rel='preconnect' href='https://fonts.googleapis.com'>
<link rel='preconnect' href='https://fonts.gstatic.com' crossorigin>
<link href='https://fonts.googleapis.com/css2?family=DM+Sans:opsz,wght@9..40,400;9..40,500;9..40,600;9..40,700&family=Playfair+Display:wght@600;700&display=swap' rel='stylesheet'>
<style>
 :root {
  --primary: #1b2638;          /* deep slate */
  --secondary: #46546b;
  --accent: #c8862a;           /* burnished amber */
  --bg-main: #f6f5f1;
  --surface: #ffffff;
  --text: #1b2638;
  --text-muted: #6b7587;
  --border-color: rgba(27, 38, 56, 0.08);
  --tint: rgba(27, 38, 56, 0.025);
  --tint-hover: rgba(27, 38, 56, 0.055);
  --success: #157347; --success-bg: #e3f4ea;
  --danger: #b4232c;  --danger-bg: #fbe7e8;
  --neutral: #6b7587; --neutral-bg: #eceef2;
  --radius: 8px;
  --shadow: 0 4px 20px -2px rgba(0, 0, 0, 0.03);
  --font-display: 'Playfair Display', Georgia, 'Times New Roman', serif;
  --font-body: 'DM Sans', 'Segoe UI Variable Text', system-ui, sans-serif;
  --font-mono: ui-monospace, 'Cascadia Code', Consolas, monospace;
 }
 *, *::before, *::after { box-sizing: border-box; }
 html { -webkit-text-size-adjust: 100%; }
 body { margin: 0; background: var(--bg-main); color: var(--text); font-family: var(--font-body); font-size: 15px; line-height: 1.6; font-variant-numeric: tabular-nums; }
 .container { max-width: 1100px; margin: 0 auto; padding: 2rem; }
 a { color: var(--primary); text-decoration: none; border-bottom: 1px solid rgba(200, 134, 42, 0.45); }
 a:hover { color: var(--accent); border-bottom-color: var(--accent); }
 h1, h2 { font-family: var(--font-display); line-height: 1.2; letter-spacing: 0.01em; margin: 0; }
 h1 { font-size: clamp(2.1rem, 5vw, 3rem); font-weight: 700; }
 h2 { font-size: 1.6rem; font-weight: 600; }
 .eyebrow { font-size: 0.72rem; font-weight: 600; letter-spacing: 0.16em; text-transform: uppercase; color: var(--accent); margin-bottom: 0.75rem; }
 .muted { color: var(--text-muted); }
 .rule { display: block; width: 72px; height: 8px; margin: 1.25rem 0 1.5rem; color: var(--accent); }

 /* Masthead */
 .masthead { padding: 3rem 0 2.5rem; border-bottom: 1px solid var(--border-color); }
 .masthead-row { display: flex; flex-wrap: wrap; align-items: flex-end; justify-content: space-between; gap: 1.5rem; }
 .meta { display: flex; flex-wrap: wrap; gap: 0.5rem 2rem; margin: 0; }
 .meta div { display: flex; flex-direction: column; }
 .meta dt { font-size: 0.7rem; font-weight: 600; letter-spacing: 0.12em; text-transform: uppercase; color: var(--text-muted); }
 .meta dd { margin: 0; font-weight: 500; }
 .banner { display: inline-flex; align-items: center; gap: 0.6rem; padding: 0.6rem 1.1rem 0.6rem 0.8rem; border-radius: 999px; font-weight: 600; font-size: 0.95rem; }
 .banner .ico { width: 20px; height: 20px; padding: 3px; border-radius: 50%; background: currentColor; }
 .banner .ico path { stroke: #fff; }
 .banner.pass { background: var(--success-bg); color: var(--success); }
 .banner.fail { background: var(--danger-bg); color: var(--danger); }

 /* Sections */
 section { padding: 3rem 0 0; }
 .section-head { display: flex; align-items: baseline; justify-content: space-between; gap: 1rem; margin-bottom: 1.25rem; }
 .section-head p { margin: 0; color: var(--text-muted); font-size: 0.9rem; }
 .card { background: var(--surface); border: 1px solid var(--border-color); border-radius: var(--radius); box-shadow: var(--shadow); }

 /* KPIs */
 .kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(210px, 1fr)); gap: 1rem; }
 .kpi { background: var(--surface); border: 1px solid var(--border-color); border-radius: var(--radius); box-shadow: var(--shadow); padding: 1.5rem 1.5rem 1.25rem; border-top: 3px solid var(--primary); }
 .kpi-label { font-size: 0.72rem; font-weight: 600; letter-spacing: 0.14em; text-transform: uppercase; color: var(--text-muted); }
 .kpi-value { font-size: 2.75rem; font-weight: 700; line-height: 1.1; letter-spacing: -0.02em; margin: 0.4rem 0 0.75rem; color: var(--primary); }
 .kpi-value .of { font-size: 1.1rem; font-weight: 500; color: var(--text-muted); margin-left: 0.3rem; letter-spacing: 0; }
 .kpi-foot { display: flex; align-items: center; gap: 0.6rem; font-size: 0.85rem; }
 .kpi-sub { color: var(--text-muted); }
 .pill { display: inline-block; padding: 0.1rem 0.55rem; border-radius: 999px; font-size: 0.75rem; font-weight: 700; letter-spacing: 0.02em; }
 .pill.pass { background: var(--success-bg); color: var(--success); }
 .pill.fail { background: var(--danger-bg); color: var(--danger); }
 .pill.skip { background: var(--neutral-bg); color: var(--neutral); }

 /* Tables */
 .table-wrap { overflow-x: auto; -webkit-overflow-scrolling: touch; }
 table { width: 100%; border-collapse: collapse; font-size: 0.875rem; }
 th, td { padding: 12px 16px; text-align: left; vertical-align: top; border-bottom: 1px solid var(--border-color); }
 thead th { font-size: 0.7rem; font-weight: 600; letter-spacing: 0.12em; text-transform: uppercase; color: var(--text-muted); white-space: nowrap; background: var(--surface); }
 tbody tr:nth-child(even) { background: var(--tint); }
 tbody tr:hover { background: var(--tint-hover); }
 tbody tr:last-child td { border-bottom: none; }
 tbody tr.fail { background: var(--danger-bg); }
 tbody tr.fail td:first-child { box-shadow: inset 3px 0 0 var(--danger); }
 tbody tr.skip { color: var(--text-muted); }
 tfoot td { font-weight: 700; border-top: 2px solid var(--primary); border-bottom: none; background: var(--surface); }
 .num { text-align: right; white-space: nowrap; }
 .nowrap { white-space: nowrap; }
 .strong { font-weight: 600; }
 .stamp { white-space: nowrap; }
 .stamp span { display: block; }
 .stamp .time { font-size: 0.8rem; color: var(--text-muted); }
 tfoot .stamp .time { font-weight: 500; }
 /* Collections table: tighter cells so all ten columns fit the container width */
 .collections th, .collections td { padding: 12px 10px; }
 .collections th:first-child, .collections td:first-child { padding-left: 16px; }
 .collections th:last-child, .collections td:last-child { padding-right: 16px; }
 .collections thead th { letter-spacing: 0.06em; }
 .env { display: inline-block; font-size: 0.75rem; font-weight: 500; color: var(--secondary); background: var(--neutral-bg); padding: 0.1rem 0.5rem; border-radius: 4px; white-space: nowrap; }
 .folder { display: block; font-size: 0.72rem; color: var(--text-muted); letter-spacing: 0.02em; }
 .leaf { font-weight: 500; }
 .method { font-family: var(--font-mono); font-size: 0.72rem; font-weight: 600; padding: 0.1rem 0.4rem; border-radius: 4px; background: var(--neutral-bg); color: var(--secondary); }
 .m-get { background: #e6eefb; color: #24508f; }
 .m-post { background: #e3f4ea; color: #157347; }
 .m-put, .m-patch { background: #fbf0dd; color: #8a5a12; }
 .m-delete { background: #fbe7e8; color: #b4232c; }
 .failures { font-family: var(--font-mono); font-size: 0.78rem; color: var(--danger); line-height: 1.5; word-break: break-word; }
 a.ext { white-space: nowrap; }

 /* Badges */
 .badge { display: inline-flex; align-items: center; gap: 0.3rem; font-size: 0.68rem; font-weight: 700; letter-spacing: 0.08em; padding: 0.15rem 0.55rem 0.15rem 0.4rem; border-radius: 999px; white-space: nowrap; }
 .badge .ico { width: 12px; height: 12px; }
 .badge.pass { background: var(--success-bg); color: var(--success); }
 .badge.fail { background: var(--danger-bg); color: var(--danger); }
 .badge.skip { background: var(--neutral-bg); color: var(--neutral); }

 /* Request details */
 .detail { margin-bottom: 1.25rem; overflow: hidden; scroll-margin-top: 1rem; }
 .detail > summary { list-style: none; cursor: pointer; display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 0.75rem; padding: 1.1rem 1.5rem; border-bottom: 1px solid var(--border-color); }
 .detail > summary::-webkit-details-marker { display: none; }
 .detail > summary::before { content: ''; width: 8px; height: 8px; border-right: 2px solid var(--text-muted); border-bottom: 2px solid var(--text-muted); transform: rotate(-45deg); transition: transform 0.15s ease; margin-right: 0.25rem; }
 .detail[open] > summary::before { transform: rotate(45deg); }
 .detail:not([open]) > summary { border-bottom: none; }
 .detail-title { flex: 1; display: flex; flex-wrap: wrap; align-items: center; gap: 0.75rem; }
 .detail-name { font-family: var(--font-display); font-size: 1.2rem; font-weight: 600; line-height: 1.2; }
 .detail-meta { display: flex; flex-wrap: wrap; align-items: center; gap: 0.75rem; font-size: 0.85rem; }

 footer { padding: 3rem 0 1rem; font-size: 0.8rem; color: var(--text-muted); }

 @media (max-width: 640px) {
  .container { padding: 1rem; }
  .masthead { padding: 2rem 0 1.75rem; }
  section { padding-top: 2rem; }
  .section-head { flex-direction: column; gap: 0.25rem; }
  th, td { padding: 10px 12px; }
  .kpi-value { font-size: 2.25rem; }
  .detail > summary { padding: 1rem; }
 }
 @media print {
  body { background: #fff; }
  .card, .kpi { box-shadow: none; }
  .detail { break-inside: avoid-page; }
 }
</style></head><body>
<div class='container'>
<header class='masthead'>
 <div class='eyebrow'>Docker Applications &middot; Automated API Tests</div>
 <h1>Bruno Test Summary</h1>
 <svg class='rule' viewBox='0 0 72 8' aria-hidden='true'><line x1='0' y1='4' x2='56' y2='4' stroke='currentColor' stroke-width='2'/><circle cx='66' cy='4' r='3' fill='currentColor'/></svg>
 <div class='masthead-row'>
  <dl class='meta'>
   <div><dt>Generated</dt><dd>$generated</dd></div>
   <div><dt>Run started</dt><dd>$startedText</dd></div>
   <div><dt>Total elapsed</dt><dd>$elapsed</dd></div>
  </dl>
  <div class='banner $bannerCls'>$bannerIcon$bannerText</div>
 </div>
</header>

<section>
 <div class='section-head'><h2>At a glance</h2><p>Pass rate across all collections in this run</p></div>
 <div class='kpis'>$kpis</div>
</section>

<section>
 <div class='section-head'><h2>Collections</h2><p>Select a collection to jump to its requests</p></div>
 <div class='card table-wrap'><table class='collections'>
 <thead><tr><th>Environment</th><th>Collection</th><th>Started</th><th class='num'>Duration</th><th class='num'>Requests</th><th class='num'>Failed</th><th class='num'>Tests</th><th class='num'>Assertions</th><th>Result</th><th>Details</th></tr></thead>
 <tbody>
$summaryRows </tbody>
 <tfoot><tr><td colspan='2'>Total</td>$(if ($firstStart) { StampCell $firstStart } else { '<td></td>' })<td class='num'>$(FormatDuration $tot.Duration)</td><td class='num'>$($tot.ReqPass) / $($tot.Req)</td><td class='num'>$($tot.ReqFail)</td><td class='num'>$($tot.TestPass) / $($tot.Tests)</td><td class='num'>$($tot.AssertPass) / $($tot.Asserts)</td><td colspan='2'></td></tr></tfoot>
 </table></div>
</section>

<section>
 <div class='section-head'><h2>Request details</h2><p>Checks = tests and assertions passed per request</p></div>
$detailHtml</section>

<footer>Generated by RunBrunoTests.bat &middot; Per-collection HTML, JSON and JUnit reports are in this folder.</footer>
</div>
</body></html>
"@
Set-Content -LiteralPath (Join-Path $ReportDir 'Summary.html') -Value $html -Encoding UTF8
Write-Host "Totals: requests $($tot.ReqPass)/$($tot.Req) passed, tests $($tot.TestPass)/$($tot.Tests), assertions $($tot.AssertPass)/$($tot.Asserts)"
