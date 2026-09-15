FROM nginx:alpine

ENV PORT=80
ENV CACHE_TTL=10m

COPY nginx/gateway.conf.template /etc/nginx/gateway.conf.template
COPY --chmod=755 docker-entrypoint.d/25-render-gateway.sh /docker-entrypoint.d/25-render-gateway.sh

EXPOSE 80
