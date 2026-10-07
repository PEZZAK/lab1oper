#!/usr/bin/env bash
# collect-info.sh — сбор диагностики для технической поддержки
#
# Собирает сведения о производительности системы в один текстовый файл
# sysinfo-<hostname>-<ГГГГ-ММ-ДД-ЧЧММ>.txt в текущем каталоге.
# Прогресс выводится в stderr, а последней (и единственной) строкой
# в stdout печатается полный путь к файлу отчёта.

set -uo pipefail

OUT="sysinfo-$(hostname)-$(date +%F-%H%M).txt"
: >"$OUT"   # создать пустой файл отчёта

# Прогресс для клиента: только на экран (stderr), в файл не попадает.
say() { printf '%s\n' "$*" >&2; }

# Выполнить команду с таймаутом и записать вывод в отчёт.
# Использование: run "Заголовок" секунды 'команда с аргументами'
run() {
    local title=$1 tmo=$2 cmd=$3 rc
    printf '\n===== %s =====\n' "$title" >>"$OUT"

    if ! command -v "${cmd%% *}" >/dev/null 2>&1; then
        printf '(команда %s недоступна)\n' "${cmd%% *}" >>"$OUT"
        return 0
    fi

    timeout "$tmo" bash -c "$cmd" >>"$OUT" 2>&1
    rc=$?
    if [ "$rc" -eq 124 ]; then
        printf '(команда не уложилась в %s с — таймаут)\n' "$tmo" >>"$OUT"
    elif [ "$rc" -ne 0 ]; then
        printf '(команда завершилась с кодом %s)\n' "$rc" >>"$OUT"
    fi
    return 0
}

main() {
    say "Собираю общие сведения..."
    run "Время сбора"   5 'date'
    run "Пользователь"  5 'id'
    # Скрипт рассчитан на запуск без root: помечаем это в отчёте,
    # чтобы инженер понимал, почему каких-то данных может не быть.
    if [ "$(id -u)" -ne 0 ]; then
        printf '(скрипт запущен без прав root: часть данных может быть недоступна)\n' >>"$OUT"
    fi
    run "Система"       5 'uname -a'
    run "Аптайм"        5 'uptime'
    run "Версия ОС"     5 'cat /etc/os-release'
    run "Процессор"     5 'lscpu'

    say "Снимаю замеры нагрузки (около 5 секунд)..."
    run "Нагрузка за 5 секунд (vmstat; столбец wa — ожидание диска)" 10 'vmstat 1 5'
    run "Топ-10 по CPU"    5 'ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -11'
    run "Топ-10 по памяти" 5 'ps -eo pid,user,%mem,%cpu,comm --sort=-%mem | head -11'

    say "Собираю сведения о дисках..."
    run "Диски: место (df -h)"  10 'df -h'
    run "Диски: inode (df -i)"  10 'df -i'

    say "Готово."
    printf '%s\n' "$PWD/$OUT"
}

main "$@"
