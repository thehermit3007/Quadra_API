#!/bin/bash

# Configuración
readonly BCV_URL="https://bcv.org.ve"
readonly ARCHIVO_SALIDA="data.json"
readonly CACHE_BCV="bcv_cache.json"
readonly LINEA_DOLAR_BCV=7
readonly LINEA_EURO_BCV=3

debe_actualizar_bcv() {
    local hora_actual=$(date -u +%H)
    [[ $hora_actual == "04" || $hora_actual == "12" ]]
}

obtener_tasas_bcv() {
    local -n rates_ref=$1
    local contenido=$(curl -s --retry 3 --connect-timeout 10 "$BCV_URL")
    local tasa_dolar=$(echo "$contenido" | grep -A $LINEA_DOLAR_BCV 'Dólar' | tail -1 | sed -n 's/.*<strong>\([0-9,]\+\)<\/strong>.*/\1/p' | tr ',' '.')
    local tasa_euro=$(echo "$contenido" | grep -A $LINEA_EURO_BCV 'Euro' | tail -1 | sed -n 's/.*<strong>\([0-9,]\+\)<\/strong>.*/\1/p' | tr ',' '.')
    
    rates_ref=("$tasa_dolar" "$tasa_euro")
    
    # Guardar en cache SOLO si se obtuvieron tasas válidas
    if [ -n "$tasa_dolar" ] && [ -n "$tasa_euro" ] && [ "$tasa_dolar" != "0" ] && [ "$tasa_euro" != "0" ]; then
        echo "{\"dolar\":\"$tasa_dolar\",\"euro\":\"$tasa_euro\",\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" > $CACHE_BCV
    fi
}

cargar_tasas_bcv_cache() {
    local -n rates_ref=$1
    if [[ -f $CACHE_BCV ]]; then
        local dolar=$(jq -r '.dolar' $CACHE_BCV 2>/dev/null || echo "0")
        local euro=$(jq -r '.euro' $CACHE_BCV 2>/dev/null || echo "0")
        rates_ref=("$dolar" "$euro")
        return 0
    fi
    return 1
}

obtener_tasa_binance() {
    curl -s -X POST "https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search" \
        -H "Content-Type: application/json" \
        -H "Accept-Encoding: gzip" \
        -d '{"page":1,"rows":3,"asset":"USDT","tradeType":"BUY","fiat":"VES"}' | \
        gunzip | jq '.' | grep price | \
        awk 'NR==3 || NR==7 || NR==11 {split($0, a, "\""); sum += a[4]; count++} END {if(count>0) print sum/count; else print "0"}'
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
    
    # Inicializar arrays
    rates_bcv=()
    
    # Obtener tasas BCV (desde cache o live)
    if debe_actualizar_bcv; then
        # Solo en horarios BCV: intentar actualizar
        obtener_tasas_bcv rates_bcv
        bcv_source="live"
    else
        # Fuera de horarios BCV: solo usar cache, NUNCA sobrescribir
        if cargar_tasas_bcv_cache rates_bcv; then
            bcv_source="cache"
        else
            # Si no hay cache, mantener valores anteriores (no poner "0")
            bcv_source="no_cache"
            # No modificar rates_bcv, se mantiene vacío
        fi
    fi
    
    # Obtener tasa Binance
    usdt=$(obtener_tasa_binance)
    
    # Asignar valores (usar valores existentes si no hay nuevos)
    dolar="${rates_bcv[0]}"
    euro="${rates_bcv[1]}"
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Crear JSON de salida
    crear_json_salida "$dolar" "$euro" "$usdt" "$timestamp" "$bcv_source"
}

main "$@"
