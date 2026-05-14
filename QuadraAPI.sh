#!/bin/bash

# Configuración
readonly BCV_URL="https://www.bcv.org.ve"
readonly ARCHIVO_SALIDA="data.json"
readonly UMBRAL_CAMBIO=0.1  # 10% de cambio mínimo para considerar desactualizado

# Función para limpiar y normalizar números (espacios + coma a punto)
limpiar_y_normalizar() {
    local numero="$1"
    numero=$(echo "$numero" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
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
    
    local dolar_actual_num=$(normalizar_numero "$tasa_dolar_actual")
    local euro_actual_num=$(normalizar_numero "$tasa_euro_actual")
    local dolar_json_num=$(normalizar_numero "$tasa_dolar_json")
    local euro_json_num=$(normalizar_numero "$tasa_euro_json")
    
    echo "DEBUG - Tasas normalizadas:"
    echo "DEBUG - USD Actual: $dolar_actual_num | USD JSON: $dolar_json_num"
    echo "DEBUG - EUR Actual: $euro_actual_num | EUR JSON: $euro_json_num"
    
    if [[ -z "$dolar_json_num" || "$dolar_json_num" == "0" || \
          -z "$euro_json_num" || "$euro_json_num" == "0" ]]; then
        echo "✓ Tasas BCV en JSON inválidas, se requiere actualización"
        return 0
    fi
    
    local diff_dolar=$(echo "scale=4; (($dolar_actual_num - $dolar_json_num) / $dolar_json_num) * 100" | bc 2>/dev/null | sed 's/-//')
    local diff_euro=$(echo "scale=4; (($euro_actual_num - $euro_json_num) / $euro_json_num) * 100" | bc 2>/dev/null | sed 's/-//')
    
    echo "DEBUG - Diferencia USD: ${diff_dolar}% | EUR: ${diff_euro}%"
    
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
    local contenido=$(curl -ksl --retry 3 --connect-timeout 10 "$BCV_URL")
    
    if [ -z "$contenido" ]; then
        echo "ERROR: No se pudo obtener contenido del BCV" >&2
        return 1
    fi
    
    # Extraer tasas usando los IDs específicos del HTML actual
    local tasa_dolar=$(echo "$contenido" | grep -A 20 'id="dolar"' | grep -o '<strong class="strong-tb">[^<]*</strong>' | sed 's/<[^>]*>//g' | head -1)
    local tasa_euro=$(echo "$contenido" | grep -A 20 'id="euro"' | grep -o '<strong class="strong-tb">[^<]*</strong>' | sed 's/<[^>]*>//g' | head -1)
    
    # Fallback por si no encuentra con IDs
    if [ -z "$tasa_dolar" ] || [ -z "$tasa_euro" ]; then
        local todas_tasas=$(echo "$contenido" | grep -o '<strong class="strong-tb">[^<]*</strong>' | sed 's/<[^>]*>//g')
        tasa_euro=$(echo "$todas_tasas" | sed -n '1p')
        tasa_dolar=$(echo "$todas_tasas" | sed -n '2p')
    fi
    
    rates_ref=("$tasa_dolar" "$tasa_euro")
    
    if [ -n "$tasa_dolar" ] && [ -n "$tasa_euro" ] && [ "$tasa_dolar" != "0" ] && [ "$tasa_euro" != "0" ]; then
        return 0
    fi
    
    echo "ERROR: No se pudieron extraer tasas válidas del BCV" >&2
    return 1
}

obtener_tasa_binance() {
    local response=$(curl -s -X POST "https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search" \
        -H "Content-Type: application/json" \
        -H "Accept-Encoding: gzip" \
        -d '{"page":1,"rows":3,"asset":"USDT","tradeType":"BUY","fiat":"VES"}')
    
    if echo "$response" | file - | grep -q gzip; then
        response=$(echo "$response" | gunzip 2>/dev/null)
    fi
    
    local tasa=$(echo "$response" | jq -r '.data[].adv.price' 2>/dev/null | \
        awk 'NR==1 || NR==2 || NR==3 {sum+=$1; count++} END {if(count>0) printf "%.3f", sum/count; else print "0"}')
    
    echo "${tasa:-0}"
}

# CARGAR DATOS EXISTENTES PARA PRESERVAR
cargar_json_existente() {
    local -n dolar_ref=$1 euro_ref=$2 usdt_ref=$3 timestamp_ref=$4 bcv_source_ref=$5
    
    if [[ -f $ARCHIVO_SALIDA ]]; then
        dolar_ref=$(jq -r '.rates.USD' $ARCHIVO_SALIDA 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "0")
        euro_ref=$(jq -r '.rates.EUR' $ARCHIVO_SALIDA 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "0")
        usdt_ref=$(jq -r '.rates.USDT' $ARCHIVO_SALIDA 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "0")
        timestamp_ref=$(jq -r '.timestamp' $ARCHIVO_SALIDA 2>/dev/null || echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
        bcv_source_ref=$(jq -r '.cache_info.bcv_source' $ARCHIVO_SALIDA 2>/dev/null || echo "unknown")
        
        dolar_ref=$(limpiar_y_normalizar "$dolar_ref")
        euro_ref=$(limpiar_y_normalizar "$euro_ref")
        usdt_ref=$(limpiar_y_normalizar "$usdt_ref")
        
        return 0
    fi
    return 1
}

crear_json_salida() {
    local dolar=$1 euro=$2 usdt=$3 timestamp=$4 bcv_source=$5
    
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
}

main() {
    local rates_bcv euro dolar usdt timestamp bcv_source
    
    echo "=== INICIANDO ACTUALIZACIÓN DE TASAS ==="
    echo "Hora actual Venezuela: $(TZ='America/Caracas' date)"
    
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
    
    echo "--- ACTUALIZANDO BINANCE ---"
    local nueva_tasa_binance=$(obtener_tasa_binance)
    if [[ "$nueva_tasa_binance" != "0" && "$nueva_tasa_binance" != "0.000" ]]; then
        usdt="$nueva_tasa_binance"
        echo "Binance actualizado: $usdt"
    else
        echo "Manteniendo tasa Binance anterior: $usdt"
    fi
    
    echo "--- MANEJANDO TASAS BCV ---"
    rates_bcv=("" "")
    local actualizar_bcv_horario=$(debe_actualizar_bcv)
    
    if $actualizar_bcv_horario; then
        echo "Horario BCV detectado (4:00 AM, 9:00 AM o 12:00 PM), obteniendo tasas actuales..."
        if obtener_tasas_bcv rates_bcv; then
            local tasa_dolar_actual="${rates_bcv[0]}"
            local tasa_euro_actual="${rates_bcv[1]}"
            
            echo "Tasas BCV obtenidas - USD: $tasa_dolar_actual, EUR: $tasa_euro_actual"
            echo "Tasas JSON actuales - USD: $dolar, EUR: $euro"
            
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
    
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    crear_json_salida "$dolar" "$euro" "$usdt" "$timestamp" "$bcv_source"
    
    echo "=== ACTUALIZACIÓN COMPLETADA ==="
    echo "USD: $dolar"
    echo "EUR: $euro" 
    echo "USDT: $usdt"
    echo "Fuente BCV: $bcv_source"
    echo "Timestamp: $timestamp"
}

main "$@"
