#!/bin/bash
set -euo pipefail

# Инициализация локального CI/CD workspace
# Создание директорий для артефактов, отчетов и кеша компиляции
mkdir -p inst_dir/{report,ccache_dir,artifacts}

# Основная рабочая директория локального конвейера
INST_DIR="inst_dir"

# Инициализация трекера покрытия тестами
# Создание файла для хранения последнего % по coverage (если его нет)
if [ ! -f ${INST_DIR}/coverage_last.txt ]; then
    touch ${INST_DIR}/coverage_last.txt
    echo "0" > ${INST_DIR}/coverage_last.txt
fi

# Переменные окружения для отчетов и кеша
LOG_DIR="${INST_DIR}/report"
CACHE_DIR="${INST_DIR}/ccache_dir"

# ================================================================
# ПАРАМЕТРЫ СБОРКИ (CI/CD переменные)
# ================================================================
# MODE=release|debug|coverage - режим компиляции
# REVISION - timestamp ревизии (дата_время)
# BUILD_NUM - автоинкрементный номер сборки
MODE="$1"
REVISION="$(date +%d_%m_%Y_%H_%M_%S)"
BUILD_NUM="$(find ./${INST_DIR}/report -maxdepth 1 -name 'build_report_*.txt' | wc -l)"
BUILD_NUM="$((BUILD_NUM + 1))"

# Имя файла отчета текущей сборки - build_report_{date_time}.txt
REPORT_FILE="build_report_${REVISION}.txt"

# Директория выходных артефактов (.deb, coverage reports)
OUT_DIR="${INST_DIR}/artifacts/${MODE}"

# Очистка предыдущих артефактов текущего режима
rm -rf ${OUT_DIR} || true

# Docker образ
IMAGE="iperf3:0.1"

# Проверка, есть ли в локальном registry образ для сборки
# Да -> собирает контейнер с параметром "--rm" на основе этого образа
# Нет -> запускает сборку образа и собирает контейнер с этим образом
if ! docker image inspect iperf3:0.1 >/dev/null 2>&1; then
    echo -e "\033[31mImage not found. Building...\033[0m"
    docker build --no-cache -t "${IMAGE}" .
fi

# Логирование параметров сборки
echo -e "\033[33mStarting container with mode: ${MODE}\033[0m"
echo "Режим сборки: ${MODE}"
echo "Номер сборки: ${BUILD_NUM}"
echo "Ревизия сборки: ${REVISION}"

# ================================================================
# СЛОЖНЫЙ DOCKER RUN с volume mounts для CI/CD pipeline
# ================================================================
# --rm: автоочистка контейнера
# bind mounts: связанные директории между хостом и контейнером
docker run --rm \
    # Артефакты (.deb файлы) -> хост artifacts/${MODE}
    --mount type=bind,source="$(pwd)/${OUT_DIR}",target=/app/out/${MODE}/ \
    # ccache persistent между сборками
    --mount type=bind,source="$(pwd)/${CACHE_DIR}",target=/ccache \
    # Логи/отчеты -> хост report/
    --mount type=bind,source="$(pwd)/${LOG_DIR}",target=/app/log \
    # Coverage state (последний % покрытия)
    --mount type=bind,source="$(pwd)/${INST_DIR}/coverage_last.txt,target=/app/out/coverage_last.txt" \
    # Env для ccache
    -e CCACHE_DIR=/ccache \
    # Переменные сборки для использования уже в скрипте build_mode.sh
    -e MODE="${MODE}" \
    -e BUILD_NUM="${BUILD_NUM}" \
    -e REVISION="${REVISION}" \
    # Сам образ контейнера (iperf3:0.1)
    "${IMAGE}"

echo ""
# Окончание сборки
echo -e "\033[32m=== Сборка завершена ===\033[30m"
echo "Артефакты: ${OUT_DIR}/${MODE}"
echo "Отчет:     ${LOG_DIR}/${REPORT_FILE}"
