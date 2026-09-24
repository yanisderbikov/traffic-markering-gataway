# traffic-markering-gataway

Входная точка проекта: один публичный адрес, за которым живут бэкенд и фронтенд.
Это Caddy, который по префиксу пути решает, куда отправить запрос:

| Путь | Куда |
|---|---|
| `/api/**` | бэкенд (`BACKEND_URL`) |
| `/v3/api-docs`, `/swagger-ui/**` | бэкенд — Swagger и схема для генерации клиента |
| `/healthz` | сам гейтвей, отвечает `200 ok` |
| всё остальное | фронтенд (`FRONTEND_URL`) |

Адреса бэка и фронта задаются переменными окружения при старте контейнера,
образ пересобирать не нужно.

Соседние репозитории:
`/Users/user/IdeaProjects/traffic-markering-back`,
`/Users/user/IdeaProjects/traffic-markering-front`.

## Переменные окружения

| Переменная | Обязательна | Пример | Зачем |
|---|---|---|---|
| `BACKEND_URL` | да | `http://traffic-markering-back.railway.internal:8090` | куда проксировать `/api/**` |
| `FRONTEND_URL` | да | `http://traffic-markering-front.railway.internal:80` | куда проксировать остальное |
| `PORT` | нет, по умолчанию `80` | `8080` | порт гейтвея внутри контейнера |

Схему можно не писать — подставится `http://`. Слэш на конце адреса срезается.
Без `BACKEND_URL` или `FRONTEND_URL` контейнер не стартует и пишет, чего не хватает.

Адреса могут быть как приватными именами `*.railway.internal`, так и публичными
`https://`-адресами: заголовок `Host` уходит апстриму его собственный, так что
хостинги вроде Railway маршрутизируют запрос правильно. Исходный хост, схема и
IP клиента передаются в `X-Forwarded-Host`, `X-Forwarded-Proto` и
`X-Forwarded-For`; если гейтвей стоит за TLS-терминатором Railway, его
`X-Forwarded-*` доверяются и передаются дальше как есть.

Имя апстрима резолвится на каждое новое соединение, кеша DNS нет. Поэтому
когда бек или фронт переезжают на другой IP при редеплое, гейтвей подхватывает
это сам, без рестарта. Это и есть причина, по которой здесь Caddy, а не nginx:
nginx резолвил `*.railway.internal` один раз при старте, и после каждого деплоя
соседа гейтвей ходил на мёртвый адрес, пока его не перезапустят.

Образец — в `.env.example`. Реальный `.env` в `.gitignore`.

## Railway

Гейтвей, бек и фронт живут в одном проекте Railway и общаются через приватную
сеть. Публичный домен вешается только на гейтвей: TLS терминирует сам Railway
и выдаёт сертификат Let's Encrypt, поэтому в Caddy автоматический HTTPS
выключен и в контейнер приходит обычный HTTP. Переменные гейтвея:

```
BACKEND_URL=http://traffic-markering-back.railway.internal:8090
FRONTEND_URL=http://traffic-markering-front.railway.internal:80
```

Схема `http://`, а не `https://`: внутри приватной сети TLS нет, трафик и так
идёт по WireGuard. Порт — тот, на котором слушает сам контейнер (`8090` у бека,
`80` у фронта), а не 443. `PORT` задавать не нужно, Railway подставит свой;
если он всё же задан руками, порт в настройках домена должен с ним совпадать.

Бек и фронт должны слушать и IPv6 (`::`): Spring Boot делает это по умолчанию,
nginx фронта — через `listen [::]:80;` в его `nginx.conf`.

## Кеша нет

В отличие от прошлой версии на nginx, гейтвей ничего не кеширует: каждый запрос
уходит апстриму. После деплоя фронта новый `index.html` отдаётся сразу.

## Что поменять в беке и фронте

Через гейтвей фронт и API живут на одном origin, поэтому:

- фронт собирается с `VITE_API_URL`, равным публичному адресу гейтвея
  (или тому же домену, на котором открыт сайт);
- в беке `URL_BACK` — публичный адрес гейтвея: из него собираются redirect URI
  для OAuth соцсетей и server url в Swagger;
- в `ALLOWED_ORIGINS` бека достаточно адреса гейтвея.

## Локальный запуск

```bash
cp .env.example .env
```

Значения по умолчанию в `.env.example` смотрят на хост: бэк из
`docker-compose.yml` бэкенда на `8090` и vite-дев-сервер фронта на `3000`.

```bash
docker compose up --build
```

Гейтвей будет на `http://localhost:8080`. Проверить маршрутизацию:

```bash
curl -i http://localhost:8080/healthz
```

```bash
curl -i http://localhost:8080/api/public/campaigns
```

Порт публикации задан в `docker-compose.yml` (`8080` снаружи, `PORT` внутри).

## Как устроено

- `Caddyfile` — конфиг Caddy: слушает `:${PORT}`, `/healthz` отвечает сам,
  `/api/**`, `/v3/api-docs`, `/swagger-ui` уходят в `BACKEND_URL`, остальное в
  `FRONTEND_URL`. Тело запроса ограничено 20 МБ, на соединение с апстримом
  даётся 5 секунд.
- `docker-entrypoint.sh` — проверяет обязательные переменные, нормализует
  адреса, прогоняет `caddy validate` и запускает `caddy run`.
- `Dockerfile` — `caddy:2-alpine` плюс эти два файла.

Проверить, что конфиг собирается, не поднимая сервис:

```bash
docker build -t traffic-markering-gateway . && docker run --rm -e BACKEND_URL=http://example.com:8090 -e FRONTEND_URL=http://example.org traffic-markering-gateway caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

## Деплой

`.github/workflows/deploy.yml` на пуш в `main` собирает образ и пушит в
`ghcr.io/yanisderbikov/traffic-markering-gataway` (теги `latest` и короткий sha).
Railway собирает сервис из репозитория сам по этому же `Dockerfile`.
Переменные окружения задаются на стороне хостинга, в образ ничего не зашито.
Платформы, которые сами выдают `PORT` (Railway и подобные), подхватываются
без настройки.
