$ErrorActionPreference = 'Stop'
& python (Join-Path $PSScriptRoot 'tools\engine_updater.py') check
exit $LASTEXITCODE
