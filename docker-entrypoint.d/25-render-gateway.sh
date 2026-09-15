#!/bin/sh
set -eu

: "${BACKEND_URL:?BACKEND_URL is required, e.g. http://traffic-markering-back:8090}"
: "${FRONTEND_URL:?FRONTEND_URL is required, e.g. http://traffic-markering-front:80}"

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
export CACHE_TTL="${CACHE_TTL:-10m}"

envsubst '${PORT} ${BACKEND_URL} ${FRONTEND_URL} ${CACHE_TTL}' \
    < /etc/nginx/gateway.conf.template \
    > /etc/nginx/conf.d/default.conf

echo "gateway: :$PORT -> /api/** => $BACKEND_URL, /** => $FRONTEND_URL, cache ttl $CACHE_TTL"
