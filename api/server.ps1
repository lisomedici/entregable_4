param(
  [string]$CsvPath = "$env:USERPROFILE\Downloads\Kavak Listado Total - Con formulas (3).csv",
  [int]$Port = 8787
)

$ErrorActionPreference = "Stop"

function Get-Prop($Obj, [string]$Name, $Default = $null) {
  if ($null -eq $Obj) { return $Default }
  $p = $Obj.PSObject.Properties[$Name]
  if ($null -eq $p) { return $Default }
  if ($null -eq $p.Value -or "$($p.Value)" -eq "") { return $Default }
  return $p.Value
}

function To-Number($Value) {
  if ($null -eq $Value) { return $null }
  $s = "$Value".Trim()
  if ($s -eq "" -or $s -eq "Revisar") { return $null }
  $s = $s -replace "\$", "" -replace "\s", ""
  $d = 0.0
  $ok = [double]::TryParse(
    $s,
    [System.Globalization.NumberStyles]::Any,
    [System.Globalization.CultureInfo]::InvariantCulture,
    [ref]$d
  )
  if ($ok) { return [double]$d }
  return $null
}

function To-Date($Value) {
  if ($null -eq $Value) { return $null }
  $s = "$Value".Trim()
  if ($s -eq "") { return $null }
  if ($s -match "^(\d{4})-(\d{1,2})-(\d{1,2})") {
    return [datetime]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
  }
  if ($s -match "^(\d{1,2})/(\d{1,2})/(\d{4})") {
    return [datetime]::new([int]$Matches[3], [int]$Matches[1], [int]$Matches[2])
  }
  return $null
}

function Clean-Text($Value, [string]$Default = "Sin dato") {
  if ($null -eq $Value) { return $Default }
  $s = "$Value".Trim()
  if ($s -eq "") { return $Default }
  return $s
}

function Get-Region($Provincia) {
  $p = Clean-Text $Provincia
  if ($p -eq "Buenos Aires") { return "GBA" }
  if ($p -eq "Capital Federal") { return "CABA" }
  return "Interior"
}

function Mask-Email($Email) {
  $s = Clean-Text $Email ""
  if ($s -eq "" -or $s -notmatch "@") { return "" }
  $parts = $s.Split("@")
  $name = $parts[0]
  $domain = $parts[1]
  if ($name.Length -le 2) { return "***@$domain" }
  return ($name.Substring(0, 2) + "***@" + $domain)
}

function Mask-Phone($Phone) {
  $s = (Clean-Text $Phone "") -replace "\D", ""
  if ($s.Length -le 4) { return $s }
  return ("***" + $s.Substring($s.Length - 4))
}

function Format-Money($Value) {
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
  $idx = [math]::Floor(($arr.Count - 1) * $Q)
  return [double]$arr[$idx]
}

function Build-Policy($Row) {
  $fechaInicio = To-Date $Row.fecha_inicio_poliza
  if ($null -eq $fechaInicio) {
    $fechaInicio = To-Date $Row.fecha_vigencia_inicial
  }

  $fechaNac = To-Date $Row.fecha_nacimiento
  if ($null -eq $fechaNac) {
    $fechaNac = To-Date $Row.fecha_nacimiento_cliente
  }

  $anioBien = To-Number $Row.anio_bien
  $edad = $null
  if ($null -ne $fechaInicio -and $null -ne $fechaNac) {
    $edad = [math]::Round(($fechaInicio - $fechaNac).TotalDays / 365.25, 0)
    if ($edad -lt 18 -or $edad -gt 100) { $edad = $null }
  }

  $antiguedad = $null
  if ($null -ne $fechaInicio -and $null -ne $anioBien) {
    $antiguedad = $fechaInicio.Year - [int]$anioBien
  }

  $renovacionId = To-Number $Row.Es_renovacion_ID_poliza_anterior
  $mpc = To-Number $Row.'meses pre churn'
  $estado = Clean-Text $Row.Estado_poliza ""
  $target = $null
  if ($estado -eq "pending") {
    $target = $null
  } elseif ($estado -in @("canceled", "expired")) {
    if ($null -ne $mpc) { $target = [int]($mpc -le 3) }
  } elseif ($estado -eq "activated") {
    $target = 0
  }

  $nombre = ((Clean-Text $Row.nombre_cliente "") + " " + (Clean-Text $Row.apellido_cliente "")).Trim()
  if ($nombre -eq "") {
    $nombre = ((Clean-Text $Row.'nombre_cliente-2' "") + " " + (Clean-Text $Row.'apellido_cliente-2' "")).Trim()
  }

  [pscustomobject]@{
    id_poliza = Clean-Text $Row.ID_poliza ""
    numero_poliza = Clean-Text $Row.numero_poliza ""
    patente = Clean-Text $Row.Patente ""
    cliente = $nombre
    email = Clean-Text $Row.email_cliente ""
    telefono = Clean-Text $Row.telefono_cliente ""
    email_mask = Mask-Email $Row.email_cliente
    telefono_mask = Mask-Phone $Row.telefono_cliente
    estado = $estado
    aseguradora = Clean-Text $Row.Aseguradora
    cluster = Clean-Text $Row.Cluster_Detalle
    cobertura = Clean-Text $Row.Cobertura_nombre_corto
    metodo_pago = Clean-Text $Row.Metodo_de_pago
    rango_comision = Clean-Text $Row.rango_comision
    genero = Clean-Text $Row.genero_cliente
    provincia = Clean-Text $Row.provincia
    localidad = Clean-Text $Row.localidad ""
    region = Get-Region $Row.provincia
    marca = Clean-Text $Row.Marca
    modelo = Clean-Text $Row.modelo ""
    bien = Clean-Text $Row.Bien ""
    anio_bien = $anioBien
    fecha_inicio = if ($null -ne $fechaInicio) { $fechaInicio.ToString("yyyy-MM-dd") } else { "" }
    mes_emision = if ($null -ne $fechaInicio) { $fechaInicio.Month } else { $null }
    edad_cliente = $edad
    antiguedad_vehiculo = $antiguedad
    es_renovacion = [int]($null -ne $renovacionId -and $renovacionId -gt 0)
    gnc_flag = [int]((Clean-Text $Row.GNC "").ToLower() -eq "true")
    comision_pesos = To-Number $Row.Comision_pesos
    valor_cuota_mes_pesos = To-Number $Row.Valor_cuota_mes_pesos
    valor_asegurado_pesos = To-Number $Row.Valor_asegurado_pesos
    meses_pre_churn = $mpc
    baja_limpia = Clean-Text $Row.'baja limpia' ""
    churn_temprano = $target
  }
}

function Build-RateTable($Rows, [string]$Feature, [double]$BaseRate, [int]$Prior = 25) {
  $table = @{}
  $groups = $Rows | Group-Object -Property $Feature
  foreach ($g in $groups) {
    $n = $g.Count
    $sum = @($g.Group | Where-Object { $_.churn_temprano -eq 1 }).Count
    $rate = ($sum + ($BaseRate * $Prior)) / ($n + $Prior)
    $table[$g.Name] = [pscustomobject]@{
      feature = $Feature
      value = $g.Name
      n = $n
      churn = $sum
      rate = [math]::Round($rate, 4)
    }
  }
  return $table
}

function Rate-For($Model, [string]$Feature, $Value) {
  $v = Clean-Text $Value
  if ($Model.rateTables.ContainsKey($Feature) -and $Model.rateTables[$Feature].ContainsKey($v)) {
    return [double]$Model.rateTables[$Feature][$v].rate
  }
  return [double]$Model.baseRate
}

function Score-Policy($Policy, $Model) {
  $reasons = New-Object System.Collections.Generic.List[object]
  $score = [double]$Model.baseRate

  switch -Regex ($Policy.aseguradora) {
    "zurich" { $score += 0.10; $reasons.Add([pscustomobject]@{ label = "aseguradora"; text = "Aseguradora con mayor churn historico"; impact = 0.10 }); break }
    "sura" { $score += 0.08; $reasons.Add([pscustomobject]@{ label = "aseguradora"; text = "Aseguradora con churn sobre promedio"; impact = 0.08 }); break }
    "mercantil" { $score += 0.05; $reasons.Add([pscustomobject]@{ label = "aseguradora"; text = "Aseguradora con riesgo medio-alto"; impact = 0.05 }); break }
  }

  if ("$($Policy.cluster)" -match "Terceros") {
    $score += 0.04
    $reasons.Add([pscustomobject]@{ label = "cobertura"; text = "Cobertura de terceros"; impact = 0.04 })
  }
  if ("$($Policy.metodo_pago)" -eq "bankAccount") {
    $score += 0.06
    $reasons.Add([pscustomobject]@{ label = "pago"; text = "Metodo de pago CBU"; impact = 0.06 })
  }
  if ($null -ne $Policy.valor_cuota_mes_pesos) {
    if ($Policy.valor_cuota_mes_pesos -ge 150000) {
      $score += 0.11
      $reasons.Add([pscustomobject]@{ label = "cuota"; text = "Cuota mensual alta"; impact = 0.11 })
    } elseif ($Policy.valor_cuota_mes_pesos -ge 100000) {
      $score += 0.06
      $reasons.Add([pscustomobject]@{ label = "cuota"; text = "Cuota mensual media-alta"; impact = 0.06 })
    }
  }
  if ($null -ne $Policy.comision_pesos -and $Policy.comision_pesos -ge 22000) {
    $score += 0.05
    $reasons.Add([pscustomobject]@{ label = "comision"; text = "Comision alta"; impact = 0.05 })
  }
  if ($null -ne $Policy.edad_cliente -and $Policy.edad_cliente -lt 30) {
    $score += 0.04
    $reasons.Add([pscustomobject]@{ label = "edad"; text = "Cliente joven"; impact = 0.04 })
  }
  if ($null -ne $Policy.antiguedad_vehiculo -and $Policy.antiguedad_vehiculo -ge 8) {
    $score += 0.04
    $reasons.Add([pscustomobject]@{ label = "vehiculo"; text = "Vehiculo con mayor antiguedad"; impact = 0.04 })
  }
  if ($Policy.es_renovacion -eq 0) {
    $score += 0.07
    $reasons.Add([pscustomobject]@{ label = "renovacion"; text = "Poliza nueva, no renovacion"; impact = 0.06 })
  } else {
    $score -= 0.09
  }
  if ($Policy.region -eq "Interior") {
    $score += 0.02
  }

  $score = ($score * 0.60) + 0.02
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

  [pscustomobject]@{
    score_churn = [math]::Round($score, 3)
    nivel_riesgo = $level
    accion_recomendada = $action
    razones = $topReasons
  }
}

function Build-ModelContext([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "No se encontro el CSV: $Path"
  }

  Write-Host "Leyendo CSV: $Path"
  $raw = Import-Csv -LiteralPath $Path
  Write-Host "Filas leidas: $($raw.Count)"
  $realRows = @($raw)
  Write-Host "Polizas reales detectadas: $($realRows.Count)"

  $model = [pscustomobject]@{
    csvPath = $Path
    loadedAt = (Get-Date).ToString("s")
    totalPolicies = $realRows.Count
    baseRate = 0.255
    rateTables = @{}
    quantiles = [pscustomobject]@{}
  }

  $activeRows = @($realRows | Where-Object { "$($_.Estado_poliza)".Trim() -eq "activated" } | Select-Object -First 1200)
  Write-Host "Polizas activas para scorear: $($activeRows.Count)"
  $active = foreach ($r in $activeRows) {
    $anioBien = To-Number $r.anio_bien
    $renovacionId = To-Number $r.Es_renovacion_ID_poliza_anterior
    $fechaInicio = Clean-Text $r.fecha_inicio_poliza ""
    $nombre = ((Clean-Text $r.nombre_cliente "") + " " + (Clean-Text $r.apellido_cliente "")).Trim()
    if ($nombre -eq "") {
      $nombre = ((Clean-Text $r.'nombre_cliente-2' "") + " " + (Clean-Text $r.'apellido_cliente-2' "")).Trim()
    }
    $p = [pscustomobject]@{
      id_poliza = Clean-Text $r.ID_poliza ""
      numero_poliza = Clean-Text $r.numero_poliza ""
      patente = Clean-Text $r.Patente ""
      cliente = $nombre
      email = Clean-Text $r.email_cliente ""
      telefono = Clean-Text $r.telefono_cliente ""
      email_mask = Mask-Email $r.email_cliente
      telefono_mask = Mask-Phone $r.telefono_cliente
      estado = Clean-Text $r.Estado_poliza ""
      aseguradora = Clean-Text $r.Aseguradora
      cluster = Clean-Text $r.Cluster_Detalle
      cobertura = Clean-Text $r.Cobertura_nombre_corto
      metodo_pago = Clean-Text $r.Metodo_de_pago
      rango_comision = Clean-Text $r.rango_comision
      genero = Clean-Text $r.genero_cliente
      provincia = Clean-Text $r.provincia
      localidad = Clean-Text $r.localidad ""
      region = Get-Region $r.provincia
      marca = Clean-Text $r.Marca
      modelo = Clean-Text $r.modelo ""
      bien = Clean-Text $r.Bien ""
      anio_bien = $anioBien
      fecha_inicio = if ($fechaInicio.Length -ge 10) { $fechaInicio.Substring(0, 10) } else { $fechaInicio }
      mes_emision = $null
      edad_cliente = $null
      antiguedad_vehiculo = if ($null -ne $anioBien) { 2026 - [int]$anioBien } else { $null }
      es_renovacion = [int]($null -ne $renovacionId -and $renovacionId -gt 0)
      gnc_flag = [int]((Clean-Text $r.GNC "").ToLower() -eq "true")
      comision_pesos = To-Number $r.Comision_pesos
      valor_cuota_mes_pesos = To-Number $r.Valor_cuota_mes_pesos
      valor_asegurado_pesos = To-Number $r.Valor_asegurado_pesos
      meses_pre_churn = $null
      baja_limpia = ""
      churn_temprano = $null
    }
    $s = Score-Policy $p $model
    [pscustomobject]@{
      id_poliza = $p.id_poliza
      numero_poliza = $p.numero_poliza
      patente = $p.patente
      cliente = $p.cliente
      email = $p.email
      telefono = $p.telefono
      email_mask = $p.email_mask
      telefono_mask = $p.telefono_mask
      estado = $p.estado
      aseguradora = $p.aseguradora
      cluster = $p.cluster
      cobertura = $p.cobertura
      metodo_pago = $p.metodo_pago
      rango_comision = $p.rango_comision
      genero = $p.genero
      provincia = $p.provincia
      localidad = $p.localidad
      region = $p.region
      marca = $p.marca
      modelo = $p.modelo
      bien = $p.bien
      anio_bien = $p.anio_bien
      fecha_inicio = $p.fecha_inicio
      mes_emision = $p.mes_emision
      edad_cliente = $p.edad_cliente
      antiguedad_vehiculo = $p.antiguedad_vehiculo
      es_renovacion = $p.es_renovacion
      gnc_flag = $p.gnc_flag
      comision_pesos = $p.comision_pesos
      valor_cuota_mes_pesos = $p.valor_cuota_mes_pesos
      valor_asegurado_pesos = $p.valor_asegurado_pesos
      score_churn = $s.score_churn
      nivel_riesgo = $s.nivel_riesgo
      accion_recomendada = $s.accion_recomendada
      razones = $s.razones
    }
  }
  Write-Host "Scoring activo completo"

  [pscustomobject]@{
    model = $model
    policies = @($active)
    active = @($active | Sort-Object -Property score_churn -Descending)
    historical = @()
  }
}

function Write-Json($Response, $Data, [int]$Status = 200) {
  $json = $Data | ConvertTo-Json -Depth 8
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  $Response.StatusCode = $Status
  $Response.ContentType = "application/json; charset=utf-8"
  $Response.ContentLength64 = $bytes.Length
  $Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Write-Text($Response, [string]$Text, [string]$ContentType = "text/plain; charset=utf-8", [int]$Status = 200) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $Response.StatusCode = $Status
  $Response.ContentType = $ContentType
  $Response.ContentLength64 = $bytes.Length
  $Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Get-ContentType([string]$Path) {
  switch ([IO.Path]::GetExtension($Path).ToLower()) {
    ".html" { "text/html; charset=utf-8" }
    ".css" { "text/css; charset=utf-8" }
    ".js" { "application/javascript; charset=utf-8" }
    ".json" { "application/json; charset=utf-8" }
    ".svg" { "image/svg+xml" }
    default { "application/octet-stream" }
  }
}

function Write-FileResponse($Response, [string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Text $Response "No encontrado" "text/plain; charset=utf-8" 404
    return
  }
  $bytes = [IO.File]::ReadAllBytes($Path)
  $Response.StatusCode = 200
  $Response.ContentType = Get-ContentType $Path
  $Response.ContentLength64 = $bytes.Length
  $Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Policy-For-Output($P, [bool]$Reveal = $false) {
  [pscustomobject]@{
    id_poliza = $P.id_poliza
    numero_poliza = $P.numero_poliza
    patente = $P.patente
    cliente = $P.cliente
    email = if ($Reveal) { $P.email } else { $P.email_mask }
    telefono = if ($Reveal) { $P.telefono } else { $P.telefono_mask }
    estado = $P.estado
    aseguradora = $P.aseguradora
    cobertura = $P.cobertura
    metodo_pago = $P.metodo_pago
    region = $P.region
    provincia = $P.provincia
    marca = $P.marca
    modelo = $P.modelo
    fecha_inicio = $P.fecha_inicio
    cuota = Format-Money $P.valor_cuota_mes_pesos
    comision = Format-Money $P.comision_pesos
    score_churn = $P.score_churn
    nivel_riesgo = $P.nivel_riesgo
    accion_recomendada = $P.accion_recomendada
    razones = $P.razones
  }
}

$script:Context = Build-ModelContext $CsvPath

$dashboardRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "dashboard"
$presentationRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "presentacion"

function Parse-Query([string]$Query) {
  $out = @{}
  if ([string]::IsNullOrWhiteSpace($Query)) { return $out }
  foreach ($part in $Query.TrimStart("?").Split("&")) {
    if ($part -eq "") { continue }
    $kv = $part.Split("=", 2)
    $key = [uri]::UnescapeDataString($kv[0])
    $val = if ($kv.Count -gt 1) { [uri]::UnescapeDataString($kv[1]) } else { "" }
    $out[$key] = $val
  }
  return $out
}

function Send-Response($Stream, [int]$Status, [string]$ContentType, [byte[]]$Bytes) {
  $reason = switch ($Status) {
    200 { "OK" }
    404 { "Not Found" }
    500 { "Internal Server Error" }
    default { "OK" }
  }
  $header = "HTTP/1.1 $Status $reason`r`nContent-Type: $ContentType`r`nContent-Length: $($Bytes.Length)`r`nConnection: close`r`n`r`n"
  $headBytes = [Text.Encoding]::ASCII.GetBytes($header)
  $Stream.Write($headBytes, 0, $headBytes.Length)
  $Stream.Write($Bytes, 0, $Bytes.Length)
}

function Json-Bytes($Data) {
  [Text.Encoding]::UTF8.GetBytes(($Data | ConvertTo-Json -Depth 8))
}

function Text-Bytes([string]$Text) {
  [Text.Encoding]::UTF8.GetBytes($Text)
}

function Handle-Request([string]$Method, [string]$Path, $Query, [string]$Body) {
  if ($Path -eq "/api/health") {
    return @("application/json; charset=utf-8", (Json-Bytes ([pscustomobject]@{ ok = $true; loadedAt = $script:Context.model.loadedAt; csvPath = $script:Context.model.csvPath })), 200)
  }
  if ($Path -eq "/api/summary") {
    $active = $script:Context.active
    $high = @($active | Where-Object { $_.nivel_riesgo -eq "Alto" }).Count
    $medium = @($active | Where-Object { $_.nivel_riesgo -eq "Medio" }).Count
    $low = @($active | Where-Object { $_.nivel_riesgo -eq "Bajo" }).Count
    return @("application/json; charset=utf-8", (Json-Bytes ([pscustomobject]@{
      total_polizas = $script:Context.model.totalPolicies
      activas = $active.Count
      base_churn_temprano = [math]::Round($script:Context.model.baseRate, 3)
      alto = $high
      medio = $medium
      bajo = $low
      precision_top20_entregable_3 = 0.491
      roc_auc_entregable_3 = 0.731
      modelo_entregable_3 = "XGBoost"
      prototipo = "API local PowerShell + dashboard HTML"
    })), 200)
  }
  if ($Path -eq "/api/policies") {
    $limit = To-Number $Query["limit"]
    if ($null -eq $limit -or $limit -le 0) { $limit = 50 }
    $reveal = "$($Query["reveal"])" -eq "1"
    $items = @($script:Context.active | Select-Object -First ([int]$limit) | ForEach-Object { Policy-For-Output $_ $reveal })
    return @("application/json; charset=utf-8", (Json-Bytes $items), 200)
  }
  if ($Path -eq "/api/predict" -and $Method -eq "POST") {
    $payload = $Body | ConvertFrom-Json
    $policy = Build-Policy $payload
    $score = Score-Policy $policy $script:Context.model
    return @("application/json; charset=utf-8", (Json-Bytes ([pscustomobject]@{ input = $policy; prediction = $score })), 200)
  }
  if ($Path -eq "/api/batch" -and $Method -eq "POST") {
    $payload = $Body | ConvertFrom-Json
    $items = if ($payload -is [array]) { $payload } else { @($payload) }
    $out = foreach ($item in $items) {
      $policy = Build-Policy $item
      $score = Score-Policy $policy $script:Context.model
      $policy | Add-Member -NotePropertyName score_churn -NotePropertyValue $score.score_churn -Force
      $policy | Add-Member -NotePropertyName nivel_riesgo -NotePropertyValue $score.nivel_riesgo -Force
      $policy | Add-Member -NotePropertyName accion_recomendada -NotePropertyValue $score.accion_recomendada -Force
      $policy | Add-Member -NotePropertyName razones -NotePropertyValue $score.razones -Force
      Policy-For-Output $policy $false
    }
    return @("application/json; charset=utf-8", (Json-Bytes @($out)), 200)
  }
  if ($Path -eq "/api/schema") {
    return @("application/json; charset=utf-8", (Json-Bytes ([pscustomobject]@{
      required = @("Aseguradora", "Cluster_Detalle", "Metodo_de_pago", "provincia", "genero_cliente", "rango_comision", "fecha_inicio_poliza", "fecha_nacimiento", "anio_bien", "Comision_pesos", "Valor_cuota_mes_pesos", "Valor_asegurado_pesos", "GNC", "Es_renovacion_ID_poliza_anterior")
      output = @("score_churn", "nivel_riesgo", "accion_recomendada", "razones")
    })), 200)
  }

  if ($Path -eq "/" -or $Path -eq "/index.html") {
    $file = Join-Path $dashboardRoot "index.html"
  } elseif ($Path -eq "/presentacion" -or $Path -eq "/presentacion/") {
    $file = Join-Path $presentationRoot "index.html"
  } elseif ($Path.StartsWith("/presentacion/")) {
    $rel = $Path.Substring("/presentacion/".Length).Replace("/", [IO.Path]::DirectorySeparatorChar)
    $file = Join-Path $presentationRoot $rel
  } else {
    $rel = $Path.TrimStart("/").Replace("/", [IO.Path]::DirectorySeparatorChar)
    $file = Join-Path $dashboardRoot $rel
  }

  if (-not (Test-Path -LiteralPath $file)) {
    return @("text/plain; charset=utf-8", (Text-Bytes "No encontrado"), 404)
  }
  return @((Get-ContentType $file), [IO.File]::ReadAllBytes($file), 200)
}

$tcp = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse("127.0.0.1"), $Port)
$tcp.Start()
$prefix = "http://localhost:$Port/"
Write-Host "API lista en $prefix"
Write-Host "Polizas reales: $($script:Context.model.totalPolicies) | Base churn: $([math]::Round($script:Context.model.baseRate * 100, 1))%"

try {
  while ($true) {
    $client = $tcp.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $buffer = New-Object byte[] 65536
      $count = $stream.Read($buffer, 0, $buffer.Length)
      if ($count -le 0) { continue }
      $requestText = [Text.Encoding]::UTF8.GetString($buffer, 0, $count)
      $headerEnd = $requestText.IndexOf("`r`n`r`n")
      if ($headerEnd -lt 0) { continue }
      $head = $requestText.Substring(0, $headerEnd)
      $body = $requestText.Substring($headerEnd + 4)
      $first = $head.Split("`r`n")[0]
      $parts = $first.Split(" ")
      $method = $parts[0]
      $target = $parts[1]
      $targetParts = $target.Split("?", 2)
      $path = $targetParts[0]
      $query = if ($targetParts.Count -gt 1) { Parse-Query $targetParts[1] } else { @{} }
      $resp = Handle-Request $method $path $query $body
      Send-Response $stream $resp[2] $resp[0] $resp[1]
    } catch {
      $bytes = Json-Bytes ([pscustomobject]@{ error = $_.Exception.Message })
      Send-Response $stream 500 "application/json; charset=utf-8" $bytes
    } finally {
      $client.Close()
    }
  }
} finally {
  $tcp.Stop()
}
