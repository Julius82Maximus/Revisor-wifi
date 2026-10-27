#!/usr/bin/env bash
# Diagnóstico de WiFi lento para macOS y Linux (equivalente a diagnostico-wifi.ps1).
# Uso:  bash diagnostico-wifi.sh [velocidad_plan_mbps]     ej.: bash diagnostico-wifi.sh 600

PLAN="${1:-0}"
SO="$(uname -s)"
INFORME="$HOME/diagnostico-wifi-$(date +%Y%m%d-%H%M).txt"
HALLAZGOS=()

exec > >(tee "$INFORME") 2>&1
titulo() { echo; echo "=== $1 ==="; }

echo "Diagnóstico WiFi - $(date '+%Y-%m-%d %H:%M')  ($SO)"

# ---------------------------------------------------------------- 1. WiFi
titulo "1. Conexión WiFi actual"
CANAL=""; RSSI=""
if [ "$SO" = "Darwin" ]; then
  INFO="$(system_profiler SPAirPortDataType 2>/dev/null | awk '/Current Network Information:/{f=1;next} f&&/Other Local Wi-Fi Networks:/{exit} f')"
  CANAL="$(echo "$INFO" | awk -F': ' '/Channel:/{print $2; exit}' | awk '{print $1}')"
  RSSI="$(echo "$INFO" | awk -F': ' '/Signal \/ Noise:/{print $2; exit}' | awk '{print $1}')"
  TASA="$(echo "$INFO" | awk -F': ' '/Transmit Rate:/{print $2; exit}')"
  MODO="$(echo "$INFO" | awk -F': ' '/PHY Mode:/{print $2; exit}')"
  echo "Canal: $CANAL | Señal: $RSSI dBm | Enlace: $TASA Mbps | Estándar: $MODO"
elif command -v iw >/dev/null 2>&1 && IFACE="$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}')" && [ -n "$IFACE" ]; then
  LINK="$(iw dev "$IFACE" link 2>/dev/null)"
  RSSI="$(echo "$LINK" | awk '/signal:/{print $2}')"
  FREQ="$(echo "$LINK" | awk '/freq:/{print int($2)}')"
  TASA="$(echo "$LINK" | awk '/rx bitrate:/{print $3}')"
  if [ -n "$FREQ" ]; then
    if [ "$FREQ" -lt 3000 ]; then CANAL=$(( (FREQ - 2407) / 5 )); else CANAL=$(( (FREQ - 5000) / 5 )); fi
  fi
  echo "Interfaz: $IFACE | Canal: $CANAL | Señal: $RSSI dBm | Enlace: $TASA Mbps"
fi

if [ -z "$RSSI" ]; then
  echo "No se detectó WiFi activo (¿conectado por cable?)."
else
  R=${RSSI%%.*}
  if   [ "$R" -lt -70 ]; then HALLAZGOS+=("SEÑAL DÉBIL ($RSSI dBm): lejos del router o con muros/losa entre medio. Causa más común de lentitud.")
  elif [ "$R" -lt -60 ]; then HALLAZGOS+=("Señal regular ($RSSI dBm): acercarse al router o agregar un punto mesh mejoraría la velocidad."); fi
  if [ -n "$CANAL" ] && [ "$CANAL" -le 14 ]; then
    HALLAZGOS+=("Conectado en 2.4 GHz (canal $CANAL): rara vez supera 50-100 Mbps reales. Usa la red de 5 GHz si estás cerca del router.")
  fi
fi

# ---------------------------------------------------------------- 2. Latencia
titulo "2. Latencia y pérdida de paquetes (30 pings c/u)"
if [ "$SO" = "Darwin" ]; then GW="$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')"
else GW="$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')"; fi
GW="${GW:-192.168.1.1}"

medir_ping() {  # imprime: promedio perdida jitter(mdev/stddev)
  local out
  out="$(LC_ALL=C ping -c 30 -i 0.2 "$1" 2>/dev/null)"
  local perd; perd="$(echo "$out" | grep -oE '[0-9.]+% packet loss' | grep -oE '^[0-9.]+')"
  local stats; stats="$(echo "$out" | awk -F' = ' '/min\/avg\/max/{print $2}' | awk '{print $1}')"
  local prom; prom="$(echo "$stats" | cut -d/ -f2)"
  local jit;  jit="$(echo "$stats" | cut -d/ -f4)"
  echo "${prom:-999} ${perd:-100} ${jit:-0}"
}
read -r RP RL RJ <<<"$(medir_ping "$GW")"
read -r IP IL IJ <<<"$(medir_ping 1.1.1.1)"
[ "$RL" = "100" ] && echo "  (Si el router no responde ningún ping pero Internet sí, el router bloquea ping: ignora esa línea.)"
printf "Router (%-13s): prom %s ms | jitter %s ms | pérdida %s%%\n" "$GW" "$RP" "$RJ" "$RL"
printf "Internet (1.1.1.1)    : prom %s ms | jitter %s ms | pérdida %s%%\n" "$IP" "$IJ" "$IL"

mayor() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>b)}'; }
if [ "$RL" != "100" ] && { mayor "$RP" 15 || mayor "$RL" 1 || mayor "$RJ" 10; }; then
  HALLAZGOS+=("El problema está DENTRO DE LA CASA: latencia/pérdida hacia el propio router ya es mala. Es WiFi, no Movistar.")
elif mayor "$IP" 40 || mayor "$IL" 1 || mayor "$IJ" 15; then
  HALLAZGOS+=("La red de la casa responde bien, pero hacia Internet hay latencia/pérdida alta: apunta a la línea de Movistar.")
fi

# ---------------------------------------------------------------- 3. DNS
titulo "3. Tiempo de respuesta DNS"
if command -v dig >/dev/null 2>&1; then
  if [ "$SO" = "Darwin" ]; then DNSL="$(scutil --dns | awk '/nameserver\[0\]/{print $3; exit}')"
  else DNSL="$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)"; fi
  for S in "${DNSL:-$GW}" 1.1.1.1 8.8.8.8; do
    T=0; N=0
    for D in www.google.cl www.pjud.cl www.sii.cl www.bcentral.cl www.youtube.com; do
      MS="$(dig +tries=1 +time=2 @"$S" "$D" 2>/dev/null | awk '/Query time:/{print $4}')"
      [ -n "$MS" ] && T=$((T + MS)) && N=$((N + 1))
    done
    [ "$N" -gt 0 ] && echo "  DNS $S: $((T / N)) ms promedio" || echo "  DNS $S: sin respuesta"
  done
else
  echo "  (instala 'dig' para medir DNS)"
fi

# ---------------------------------------------------------------- 4. Velocidad
titulo "4. Velocidad real (servidores Cloudflare)"
BAJ="$(curl -s -o /dev/null -w '%{speed_download}' 'https://speed.cloudflare.com/__down?bytes=50000000')"
SUB="$(head -c 15000000 /dev/zero | curl -s -o /dev/null -w '%{speed_upload}' --data-binary @- 'https://speed.cloudflare.com/__up')"
BAJ_M="$(awk -v b="${BAJ:-0}" 'BEGIN{printf "%.1f", b*8/1e6}')"
SUB_M="$(awk -v b="${SUB:-0}" 'BEGIN{printf "%.1f", b*8/1e6}')"
echo "  Bajada: $BAJ_M Mbps | Subida: $SUB_M Mbps"
if [ "$BAJ_M" = "0.0" ]; then
  echo "  No se pudo medir la velocidad (¿sin Internet o sin curl?)."
elif [ "$PLAN" -gt 0 ]; then
  PCT="$(awk -v a="$BAJ_M" -v p="$PLAN" 'BEGIN{printf "%d", 100*a/p}')"
  echo "  Plan contratado: $PLAN Mbps -> obtienes $PCT%"
  [ "$PCT" -lt 50 ] && HALLAZGOS+=("Obtienes solo $PCT% del plan. Repite con cable al router: si por cable llega cerca del plan, el problema es el WiFi; si no, es la línea de Movistar.")
fi

# ---------------------------------------------------------------- Diagnóstico
titulo "DIAGNÓSTICO"
if [ "${#HALLAZGOS[@]}" -eq 0 ]; then
  echo "Sin problemas claros ahora. Si la lentitud es en horario punta (19-23 h), repite a esa hora."
else
  i=1; for h in "${HALLAZGOS[@]}"; do echo "$i. $h"; i=$((i + 1)); done
fi
echo; echo "Soluciones detalladas: GUIA-WIFI-MOVISTAR.md"
echo "Informe guardado en: $INFORME"
