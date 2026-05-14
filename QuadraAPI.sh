#!/bin/bash

# Configuración
readonly BCV_URL="https://www.bcv.org.ve"
readonly ARCHIVO_SALIDA="data.json"
readonly UMBRAL_CAMBIO=0.1  # 10% de cambio mínimo para considerar desactualizado

# Función para limpiar y normalizar números (espacios + coma a punto)
limpiar_y_normalizar() {
    local numero="$1"
    # Eliminar espacios al inicio y final
    numero=$(echo "$numero" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # Cambiar coma por punto
    echo "$numero" | tr ',' '.'
}

# Función para normalizar formato numérico (mantener compatibilidad)
normalizar_numero() {
    local numero="$1"
    limpiar_y_normalizar "$numero"
}

# Función para verificar si estamos en horario BCV
debe_actualizar_bcv() {
    local hora_actual=$(TZ='America/Caracas' date +%-H)
    [[ $hora_actual == "4" || $hora_actual == "9" || $hora_actual == "12" ]]
}

# Función: Validar si las tasas BCV están desactualizadas
validar_tasas_desactualizadas() {
    local tasa_dolar_actual=$1
    local tasa_euro_actual=$2
    local tasa_dolar_json=$3
    local tasa_euro_json=$4
    
    # Limpiar y normalizar (elimina espacios Y cambia coma a punto)
    local dolar_actual_num=$(limpiar_y_normalizar "$tasa_dolar_actual")
    local euro_actual_num=$(limpiar_y_normalizar "$tasa_euro_actual")
    local dolar_json_num=$(limpiar_y_normalizar "$tasa_dolar_json")
    local euro_json_num=$(limpiar_y_normalizar "$tasa_euro_json")
    
    echo "DEBUG - Tasas limpiadas:"
    echo "DEBUG - USD Actual: '$dolar_actual_num' | USD JSON: '$dolar_json_num'"
    echo "DEBUG - EUR Actual: '$euro_actual_num' | EUR JSON: '$euro_json_num'"
    
    # Validar que las tasas actuales sean números válidos
    if ! [[ "$dolar_actual_num" =~ ^[0-9]+([.][0-9]+)?$ ]] || \
       ! [[ "$euro_actual_num" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo "✗ Tasas BCV no son números válidos después de limpiar"
        return 1
    fi
    
    # Si alguna tasa JSON es 0 o vacía, considerar desactualizado
    if [[ -z "$dolar_json_num" || "$dolar_json_num" == "0" || \
          -z "$euro_json_num" || "$euro_json_num" == "0" ]]; then
        echo "✓ Tasas BCV en JSON inválidas, se requiere actualización"
        return 0
    fi
    
    # Calcular diferencia porcentual
    local diff_dolar=$(echo "scale=4; (($dolar_actual_num - $dolar_json_num) / $dolar_json_num) * 100" | bc 2>/dev/null | sed 's/-//')
    local diff_euro=$(echo "scale=4; (($euro_actual_num - $euro_json_num) / $euro_json_num) * 100" | bc 2>/dev/null | sed 's/-//')
    
    echo "DEBUG - Diferencia USD: ${diff_dolar}% | EUR: ${diff_euro}%"
    
    # Si el cambio es mayor al umbral, considerar desactualizado
    if (( $(echo "$diff_dolar > $UMBRAL_CAMBIO" | bc -l 2>/dev/null) )) || \
       (( $(echo "$diff_euro > $UMBRAL_CAMBIO" | bc -l 2>/dev/null) )); then
        echo "✓ Tasas BCV desactualizadas (cambio > ${UMBRAL_CAMBIO}%), se requiere actualización"
        return 0
    else
        echo "✓ Tasas BCV actualizadas (cambio ≤ ${UMBRAL_CAMBIO}%), no se requiere actualización"
        return 1
    fi
}

obtener_tasas_bcv() {
    local -n rates_ref=$1
    echo "DEBUG - Descargando HTML del BCV..."
    local contenido=$(curl -ksl --retry 3 --connect-timeout 10 "$BCV_URL")
    
    # Verificar si se obtuvo contenido
    if [ -z "$contenido" ]; then
        echo "ERROR: No se pudo obtener contenido del BCV"
        return 1
    fi
    
    echo "DEBUG - HTML descargado (tamaño: ${#contenido} bytes)"
    
    # Extraer tasas usando los IDs específicos del HTML actual
    # Buscar el contenedor del dólar que tiene id="dolar"
    local tasa_dolar=$(echo "$contenido" | grep -A 20 'id="dolar"' | grep -o '<strong class="strong-tb">[^<]*</strong>' | sed 's/<[^>]*>//g' | head -1)
    
    # Buscar el contenedor del euro que tiene id="euro"
    local tasa_euro=$(echo "$contenido" | grep -A 20 'id="euro"' | grep -o '<strong class="strong-tb">[^<]*</strong>' | sed 's/<[^>]*>//g' | head -1)
    
    # Fallback: buscar cualquier strong con class strong-tb
    if [ -z "$tasa_dolar" ] || [ -z "$tasa_euro" ]; then
        echo "DEBUG - Usando fallback: buscando strong class='strong-tb'"
        local todas_tasas=$(echo "$contenido" | grep -o '<strong class="strong-tb">[^<]*</strong>' | sed 's/<[^>]*>//g')
        
        # En el HTML, el EUR aparece primero, luego el USD
        tasa_euro=$(echo "$todas_tasas" | sed -n '1p')
        tasa_dolar=$(echo "$todas_tasas" | sed -n '2p')
    fi
    
    # Limpiar las tasas encontradas
    if [ -n "$tasa_dolar" ]; then
        tasa_dolar=$(limpiar_y_normalizar "$tasa_dolar")
    fi
    
    if [ -n "$tasa_euro" ]; then
        tasa_euro=$(limpiar_y_normalizar "$tasa_euro")
    fi
    
    rates_ref=("$tasa_dolar" "$tasa_euro")
    
    echo "DEBUG - Tasas encontradas: USD='$tasa_dolar', EUR='$tasa_euro'"
    
    if [ -n "$tasa_dolar" ] && [ -n "$tasa_euro" ] && [ "$tasa_dolar" != "0" ] && [ "$tasa_euro" != "0" ]; then
        echo "✓ Tasas BCV obtenidas correctamente"
        return 0
    fi
    
    echo "ERROR: No se pudieron extraer tasas válidas del BCV"
    return 1
}

obtener_tasa_binance() {
    echo "DEBUG - Consultando Binance..."
    local response=$(curl -s -X POST "https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search" \
        -H "Content-Type: application/json" \
        -H "Accept-Encoding: gzip" \
        -d '{"page":1,"rows":3,"asset":"USDT","tradeType":"BUY","fiat":"VES"}')
    
    # Verificar si la respuesta está comprimida
    if echo "$response" | file - | grep -q gzip; then
        response=$(echo "$response" | gunzip 2>/dev/null)
    fi
    
    local tasa=$(echo "$response" | jq -r '.data[].adv.price' 2>/dev/null | \
        awk 'NR==1 || NR==2 || NR==3 {sum+=$1; count++} END {if(count>0) printf "%.3f", sum/count; else print "0"}')
    
    local resultado="${tasa:-0}"
    echo "DEBUG - Tasa Binance: $resultado"
    echo "$resultado"
}

# CARGAR DATOS EXISTENTES PARA PRESERVAR
cargar_json_existente() {
    local -n dolar_ref=$1 euro_ref=$2 usdt_ref=$3 timestamp_ref=$4 bcv_source_ref=$5
    
    if [[ -f $ARCHIVO_SALIDA ]]; then
        echo "DEBUG - Cargando JSON existente desde $ARCHIVO_SALIDA"
        dolar_ref=$(jq -r '.rates.USD' $ARCHIVO_SALIDA 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "0")
        euro_ref=$(jq -r '.rates.EUR' $ARCHIVO_SALIDA 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "0")
        usdt_ref=$(jq -r '.rates.USDT' $ARCHIVO_SALIDA 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "0")
        timestamp_ref=$(jq -r '.timestamp' $ARCHIVO_SALIDA 2>/dev/null || echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
        bcv_source_ref=$(jq -r '.cache_info.bcv_source' $ARCHIVO_SALIDA 2>/dev/null || echo "unknown")
        
        # Limpiar los valores cargados
        dolar_ref=$(limpiar_y_normalizar "$dolar_ref")
        euro_ref=$(limpiar_y_normalizar "$euro_ref")
        usdt_ref=$(limpiar_y_normalizar "$usdt_ref")
        
        echo "DEBUG - Datos cargados: USD=$dolar_ref, EUR=$euro_ref, USDT=$usdt_ref"
        return 0
    fi
    echo "DEBUG - No existe archivo JSON previo"
    return 1
}

crear_json_salida() {
    local dolar=$1 euro=$2 usdt=$3 timestamp=$4 bcv_source=$5
    
    # Asegurar que los valores no tengan espacios
    dolar=$(echo "$dolar" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    euro=$(echo "$euro" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    usdt=$(echo "$usdt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    cat > $ARCHIVO_SALIDA << EOF
{
  "status": "success",
  "timestamp": "$timestamp",
  "base_currency": "USD/EUR/USDT",
  "target_currency": "BS / VES",
  "rates": {
    "USD": "$dolar",
    "EUR": "$euro",
    "USDT": "$usdt"
  },
  "cache_info": {
    "bcv_source": "$bcv_source"
  }
}
EOF
    echo "DEBUG - JSON guardado en $ARCHIVO_SALIDA"
}

main() {
    local rates_bcv euro dolar usdt timestamp bcv_source
    
    echo "=== INICIANDO ACTUALIZACIÓN DE TASAS ==="
    echo "Hora actual Venezuela: $(TZ='America/Caracas' date)"
    echo "Hora actual UTC: $(date -u)"
    
    # Cargar valores existentes del JSON (si existe)
    if ! cargar_json_existente dolar euro usdt timestamp bcv_source; then
        echo "No existe archivo JSON previo, inicializando con valores por defecto"
        dolar="0"
        euro="0"
        usdt="0"
        timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        bcv_source="unknown"
    else
        echo "Datos existentes cargados: USD=$dolar, EUR=$euro, USDT=$usdt"
    fi
    
    # Obtener tasa Binance (SIEMPRE se actualiza)
    echo "--- ACTUALIZANDO BINANCE ---"
    local nueva_tasa_binance=$(obtener_tasa_binance)
    if [[ "$nueva_tasa_binance" != "0" && "$nueva_tasa_binance" != "0.000" ]]; then
        usdt="$nueva_tasa_binance"
        echo "✓ Binance actualizado: $usdt"
    else
        echo "⚠️ Manteniendo tasa Binance anterior: $usdt"
    fi
    
    # Manejar tasas BCV según horario y validación
    echo "--- MANEJANDO TASAS BCV ---"
    rates_bcv=("" "")
    local actualizar_bcv_horario=$(debe_actualizar_bcv)
    
    echo "DEBUG - ¿Estamos en horario BCV? $actualizar_bcv_horario (horas permitidas: 4, 9, 12)"
    
    if $actualizar_bcv_horario; then
        echo "Horario BCV detectado (4:00 AM, 9:00 AM o 12:00 PM), obteniendo tasas actuales..."
        if obtener_tasas_bcv rates_bcv; then
            local tasa_dolar_actual="${rates_bcv[0]}"
            local tasa_euro_actual="${rates_bcv[1]}"
            
            echo "Tasas BCV obtenidas - USD: $tasa_dolar_actual, EUR: $tasa_euro_actual"
            echo "Tasas JSON actuales - USD: $dolar, EUR: $euro"
            
            # Validar si las tasas están desactualizadas
            if validar_tasas_desactualizadas "$tasa_dolar_actual" "$tasa_euro_actual" "$dolar" "$euro"; then
                dolar="$tasa_dolar_actual"
                euro="$tasa_euro_actual"
                bcv_source="live_updated"
                echo "✓ Tasas BCV actualizadas por cambio significativo"
            else
                bcv_source="live_no_change"
                echo "✓ Tasas BCV mantienen valores anteriores (sin cambio significativo)"
            fi
        else
            bcv_source="live_failed"
            echo "✗ Falló la obtención en vivo de BCV, manteniendo valores anteriores"
        fi
    else
        echo "Fuera de horario BCV, no se actualizan tasas BCV"
        bcv_source="no_update"
    fi
    
    # Actualizar timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Crear JSON de salida
    crear_json_salida "$dolar" "$euro" "$usdt" "$timestamp" "$bcv_source"
    
    echo "=== ACTUALIZACIÓN COMPLETADA ==="
    echo "USD: $dolar"
    echo "EUR: $euro" 
    echo "USDT: $usdt"
    echo "Fuente BCV: $bcv_source"
    echo "Timestamp: $timestamp"
    echo ""
    echo "--- JSON GENERADO ---"
    cat "$ARCHIVO_SALIDA"
}

main "$@"
