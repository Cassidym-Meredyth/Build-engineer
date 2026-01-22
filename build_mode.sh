#!/bin/bash
set -e

case "$BUILD_MODE" in
    release)
        echo -e "\033[33m=== Building in ${BUILD_MODE} mode ===\033[0m"

        # Release build
        ./bootstrap.sh
        ./configure CFLAGS="-O2 -Wall" LDFLAGS="-static" --disable-shared
        make clean && make -j$(nproc)

        # i. Создание информации о пакете
        make install DESTDIR=/app/staging

        strip -s /app/staging/usr/local/bin/iperf3

        mkdir -p /app/out/deb/DEBIAN /app/out/deb/usr/bin
        cat > /app/out/deb/DEBIAN/control << EOF
Package: iperf3
Version: ${BUILD_NUM}
Architecture: amd64
Maintainer: Local CI <ci@cassidym>
Section: net
Priority: optional
Description: iperf3 network tool v${BUILD_NUM}
    Stripped release build
EOF
        chmod 644 /app/out/deb/DEBIAN/control

        # ii. Копируем бинарник с удаленной отладочной информацией (strip)
        cp /app/staging/usr/local/bin/iperf3 /app/out/deb/usr/bin/

        # iii. Создание release deb пакета
        dpkg-deb --build /app/out/deb /app/out/iperf3_${REVISION}_${BUILD_NUM}_amd64.deb
        ;;
    debug)
        echo -e "\033[33m=== Building in ${BUILD_MODE} mode ===\033[0m"

        # Debug build
        ./bootstrap.sh
        ./configure CFLAGS="-g -O0 -Wall" LDFLAGS="-static"
        make clean && make -j$(nproc)

        # i. Создание информации о пакете
        make install DESTDIR=/app/staging

        DEBUG_BINARY="/app/staging/usr/local/bin/iperf3"
        DEBUG_FILE="/app/out/iperf3-debug-${REVISION}.dbg"

        mkdir -p /app/out/deb/DEBIAN /app/out/deb/usr/bin /app/out/deb/usr/share/doc/iperf3
        mkdir -p /app/out/debug-deb/DEBIAN /app/out/debug-deb/usr/lib/debug/usr/bin

        mkdir -p /app/out/deb/usr/bin /app/out/deb/usr/share/doc/iperf3
        # 1. Извлечь debug symbols
        objcopy --only-keep-debug "${DEBUG_BINARY}" "${DEBUG_FILE}"

        # 2. Strip binary (оставить debuglink)
        strip --strip-all "${DEBUG_BINARY}"
        objcopy --add-gnu-debuglink "${DEBUG_FILE}" "${DEBUG_BINARY}"

        cp "${DEBUG_BINARY}" /app/out/deb/usr/bin/iperf3

        # 4. Main deb package
        BUILD_VERSION="1.0.${BUILD_NUM}"
        cat > /app/out/deb/DEBIAN/control << EOF
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
        chmod 644 /app/out/deb/DEBIAN/control
        dpkg-deb --build /app/out/deb /app/out/iperf3_${BUILD_NUM}_debug_amd64.deb

        # 5. Отдельный debug пакет (bonus)
        cp "${DEBUG_FILE}" /app/out/debug-deb/usr/lib/debug/usr/bin/iperf3.debug
        cat > /app/out/debug-deb/DEBIAN/control << EOF
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
        chmod 644 /app/out/debug-deb/DEBIAN/control
        dpkg-deb --build /app/out/debug-deb /app/out/iperf3-debug_${BUILD_NUM}_amd64.deb

        echo "Stripped binary: $(file /app/out/deb/usr/bin/iperf3)"
        echo "Debug file: $(ls -lh ${DEBUG_FILE})"
        echo "Debug прошел успешно! Финальный отчет:"
        ls -lh /app/out/*.deb
        dpkg-deb -I /app/out/iperf3_*_debug_amd64.deb
        dpkg-deb -I /app/out/iperf3-debug_*_amd64.deb
        du -sh /app/out/
        tar -czf /app/out/iperf3-complete.tar.gz /app/out/iperf3*.deb 2>/dev/null
        ls -lh iperf3-complete.tar.gz
        ;;
    coverage)
        echo -e "\033[33m=== Building in ${BUILD_MODE} mode ===\033[0m"
        ;;
    *)
        echo "Invalid or unset mode: '${BUILD_MODE}'"
        exit 1
        ;;
esac
echo -e "\033[34mСборка выполнена\033[0m"
