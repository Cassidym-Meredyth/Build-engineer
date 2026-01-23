#!/bin/bash
set -e

mkdir -p report
mkdir -p artifacts

MODE="$1"
REVISION="$(date +%d_%m_%Y_%H_%M_%S)"
BUILD_NUM="$(find ./report -maxdepth 1 -name 'build_report_*.txt' | wc -l)"
BUILD_NUM="$((BUILD_NUM + 1))"

TIMESTAMP="${REVISION}"
REPORT_FILE="build_report_${TIMESTAMP}.txt"

echo "Building #${BUILD_NUM}, rev: ${REVISION}, mode: ${MODE}" >> "report/${REPORT_FILE}"

IMAGE="iperf3:0.1"

if ! docker image inspect iperf3:0.1 >/dev/null 2>&1; then
    echo -e "\033[31mImage not found. Building...\033[0m"
    docker build --no-cache -t "${IMAGE}" .
fi

echo -e "\033[33mStarting container with mode: ${MODE}\033[0m"
echo "Режим сборки: ${MODE}"
echo "Номер сборки: ${BUILD_NUM}"
echo "Ревизия сборки: ${REVISION}"
docker run --rm \
    -v "$(pwd)/artifacts:/app/deb" \
    -e MODE="${MODE}" \
    -e BUILD_NUM="${BUILD_NUM}" \
    -e REVISION="${REVISION}" \
    --entrypoint /bin/bash \
    "${IMAGE}" \
    ./build_mode.sh

echo ""
echo -e "\033[32m=== Сборка завершена ===\033[30m"
echo "Файлы: artifacts/iperf3-${REVISION}.deb и ${REPORT_FILE}"
