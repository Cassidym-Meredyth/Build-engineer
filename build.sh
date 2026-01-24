#!/bin/bash
set -e

mkdir -p inst_dir/{report,ccache_dir,artifacts}
INST_DIR="inst_dir"

# Создание файла для хранения последнего процента по coverage
if [ ! -f ${INST_DIR}/coverage_last.txt ]; then
    touch ${INST_DIR}/coverage_last.txt
    echo "0" > ${INST_DIR}/coverage_last.txt
fi

# Объявление переменных:
# mode - параметр для запуска сборки (release, debug, coverage)
# revision - номер ревизии
# build number - номер сборки
MODE="$1"
REVISION="$(date +%d_%m_%Y_%H_%M_%S)"
BUILD_NUM="$(find ./${INST_DIR}/report -maxdepth 1 -name 'build_report_*.txt' | wc -l)"
BUILD_NUM="$((BUILD_NUM + 1))"

# Создание файла отчета сборки build_report_{date_time}.txt
TIMESTAMP="${REVISION}"
REPORT_FILE="build_report_${TIMESTAMP}.txt"

# Создание build_report
echo "Building #${BUILD_NUM}, rev: ${REVISION}, mode: ${MODE}" >> "${INST_DIR}/report/${REPORT_FILE}"

# Удаление монтируемой папки с определенным параметром сборки
rm -rf ${INST_DIR}/artifacts/${MODE} || true

# Переменная Docker-образа
IMAGE="iperf3:0.1"

# Проверка, есть ли в локальном репозитории образ docker для сборки
# Да -> собирает контейнер с параметром "--rm" на основе этого образа
# Нет -> запускает сборку образа и собирает контейнер с этим образом
if ! docker image inspect iperf3:0.1 >/dev/null 2>&1; then
    echo -e "\033[31mImage not found. Building...\033[0m"
    docker build --no-cache -t "${IMAGE}" .
fi

# Запуск контейнера + вывод используемых параметров, которые будут переданы в контейнер
echo -e "\033[33mStarting container with mode: ${MODE}\033[0m"
echo "Режим сборки: ${MODE}"
echo "Номер сборки: ${BUILD_NUM}"
echo "Ревизия сборки: ${REVISION}"

docker run --rm \
    --mount type=bind,source="$(pwd)/${INST_DIR}/artifacts/${MODE}",target=/app/out/${MODE}/ \
    --mount type=bind,source="$(pwd)/${INST_DIR}/ccache_dir",target=/ccache \
    --mount type=bind,source="$(pwd)/${INST_DIR}/coverage_last.txt,target=/app/out/coverage_last.txt" \
    -e CCACHE_DIR=/ccache \
    -e MODE="${MODE}" \
    -e BUILD_NUM="${BUILD_NUM}" \
    -e REVISION="${REVISION}" \
    "${IMAGE}"

echo ""
# Окончание сборки
echo -e "\033[32m=== Сборка завершена ===\033[30m"
echo "Результат сборки находится в artifacts/${MODE}"
echo "Отчет находится в report/${REPORT_FILE}"
