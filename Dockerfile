# ================================================================
# Local Pipeline: Docker Pipeline for iperf3 Debian Packaging
# ================================================================
# STAGES: builder (git clone) -> runner (direct source build)
# ENTRYPOINT: build_mode.sh (MODE=release|debug|coverage -> .deb)
# ================================================================

# ================================================================
# STAGE 1: git clone
# ================================================================
FROM debian:stable-slim AS builder

# Обновление пакетов и установка git
RUN apt-get update && \
    apt-get install -y git && \
    rm -rf /var/lib/apt/lists/*

# Рабочая директория
WORKDIR /app

# Клонирование репозитория iperf3
RUN git clone https://github.com/esnet/iperf.git

# ================================================================
# STAGE 2: Build + Package Runner
# ================================================================
FROM debian:stable-slim AS runner

# Установка необходимых инструментов
RUN apt-get update && \
    apt-get install -y \
    # Пакеты для сборки проекта iperf3
    autoconf automake libtool pkg-config \
    # Компиляция + сборка deb-пакета
    build-essential lcov checkinstall bc libssl-dev \
    # Установка ccache (сборка с использованием кеша)
    ccache && \
    rm -rf /var/lib/apt/lists/*

# ccache в PATH
ENV PATH="/usr/lib/ccache:$PATH"

# Рабочая директория
WORKDIR /app/iperf

# Передача исходников из git репозитория из предыдущего стейджа
COPY --from=builder /app/iperf/ .

# Передача скрипта
COPY build_mode.sh /app/iperf/build_mode.sh
RUN chmod +x /app/iperf/build_mode.sh

# Запуск скрипта сразу после запуска контейнера
ENTRYPOINT ["./build_mode.sh"]
