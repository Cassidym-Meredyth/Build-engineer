FROM alpine:3.23.2 AS builder

RUN apk update && \
    apk add build-base && \
    apk add ncurses-dev && \
    apk add git

WORKDIR /app

RUN git clone https://github.com/NicolasHug/snake.git && \
    cd snake && \
    make snake && \
    mv /app/snake/snake /app/snake_game && \
    cd .. && \
    rm -rf /app/snake

USER snake

FROM alpine:3.23.2

COPY --from=builder /app/snake_game /app/snake_game

RUN apk update && apk add ncurses && rm -rf /var/cache/apk/* && \
    addgroup -S snake && \
    adduser -S snake -G snake && \
    chown snake:snake /app/snake_game

WORKDIR /app
USER snake

CMD ["./snake_game"]
