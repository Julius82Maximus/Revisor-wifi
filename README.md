# Revisor-wifi
Revisa el estado del wifi y entrega un diagnóstico con soluciones (orientado a Movistar Chile).

| Archivo | Para qué |
|---|---|
| `diagnostico-wifi.ps1` | Diagnóstico automático en **Windows**: `powershell -ExecutionPolicy Bypass -File .\diagnostico-wifi.ps1 -PlanMbps 600` |
| `diagnostico-wifi.sh` | Diagnóstico automático en **macOS / Linux**: `bash diagnostico-wifi.sh 600` |
| `GUIA-WIFI-MOVISTAR.md` | Cómo interpretar el resultado y las soluciones paso a paso (incluye cómo reclamar) |

Ambos scripts miden la señal, la banda (2.4/5 GHz), el canal y las redes vecinas, la latencia al router y a Internet, el DNS y la velocidad real. Al final dicen si el problema está **en el WiFi de la casa** o **en la línea de Movistar**, y guardan un informe `.txt`.
