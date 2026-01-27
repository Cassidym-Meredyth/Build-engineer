#!/bin/bash
# ================================================================
# Local Pipeline: Debian Package Builder (project - iperf3)
# ================================================================
# Ручной подход dpkg-deb (.deb с debug symbols, coverage)
# Режимы: release, debug, coverage
# ================================================================
set -euo pipefail

# ================================================================
# ENVIRONMENT VARIABLES (из Docker run)
# ================================================================
MODE="${MODE?Error: MODE variable is not set}"
BUILD_NUM="${BUILD_NUM?Error: BUILD_NUM variable is not set}"
REVISION="${REVISION?Error: REVISION variable is not set}"

# Используем схему версионирования для deb пакетов (своя сборка - свои версии сборок как ни как)
BUILD_VERSION="1.0.${BUILD_NUM}"

# ================================================================
# FILESYSTEM LAYOUT (staging -> deb -> artifacts)
# ================================================================
APP_DIR="/app"                                  # Docker WORKDIR
LOG_DIR="${APP_DIR}/log"                        # Директория для логов
TMP_DIR="${APP_DIR}/tmp"                        # Директория для временных файлов
OUT_DIR="${APP_DIR}/out/${MODE}"                # Директория для артефактов сборки
STAGING_DIR="${APP_DIR}/staging"                # make install DESTDIR
DEB_ROOT="${TMP_DIR}/deb"                       # Директория для deb пакетов (root)
DEBUG_DEB_ROOT="${TMP_DIR}/debug-deb"           # Директория для debug deb пакетов (root)
PREV_FILE="${APP_DIR}/out/coverage_last.txt"    # Путь к предыдущему файлу покрытия кода
COVERAGE_VALUE="0.0"                            # Значение покрытия кода по умолчанию

# ================================================================
# WORKSPACE CLEANUP + SETUP
# ================================================================
# Полная очистка предыдущих артефактов
rm -rf "${STAGING_DIR}" "${TMP_DIR}" "${DEBUG_DEB_ROOT}" "${TMP_DIR}/iperf3"
mkdir -p "${OUT_DIR}" "${STAGING_DIR}" "${DEB_ROOT}/DEBIAN" "${DEB_ROOT}/usr/bin"
chmod -R 755 "${TMP_DIR}" # Права для доступа docker

# ================================================================
# PERSISTENT LOGGING (trap: всегда запишет финал, даже при ошибке)
# ================================================================
LOG_FILE="${LOG_DIR}/build_report_${REVISION}.txt"

trap 'echo "--- Build Report End ---" >> "${LOG_FILE}"' EXIT
{
    echo "=== Building in ${MODE} mode ==="
    echo "Run Num: ${BUILD_NUM}"
    echo "Revision: ${REVISION}"
    echo "Build type: ${MODE}"
} >> "${LOG_FILE}"

# ================================================================
# BUILD START
# ================================================================
echo -e "\033[33m=== Building in ${MODE} mode ===\033[0m"
./bootstrap.sh # automake, autoconf (запуск сборки согласно документации iperf3)

case "$MODE" in
    # ================================================================
    release)
    # ================================================================
        echo -e "\033[33m=== Building in ${MODE} mode ===\033[0m"
        # Make сборки с тегом release
        ./configure \
            --prefix=/usr \
            CFLAGS="-O2 -Wall" \
            LDFLAGS="" \
            --enable-shared \
            --disable-static-bin
        make clean && make -j$(nproc) # параллельная сборка
        make install DESTDIR="${STAGING_DIR}"

        # Запуск процедуры strip для удаления отладочной информации
        strip -s "${STAGING_DIR}/usr/bin/iperf3"

        # Файл control: краткая информация о release-пакете
        cat > "${DEB_ROOT}/DEBIAN/control" << EOF
Package: iperf3
Version: ${BUILD_VERSION}
Architecture: amd64
Maintainer: Local CI <ci@cassidym>
Section: net
Priority: optional
Description: iperf3 network tool v${BUILD_VERSION}
    Stripped release build
EOF
        # Копирование бинарника с удаленной отладочной информацией (strip)
        cp "${STAGING_DIR}/usr/bin/iperf3" "${DEB_ROOT}/usr/bin/"

        # Создание release-пакета
        dpkg-deb --build "${DEB_ROOT}" "${OUT_DIR}/iperf3_${REVISION}_${BUILD_NUM}_amd64.deb"
        ;;
    # ================================================================
    debug)
    # ================================================================
        echo -e "\033[33m=== Building in ${MODE} mode ===\033[0m"
        # Make сборки с тегом debug
        ./configure \
            --prefix=/usr \
            CFLAGS="-g -O0 -Wall" \
            LDFLAGS="-static" \
            --enable-static-bin \
            --disable-shared
        make clean && make -j$(nproc) V=1 --output-sync=target
        make install DESTDIR="${STAGING_DIR}"

        # Создание debug директорий
        mkdir -p "${DEBUG_DEB_ROOT}/DEBIAN" "${DEBUG_DEB_ROOT}/usr/lib/debug/usr/bin"
        DEBUG_BINARY="${STAGING_DIR}/usr/bin/iperf3"
        DEBUG_FILE="${TMP_DIR}/iperf3.debug"


        echo -e "\033[31mCheck\033[0m"
        readelf -S "${DEBUG_BINARY}" | grep -q ".debug_info" \
          || { echo "ERROR: no debug info in binary"; exit 1; }

        # Извлекаем debug symbols из stripped binary
        objcopy --only-keep-debug "${DEBUG_BINARY}" "${DEBUG_FILE}"

        # Strip binary (оставить debuglink)
        strip --strip-debug "${DEBUG_BINARY}"

        # Добавляем debuglink
        # objcopy --add-gnu-debuglink="${DEBUG_FILE}" "${DEBUG_BINARY}"

        # Бинарник для debug (stripped)
        cp "${DEBUG_BINARY}" "${DEB_ROOT}/usr/bin/iperf3"
        echo -e "\033[33mСоздание DEB-пакета для режима ${MODE}...\033[0m"
        cat > "${DEB_ROOT}/DEBIAN/control" << EOF
Package: iperf3
Version: ${BUILD_VERSION}
Architecture: amd64
Maintainer: Local CI <ci@cassidym>
Section: net
Priority: optional
Description: iperf3 network tool debug build v${BUILD_VERSION}
    Stripped binary with debuglink for gdb. Use with iperf3-debug package.
EOF
        dpkg-deb --build "${DEB_ROOT}" "${OUT_DIR}/iperf3_${REVISION}_${BUILD_NUM}_amd64.deb"

        # Бинарник для debug (debuglink)
        cp "${DEBUG_FILE}" "${DEBUG_DEB_ROOT}/usr/lib/debug/usr/bin/iperf3.debug"
        cat > "${DEBUG_DEB_ROOT}/DEBIAN/control" << EOF
Package: iperf3-debug
Version: ${BUILD_VERSION}
Architecture: amd64
Maintainer: Local CI <ci@cassidym>
Section: debug
Priority: extra
Depends: iperf3 (= ${BUILD_VERSION})
Description: iperf3 debug symbols
    Debug information package.
EOF
        dpkg-deb --build "${DEBUG_DEB_ROOT}" "${OUT_DIR}/iperf3-debug_${REVISION}_${BUILD_NUM}_amd64.deb"
        ;;
    # ================================================================
    coverage)
    # ================================================================
        echo -e "\033[33m=== Building in ${MODE} mode ===\033[0m"
        # Make сборки с тегом coverage
        ./configure \
          --prefix=/usr \
          CFLAGS="--coverage -O0 -g -fno-inline -Wall" \
          LDFLAGS="--coverage -lgcov" \
          --disable-shared
        make clean -j$(nproc)
        make -j$(nproc) V=1
        make install DESTDIR="${STAGING_DIR}"

        strip -s "${STAGING_DIR}/usr/bin/iperf3"

        # Динамическая компиляция iperf3, надо для сборки coverage (gcov libs)
        export LD_LIBRARY_PATH="${STAGING_DIR}/usr/local/lib:${LD_LIBRARY_PATH:-}"
        BIN="${STAGING_DIR}/usr/bin/iperf3"

        # Интеграционное тестирование - тестируем "iperf3 --version"
        echo -e "\033[34mRunning integration test...\033[0m"
        ${BIN} --version || true

        # Получаем информацию о покрытии кода
        echo -e "\033[34mCollecting coverage\033[0m"
        lcov --directory . \
             --capture \
             --output-file coverage.info \
             --ignore-errors empty

        # Очистка файлов
        lcov --remove coverage.info '/usr/*' \
             --output-file coverage.info

        # Создаем html-отчет о покрытии кода
        genhtml coverage.info --output-directory "${OUT_DIR}/coverage-report"

        # Переменная окружения о покрытии кода
        COVERAGE_VALUE=$(lcov --summary coverage.info | \
           grep "lines" | \
           awk '{print $2}' | \
           sed 's/%//')
        COVERAGE_VALUE=${COVERAGE_VALUE:-0}

        echo -e "\033[31mCoverage\033[0m: ${COVERAGE_VALUE}%\n"

        # Сравнение покрытия кода с предыдущим значением
        echo -e "\033[33mCoverage comprasion...\033[0m"
        PREV_FILE="/app/out/coverage_last.txt"

        # Проверка наличия файла с предыдущим значением покрытия кода
        if [ -f "${PREV_FILE}" ]; then
                PREV_COVERAGE=$(cat "${PREV_FILE}")
                PREV_COVERAGE=${PREV_COVERAGE:-0}
                echo "Previous coverage: ${PREV_COVERAGE}%"

                if [ "$(echo "${COVERAGE_VALUE} < ${PREV_COVERAGE}" | bc -l )" -eq 1 ]; then
                        echo -e "\033[31mCoverage decreased!\033[0m"
                        # В случае ошибки выходим
                        exit 1
                else
                    echo -e "\033[32mCoverage maintained or increased! (${COVERAGE_VALUE}% >= ${PREV_COVERAGE}%)\033[0m"
                fi
        fi
        # Сохраняем новое значение для следующего раза
        echo "${COVERAGE_VALUE}" > "${PREV_FILE}"
        echo ""

        # Бинарник для coverage
        echo -e "\033[33m=== Создание DEB-пакета для режима ${MODE} ===\033[0m"
        cat > "${DEB_ROOT}/DEBIAN/control" << EOF
Package: iperf3-coverage
Version: ${BUILD_VERSION}
Architecture: amd64
Maintainer: Local CI <ci@cassidym>
Section: network
Priority: optional
Description: iperf3 network tool coverage build v${BUILD_VERSION}
    Coverage: ${COVERAGE_VALUE}%
EOF

        cp "${STAGING_DIR}/usr/bin/iperf3" "${DEB_ROOT}/usr/bin/"
        dpkg-deb --build "${DEB_ROOT}" "${OUT_DIR}/iperf3-coverage_${REVISION}_${BUILD_NUM}_amd64.deb"
        ;;
    # ================================================================
    *)
    # ================================================================
        echo "Invalid or unset mode: ${MODE}"
        exit 1
        ;;
esac

# ================================================================
# BUILD SUMMARY + ARTIFACTS
# ================================================================
echo -e "\033[32m=== Финальный отчет ===\033[0m"
echo -e "\033[34mРазмер пакетов в ${OUT_DIR}:\033[30m"
du -sh "${OUT_DIR}/"
ls -lh "${OUT_DIR}/"
