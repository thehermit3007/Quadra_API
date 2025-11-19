#!/bin/bash

# Configuración
readonly BCV_URL="https://bcv.org.ve"
readonly ARCHIVO_SALIDA="data.json"
readonly LINEA_DOLAR_BCV=7
readonly LINEA_EURO_BCV=3

debe_actualizar_bcv() {
    local hora_actual=$(TZ='America/Caracas' date +%H)
    [[ $hora_actual == "04" || $hora_actual == "12" ]]
}

obtener_tasas_bcv() {
    local -n rates_ref=$1
    local contenido=$(curl -s --retry 3 --connect-timeout 10 "$BCV_URL")
    local tasa_dolar=$(echo "$contenido" | grep -A $LINEA_DOLAR_BCV 'Dólar' | tail -1 | sed -n 's/.*<strong>\([0-9,]\+\)<\/strong>.*/\1/p' | tr ',' '.')
    local tasa_euro=$(echo "$contenido" | grep -A $LINEA_EURO_BCV 'Euro' | tail -1 | sed -n 's/.*<strong>\([0-9,]\+\)<\/strong>.*/\1/p' | tr ',' '.')
    
    rates_ref=("$tasa_dolar" "$tasa_euro")
    
    if [ -n "$tasa_dolar" ] && [ -n "$tasa_euro" ] && [ "$tasa_dolar" != "0" ] && [ "$tasa_euro" != "0" ]; then
        return 0
    fi
    return 1
}

obtener_tasa_binance() {
    local tasa=$(curl -s -X POST "https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search" \
        -H "Content-Type: application/json" \
        -H "Accept-Encoding: gzip" \
        -d '{"page":1,"rows":3,"asset":"USDT","tradeType":"BUY","fiat":"VES"}' | \
        gunzip | jq '.' | grep price | \
        awk 'NR==3 || NR==7 || NR==11 {split($0, a, "\""); sum += a[4]; count++} END {if(count>0) print sum/count; else print "0"}')
    
    echo "${tasa:-0}"
}

# CARGAR DATOS EXISTENTES PARA PRESERVAR
cargar_json_existente() {
    local -n dolar_ref=$1 euro_ref=$2 usdt_ref=$3 timestamp_ref=$4 bcv_source_ref=$5
    
    if [[ -f $ARCHIVO_SALIDA ]]; then
        dolar_ref=$(jq -r '.rates.USD' $ARCHIVO_SALIDA 2>/dev/null || echo "0")
        euro_ref=$(jq -r '.rates.EUR' $ARCHIVO_SALIDA 2>/dev/null || echo "0")
        usdt_ref=$(jq -r '.rates.USDT' $ARCHIVO_SALIDA 2>/dev/null || echo "0")
        timestamp_ref=$(jq -r '.timestamp' $ARCHIVO_SALIDA 2>/dev/null || echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
        bcv_source_ref=$(jq -r '.cache_info.bcv_source' $ARCHIVO_SALIDA 2>/dev/null || echo "unknown")
        return 0
    fi
    return 1
}

crear_json_salida() {
    local dolar=$1 euro=$2 usdt=$3 timestamp=$4 bcv_source=$5
    
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
    echo "Hora actual UTC: $(date -u +"%H:%M")"
    
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
    if [[ "$nueva_tasa_binance" != "0" ]]; then
        usdt="$nueva_tasa_binance"
        echo "Binance actualizado: $usdt"
    else
        echo "Manteniendo tasa Binance anterior: $usdt"
    fi
    
    # Manejar tasas BCV según horario
    echo "--- MANEJANDO TASAS BCV ---"
    rates_bcv=("" "")
    
    if debe_actualizar_bcv; then
        echo "Horario BCV detectado, intentando actualizar..."
        if obtener_tasas_bcv rates_bcv; then
            dolar="${rates_bcv[0]}"
            euro="${rates_bcv[1]}"
            bcv_source="live"
            echo "✓ Tasas BCV actualizadas desde fuente en vivo"
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
}

main "$@"
