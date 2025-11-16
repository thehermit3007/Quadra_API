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
    echo "Obteniendo tasas BCV desde $BCV_URL..."
    
    local contenido=$(curl -s --retry 3 --connect-timeout 10 -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" "$BCV_URL")
    
    if [ -z "$contenido" ]; then
        echo "Error: No se pudo obtener contenido de BCV"
        return 1
    fi
    
    # Método más robusto para extraer tasas
    local tasa_dolar=$(echo "$contenido" | grep -oP 'USD</span>\s*</strong>\s*</div>\s*<div[^>]*>\s*<strong[^>]*>\s*\K[0-9,]+' | head -1 | tr ',' '.')
    local tasa_euro=$(echo "$contenido" | grep -oP 'EUR</span>\s*</strong>\s*</div>\s*<div[^>]*>\s*<strong[^>]*>\s*\K[0-9,]+' | head -1 | tr ',' '.')
    
    # Si falla el método anterior, intentar método alternativo
    if [ -z "$tasa_dolar" ]; then
        tasa_dolar=$(echo "$contenido" | grep -A $LINEA_DOLAR_BCV 'Dólar' | tail -1 | sed -n 's/.*<strong>\([0-9,]\+\)<\/strong>.*/\1/p' | tr ',' '.')
    fi
    
    if [ -z "$tasa_euro" ]; then
        tasa_euro=$(echo "$contenido" | grep -A $LINEA_EURO_BCV 'Euro' | tail -1 | sed -n 's/.*<strong>\([0-9,]\+\)<\/strong>.*/\1/p' | tr ',' '.')
    fi
    
    echo "Tasa dólar cruda: $tasa_dolar"
    echo "Tasa euro cruda: $tasa_euro"
    
    # Validar tasas obtenidas
    if [[ -n "$tasa_dolar" && -n "$tasa_euro" ]] && 
       [[ "$tasa_dolar" =~ ^[0-9]+(\.[0-9]+)?$ ]] && 
       [[ "$tasa_euro" =~ ^[0-9]+(\.[0-9]+)?$ ]] && 
       [[ "$tasa_dolar" != "0" && "$tasa_euro" != "0" ]]; then
        
        rates_ref=("$tasa_dolar" "$tasa_euro")
        
        # Guardar en cache
        echo "{\"dolar\":\"$tasa_dolar\",\"euro\":\"$tasa_euro\",\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" > $CACHE_BCV
        echo "Tasas BCV guardadas en cache: USD=$tasa_dolar, EUR=$tasa_euro"
        return 0
    else
        echo "Error: Tasas BCV inválidas o vacías"
        return 1
    fi
}

cargar_tasas_bcv_cache() {
    local -n rates_ref=$1
    if [[ -f $CACHE_BCV ]]; then
        echo "Cargando tasas BCV desde cache..."
        local dolar=$(jq -r '.dolar // empty' $CACHE_BCV 2>/dev/null)
        local euro=$(jq -r '.euro // empty' $CACHE_BCV 2>/dev/null)
        
        # Verificar que los valores del cache sean válidos
        if [[ -n "$dolar" && -n "$euro" ]] && 
           [[ "$dolar" =~ ^[0-9]+(\.[0-9]+)?$ ]] && 
           [[ "$euro" =~ ^[0-9]+(\.[0-9]+)?$ ]] && 
           [[ "$dolar" != "0" && "$euro" != "0" ]]; then
            
            rates_ref=("$dolar" "$euro")
            echo "Cache BCV cargado: USD=$dolar, EUR=$euro"
            return 0
        else
            echo "Cache BCV contiene valores inválidos"
        fi
    else
        echo "No existe archivo de cache BCV"
    fi
    return 1
}

obtener_tasa_binance() {
    echo "Obteniendo tasa Binance..."
    
    local response=$(curl -s -X POST "https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search" \
        -H "Content-Type: application/json" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        -H "Accept-Encoding: gzip" \
        -d '{"page":1,"rows":10,"asset":"USDT","tradeType":"BUY","fiat":"VES"}' 2>/dev/null)
    
    if [ -z "$response" ]; then
        echo "Error: No se pudo obtener respuesta de Binance"
        echo "0"
        return 1
    fi
    
    # Verificar si la respuesta está comprimida
    if echo "$response" | head -c 2 | grep -q '\x1f\x8b'; then
        response=$(echo "$response" | gunzip 2>/dev/null || echo "$response")
    fi
    
    local tasa=$(echo "$response" | jq -r '.data | map(select(.adv.tradeMethods[0].tradeMethodName == "Bs.")) | [.[] | .adv.price] | map(tonumber?) | if length > 0 then (add / length) else 0 end' 2>/dev/null || echo "0")
    
    # Validar que la tasa sea un número válido
    if [[ "$tasa" =~ ^[0-9]+(\.[0-9]+)?$ ]] && [[ "$tasa" != "0" ]]; then
        echo "Tasa Binance obtenida: $tasa"
        echo "$tasa"
    else
        echo "Error: Tasa Binance inválida: $tasa"
        echo "0"
        return 1
    fi
}

cargar_json_existente() {
    local -n dolar_ref=$1 euro_ref=$2 usdt_ref=$3 timestamp_ref=$4 bcv_source_ref=$5
    
    if [[ -f $ARCHIVO_SALIDA ]]; then
        echo "Cargando datos existentes del JSON..."
        dolar_ref=$(jq -r '.rates.USD // "0"' $ARCHIVO_SALIDA 2>/dev/null || echo "0")
        euro_ref=$(jq -r '.rates.EUR // "0"' $ARCHIVO_SALIDA 2>/dev/null || echo "0")
        usdt_ref=$(jq -r '.rates.USDT // "0"' $ARCHIVO_SALIDA 2>/dev/null || echo "0")
        timestamp_ref=$(jq -r '.timestamp // empty' $ARCHIVO_SALIDA 2>/dev/null || echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")
        bcv_source_ref=$(jq -r '.cache_info.bcv_source // "unknown"' $ARCHIVO_SALIDA 2>/dev/null || echo "unknown")
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
    
    # Manejar tasas BCV
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
            echo "✗ Falló la obtención en vivo de BCV, intentando cache..."
            if cargar_tasas_bcv_cache rates_bcv; then
                dolar="${rates_bcv[0]}"
                euro="${rates_bcv[1]}"
                bcv_source="cache_fallback"
                echo "✓ Tasas BCV cargadas desde cache (fallback)"
            else
                bcv_source="live_failed"
                echo "✗ No se pudieron obtener tasas BCV, manteniendo valores anteriores"
            fi
        fi
    else
        echo "Fuera de horario BCV, usando cache si es necesario..."
        # Solo actualizar BCV si los valores actuales son inválidos
        if [[ "$dolar" == "0" || "$euro" == "0" || "$dolar" == "" || "$euro" == "" ]]; then
            echo "Valores BCV actuales inválidos, intentando cargar cache..."
            if cargar_tasas_bcv_cache rates_bcv; then
                dolar="${rates_bcv[0]}"
                euro="${rates_bcv[1]}"
                bcv_source="cache_initial"
                echo "✓ Tasas BCV inicializadas desde cache"
            else
                bcv_source="no_cache"
                echo "✗ No hay cache disponible, manteniendo valores actuales"
            fi
        else
            bcv_source="existing_data"
            echo "✓ Manteniendo valores BCV existentes"
        fi
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
