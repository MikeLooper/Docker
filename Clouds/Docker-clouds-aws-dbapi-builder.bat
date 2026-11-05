@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM Docker - Setup - Clouds - AWS databases and APIs (Terraform)
REM Usage: Docker-clouds-aws-dbapi-builder.bat [-destroy]
REM   RDS (SQL Server + PostgreSQL) loaded with Northwind, and the 6 APIs on
REM   ECS Fargate behind API Gateway HTTP APIs (v2). See docs\CloudEmulatorsDbAndApi.md.

pushd "%~dp0"

set "CLOUD=aws"
set "COMMON=%~dp0scripts\dbapi-common.bat"
set "REGISTRY=000000000000.dkr.ecr.us-east-1.amazonaws.com"

set "DESTROY="
if /I "%~1"=="-destroy" set "DESTROY=1"
if not "%~1"=="" if not defined DESTROY (
	echo Usage: Docker-clouds-aws-dbapi-builder.bat [-destroy]
	goto failed
)

docker info >nul 2>&1
if errorlevel 1 (
	echo Docker is not running or not available.
	goto failed
)

REM 0. Load and validate secrets\clouds-db.env.
call "%COMMON%" :load_secrets || goto failed

REM 1. Platform and running services.
if defined DESTROY goto destroy
call "%COMMON%" :check_platform %CLOUD% || goto failed
call "%COMMON%" :check_running %CLOUD% || goto failed

REM 2. The API images must exist.
call "%COMMON%" :check_images || goto failed

REM 3. Terraform image.
docker pull -q hashicorp/terraform:latest || goto failed

REM 4. Databases (RDS).
call "%COMMON%" :tf_apply %CLOUD% 10-databases || goto failed

REM 5. Endpoints.
call "%COMMON%" :tf_output %CLOUD% 10-databases mssql_host MSSQL_HOST || goto failed
call "%COMMON%" :tf_output %CLOUD% 10-databases mssql_port MSSQL_PORT || goto failed
call "%COMMON%" :tf_output %CLOUD% 10-databases postgres_host POSTGRES_HOST || goto failed
call "%COMMON%" :tf_output %CLOUD% 10-databases postgres_port POSTGRES_PORT || goto failed
echo SQL Server: %MSSQL_HOST%:%MSSQL_PORT%   PostgreSQL: %POSTGRES_HOST%:%POSTGRES_PORT%

REM 6. Load Northwind.
call "%~dp0scripts\load-mssql.bat" %MSSQL_HOST% %MSSQL_PORT% managed || goto failed
call "%~dp0scripts\load-postgres.bat" %POSTGRES_HOST% %POSTGRES_PORT% managed || goto failed

REM 7. ECR-shaped image tags. No push: Floci runs the local image when the pull fails.
for /f "usebackq tokens=*" %%N in (`powershell -NoProfile -Command "(Get-Content '%~dp0terraform\apis.json' -Raw | ConvertFrom-Json).name"`) do (
	docker tag "%%N:1.0" "%REGISTRY%/%%N:1.0" || goto failed
)

REM 8. APIs (ECS + API Gateway).
call "%COMMON%" :tf_apply %CLOUD% 20-apis || goto failed

REM 9. Health checks and the authenticated data probe.
call "%COMMON%" :verify_apis %CLOUD% 20-apis || goto failed

popd

REM 10. Open the health checks in the browser.
call "%COMMON%" :open_healthchecks %CLOUD%
goto :eof

:destroy
call "%COMMON%" :is_running local-%CLOUD% || (
	echo local-%CLOUD% must be running to destroy its resources.
	goto failed
)
set "DESTROY_FAILED="
call "%COMMON%" :tf_destroy %CLOUD% 20-apis || set "DESTROY_FAILED=1"
call "%COMMON%" :tf_destroy %CLOUD% 10-databases || call :forget_network || set "DESTROY_FAILED=1"
call "%COMMON%" :remove_leftovers floci-aws-ecs- floci-aws-rds-
popd
if defined DESTROY_FAILED exit /b 1
echo AWS databases and APIs destroyed.
goto :eof

:failed
popd
exit /b 1

REM ---------------------------------------------------------------------------
REM :forget_network
REM   Floci can leave the ENIs of pre-restart ECS tasks behind (in use, not
REM   deletable), which blocks deleting the subnets and VPC. When only those are
REM   left in 10-databases, drop them from the state; the next apply creates a
REM   new network (20-apis reads the VPC from 10-databases, not by tag).
REM ---------------------------------------------------------------------------
:forget_network
set "FN_FILE=%TEMP%\cloud-aws-state-%RANDOM%.txt"
call "%COMMON%" :tf %CLOUD% 10-databases "state list -no-color" > "%FN_FILE%" 2>nul
findstr /V /B /C:"aws_subnet." /C:"aws_vpc." "%FN_FILE%" | findstr /R "." >nul
if not errorlevel 1 (
	del /Q "%FN_FILE%" >nul 2>&1
	exit /b 1
)
echo WARNING: Floci left ECS network interfaces in the VPC (seen after a local-aws restart).
echo          Removing the VPC and subnets from the Terraform state only.
for /f "usebackq tokens=*" %%R in ("%FN_FILE%") do call "%COMMON%" :tf %CLOUD% 10-databases "state rm -no-color %%R" >nul
del /Q "%FN_FILE%" >nul 2>&1
exit /b 0
