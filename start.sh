#!/bin/bash

# =================================================
# Multi-mode start script for InfoTecs Test-case
# =================================================
# Программа для запуска всех вариантов сборок
# =================================================

# Запуск Release-сборки
echo -e "\033[36mЗапуск Release-сборки\033[0m"
./build.sh release

# Запуск Debug-сборки
echo -e "\033[36mЗапуск Debug-сборки\033[0m"
./build.sh debug

# Запуск Coverage-сборки
echo -e "\033[36mЗапуск Coverage-сборки\033[0m"
./build.sh coverage
