# Guía: WiFi lento con Movistar (Chile)

## Paso 0: averiguar dónde está el problema (5 minutos)

La lentitud viene de una de tres partes. Antes de cambiar nada hay que saber cuál:

| Dónde | Síntoma típico | Responsable |
|---|---|---|
| **A. El WiFi de la casa** | Rápido junto al router y lento en otras piezas. Por cable anda bien. | Usted (se arregla en casa) |
| **B. El router de Movistar** | Lento incluso al lado del router, se "pega", mejora un rato al reiniciarlo. | Compartido (se puede pedir el cambio) |
| **C. La línea o red de Movistar** | Lento **también por cable**, o lento todos los días en horario punta (19-23 h). | Movistar (reclamo) |

**Ejecute el diagnóstico automático** en el computador:

- **Windows:** clic derecho en el menú Inicio → *Terminal* (o *PowerShell*), vaya a la carpeta del repositorio y ejecute
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\diagnostico-wifi.ps1 -PlanMbps 600
  ```
  (cambie `600` por los megas de su plan). En Windows 11, si dice que no puede leer el WiFi, active *Configuración → Privacidad → Ubicación*.
- **Mac / Linux:** `bash diagnostico-wifi.sh 600`

El script mide señal, banda, canal, redes vecinas, latencia al router y a Internet, DNS y velocidad, y deja un informe `.txt` en el Escritorio (o en la carpeta personal). Ese informe le sirve también como respaldo si después reclama.

**La prueba decisiva:** conecte un notebook **por cable de red** al router y mida en <https://www.speedtest.net> o en el medidor de Movistar. Si por cable llega cerca de lo contratado, el problema es el WiFi (A o B). Si por cable también es bajo, es la línea (C).

---

## A. Soluciones para el WiFi de la casa (de más a menos efectiva)

### 1. Use la red de 5 GHz
Los routers de fibra de Movistar emiten dos redes: una normal y otra terminada en `-5G` (o una sola red combinada, "Smart WiFi").
- **2.4 GHz:** llega más lejos, pero rara vez entrega más de 50-100 Mbps reales y es la banda más saturada por los vecinos.
- **5 GHz:** entrega 300-600+ Mbps, pero se debilita con muros y losas.

Si el plan es de 300 Mbps o más y usted está a 1-2 piezas del router, **conéctese a la red -5G**. Si el router tiene ambas redes con el mismo nombre y el equipo insiste en 2.4 GHz, separe las bandas (punto 4) y ponga un nombre distinto a cada una.

### 2. Ubique bien el router
Es la mejora gratuita más subestimada:
- **Al centro de la casa y en altura** (sobre un mueble, no en el suelo ni dentro de un mueble cerrado).
- Lejos del microondas, teléfonos inalámbricos, peceras, espejos y muros con armadura (cocina, baños, shaft de ascensor).
- Antenas (si las tiene): una vertical y una horizontal.
- El técnico suele dejarlo donde entra la fibra (a veces un rincón o el living junto a la puerta). Movistar puede reubicar la roseta óptica; también puede dejar el router ahí y llevar la señal con un cable de red hasta un punto de acceso al centro de la casa.

### 3. Cambie el canal WiFi
Si el diagnóstico marca su canal como **congestionado**:
1. Abra `http://192.168.1.1` en el navegador (si no carga, use la puerta de enlace que muestra el script).
2. Usuario y clave: están en la **etiqueta bajo el router** (no son los mismos del WiFi).
3. Menú *WiFi / Red inalámbrica / WLAN*:
   - **2.4 GHz:** canal **1, 6 u 11** (el menos ocupado según el script), ancho de canal **20 MHz**.
   - **5 GHz:** canal **36, 40, 44, 48** o **149-161**, ancho **80 MHz**.
4. Guarde y espere un minuto.

También se puede hacer desde la app **Mi Movistar** (sección *Smart WiFi*), según el modelo de router.

### 4. Ajustes recomendados en el router
- **Seguridad WPA2-AES o WPA2/WPA3.** Evite "WPA/WPA2 mixto con TKIP": limita la velocidad a 54 Mbps.
- **Cambie la clave WiFi** si la ha compartido mucho: un vecino o un equipo olvidado conectado puede estar consumiendo ancho de banda. En la página del router vea *Dispositivos conectados* y quite los desconocidos.
- **Desactive WPS** (seguridad).
- **Separar bandas ("Band Steering" desactivado)** si quiere elegir manualmente 2.4 o 5 GHz.

### 5. Cubra toda la casa con mesh, no con repetidores baratos
Si la casa tiene más de ~80-100 m², dos pisos o muros de hormigón, un solo router no alcanza:
- **Mesh (recomendado):** 2-3 nodos con el mismo nombre de red; el equipo se cambia solo al nodo más cercano. Movistar ofrece sus propios extensores *Smart WiFi* en arriendo; también sirven marcas como TP-Link Deco, Eero o Asus ZenWiFi (busque modelos WiFi 6 o 6E).
- **Ideal:** unir los nodos **por cable de red** ("backhaul cableado"). Si no hay cable, ubique cada nodo a mitad de camino, donde todavía tenga buena señal del router.
- **Evite** los repetidores "de enchufe" baratos: suelen cortar la velocidad a la mitad.
- **PLC / powerline** (internet por el enchufe eléctrico) es una alternativa cuando no se puede tender cable, aunque su rendimiento depende de la instalación eléctrica.

### 6. Revise los propios equipos
- Notebooks o celulares de más de 6-7 años suelen tener WiFi 4 (802.11n): no aprovechan un plan de fibra. El script lo indica ("Estándar"). Un adaptador USB WiFi 6 cuesta poco y resuelve en PC.
- Actualice el controlador de WiFi (Windows: Administrador de dispositivos → Adaptadores de red).
- Para el **televisor, la consola o el PC de escritorio, use cable** cuando se pueda: liberan el WiFi para el resto.
- Pause actualizaciones automáticas, respaldos en la nube (OneDrive, Google Fotos, iCloud) y descargas de juegos mientras necesita velocidad.

### 7. Cambie el DNS (si el script lo marca como lento)
Hace que las páginas "empiecen a cargar" más rápido. En el router (*LAN / DHCP / DNS*) o en el equipo:
- Cloudflare: `1.1.1.1` y `1.0.0.1`
- Google: `8.8.8.8` y `8.8.4.4`

En Windows: *Configuración → Red e Internet → WiFi → Propiedades de hardware → Asignación de servidor DNS → Editar → Manual*.

---

## B. Cuando el problema es el router de Movistar

- **Reinicio correcto:** desenchufe el router 30 segundos y vuelva a enchufarlo. Si debe hacerlo seguido (más de una vez por semana), el equipo está fallando.
- **Luces:** la luz **LOS / PON en rojo o parpadeando** indica un problema de fibra (corresponde visita técnica, no es el WiFi).
- **Router antiguo:** si su router no tiene WiFi 5 (802.11ac) o WiFi 6 (802.11ax), o si contrató un plan más alto después de la instalación, **pida a Movistar el cambio por un modelo actual (WiFi 6)**. Muchas veces lo cambian sin costo si el router no permite alcanzar la velocidad del plan contratado; insista en ese punto.
- **Fibra óptica:** verifique que el cable de fibra (delgado, normalmente verde o azul en la punta) no esté doblado en ángulo agudo ni aplastado por un mueble.
- Si tiene **ADSL/VDSL (cobre)** en vez de fibra, pregunte por la migración a fibra: es el cambio que más mejora la conexión.

---

## C. Cuando el problema es la línea de Movistar: cómo reclamar

1. **Documente:** ejecute el diagnóstico **por cable**, en distintos días y horarios (especialmente 19-23 h), y guarde los informes `.txt` y capturas del medidor de velocidad de Movistar o speedtest.net.
2. **Soporte técnico:** llame a Movistar (desde el teléfono de la cuenta o vía app Mi Movistar) y pida **visita técnica**. **Anote el número de reclamo / ticket.**
3. **Reclamo formal ante la empresa:** si no se resuelve, haga un reclamo por escrito en los canales de Movistar, y guarde el número de ingreso.
4. **SUBTEL:** si la respuesta no llega dentro del plazo o no lo satisface, reclame ante la Subsecretaría de Telecomunicaciones en <https://www.subtel.gob.cl> (sección de reclamos), adjuntando número de reclamo previo y mediciones.
5. **SERNAC:** alternativa o complemento por incumplimiento de lo contratado (Ley 19.496).

**Marco normativo útil:** la **Ley 21.046** (2017), que modificó la Ley General de Telecomunicaciones, establece la obligación de las empresas de garantizar una **velocidad mínima de acceso a Internet**, informarla en el contrato y poner a disposición del usuario una herramienta de medición. Revise en su contrato o en la web de Movistar cuál es la **velocidad mínima garantizada** de su plan (suele ser un porcentaje de la velocidad "hasta" anunciada), y compárela con sus mediciones **por cable**: las mediciones por WiFi no sirven para reclamar porque la empresa las atribuirá a su red interna.

> Nota: verifique en Ley Chile y en la normativa reglamentaria vigente de SUBTEL los plazos exactos de respuesta y los requisitos de medición antes de formalizar el reclamo.

---

## Resumen rápido

1. Ejecute el script y haga la prueba **por cable**.
2. Si por cable va bien → **5 GHz**, ubicación del router, **cambio de canal**, y si la casa es grande, **mesh**.
3. Si el router es antiguo o se reinicia seguido → pida **cambio de router WiFi 6**.
4. Si por cable también va mal → documente y **reclame** (Movistar → SUBTEL), invocando la velocidad mínima garantizada.
