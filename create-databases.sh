#!/bin/bash
set -euo pipefail

SQLCMD="/opt/mssql-tools18/bin/sqlcmd"
HOST="sqlserver"

IFS=',' read -ra DBS <<< "${DATABASES_TO_CREATE}"

for db in "${DBS[@]}"; do
  db_trimmed=$(echo "$db" | xargs)
  login_name="$(echo "$db_trimmed" | tr '[:upper:]' '[:lower:]')_svc"

  echo ">> Ensuring database exists: $db_trimmed"
  "$SQLCMD" -S "$HOST" -U sa -P "$MSSQL_SA_PASSWORD" -C -Q \
    "IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'$db_trimmed') CREATE DATABASE [$db_trimmed];"

  echo ">> Ensuring dedicated login exists: $login_name"
  "$SQLCMD" -S "$HOST" -U sa -P "$MSSQL_SA_PASSWORD" -C -Q \
    "IF NOT EXISTS (SELECT name FROM sys.server_principals WHERE name = N'$login_name')
       CREATE LOGIN [$login_name] WITH PASSWORD = N'$SERVICE_DB_PASSWORD', CHECK_POLICY = OFF;
     ALTER LOGIN [$login_name] WITH PASSWORD = N'$SERVICE_DB_PASSWORD', CHECK_POLICY = OFF;"

  echo ">> Ensuring user + least-privilege roles inside $db_trimmed for $login_name"
  "$SQLCMD" -S "$HOST" -U sa -P "$MSSQL_SA_PASSWORD" -C -d "$db_trimmed" -Q \
    "IF NOT EXISTS (SELECT name FROM sys.database_principals WHERE name = N'$login_name')
       CREATE USER [$login_name] FOR LOGIN [$login_name];
     ALTER ROLE db_datareader ADD MEMBER [$login_name];
     ALTER ROLE db_datawriter ADD MEMBER [$login_name];
     ALTER ROLE db_ddladmin  ADD MEMBER [$login_name];"
done

echo ">> Done. Databases + dedicated logins ready: ${DATABASES_TO_CREATE}"
