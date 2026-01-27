# Локальный конвейер сборки проекта

## Описание
Этот репозиторий содержит локальный конвейер сборки для тестового задания. Конвейер собирает проект на C (используется iperf3 из открытого репозитория ESnet) в трех режимах:
- **Release** — оптимизированный `.deb` пакет с удалением отладочной информации (`strip`).
- **Debug** — `.deb` пакет + отдельный пакет с debug symbols.
- **Coverage** — `.deb` пакет + отчет покрытия gcov/lcov (HTML) с проверкой динамики покрытия.

Источник: [iperf3 (ESnet)](https://github.com/esnet/iperf), версия 3.20.

## Архитектура
```
build.sh -> Docker (multi-stage) -> build_mode.sh -> .deb artifacts
├── inst_dir/artifacts/{release,debug,coverage}/*.deb
├── inst_dir/report/build_report_*.txt
├── inst_dir/ccache_dir/        # persistent cache
└── inst_dir/coverage_last.txt  # последнее покрытие
```

## Структура проекта
| Файл          | Назначение                                                        |
| ------------- | ----------------------------------------------------------------- |
| build.sh      | Главная точка входа CI/CD. Управляет Docker образом + параметрами |
| Dockerfile    | Multi-stage: git clone -> build environment                       |
| build_mode.sh | Логика сборки: ./configure -> make -> make install -> dpkg-deb    |
| inst_dir/     | Workspace: artifacts, reports, ccache                             |
| start.sh      | Запуск всех режимов последовательно                               |

## Быстрый старт
Сборка в нужном режиме:
```
./build.sh release
./build.sh debug
./build.sh coverage
```
Запуск всех режимов подряд:
```
./start.sh
```

## Логика конвейера
1. Проверка наличия Docker-образа:
   - Есть образ — используется напрямую.
   - Нет образа — выполняется `docker build`.

2. Режимы сборки:
- **Release**: оптимизации, `strip`, выпуск `.deb` с номером ревизии в имени файла.
- **Debug**: сборка с debug symbols, формирование двух пакетов (`iperf3` и `iperf3-debug`).
- **Coverage**: сборка с gcov/lcov, запуск интеграционного теста (`iperf3 --version`), генерация HTML-отчета и проверка динамики покрытия. Если покрытие упало относительно прошлого запуска — сборка завершается с ошибкой.

3. История сборок:
- Каждый запуск пишет файл `inst_dir/report/build_report_{date_time}.txt`.
- В отчете фиксируются: номер запуска, ревизия, режим сборки, покрытие (при сборке с coverage).

## Артефакты
- `inst_dir/artifacts/release/*.deb`
- `inst_dir/artifacts/debug/*.deb`
- `inst_dir/artifacts/coverage/*.deb`
- `inst_dir/artifacts/coverage/coverage-report/` (HTML-отчет покрытия)

## Обоснованние модернизаций
- **Multi-stage Docker**: отдельный stage для загрузки исходников и отдельный runner для сборки. Это уменьшает размер финального образа и ускоряет повторные сборки за счет кеширования слоев.

| Одностадийный       | Multi-stage         | Выигрыш          |
| ------------------- | ------------------- | ---------------- |
| ~900MB              | ~800MB              | На 12% меньше размер |
| Весь toolchain      | Только runtime deps | Быстрее pull     |

- **dpkg-deb вместо dh_make/debuild**: позволяет контролировать состав пакета, отдельно формировать debug symbols и добавлять метаданные.

| Стандарт                         | Мой подход                    | Обоснование                                                                                                                       |
| -------------------------------- | ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| dh_make -> debian/rules -> debuild | ./configure -> make -> dpkg-deb | Полный контроль над: <br> - Debug symbols workflow<br> - Custom control файлы <br> - Multi-package output (binary+debug) <br> - Coverage в .deb |

- **Два `.deb` пакета в Debug-сборке**: один для основного приложения и другой для отладочных символов.

## Примечания для проверки
- Все артефакты и отчеты появляются в `inst_dir/`.
- Файл `coverage_last.txt` хранит последнюю метрику покрытия.
- Образ собирается автоматически из `Dockerfile`.

## Примечания для проверки Debug-сборки
Чтобы проверить файл отладочных символов в `gdb`, установите оба `.deb` пакета (основной и `iperf3-debug`), затем выполните:
```
sudo apt update && sudo apt install -y gdb

BUILD_ID=$(readelf -n /usr/bin/iperf3 | awk '/Build ID/ {print $3}')
mkdir -p /usr/lib/debug/.build-id/${BUILD_ID:0:2}
cp /usr/lib/debug/usr/bin/iperf3.debug \
  /usr/lib/debug/.build-id/${BUILD_ID:0:2}/${BUILD_ID:2}.debug

gdb /usr/bin/iperf3
```
Проверка внутри `gdb`:
```
(gdb) list main
(gdb) info sources
```
