param(
  [string]$CsvPath = "$env:USERPROFILE\Downloads\Kavak Listado Total - Con formulas (3).csv",
  [int]$Port = 8787
)

$ErrorActionPreference = "Stop"

$server = Join-Path $PSScriptRoot "api\server.ps1"
if (-not (Test-Path -LiteralPath $server)) {
  throw "No se encontro api\server.ps1"
}

Write-Host ""
Write-Host "Kavak Seguros - Entregable 4"
Write-Host "Dashboard: http://localhost:$Port/"
Write-Host "Slides:    http://localhost:$Port/presentacion"
Write-Host ""
Write-Host "Para cerrar el servidor: Ctrl+C"
Write-Host ""

& $server -CsvPath $CsvPath -Port $Port
