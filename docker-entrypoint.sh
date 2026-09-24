#!/bin/sh
set -eu

: "${BACKEND_URL:?BACKEND_URL is required, e.g. http://traffic-markering-back.railway.internal:8090}"
: "${FRONTEND_URL:?FRONTEND_URL is required, e.g. http://traffic-markering-front.railway.internal:80}"

normalize_url() {
    url="${1%/}"
    case "$url" in
        http://*|https://*) ;;
        *) url="http://$url" ;;
    esac
    printf '%s' "$url"
}

export BACKEND_URL="$(normalize_url "$BACKEND_URL")"
export FRONTEND_URL="$(normalize_url "$FRONTEND_URL")"
export PORT="${PORT:-80}"

# Если контейнеру передали команду (например, caddy validate), выполняем её
# с уже нормализованным окружением вместо запуска сервера.
if [ "$#" -gt 0 ]; then
    exec "$@"
fi

echo "gateway: :$PORT -> /api/** => $BACKEND_URL, /** => $FRONTEND_URL"

caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
