# Первая стадия сборки образа:
FROM debian:stable-slim AS builder

RUN apt-get update && \
    apt-get install -y git && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN git clone https://github.com/esnet/iperf.git

FROM debian:stable-slim AS runner

# ENV BUILD_MODE=$MODE \
#     REVISION=$REVISION \
#     BUILD_NUM=$BUILD_NUM

RUN apt-get update && \
    apt-get install -y \
    autoconf automake libtool pkg-config \
    build-essential lcov checkinstall bc

WORKDIR /app/iperf

COPY --from=builder /app/iperf/ .
COPY build_mode.sh /app/iperf/build_mode.sh

RUN chmod +x /app/iperf/build_mode.sh

CMD ["./build_mode.sh"]
