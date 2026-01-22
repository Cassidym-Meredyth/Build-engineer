#!/bin/bash
case "$BUILD_MODE" in
    release)
        echo -e "\033[33m=== Building in ${BUILD_MODE} mode ===\033[0m"
        ./configure CFLAGS="-O2 -Wall" LDFLAGS="-static" --disable-shared
        make clean && make -j$(nproc)

        # Удаление отладочной информации
        strip src/iperf3

        make install DESTDIR=/app/staging
        mkdir -p /app/out/deb/DEBIAN /app/out/deb/usr/bin /app/out/deb/usr/share/doc/iperf3

        # Создание release deb пакета
        make install DESTDIR=/app/staging
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

        # Фикс прав/пробелов
        sed -i '/^$/d' /app/out/deb/DEBIAN/control  # Удалить пустые строки
        chmod 644 /app/out/deb/DEBIAN/control

        cp /app/staging/usr/local/bin/iperf3 /app/out/deb/usr/bin/
        dpkg-deb --build /app/out/deb /app/out/iperf3_${REVISION}_${BUILD_NUM}_amd64.deb
        ;;
    debug)
        echo -e "\033[32m=== Building in debug mode ===\033[0m"
        ;;
    *)
        echo "Invalid or unset mode: '${BUILD_MODE}'"
        exit 1
        ;;
esac
echo -e "\033[34mСборка выполнена\033[34m"
