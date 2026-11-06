@echo off
rem ===========================================================================
rem  RunBrunoCloudTests-aws.bat
rem
rem  Runs the Bruno test collections for the Pilot APIs (DotNet, Java, Python)
rem  against the six APIs deployed in the AWS cloud emulator, and writes a
rem  combined HTML report (plus per-run HTML/JSON/JUnit reports) to
rem  BrunoReports\<timestamp>_aws.
rem
rem    1. Starts the emulator : ..\Clouds\Docker-clouds-aws-start.bat
rem    2. Runs the tests      : Bruno environments "AWS - SQL Server" and
rem                             "AWS - PostgreSQL"
rem    3. Stops the emulator  : ..\Clouds\Docker-clouds-aws-stop.bat
rem
rem  Usage:
rem    RunBrunoCloudTests-aws.bat                   run all three collections
rem    RunBrunoCloudTests-aws.bat PilotApiJava      run one collection
rem    RunBrunoCloudTests-aws.bat -norebuild        do not re-run the dbapi builder
rem                                                when an API does not answer
rem
rem  The AWS APIs must have been deployed once with
rem  ..\Clouds\Docker-clouds-aws-dbapi-builder.bat. See scripts\RunBrunoCloudTests.bat.
rem ===========================================================================
call "%~dp0scripts\RunBrunoCloudTests.bat" aws %*
exit /b %errorlevel%