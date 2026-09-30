# Secrets Directory

This folder contains local-only runtime secrets used by batch scripts.

## Files expected by scripts

For each of the following files, there is a related template file that is named the same with `.example` appended.

- `secrets/api-java.env`
- `secrets/appsettings-api-dotnet-postgresql.env`
- `secrets/appsettings-api-dotnet-sqlserver.env`
- `secrets/appsettings-api-python-postgresql.env`
- `secrets/appsettings-api-python-sqlserver.env`
- `secrets/appsettings-utility-dotnet-postgresql.env`
- `secrets/appsettings-utility-dotnet-sqlserver.env`
- `secrets/ms-dab.env`
- `secrets/postgresql.env`
- `secrets/sqlserver.env`

Create each file from its `.example` template and replace placeholders before running scripts.

## Notes

- Do not commit real secrets.
- `.env` files are ignored by git via `.gitignore`.
- Keep keys in `KEY=value` format, one per line.
- Lines starting with `#` are treated as comments.
