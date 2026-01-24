# Стейдж подготовки исходников
FROM debian:stable-slim AS builder

RUN apt-get update && \
    apt-get install -y git && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN git clone https://github.com/esnet/iperf.git

# Стейдж сборки
FROM debian:stable-slim AS runner

# Установка необходимых инструментов
RUN apt-get update && \
    apt-get install -y \
    autoconf automake libtool pkg-config \
    build-essential lcov checkinstall bc \
    ccache && \
    rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/lib/ccache:$PATH"
# Наша рабочая директория
WORKDIR /app/iperf

# Копирование кеша кода проекта iperf3 из предыдущего стейджа + копирование скрипта
COPY --from=builder /app/iperf/ .
COPY build_mode.sh /app/iperf/build_mode.sh
RUN chmod +x /app/iperf/build_mode.sh

ENTRYPOINT ["./build_mode.sh"]
