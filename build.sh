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
# TIMESTAMP - дата_время для написания репорта
# BUILD_NUM - автоинкрементный номер сборки
# REVISION - номер ревизии (date_time + build_num)
MODE="$1"
TIMESTAMP="$(date +%d_%m_%Y_%H_%M_%S)"
BUILD_NUM="$(find ./${INST_DIR}/report -maxdepth 1 -name 'build_report_*.txt' | wc -l)"
BUILD_NUM="$((BUILD_NUM + 1))"
REVISION="${TIMESTAMP}-${BUILD_NUM}"

# Имя файла отчета текущей сборки - build_report_{date_time}.txt
REPORT_FILE="build_report_${TIMESTAMP}.txt"

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
# ================================================================
# bind mounts: связанные директории между хостом и контейнером:
# Mount 1: Артефакты (.deb файлы) -> хост artifacts/${MODE}
# Mount 2: ccache persistent между сборками
# Mount 3: Логи/отчеты -> хост report/
# Mount 4: Coverage state (последний % покрытия)
# ================================================================
# Env для ccache
# ================================================================
# Переменные сборки для использования уже в скрипте build_mode.sh:
# MODE, BUILD_NUM, REVISION
# ================================================================
# Сам образ контейнера (IMAGE=iperf3:0.1)
# ================================================================
docker run --rm \
    --mount type=bind,source="$(pwd)/${OUT_DIR}",target=/app/out/${MODE}/ \
    --mount type=bind,source="$(pwd)/${CACHE_DIR}",target=/ccache \
    --mount type=bind,source="$(pwd)/${LOG_DIR}",target=/app/log \
    --mount type=bind,source="$(pwd)/${INST_DIR}/coverage_last.txt,target=/app/out/coverage_last.txt" \
    -e CCACHE_DIR=/ccache \
    -e MODE="${MODE}" \
    -e BUILD_NUM="${BUILD_NUM}" \
    -e REVISION="${REVISION}" \
    -e TIMESTAMP="${TIMESTAMP}" \
    "${IMAGE}"

echo ""
# Окончание сборки
echo -e "\033[32m=== Сборка завершена ===\033[30m"
echo "Артефакты: ${OUT_DIR}/${MODE}"
echo "Отчет:     ${LOG_DIR}/${REPORT_FILE}"
