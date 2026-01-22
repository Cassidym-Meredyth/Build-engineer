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

docker build \
    --build-arg MODE="${MODE}" \
    --build-arg REVISION="${REVISION}" \
    --build-arg BUILD_NUM="${BUILD_NUM}" \
    -t iperf3:"${REVISION}_${MODE}" \
    -f Dockerfile .

docker run --rm \
  -v "$(pwd)/artifacts:/app/deb" \
  "iperf3:${REVISION}_${MODE}"
echo "Готово: artifacts/iperf3-${REVISION}.deb и ${REPORT_FILE}"
