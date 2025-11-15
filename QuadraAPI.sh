#!/bin/bash

# Configuración
readonly BCV_URL="https://bcv.org.ve"
readonly BINANCE_API_URL="https://p2p.binance.com/bapi/c2c/v2/friendly/c2c/adv/search"
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
    echo "Conectando a BCV..."
    local contenido=$(curl -s --retry 3 --connect-timeout 10 "$BCV_URL")
    
    if [ -z "$contenido" ]; then
        echo "Error: No se pudo obtener contenido del BCV"
        rates_ref=("0" "0")
        return 1
    fi
    
    # Extraer tasa del dólar
    local tasa_dolar=$(echo "$contenido" | grep -A $LINEA_DOLAR_BCV 'Dólar' | tail -1 | sed -n 's/.*<strong>\([0-9,]\+\)<\/strong>.*/\1/p' | tr ',' '.')
    # Extraer tasa del euro
    local tasa_euro=$(echo "$contenido" | grep -A $LINEA_EURO_BCV 'Euro' | tail -1 | sed -n 's/.*<strong>\([0-9,]\+\)<\/strong>.*/\1/p' | tr ',' '.')
    
    # Validar que se obtuvieron tasas
    if [ -z "$tasa_dolar" ] || [ -z "$tasa_euro" ]; then
        echo "Error: No se pudieron extraer las tasas del BCV"
        rates_ref=("0" "0")
        return 1
    fi
    
    echo "Tasa dólar extraída: $tasa_dolar"
    echo "Tasa euro extraída: $tasa_euro"
    
    rates_ref=("$tasa_dolar" "$tasa_euro")
    
    # Guardar en cache
    echo "{\"dolar\":\"$tasa_dolar\",\"euro\":\"$tasa_euro\",\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" > $CACHE_BCV
    return 0
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
    echo "Consultando API de Binance..."
    
    # Crear archivo temporal para el request
    local request_file=$(mktemp)
    cat > "$request_file" << EOF
{
    "page": 1,
    "rows": 3,
    "payTypes": [],
    "asset": "USDT",
    "tradeType": "BUY",
    "fiat": "VES",
    "publisherType": null
}
EOF

    # Crear archivo temporal para la respuesta
    local response_file=$(mktemp)
    
    # Hacer la petición
    local http_code=$(curl -s -X POST "$BINANCE_API_URL" \
        -H "Content-Type: application/json" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        -d @"$request_file" \
        --connect-timeout 15 \
        --max-time 20 \
        -w "%{http_code}" \
        -o "$response_file")
    
    # Limpiar archivos temporales
    rm -f "$request_file"
    
    # Leer respuesta
    local response=$(cat "$response_file")
    rm -f "$response_file"
    
    # Verificar código HTTP
    if [ "$http_code" != "200" ]; then
        echo "Error: HTTP $http_code de Binance - $response"
        echo "0"
        return 1
    fi
    
    if [ -z "$response" ]; then
        echo "Error: Respuesta vacía de Binance"
        echo "0"
        return 1
    fi
    
    # Verificar si la respuesta es JSON válido
    if ! echo "$response" | jq -e . >/dev/null 2>&1; then
        echo "Error: Respuesta no es JSON válido de Binance"
        echo "0"
        return 1
    fi
    
    # Verificar si la API devolvié error
    if echo "$response" | jq -e '.code != null' >/dev/null 2>&1; then
        local error_code=$(echo "$response" | jq -r '.code')
        local error_msg=$(echo "$response" | jq -r '.message')
        echo "Error de API Binance: $error_code - $error_msg"
        echo "0"
        return 1
    fi
    
    # Verificar estructura esperada
    if ! echo "$response" | jq -e '.data' >/dev/null 2>&1; then
        echo "Error: Estructura de respuesta Binance inesperada"
        echo "0"
        return 1
    fi
    
    # Verificar que hay datos
    local data_count=$(echo "$response" | jq '.data | length')
    if [ "$data_count" -eq 0 ]; then
        echo "Error: No hay datos disponibles en Binance P2P"
        echo "0"
        return 1
    fi
    
    # Obtener precios con valores por defecto
    local precio1=0
    local precio2=0
    local precio3=0
    
    if [ "$data_count" -ge 1 ]; then
        precio1=$(echo "$response" | jq -r '.data[0].adv.price // "0"' 2>/dev/null)
    fi
    if [ "$data_count" -ge 2 ]; then
        precio2=$(echo "$response" | jq -r '.data[1].adv.price // "0"' 2>/dev/null)
    fi
    if [ "$data_count" -ge 3 ]; then
        precio3=$(echo "$response" | jq -r '.data[2].adv.price // "0"' 2>/dev/null)
    fi
    
    echo "Precios obtenidos: $precio1, $precio2, $precio3"
    
    # Validar que los precios sean números
    if ! [[ "$precio1" =~ ^[0-9.]+$ ]] || ! [[ "$precio2" =~ ^[0-9.]+$ ]] || ! [[ "$precio3" =~ ^[0-9.]+$ ]]; then
        echo "Error: Precios inválidos de Binance"
        echo "0"
        return 1
    fi
    
    # Calcular promedio
    local promedio=$(echo "scale=4; ($precio1 + $precio2 + $precio3) / 3" | bc 2>/dev/null || echo "0")
    echo "Promedio calculado: $promedio"
    echo "$promedio"
}

crear_json_salida() {
    local dolar=$1 euro=$2 usdt=$3 timestamp=$4 bcv_source=$5
    
    # Usar valores por defecto si están vacíos
    dolar=${dolar:-"0"}
    euro=${euro:-"0"} 
    usdt=${usdt:-"0"}
    
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
    local hora_actual=$(date -u +%H)
    
    echo "=== INICIANDO ACTUALIZACIÓN ==="
    echo "Hora actual UTC: $hora_actual"
    echo "Debe actualizar BCV: $(debe_actualizar_bcv && echo 'SÍ' || echo 'NO')"
    
    # Inicializar arrays
    rates_bcv=()
    
    # Obtener tasas BCV (desde cache o live)
    if debe_actualizar_bcv; then
        echo "Actualizando BCV desde live..."
        if ! obtener_tasas_bcv rates_bcv; then
            echo "Falló actualización BCV, intentando cargar cache..."
            if ! cargar_tasas_bcv_cache rates_bcv; then
                echo "No hay cache disponible, usando valores por defecto"
                rates_bcv=("0" "0")
                bcv_source="error"
            else
                bcv_source="cache_fallback"
            fi
        else
            bcv_source="live"
        fi
    else
        echo "Cargando BCV desde cache..."
        if ! cargar_tasas_bcv_cache rates_bcv; then
            echo "No hay cache disponible, usando valores por defecto"
            rates_bcv=("0" "0")
            bcv_source="default"
        else
            bcv_source="cache"
        fi
    fi
    
    echo "Dólar final: ${rates_bcv[0]}"
    echo "Euro final: ${rates_bcv[1]}"
    
    # Obtener tasa Binance
    echo "Obteniendo tasa Binance..."
    usdt=$(obtener_tasa_binance)
    echo "USDT final: $usdt"
    
    # Asignar valores (con valores por defecto)
    dolar="${rates_bcv[0]:-0}"
    euro="${rates_bcv[1]:-0}"
    usdt="${usdt:-0}"
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Crear JSON de salida
    crear_json_salida "$dolar" "$euro" "$usdt" "$timestamp" "$bcv_source"
    
    echo "=== ACTUALIZACIÓN COMPLETADA ==="
    echo "Archivo generado: $ARCHIVO_SALIDA"
}

main "$@"
