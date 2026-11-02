param([switch]$Latest)
$ErrorActionPreference = 'Stop'
if($Latest){ & python (Join-Path $PSScriptRoot 'tools\engine_updater.py') stage --engine all --latest }
else { & python (Join-Path $PSScriptRoot 'tools\engine_updater.py') stage --engine all }
exit $LASTEXITCODE
