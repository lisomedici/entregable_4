param(
  [string]$CsvPath = "$env:USERPROFILE\Downloads\Kavak Listado Total - Con formulas (3).csv",
  [string]$OutPath = "$PSScriptRoot\..\dashboard\demo-data.js",
  [int]$MaxPolicies = 1500
)

$ErrorActionPreference = "Stop"

function Txt($Value, [string]$Default = "Sin dato") {
  if ($null -eq $Value) { return $Default }
  $s = "$Value".Trim()
  if ($s -eq "" -or $s.ToLower() -eq "empty") { return $Default }
  return $s
}

function Num($Value) {
  if ($null -eq $Value) { return $null }
  $s = "$Value".Trim()
  if ($s -eq "" -or $s -eq "Revisar") { return $null }
  $s = $s -replace "\$", "" -replace "\s", "" -replace ",", "."
  $d = 0.0
  if ([double]::TryParse($s, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
    return [double]$d
  }
  return $null
}

function Region($Provincia) {
  $p = Txt $Provincia
  if ($p -eq "Buenos Aires") { return "GBA" }
  if ($p -eq "Capital Federal") { return "CABA" }
  return "Interior"
}

function Money($Value) {
  if ($null -eq $Value) { return "" }
  return ([math]::Round([double]$Value, 0)).ToString("N0", [System.Globalization.CultureInfo]::GetCultureInfo("es-AR"))
}

function Clamp([double]$Value, [double]$Min, [double]$Max) {
  if ($Value -lt $Min) { return $Min }
  if ($Value -gt $Max) { return $Max }
  return $Value
}

function Quantile($Values, [double]$Q) {
  $arr = @($Values | Where-Object { $null -ne $_ } | Sort-Object)
  if ($arr.Count -eq 0) { return $null }
  return [double]$arr[[math]::Floor(($arr.Count - 1) * $Q)]
}

function Add-Reason($Reasons, [string]$Label, [string]$Text, [double]$Impact) {
  if ($Impact -gt 0.012) {
    $Reasons.Add([pscustomobject]@{
      label = $Label
      text = $Text
      impact = [math]::Round($Impact, 3)
    }) | Out-Null
  }
}

function Build-RateTables($Rows, [double]$BaseRate, [int]$Prior = 80) {
  $features = @("Aseguradora", "Cluster_Detalle", "Metodo_de_pago", "provincia", "rango_comision")
  $tables = @{}
  foreach ($feature in $features) {
    $bucket = @{}
    foreach ($r in $Rows) {
      $key = Txt $r.$feature
      if (-not $bucket.ContainsKey($key)) {
        $bucket[$key] = [pscustomobject]@{ n = 0; churn = 0 }
      }
      $bucket[$key].n += 1
      $mpc = Num $r.'meses pre churn'
      if (($r.Estado_poliza -in @("canceled", "expired")) -and $null -ne $mpc -and $mpc -le 3) {
        $bucket[$key].churn += 1
      }
    }

    $table = @{}
    foreach ($key in $bucket.Keys) {
      $n = [double]$bucket[$key].n
      $churn = [double]$bucket[$key].churn
      $table[$key] = [pscustomobject]@{
        n = [int]$n
        churn = [int]$churn
        rate = [math]::Round((($churn + ($BaseRate * $Prior)) / ($n + $Prior)), 4)
      }
    }
    $tables[$feature] = $table
  }
  return $tables
}

function Rate-Delta($Tables, [string]$Feature, $Value, [double]$BaseRate, [double]$Weight, [double]$Min, [double]$Max) {
  $key = Txt $Value
  if (-not $Tables.ContainsKey($Feature) -or -not $Tables[$Feature].ContainsKey($key)) { return 0.0 }
  return Clamp (([double]$Tables[$Feature][$key].rate - $BaseRate) * $Weight) $Min $Max
}

function Score-Policy($Row, $Tables, [double]$BaseRate, $Q) {
  $reasons = New-Object System.Collections.Generic.List[object]
  $score = $BaseRate

  $insurerDelta = Rate-Delta $Tables "Aseguradora" $Row.Aseguradora $BaseRate 0.85 -0.07 0.11
  $clusterDelta = Rate-Delta $Tables "Cluster_Detalle" $Row.Cluster_Detalle $BaseRate 0.55 -0.05 0.08
  $paymentDelta = Rate-Delta $Tables "Metodo_de_pago" $Row.Metodo_de_pago $BaseRate 0.45 -0.04 0.06
  $provinceDelta = Rate-Delta $Tables "provincia" $Row.provincia $BaseRate 0.25 -0.03 0.04
  $commissionRangeDelta = Rate-Delta $Tables "rango_comision" $Row.rango_comision $BaseRate 0.30 -0.03 0.04

  $score += $insurerDelta + $clusterDelta + $paymentDelta + $provinceDelta + $commissionRangeDelta
  Add-Reason $reasons "aseguradora" "Aseguradora con churn historico sobre promedio" $insurerDelta
  Add-Reason $reasons "cobertura" "Cobertura/cluster con mayor churn historico" $clusterDelta
  Add-Reason $reasons "pago" "Metodo de pago con mayor riesgo observado" $paymentDelta
  Add-Reason $reasons "region" "Provincia con churn historico sobre promedio" $provinceDelta
  Add-Reason $reasons "comision" "Rango de comision con mayor riesgo observado" $commissionRangeDelta

  $cuota = Num $Row.Valor_cuota_mes_pesos
  if ($null -ne $cuota) {
    if ($cuota -ge $Q.cuota_p90) {
      $score += 0.075
      Add-Reason $reasons "cuota" "Cuota mensual en percentil alto" 0.075
    } elseif ($cuota -ge $Q.cuota_p75) {
      $score += 0.045
      Add-Reason $reasons "cuota" "Cuota mensual sobre el promedio" 0.045
    } elseif ($cuota -le $Q.cuota_p25) {
      $score -= 0.025
    }
  }

  $comision = Num $Row.Comision_pesos
  if ($null -ne $comision -and $comision -ge $Q.comision_p80) {
    $score += 0.025
    Add-Reason $reasons "comision" "Comision alta" 0.025
  }

  $valor = Num $Row.Valor_asegurado_pesos
  if ($null -ne $valor -and $valor -ge $Q.valor_p85) {
    $score += 0.018
    Add-Reason $reasons "valor_asegurado" "Valor asegurado alto" 0.018
  }

  $renovacion = Num $Row.Es_renovacion_ID_poliza_anterior
  if ($null -eq $renovacion -or $renovacion -le 0) {
    $score += 0.045
  } else {
    $score -= 0.070
  }

  $anio = Num $Row.anio_bien
  if ($null -ne $anio -and (2026 - [int]$anio) -ge 8) {
    $score += 0.028
    Add-Reason $reasons "vehiculo" "Vehiculo con mayor antiguedad" 0.028
  }

  if ((Txt $Row.GNC "").ToLower() -eq "true") {
    $score += 0.014
    Add-Reason $reasons "gnc" "Vehiculo con GNC" 0.014
  }

  $score = Clamp $score 0.03 0.82
  $level = "Bajo"
  $action = "Flujo normal de onboarding."
  if ($score -gt 0.40) {
    $level = "Alto"
    $action = "Contactar en la primera semana y revisar dolor de precio/cobertura."
  } elseif ($score -ge 0.20) {
    $level = "Medio"
    $action = "Seguimiento preventivo durante onboarding."
  }

  $topReasons = @($reasons | Sort-Object -Property impact -Descending | Select-Object -First 3)
  if ($topReasons.Count -eq 0) {
    $topReasons = @([pscustomobject]@{ label = "perfil"; text = "Sin driver critico dominante"; impact = 0.01 })
  }

  return [pscustomobject]@{
    score_churn = [math]::Round($score, 3)
    nivel_riesgo = $level
    accion_recomendada = $action
    razones = $topReasons
  }
}

if (-not (Test-Path -LiteralPath $CsvPath)) {
  throw "No se encontro el CSV: $CsvPath"
}

Write-Host "Leyendo CSV..."
$raw = Import-Csv -LiteralPath $CsvPath
Write-Host "Filas CSV: $($raw.Count)"

$training = @($raw | Where-Object { $_.Estado_poliza -in @("activated", "canceled", "expired") })
$early = 0
foreach ($r in $training) {
  $mpc = Num $r.'meses pre churn'
  if (($r.Estado_poliza -in @("canceled", "expired")) -and $null -ne $mpc -and $mpc -le 3) {
    $early += 1
  }
}
$baseRate = [math]::Round($early / [double]$training.Count, 4)
Write-Host "Training=$($training.Count) Early=$early BaseRate=$baseRate"

$tables = Build-RateTables $training $baseRate
Write-Host "Tablas historicas listas"

$active = @($raw | Where-Object { $_.Estado_poliza -eq "activated" })
$activeForDemo = @()
if ($active.Count -le $MaxPolicies) {
  $activeForDemo = $active
} else {
  $step = $active.Count / [double]$MaxPolicies
  for ($i = 0; $i -lt $MaxPolicies; $i += 1) {
    $activeForDemo += $active[[math]::Floor($i * $step)]
  }
}
Write-Host "Activas seleccionadas para demo: $($activeForDemo.Count)"

$q = [pscustomobject]@{
  cuota_p25 = Quantile (@($active | ForEach-Object { Num $_.Valor_cuota_mes_pesos })) 0.25
  cuota_p75 = Quantile (@($active | ForEach-Object { Num $_.Valor_cuota_mes_pesos })) 0.75
  cuota_p90 = Quantile (@($active | ForEach-Object { Num $_.Valor_cuota_mes_pesos })) 0.90
  comision_p80 = Quantile (@($active | ForEach-Object { Num $_.Comision_pesos })) 0.80
  valor_p85 = Quantile (@($active | ForEach-Object { Num $_.Valor_asegurado_pesos })) 0.85
}

$policies = New-Object System.Collections.Generic.List[object]
$counter = 1
foreach ($r in $activeForDemo) {
  $s = Score-Policy $r $tables $baseRate $q
  $policies.Add([pscustomobject]@{
    id_poliza = "DEMO-$($counter.ToString("0000"))"
    numero_poliza = "POL-$($counter.ToString("000000"))"
    patente = "PAT-$($counter.ToString("0000"))"
    cliente = "Cliente demo $($counter.ToString("0000"))"
    email = "cl***$($counter.ToString("0000"))@demo.com"
    telefono = "***$((1000 + ($counter % 9000)).ToString("0000"))"
    estado = "activated"
    aseguradora = Txt $r.Aseguradora
    cobertura = Txt $r.Cobertura_nombre_corto
    metodo_pago = Txt $r.Metodo_de_pago
    region = Region $r.provincia
    provincia = Txt $r.provincia
    marca = Txt $r.Marca
    modelo = Txt $r.modelo ""
    fecha_inicio = ((Txt $r.fecha_inicio_poliza "") + "          ").Substring(0, 10).Trim()
    cuota = Money (Num $r.Valor_cuota_mes_pesos)
    comision = Money (Num $r.Comision_pesos)
    score_churn = $s.score_churn
    nivel_riesgo = $s.nivel_riesgo
    accion_recomendada = $s.accion_recomendada
    razones = $s.razones
  }) | Out-Null
  $counter += 1
}

$sorted = @($policies | Sort-Object -Property score_churn -Descending)
$high = @($sorted | Where-Object { $_.nivel_riesgo -eq "Alto" }).Count
$medium = @($sorted | Where-Object { $_.nivel_riesgo -eq "Medio" }).Count
$low = @($sorted | Where-Object { $_.nivel_riesgo -eq "Bajo" }).Count
Write-Host "Scoring listo: Activas=$($sorted.Count) Alto=$high Medio=$medium Bajo=$low"

$summary = [pscustomobject]@{
  total_polizas = $raw.Count
  activas = $sorted.Count
  base_churn_temprano = $baseRate
  alto = $high
  medio = $medium
  bajo = $low
  precision_top20_entregable_3 = 0.491
  roc_auc_entregable_3 = 0.731
  modelo_entregable_3 = "XGBoost"
  prototipo = "Demo web estatica generada desde CSV anonimizado"
}

$summaryJson = $summary | ConvertTo-Json -Depth 8
$policiesJson = $sorted | ConvertTo-Json -Depth 8
$generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$content = @"
// Auto-generated by scripts/generate_demo_data.ps1 on $generatedAt.
// Source: anonymized active policies derived from the Kavak Seguros CSV.
window.DEMO_SUMMARY = $summaryJson;

window.DEMO_POLICIES = $policiesJson;
"@

$resolvedOut = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutPath)
[IO.File]::WriteAllText($resolvedOut, $content, [Text.Encoding]::UTF8)
Write-Host "Demo data generado: $resolvedOut"
