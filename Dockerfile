FROM elixir:1.18-alpine AS build

RUN apk add --no-cache build-base git

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod
RUN mix deps.compile

COPY assets assets
COPY lib lib
COPY priv priv

RUN mix compile
RUN mix assets.deploy
RUN mix release

FROM alpine:3.21 AS app

RUN apk add --no-cache ca-certificates libgcc libstdc++ ncurses-libs openssl sqlite-libs

WORKDIR /app

RUN addgroup -S inkit && adduser -S inkit -G inkit

COPY --from=build --chown=inkit:inkit /app/_build/prod/rel/inkit ./
COPY --chown=inkit:inkit docker/entrypoint.sh ./bin/docker-entrypoint
COPY --chown=inkit:inkit priv/demo ./demo

RUN chmod +x ./bin/docker-entrypoint

# Create the data dir with the non-root owner BEFORE declaring USER/VOLUME so
# that Docker seeds a freshly-created named volume with inkit:inkit ownership
# on first mount. Otherwise the volume is root-owned and the non-root runtime
# user cannot create `/data/uploads` or the SQLite file.
RUN mkdir -p /data /data/uploads && chown -R inkit:inkit /data

ENV HOME=/app \
    PHX_SERVER=true \
    PHX_HOST=localhost \
    PHX_SCHEME=http \
    PHX_URL_PORT=4000 \
    PORT=4000 \
    DATABASE_PATH=/data/inkit.db \
    UPLOAD_DIR=/data/uploads

VOLUME ["/data"]

USER inkit

EXPOSE 4000

ENTRYPOINT ["./bin/docker-entrypoint"]
CMD ["./bin/inkit", "start"]
