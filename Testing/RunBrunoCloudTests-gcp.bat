@echo off
rem ===========================================================================
rem  RunBrunoCloudTests-gcp.bat
rem
rem  Runs the Bruno test collections for the Pilot APIs (DotNet, Java, Python)
rem  against the six APIs deployed in the GCP cloud emulator, and writes a
rem  combined HTML report (plus per-run HTML/JSON/JUnit reports) to
rem  BrunoReports\<timestamp>_gcp.
rem
rem    1. Starts the emulator : ..\Clouds\Docker-clouds-gcp-start.bat
rem    2. Runs the tests      : Bruno environments "GCP - SQL Server" and
rem                             "GCP - PostgreSQL"
rem    3. Stops the emulator  : ..\Clouds\Docker-clouds-gcp-stop.bat
rem
rem  Usage:
rem    RunBrunoCloudTests-gcp.bat                   run all three collections
rem    RunBrunoCloudTests-gcp.bat PilotApiJava      run one collection
rem    RunBrunoCloudTests-gcp.bat -norebuild        do not re-run the dbapi builder
rem                                                when an API does not answer
rem
rem  The GCP APIs must have been deployed once with
rem  ..\Clouds\Docker-clouds-gcp-dbapi-builder.bat. See scripts\RunBrunoCloudTests.bat.
rem ===========================================================================
call "%~dp0scripts\RunBrunoCloudTests.bat" gcp %*
exit /b %errorlevel%