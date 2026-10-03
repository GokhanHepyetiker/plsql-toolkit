#!/usr/bin/env bash
# Usage: scripts/tk.sh [install|test|examples|uninstall]
# Runs the SQL scripts with SQL*Plus inside the docker-compose database container.
set -euo pipefail
cd "$(dirname "$0")/.."

run_sql() {
  docker compose exec -T oracle bash -c \
    'cd /workspace && sqlplus -s -L "toolkit/toolkit@//localhost:1521/${TK_PDB}" @'"$1"' </dev/null'
}

case "${1:-test}" in
  install)
    run_sql install.sql
    ;;
  uninstall)
    run_sql uninstall.sql
    ;;
  examples)
    for f in examples/*.sql; do
      echo "----- ${f} -----"
      run_sql "${f}"
    done
    ;;
  test)
    run_sql install.sql
    run_sql test/install_tests.sql
    output="$(run_sql test/run_tests.sql)"
    echo "${output}"
    # utPLSQL does not set an exit code: check the summary line
    echo "${output}" | grep -Eq '^[0-9]+ tests?, 0 failed, 0 errored' || { echo "Tests failed" >&2; exit 1; }
    ;;
  *)
    echo "Usage: $0 [install|test|examples|uninstall]" >&2
    exit 2
    ;;
esac
