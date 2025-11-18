#!/bin/bash

# Configuración
readonly BCV_URL="https://bcv.org.ve"
readonly ARCHIVO_SALIDA="data.json"
readonly LINEA_DOLAR_BCV=7
readonly LINEA_EURO_BCV=3

debe_actualizar_bcv() {
    local hora_actual=$(date -u +%H)
    [[ $hora_actual == "08" || $hora_actual == "16" ]]
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
    # MANTENIENDO LA LÓGICA ORIGINAL DE BINANCE
    local tasa=$(curl -s -X POST "https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search" \
        -H "Content-Type: application/json" \
        -H "Accept-Encoding: gzip" \
        -d '{"page":1,"rows":3,"asset":"USDT","tradeType":"BUY","fiat":"VES"}' | \
        gunzip | jq '.' | grep price | \
        awk 'NR==3 || NR==7 || NR==11 {split($0, a, "\""); sum += a[4]; count++} END {if(count>0) print sum/count; else print "0"}')
    
    # Validar que la tasa no esté vacía
    echo "${tasa:-0}"
}

actualizar_campo_json() {
    local campo="$1"
    local valor="$2"
    local temp_file=$(mktemp)
    
    jq --arg campo "$campo" --arg valor "$valor" '.rates[$campo] = $valor' $ARCHIVO_SALIDA > "$temp_file" && mv "$temp_file" $ARCHIVO_SALIDA
}

actualizar_timestamp_json() {
    local temp_file=$(mktemp)
    jq --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '.timestamp = $timestamp' $ARCHIVO_SALIDA > "$temp_file" && mv "$temp_file" $ARCHIVO_SALIDA
}

actualizar_fuente_bcv_json() {
    local fuente="$1"
    local temp_file=$(mktemp)
    jq --arg fuente "$fuente" '.cache_info.bcv_source = $fuente' $ARCHIVO_SALIDA > "$temp_file" && mv "$temp_file" $ARCHIVO_SALIDA
}

inicializar_json() {
    if [[ ! -f $ARCHIVO_SALIDA ]]; then
        cat > $ARCHIVO_SALIDA << EOF
{
  "status": "success",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "base_currency": "USD/EUR/USDT",
  "target_currency": "BS / VES",
  "rates": {
    "USD": "0",
    "EUR": "0",
    "USDT": "0"
  },
  "cache_info": {
    "bcv_source": "initial"
  }
}
EOF
    fi
}

main() {
    echo "=== INICIANDO ACTUALIZACIÓN DE TASAS ==="
    echo "Hora actual UTC: $(date -u +"%H:%M")"
    
    # Inicializar JSON si no existe
    inicializar_json
    
    # Actualizar Binance (SIEMPRE)
    echo "--- ACTUALIZANDO BINANCE ---"
    local nueva_tasa_binance=$(obtener_tasa_binance)
    if [[ "$nueva_tasa_binance" != "0" ]]; then
        actualizar_campo_json "USDT" "$nueva_tasa_binance"
        echo "Binance actualizado: $nueva_tasa_binance"
    else
        echo "Manteniendo tasa Binance anterior"
    fi
    
    # Manejar BCV según horario
    echo "--- MANEJANDO TASAS BCV ---"
    
    if debe_actualizar_bcv; then
        echo "Horario BCV detectado, intentando actualizar..."
        local rates_bcv=("" "")
        if obtener_tasas_bcv rates_bcv; then
            actualizar_campo_json "USD" "${rates_bcv[0]}"
            actualizar_campo_json "EUR" "${rates_bcv[1]}"
            actualizar_fuente_bcv_json "live"
            echo "✓ Tasas BCV actualizadas desde fuente en vivo"
        else
            actualizar_fuente_bcv_json "live_failed"
            echo "✗ Falló la obtención en vivo de BCV, manteniendo valores anteriores"
        fi
    else
        echo "Fuera de horario BCV, no se actualizan tasas BCV"
        actualizar_fuente_bcv_json "no_update"
    fi
    
    # Actualizar timestamp siempre
    actualizar_timestamp_json
    
    echo "=== ACTUALIZACIÓN COMPLETADA ==="
    echo "Contenido final:"
    cat $ARCHIVO_SALIDA
}

main "$@"
