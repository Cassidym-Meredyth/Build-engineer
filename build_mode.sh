#!/bin/bash
set -e

export MODE="${MODE}"
export BUILD_NUM="${BUILD_NUM}"
export REVISION="${REVISION}"


mkdir -p /app/out/${MODE}/

case "$MODE" in
    release)
        echo -e "\033[33m=== Building in ${MODE} mode ===\033[0m"

        # Release build
        ./bootstrap.sh
        ./configure CFLAGS="-O2 -Wall" LDFLAGS="-static" --disable-shared
        make clean && make -j$(nproc)

        # i. Создание информации о пакете
        make install DESTDIR=/app/staging

        strip -s /app/staging/usr/local/bin/iperf3

        mkdir -p /app/tmp/deb/DEBIAN /app/tmp/deb/usr/bin

        cat > /app/tmp/deb/DEBIAN/control << EOF
Package: iperf3
Version: ${BUILD_NUM}
Architecture: amd64
Maintainer: Local CI <ci@cassidym>
Section: net
Priority: optional
Description: iperf3 network tool v${BUILD_NUM}
    Stripped release build
EOF
        chmod 644 /app/tmp/deb/DEBIAN/control

        # ii. Копируем бинарник с удаленной отладочной информацией (strip)
        cp /app/staging/usr/local/bin/iperf3 /app/tmp/deb/usr/bin/

        # iii. Создание release deb пакета
        dpkg-deb --build /app/tmp/deb /app/tmp/iperf3_${REVISION}_${BUILD_NUM}_amd64.deb

        echo -e "\033[32m=== Финальный отчет ===\033[0m"
        echo -e "\033[34mИнформация о пакетах:\033[30m"
        dpkg-deb -I /app/tmp/iperf3_*_amd64.deb
        echo ""

        cp -r /app/tmp/iperf3_${REVISION}_${BUILD_NUM}_amd64.deb /app/out/${MODE}/iperf3_${REVISION}_${BUILD_NUM}_amd64.deb
        echo ""

        echo -e "\033[34mРазмер пакетов:\033[30m"
        du -sh /app/out/${MODE}/
        ;;
    debug)
        echo -e "\033[33m=== Building in ${MODE} mode ===\033[0m"

        # Debug build
        ./bootstrap.sh
        ./configure CFLAGS="-g -O0 -Wall" LDFLAGS="-static"
        make clean && make -j$(nproc)

        # i. Создание информации о пакете
        make install DESTDIR=/app/staging

        DEBUG_BINARY="/app/staging/usr/local/bin/iperf3"
        DEBUG_FILE="/app/tmp/iperf3-debug-${REVISION}.dbg"

        mkdir -p /app/tmp/deb/DEBIAN /app/tmp/deb/usr/bin /app/tmp/deb/usr/share/doc/iperf3
        mkdir -p /app/tmp/debug-deb/DEBIAN /app/tmp/debug-deb/usr/lib/debug/usr/bin

        mkdir -p /app/tmp/deb/usr/bin /app/tmp/deb/usr/share/doc/iperf3
        # 1. Извлечь debug symbols
        objcopy --only-keep-debug "${DEBUG_BINARY}" "${DEBUG_FILE}"

        # 2. Strip binary (оставить debuglink)
        strip --strip-all "${DEBUG_BINARY}"
        objcopy --add-gnu-debuglink "${DEBUG_FILE}" "${DEBUG_BINARY}"

        cp "${DEBUG_BINARY}" /app/tmp/deb/usr/bin/iperf3

        # 4. Main deb package
        BUILD_VERSION="1.0.${BUILD_NUM}"
        cat > /app/tmp/deb/DEBIAN/control << EOF
Package: iperf3
Version: ${BUILD_VERSION}
Architecture: amd64
Maintainer: Local CI <ci@cassidym>
Section: net
Priority: optional
Description: iperf3 network tool debug build v${BUILD_VERSION}
    Stripped binary with debuglink for gdb.
    .
    Use with iperf3-debug package.
EOF
        chmod 644 /app/tmp/deb/DEBIAN/control
        dpkg-deb --build /app/tmp/deb /app/tmp/iperf3_${BUILD_NUM}_debug_amd64.deb

        # 5. Отдельный debug пакет (bonus)
        cp "${DEBUG_FILE}" /app/tmp/debug-deb/usr/lib/debug/usr/bin/iperf3.debug
        cat > /app/tmp/debug-deb/DEBIAN/control << EOF
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
        chmod 644 /app/tmp/debug-deb/DEBIAN/control
        dpkg-deb --build /app/tmp/debug-deb /app/tmp/iperf3-debug_${BUILD_NUM}_amd64.deb


        echo -e "\033[32m=== Финальный отчет ===\033[0m"
        echo -e "\033[34mStripped binary:\033[30m $(file /app/tmp/deb/usr/bin/iperf3)"
        echo -e "\033[34mDebug file:\033[30m $(ls -lh ${DEBUG_FILE})"
        echo ""

        echo -e "\033[34mDeb пакеты:\033[30m"
        ls -lh /app/tmp/*.deb
        echo ""

        echo -e "\033[34mИнформация о пакетах:\033[30m"
        echo -e "\033[30mОсновной ${MODE} пакет\033[30m"
        dpkg-deb -I /app/tmp/iperf3_*_debug_amd64.deb
        echo ""
        echo -e "\033[30mДополнительный ${MODE} пакет\033[30m"
        dpkg-deb -I /app/tmp/iperf3-debug_*_amd64.deb
        echo ""

        cp /app/tmp/iperf3-debug_${BUILD_NUM}_amd64.deb /app/out/${MODE}/iperf3-debug_${BUILD_NUM}_amd64.deb
        cp /app/tmp/iperf3_${BUILD_NUM}_amd64.deb /app/out/${MODE}/iperf3_${BUILD_NUM}_amd64.deb

        echo -e "\033[34mРазмер пакетов:\033[30m"
        du -sh /app/out/${MODE}/
        ;;
    coverage)
        echo -e "\033[33m=== Building in ${MODE} mode ===\033[0m"
        # Coverage build
        ./bootstrap.sh
        ./configure CFLAGS="--coverage -O0 -g" LDFLAGS="--coverage"
        make clean && make -j$(nproc)
        make install DESTDIR=/app/staging

        export LD_LIBRARY_PATH=/app/staging/usr/local/lib:$LD_LIBRARY_PATH

        BIN="/app/staging/usr/local/bin/iperf3"

        # 2. Integration test
        echo -e "\033[34mRunning integration test...\033[0m"
        ${BIN} --version || true

        # 3. Collect coverage
        echo -e "\033[34mCollecting coverage\033[0m"
        lcov --directory . \
             --capture \
             --output-file coverage.info \
             --ignore-errors empty

        # 4. Clear system file
        lcov --remove coverage.info '/usr/*' \
             --output-file coverage.info

        # 5. Generate HTML report
        genhtml coverage.info --output-directory coverage-report

        # 6. Get coverage
        COVERAGE=$(lcov --summary coverage.info | \
           grep "lines" | \
           awk '{print $2}' | \
           sed 's/%//')

        echo -e "\033[31mCoverage\033[0m: ${COVERAGE}%\n"

        # 7. Coverage comparison
        echo -e "\033[33mCoverage comprasion...\033[0m"
        PREV_FILE="/app/out/coverage_last.txt"

        if [ -f "${PREV_FILE}" ]; then
                PREV_COVERAGE=$(cat "${PREV_FILE}")
                echo "Previous coverage: ${PREV_COVERAGE}%"

                if (( echo "${COVERAGE} < ${PREV_COVERAGE}" | bc -l )); then
                        echo -e "\033[31mCoverage decreased!\033[0m"
                        exit 1
                fi
        else
                PREV_COVERAGE=0
        fi

        echo "${COVERAGE}% > ${PREV_COVERAGE}%"
        ;;
    *)
        echo "Invalid or unset mode: '${MODE}'"
        exit 1
        ;;
esac
