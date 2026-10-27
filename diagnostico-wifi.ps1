<#
.SYNOPSIS
  Diagnóstico de WiFi lento (pensado para hogares con Movistar Chile, sirve para cualquier proveedor).

.DESCRIPTION
  Mide, en este orden:
    1. Calidad de la conexión WiFi (señal, banda, canal, velocidad de enlace).
    2. Congestión de canales (cuántas redes vecinas comparten tu canal).
    3. Latencia y pérdida de paquetes hacia el router (red de la casa) y hacia Internet.
    4. Tiempo de respuesta DNS (Movistar vs. Cloudflare vs. Google).
    5. Velocidad real de descarga y subida.
  Al final entrega un diagnóstico en lenguaje simple y guarda un informe .txt en el Escritorio.

.PARAMETER PlanMbps
  Velocidad de bajada contratada (ej.: 600 para "Fibra 600 Megas"). Si se indica, se compara.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\diagnostico-wifi.ps1 -PlanMbps 600
#>
param(
    [int]$PlanMbps = 0
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$informe   = New-Object System.Collections.Generic.List[string]
$hallazgos = New-Object System.Collections.Generic.List[string]

function Escribir([string]$texto, [string]$color = 'Gray') {
    Write-Host $texto -ForegroundColor $color
    $informe.Add($texto)
}
function Titulo([string]$texto) { Escribir ''; Escribir "=== $texto ===" 'Cyan' }

# netsh entrega los campos en el idioma de Windows: se buscan en español e inglés.
function Valor-Netsh([string[]]$lineas, [string]$patron) {
    foreach ($l in $lineas) {
        if ($l -match "^\s*($patron)\s*:\s*(.+)$") { return $Matches[2].Trim() }
    }
    return $null
}

function Medir-Ping([string]$destino, [int]$cantidad = 30) {
    $p = New-Object System.Net.NetworkInformation.Ping
    $tiempos = @(); $perdidos = 0
    for ($i = 0; $i -lt $cantidad; $i++) {
        try {
            $r = $p.Send($destino, 1000)
            if ($r.Status -eq 'Success') { $tiempos += $r.RoundtripTime } else { $perdidos++ }
        } catch { $perdidos++ }
        Start-Sleep -Milliseconds 100
    }
    if ($tiempos.Count -eq 0) { return [pscustomobject]@{ Prom = $null; Max = $null; Jitter = $null; Perdida = 100 } }
    $prom = ($tiempos | Measure-Object -Average).Average
    $jitter = 0
    if ($tiempos.Count -gt 1) {
        $difs = for ($i = 1; $i -lt $tiempos.Count; $i++) { [math]::Abs($tiempos[$i] - $tiempos[$i - 1]) }
        $jitter = ($difs | Measure-Object -Average).Average
    }
    [pscustomobject]@{
        Prom    = [math]::Round($prom, 1)
        Max     = ($tiempos | Measure-Object -Maximum).Maximum
        Jitter  = [math]::Round($jitter, 1)
        Perdida = [math]::Round(100 * $perdidos / $cantidad, 1)
    }
}

Escribir "Diagnóstico WiFi - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" 'White'
Escribir "Equipo: $env:COMPUTERNAME"

# ---------------------------------------------------------------- 1. WiFi
Titulo '1. Conexión WiFi actual'
$iface = @(netsh wlan show interfaces 2>$null)
$senal = Valor-Netsh $iface 'Se.{1,3}al|Signal'
$ssid  = Valor-Netsh $iface 'SSID'
$banda = Valor-Netsh $iface 'Banda|Band'
$canal = Valor-Netsh $iface 'Canal|Channel'
$radio = Valor-Netsh $iface 'Tipo de radio|Radio type'
$rx    = Valor-Netsh $iface 'Velocidad de recepci.{1,3}n \(Mbps\)|Receive rate \(Mbps\)'
$tx    = Valor-Netsh $iface 'Velocidad de transmisi.{1,3}n \(Mbps\)|Transmit rate \(Mbps\)'
$enWifi = [bool]$senal

if (-not $enWifi) {
    Escribir 'No se detectó conexión WiFi activa (¿estás por cable?, o Windows exige activar "Ubicación" para leer datos WiFi).' 'Yellow'
} else {
    $senalNum = [int]($senal -replace '[^\d]', '')
    $canalNum = [int]($canal -replace '[^\d]', '')
    if (-not $banda) { $banda = if ($canalNum -gt 14) { '5 GHz' } else { '2.4 GHz' } }
    Escribir "Red (SSID):            $ssid"
    Escribir "Señal:                 $senal"
    Escribir "Banda / Canal:         $banda / canal $canal"
    Escribir "Estándar:              $radio"
    Escribir "Velocidad de enlace:   bajada $rx Mbps / subida $tx Mbps"

    if ($senalNum -lt 50)     { $hallazgos.Add("SEÑAL DÉBIL ($senal): estás lejos del router o hay muros/losa entre medio. Es la causa más común de lentitud.") }
    elseif ($senalNum -lt 70) { $hallazgos.Add("Señal regular ($senal): acercarse al router o agregar un punto mesh mejoraría la velocidad.") }
    if ($canalNum -le 14)     { $hallazgos.Add("Conectado en 2.4 GHz (canal $canal): esta banda rara vez supera 50-100 Mbps reales. Si estás a 1-2 habitaciones del router, usa la red de 5 GHz.") }
    if ($rx -and [double]$rx -lt 100) { $hallazgos.Add("Velocidad de enlace baja ($rx Mbps): el techo físico de tu WiFi ya es menor que un plan de fibra.") }
    if ($radio -match '802\.11(n|g|b)$') { $hallazgos.Add("Tu equipo se conecta con $radio (WiFi 4 o anterior): tarjeta WiFi antigua, limita la velocidad aunque el plan sea alto.") }
}

# ---------------------------------------------------------------- 2. Canales
Titulo '2. Redes vecinas por canal'
$redes = @(netsh wlan show networks mode=bssid 2>$null)
$canales = @{}
foreach ($l in $redes) {
    if ($l -match '^\s*(Canal|Channel)\s*:\s*(\d+)') {
        $c = [int]$Matches[2]; $canales[$c] = 1 + [int]$canales[$c]
    }
}
if ($canales.Count -eq 0) {
    Escribir 'No se pudieron listar redes vecinas (activa "Ubicación" en Configuración > Privacidad si usas Windows 11).' 'Yellow'
} else {
    foreach ($c in ($canales.Keys | Sort-Object)) {
        $b = if ($c -le 14) { '2.4 GHz' } else { '5 GHz  ' }
        $marca = if ($enWifi -and $c -eq $canalNum) { '  <- tu canal' } else { '' }
        Escribir ("  {0} canal {1,3}: {2} {3}{4}" -f $b, $c, ('#' * $canales[$c]), $canales[$c], $marca)
    }
    if ($enWifi -and $canales[$canalNum] -ge 5) {
        $hallazgos.Add("Canal $canal CONGESTIONADO: $($canales[$canalNum]) redes lo comparten. Cambia el canal en el router (2.4 GHz: usa 1, 6 u 11, el menos ocupado; 5 GHz: 36-48 o 149-161).")
    }
}

# ---------------------------------------------------------------- 3. Latencia
Titulo '3. Latencia y pérdida de paquetes (30 pings c/u)'
$gw = $null
try {
    $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
           Sort-Object RouteMetric | Select-Object -First 1).NextHop
} catch { }
if (-not $gw) { $gw = '192.168.1.1' }

$pRouter = Medir-Ping $gw
$pInet   = Medir-Ping '1.1.1.1'
Escribir ("Router ({0,-13}): prom {1} ms | máx {2} ms | jitter {3} ms | pérdida {4}%" -f $gw, $pRouter.Prom, $pRouter.Max, $pRouter.Jitter, $pRouter.Perdida)
Escribir ("Internet (1.1.1.1)    : prom {0} ms | máx {1} ms | jitter {2} ms | pérdida {3}%" -f $pInet.Prom, $pInet.Max, $pInet.Jitter, $pInet.Perdida)

$routerBloqueaPing = ($pRouter.Perdida -eq 100) -and ($pInet.Perdida -lt 100)
if ($routerBloqueaPing) { Escribir '  (El router no responde ping pero Internet sí: el router lo bloquea; se ignora esa línea.)' 'Yellow' }
$problemaLocal = (-not $routerBloqueaPing) -and (($pRouter.Prom -gt 15) -or ($pRouter.Perdida -gt 1) -or ($pRouter.Jitter -gt 10))
$problemaISP   = (-not $problemaLocal) -and (($pInet.Prom -gt 40) -or ($pInet.Perdida -gt 1) -or ($pInet.Jitter -gt 15))
if ($problemaLocal) { $hallazgos.Add("El problema está DENTRO DE LA CASA: la latencia/pérdida hacia el propio router ya es mala. Es WiFi (señal, interferencia o router saturado), no Movistar.") }
if ($problemaISP)   { $hallazgos.Add("La red de la casa responde bien, pero hacia Internet hay latencia/pérdida alta: apunta a la línea o red de Movistar. Corresponde llamar o reclamar (ver guía).") }

# ---------------------------------------------------------------- 4. DNS
Titulo '4. Tiempo de respuesta DNS'
$dominios = 'www.google.cl','www.pjud.cl','www.sii.cl','www.bcentral.cl','www.youtube.com'
# Se consulta directo al DNS configurado (y no al caché de Windows) para que la comparación sea justa.
$dnsLocal = $null
try {
    $dnsLocal = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
                 Where-Object { $_.ServerAddresses } | Select-Object -First 1).ServerAddresses[0]
} catch { }
if (-not $dnsLocal) { $dnsLocal = $gw }
$servidores = [ordered]@{ 'DNS actual (Movistar/router)' = $dnsLocal; 'Cloudflare 1.1.1.1' = '1.1.1.1'; 'Google 8.8.8.8' = '8.8.8.8' }
$dnsRes = @{}
foreach ($n in $servidores.Keys) {
    $total = 0; $ok = 0
    foreach ($d in $dominios) {
        try {
            $t = Measure-Command {
                Resolve-DnsName $d -Server $servidores[$n] -DnsOnly -QuickTimeout -ErrorAction Stop | Out-Null
            }
            $total += $t.TotalMilliseconds; $ok++
        } catch { }
    }
    $dnsRes[$n] = if ($ok) { [math]::Round($total / $ok) } else { $null }
    Escribir ("  {0,-30}: {1} ms promedio" -f $n, $dnsRes[$n])
}
$dnsActual = $dnsRes['DNS actual (Movistar/router)']
$dnsMejor  = (@($dnsRes['Cloudflare 1.1.1.1'], $dnsRes['Google 8.8.8.8']) | Where-Object { $_ } | Measure-Object -Minimum).Minimum
if ($dnsActual -and $dnsMejor -and ($dnsActual -gt 2 * $dnsMejor) -and ($dnsActual -gt 40)) {
    $hallazgos.Add("DNS lento ($dnsActual ms vs $dnsMejor ms): las páginas 'tardan en empezar a cargar'. Cambia el DNS a 1.1.1.1 / 8.8.8.8 (ver guía).")
}

# ---------------------------------------------------------------- 5. Velocidad
Titulo '5. Velocidad real (servidores Cloudflare)'
$bajada = $null; $subida = $null
try {
    $wc = New-Object System.Net.WebClient
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $datos = $wc.DownloadData('https://speed.cloudflare.com/__down?bytes=50000000')
    $sw.Stop()
    $bajada = [math]::Round(($datos.Length * 8 / 1e6) / $sw.Elapsed.TotalSeconds, 1)
    Escribir "  Bajada: $bajada Mbps"
} catch { Escribir "  No se pudo medir la bajada: $($_.Exception.Message)" 'Yellow' }
try {
    $wc = New-Object System.Net.WebClient
    $carga = New-Object byte[] 15000000
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $wc.UploadData('https://speed.cloudflare.com/__up', 'POST', $carga) | Out-Null
    $sw.Stop()
    $subida = [math]::Round(($carga.Length * 8 / 1e6) / $sw.Elapsed.TotalSeconds, 1)
    Escribir "  Subida: $subida Mbps"
} catch { Escribir "  No se pudo medir la subida: $($_.Exception.Message)" 'Yellow' }
Escribir '  (Prueba de una sola conexión: puede quedar algo bajo el máximo. Contrasta con el medidor de Movistar o speedtest.net.)'

if ($PlanMbps -gt 0 -and $bajada) {
    $pct = [math]::Round(100 * $bajada / $PlanMbps)
    Escribir "  Plan contratado: $PlanMbps Mbps -> obtienes $pct% por WiFi"
    if ($pct -lt 50) {
        if ($enWifi) { $hallazgos.Add("Obtienes solo $pct% del plan por WiFi. Repite la prueba con un cable conectado al router: si por cable llega cerca del plan, el cuello de botella es el WiFi; si por cable también es bajo, es la línea de Movistar.") }
        else         { $hallazgos.Add("Por cable obtienes solo $pct% del plan: problema de la línea/equipo de Movistar. Reinicia el router y, si persiste, reclama (Ley 21.046, velocidad mínima garantizada).") }
    }
}

# ---------------------------------------------------------------- Diagnóstico
Titulo 'DIAGNÓSTICO'
if ($hallazgos.Count -eq 0) {
    Escribir 'No se detectaron problemas claros en este momento. Si la lentitud es en horario punta (19-23 h), repite el diagnóstico a esa hora.' 'Green'
} else {
    $i = 1
    foreach ($h in $hallazgos) { Escribir "$i. $h" 'Yellow'; $i++ }
}
Escribir ''
Escribir 'Soluciones detalladas: ver GUIA-WIFI-MOVISTAR.md en este mismo repositorio.'

$destino = Join-Path ([Environment]::GetFolderPath('Desktop')) ("diagnostico-wifi-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmm'))
try { $informe | Out-File -FilePath $destino -Encoding utf8; Write-Host "`nInforme guardado en: $destino" -ForegroundColor Green } catch { }
