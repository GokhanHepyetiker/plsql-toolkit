# Usage: .\scripts\tk.ps1 [install|test|examples|uninstall]
# Runs the SQL scripts with SQL*Plus inside the docker-compose database container.
param([ValidateSet('install', 'test', 'examples', 'uninstall')][string]$Command = 'test')

$ErrorActionPreference = 'Continue'
Set-Location (Join-Path $PSScriptRoot '..')

function Invoke-Sql([string]$Script) {
    $output = docker compose exec -T oracle bash -c "cd /workspace && sqlplus -s -L toolkit/toolkit@//localhost:1521/`$TK_PDB @$Script </dev/null" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "$Script failed with exit code $LASTEXITCODE"
    }
    return $output
}

switch ($Command) {
    'install'   { Invoke-Sql 'install.sql' | Write-Host }
    'uninstall' { Invoke-Sql 'uninstall.sql' | Write-Host }
    'examples' {
        Get-ChildItem examples\*.sql | Sort-Object Name | ForEach-Object {
            Write-Host "----- $($_.Name) -----"
            Invoke-Sql "examples/$($_.Name)" | Write-Host
        }
    }
    'test' {
        Invoke-Sql 'install.sql' | Write-Host
        Invoke-Sql 'test/install_tests.sql' | Write-Host
        $output = Invoke-Sql 'test/run_tests.sql'
        Write-Host $output
        # utPLSQL does not set an exit code: check the summary line
        if ($output -notmatch '(?m)^\d+ tests?, 0 failed, 0 errored') {
            throw 'Tests failed'
        }
    }
}
