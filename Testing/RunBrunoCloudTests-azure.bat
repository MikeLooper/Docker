@echo off
rem ===========================================================================
rem  RunBrunoCloudTests-azure.bat
rem
rem  Runs the Bruno test collections for the Pilot APIs (DotNet, Java, Python)
rem  against the six APIs deployed in the Azure cloud emulator, and writes a
rem  combined HTML report (plus per-run HTML/JSON/JUnit reports) to
rem  BrunoReports\<timestamp>_azure.
rem
rem    1. Starts the emulator : ..\Clouds\Docker-clouds-azure-start.bat
rem    2. Runs the tests      : Bruno environments "Azure - SQL Server" and
rem                             "Azure - PostgreSQL"
rem    3. Stops the emulator  : ..\Clouds\Docker-clouds-azure-stop.bat
rem
rem  Usage:
rem    RunBrunoCloudTests-azure.bat                   run all three collections
rem    RunBrunoCloudTests-azure.bat PilotApiJava      run one collection
rem    RunBrunoCloudTests-azure.bat -norebuild        do not re-run the dbapi builder
rem                                                when an API does not answer
rem
rem  The Azure APIs must have been deployed once with
rem  ..\Clouds\Docker-clouds-azure-dbapi-builder.bat. See scripts\RunBrunoCloudTests.bat.
rem ===========================================================================
call "%~dp0scripts\RunBrunoCloudTests.bat" azure %*
exit /b %errorlevel%