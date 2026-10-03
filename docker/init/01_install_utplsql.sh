#!/bin/bash
# Installs the utPLSQL testing framework into the application PDB on first start.
set -euo pipefail

version="${UTPLSQL_VERSION:-v.3.2.3}"
pdb="${TK_PDB:-FREEPDB1}"
work=/tmp/utplsql
url="https://github.com/utPLSQL/utPLSQL/releases/download/${version}/utPLSQL.tar.gz"

echo "Installing utPLSQL ${version} into ${pdb} ..."
mkdir -p "${work}"
cd "${work}"
curl -fsSL "${url}" -o utPLSQL.tar.gz
curl -fsSL "${url}.sha256" -o utPLSQL.tar.gz.sha256
line="$(tr -d '\r\n' < utPLSQL.tar.gz.sha256)"
# supports both "SHA256 (file) = <hash>" and "<hash>  file"
if [[ "${line}" == *"="* ]]; then expected="${line##* }"; else expected="${line%% *}"; fi
echo "${expected}  utPLSQL.tar.gz" | sha256sum -c -
tar -xzf utPLSQL.tar.gz

cd "${work}/utPLSQL/source"
# Definer-rights toolkit packages run DDL with EXECUTE IMMEDIATE, so these privileges must be
# granted directly (privileges received through roles are not visible inside such packages).
sqlplus -s -L "sys/${ORACLE_PASSWORD}@//localhost:1521/${pdb} as sysdba" <<SQL
whenever sqlerror exit failure
grant create table, create trigger, create procedure, create sequence, create view to toolkit;
exit
SQL

# install_headless.sql ends with EXIT, so it must be the last command of its session
sqlplus -s -L "sys/${ORACLE_PASSWORD}@//localhost:1521/${pdb} as sysdba" <<SQL
whenever sqlerror exit failure
set echo off feedback off heading off
@install_headless.sql ut3 ut3 users
SQL

cd /
rm -rf "${work}"
touch /tmp/toolkit_ready
echo "utPLSQL ${version} installed."
