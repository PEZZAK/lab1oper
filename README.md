# Лабораторная работа 1. Скрипт сбора диагностики для технической поддержки
 
**Студент:** Старков Владимир Андреевич, ИКНТ, ПГНИУ
**Файлы:** `collect-info.sh` (скрипт), `sysinfo-<hostname>-<дата>.txt` (результат запуска)
 
---
 
## 1. Задача
 
Клиент жалуется: «сервер тормозит». Доступа к машине нет, администратором клиент не является. Поэтому ему отправляют один скрипт, а он присылает обратно один текстовый файл. Скрипт собирает только то, что относится к производительности, и делится на три блока:
 
| Блок | Команды | Зачем |
|---|---|---|
| Система | `date`, `id`, `uname -a`, `uptime`, `/etc/os-release`, `lscpu` | с чем имеем дело, сколько ядер, под кем запущен скрипт |
| Нагрузка | `vmstat 1 5`, топ-10 по CPU, топ-10 по памяти | кто занял ресурсы и во что упирается машина |
| Диски | `df -h`, `df -i` | переполненный раздел или кончившиеся inode |
 
## 2. Листинг скрипта
 
```bash
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
```
 
## 3. Как это работает
 
### Каркас
 
| Строка | Что делает |
|---|---|
| `#!/usr/bin/env bash` | shebang: ищет `bash` в `PATH`, поэтому работает и там, где bash лежит не в `/bin` |
| `set -uo pipefail` | `-u` — обращение к необъявленной переменной считается ошибкой. `-o pipefail` — код возврата конвейера равен коду первой упавшей команды. Флага `-e` нет **намеренно**: скрипт не должен умирать, если одна из команд упала, он обязан собрать всё остальное |
| `OUT="sysinfo-$(hostname)-$(date +%F-%H%M).txt"` | имя файла. `date +%F` даёт `ГГГГ-ММ-ДД`, `%H%M` — часы и минуты |
| `: >"$OUT"` | `:` — пустая команда, перенаправление `>` создаёт файл (или обнуляет, если он уже есть). Так файл существует с самого начала |
| `say() { printf '%s\n' "$*" >&2; }` | вывод прогресса. `>&2` отправляет его в **stderr**, поэтому в stdout и в файл он не попадает. `printf` вместо `echo` — потому что `echo` по-разному ведёт себя со строками, начинающимися с `-` |
 
### Функция run
 
| Строка | Что делает |
|---|---|
| `local title=$1 tmo=$2 cmd=$3 rc` | аргументы: заголовок, таймаут в секундах, команда строкой. `local` не даёт переменным «утечь» наружу |
| `printf '\n===== %s =====\n' "$title" >>"$OUT"` | заголовок блока. `>>` дописывает в конец файла |
| `${cmd%% *}` | подстановка параметра: удаляет самый длинный суффикс, подходящий под `" *"`, то есть всё после первого пробела. Остаётся имя утилиты: из `'vmstat 1 5'` получается `vmstat` |
| `command -v "..." >/dev/null 2>&1` | проверяет, что команда существует (встроенная в оболочку, функция, файл в `PATH`). Вывод выбрасывается, нужен только код возврата |
| `(команда ... недоступна)` + `return 0` | отсутствие утилиты не ошибка: пишем пометку и идём дальше |
| `timeout "$tmo" bash -c "$cmd"` | запускает команду с лимитом времени. `bash -c` нужен потому, что в `$cmd` целая строка с конвейером (`ps ... \| head -11`), а `timeout` умеет запускать только одну программу |
| `>>"$OUT" 2>&1` | stdout команды идёт в файл, а stderr направлен туда же (`2>&1`). Порядок важен: сначала файл, потом дублирование. Сообщения об ошибках («Permission denied») попадают в отчёт и не видны клиенту на экране |
| `rc=$?` | код возврата **сразу** после `timeout`: любая другая команда между ними его бы перетёрла |
| `rc -eq 124` | `timeout` возвращает 124, если убил команду по времени. Это отдельная пометка «таймаут» |
| `rc -ne 0` | любая другая ненулевая причина: пометка «завершилась с кодом N» |
| `return 0` | функция всегда успешна, поэтому один сбой не ломает остальной сбор |
 
### Функция main
 
- Блок **«Система»**: `date`, `id`, `uname -a` (ядро и архитектура), `uptime` (время работы и load average за 1/5/15 минут), `cat /etc/os-release` (дистрибутив), `lscpu` (число ядер, модель, кэши).
- `if [ "$(id -u)" -ne 0 ]`: `id -u` печатает числовой UID, у root он равен 0. Если скрипт запущен без root, в отчёт добавляется пометка, чтобы инженер знал, откуда возможные пробелы в данных. Сами команды выбраны так, что обычному пользователю они доступны.
- Блок **«Нагрузка»**: `vmstat 1 5` выводит 5 строк с интервалом 1 с. Таймаут 10 с с запасом: реальное время около 4 с. `ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -11`: `-e` — все процессы, `-o` — выбранные столбцы, `--sort=-%cpu` — по убыванию CPU, `head -11` оставляет заголовок и 10 процессов. Для памяти — то же с `-%mem`.
- Блок **«Диски»**: `df -h` — место в человекочитаемом виде, `df -i` — inode.
- `printf '%s\n' "$PWD/$OUT"`: единственная строка в stdout, абсолютный путь к файлу.
- `main "$@"`: запуск главной функции с передачей аргументов скрипта. Это стандартная структура: сначала определения, потом одна точка входа.
### Что показывают ключевые команды
 
- **`vmstat 1 5` — серия, а не снимок.** Состояние «тормозит» развивается во времени. Первая строка вывода — средние значения с момента загрузки системы, остальные четыре — реальные замеры по секундам.
- **Столбец `wa`** — доля времени, когда процессор простаивал в ожидании диска. Высокий `wa` при низком `us`+`sy` означает, что процессы заблокированы вводом-выводом и упирается диск, а не процессор. Столбец `b` — число процессов, заблокированных на I/O, `r` — число процессов в очереди на процессор.
- **`df -i`** нужен потому, что раздел может быть заполнен не байтами, а inode (миллионы мелких файлов). `df -h` при этом покажет свободное место, а создавать файлы будет нельзя.
## 4. Проверка требований
 
| № | Требование | Как выполнено | Проверка |
|---|---|---|---|
| 1 | Таймаут, отдельная пометка при коде 124 | `timeout` в `run`, ветка `rc -eq 124` | тестовая команда `sleep 5` с лимитом 1 с дала «(команда не уложилась в 1 с — таймаут)» |
| 2 | Проверка наличия через `command -v` | начало `run` | вымышленная `nonexistent-tool` дала «(команда nonexistent-tool недоступна)» |
| 3 | Работа без root | пометка в отчёте, ошибки уходят в файл | реальный запуск от обычного пользователя `vboxuser` (UID 1000): в отчёте есть пометка «скрипт запущен без прав root», ошибок на экране нет. Дополнительно в тесте от `nobody` команда `cat /root/secret` дала «Permission denied» только в файле и код 1 |
| 4 | Разделение потоков | `say` пишет в stderr, `run` — в файл, `printf` в конце — в stdout | `./collect-info.sh 2>/dev/null \| wc -l` на виртуальной машине Ubuntu 24.04 выдал **1** |
| 5 | `shellcheck` без error и warning | — | `shellcheck collect-info.sh` (версия 0.9.0-1 на ВМ Ubuntu) ничего не вывел, то есть замечаний нет |
 
## 5. Что добавлено к каркасу
 
Каркас задания сохранён без изменений. Дописаны:
 
1. блок `os-release` и `lscpu`, топ по CPU и блок дисков (были помечены TODO);
2. блоки `date` и `id`, чтобы инженер видел, когда и под кем собраны данные;
3. пометка о запуске без root;
4. в заголовок блока vmstat добавлена подсказка про столбец `wa`;
5. сообщение «Готово.» в stderr перед печатью пути.
## 6. Ограничения скрипта
 
- `command -v` проверяет только **первое слово** строки. В `'ps ... | head -11'` проверяется `ps`, а наличие `head` — нет.
- Код возврата конвейера внутри `bash -c` — это код **последней** команды (`head`), так как `pipefail` в дочернем bash не включён. Поэтому сбой `ps` не был бы помечен кодом ошибки.
- `%CPU` в `ps` считается как среднее за всё время жизни процесса, а не мгновенное значение. Мгновенную картину даёт `vmstat`.
- Скрипт написан под Linux. На macOS нет `lscpu` и `/etc/os-release`, а у `ps` другие ключи: такие блоки получат пометку «недоступна» или «код N».
## 7. Результат работы
 
Скрипт запущен на виртуальной машине VirtualBox: Ubuntu 24.04.3 LTS, ядро 7.0.0-31-generic, 4 ядра (Intel Core i7-13620H), пользователь `vboxuser` без root.
 
```
vboxuser@UbuntuLinux:~$ ./collect-info.sh
Собираю общие сведения...
Снимаю замеры нагрузки (около 5 секунд)...
Собираю сведения о дисках...
Готово.
/home/vboxuser/sysinfo-UbuntuLinux-2026-10-07-1139.txt
```
 
Скрипт печатает в stdout только путь к файлу, а не его содержимое (требование 4). Чтобы сразу вывести содержимое отчёта на экран, нужно выполнить команду:
 
```
cat "$(./collect-info.sh)"
```
 
Здесь `$(./collect-info.sh)` запускает скрипт и подставляет его stdout, то есть путь к отчёту, а `cat` выводит этот файл. Прогресс («Собираю общие сведения...») при этом по-прежнему идёт в stderr и виден на экране. Кавычки защищают путь от разбиения по пробелам.
 
Содержимое файла `sysinfo-UbuntuLinux-2026-10-07-1139.txt` (приложен отдельным файлом):
 
```
===== Время сбора =====
Wed Oct  7 11:39:26 AM UTC 2026
 
===== Пользователь =====
uid=1000(vboxuser) gid=1000(vboxuser) groups=1000(vboxuser),4(adm),24(cdrom),27(sudo),30(dip),46(plugdev),100(users),114(lpadmin)
(скрипт запущен без прав root: часть данных может быть недоступна)
 
===== Система =====
Linux UbuntuLinux 7.0.0-31-generic #31~24.04.1-Ubuntu SMP PREEMPT_DYNAMIC Mon Aug 10 09:38:02 UTC 2 x86_64 x86_64 x86_64 GNU/Linux
 
===== Аптайм =====
 11:39:26 up 13 min,  1 user,  load average: 1.15, 2.35, 1.77
 
===== Версия ОС =====
PRETTY_NAME="Ubuntu 24.04.3 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION="24.04.3 LTS (Noble Numbat)"
VERSION_CODENAME=noble
ID=ubuntu
ID_LIKE=debian
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
UBUNTU_CODENAME=noble
LOGO=ubuntu-logo
 
===== Процессор =====
Architecture:                            x86_64
CPU op-mode(s):                          32-bit, 64-bit
Address sizes:                           39 bits physical, 48 bits virtual
Byte Order:                              Little Endian
CPU(s):                                  4
On-line CPU(s) list:                     0-3
Vendor ID:                               GenuineIntel
Model name:                              13th Gen Intel(R) Core(TM) i7-13620H
CPU family:                              6
Model:                                   186
Thread(s) per core:                      1
Core(s) per socket:                      4
Socket(s):                               1
Stepping:                                2
BogoMIPS:                                5836.78
Flags:                                   fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ht syscall nx rdtscp lm constant_tsc rep_good nopl xtopology nonstop_tsc cpuid tsc_known_freq pni pclmulqdq ssse3 fma cx16 sse4_1 sse4_2 x2apic movbe popcnt aes xsave avx f16c rdrand hypervisor lahf_lm abm 3dnowprefetch fsgsbase bmi1 avx2 bmi2 invpcid rdseed adx clflushopt sha_ni arat md_clear flush_l1d arch_capabilities
Hypervisor vendor:                       KVM
Virtualization type:                     full
L1d cache:                               128 KiB (4 instances)
L1i cache:                               256 KiB (4 instances)
L2 cache:                                8 MiB (4 instances)
L3 cache:                                96 MiB (4 instances)
NUMA node(s):                            1
NUMA node0 CPU(s):                       0-3
Vulnerability Gather data sampling:      Not affected
Vulnerability Ghostwrite:                Not affected
Vulnerability Indirect target selection: Mitigation; Aligned branch/return thunks
Vulnerability Itlb multihit:             Not affected
Vulnerability L1tf:                      Not affected
Vulnerability Mds:                       Not affected
Vulnerability Meltdown:                  Not affected
Vulnerability Mmio stale data:           Not affected
Vulnerability Old microcode:             Not affected
Vulnerability Reg file data sampling:    Vulnerable: No microcode
Vulnerability Retbleed:                  Not affected
Vulnerability Spec rstack overflow:      Not affected
Vulnerability Spec store bypass:         Vulnerable
Vulnerability Spectre v1:                Mitigation; usercopy/swapgs barriers and __user pointer sanitization
Vulnerability Spectre v2:                Mitigation; Retpolines; STIBP disabled; RSB filling; PBRSB-eIBRS Not affected; BHI SW loop, KVM SW loop
Vulnerability Srbds:                     Not affected
Vulnerability Tsa:                       Not affected
Vulnerability Tsx async abort:           Not affected
Vulnerability Vmscape:                   Not affected
 
===== Нагрузка за 5 секунд (vmstat; столбец wa — ожидание диска) =====
procs -----------memory---------- ---swap-- -----io---- -system-- -------cpu-------
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st gu
 9  0      0 639264  20500 3658004    0    0  4811  5357 6759   26 28 11 60  1  0  0
 1  0      0 634220  20552 3658276    0    0   168   292 8799 12629 29  9 62  0  0  0
 0  0      0 637928  20552 3656792    0    0     0     0 7276 9386 21  7 72  0  0  0
 2  0      0 637672  20552 3656792    0    0     0     0 3741 3663  5  3 92  0  0  0
 2  0      0 637672  20576 3656764    0    0     0   512 4576 4529  7  5 86  2  0  0
 
===== Топ-10 по CPU =====
    PID USER     %CPU %MEM COMMAND
  32506 vboxuser  100  0.0 ps
   2071 vboxuser 38.6  7.3 gnome-shell
   2725 vboxuser 36.9  9.8 firefox
   3450 vboxuser 21.3  6.7 Isolated Web Co
   4638 root      2.9  0.8 snapd
  32413 vboxuser  2.5  0.9 gnome-terminal-
      1 root      1.6  0.2 systemd
    587 root      1.1  0.0 kworker/u17:3-loop6
  32486 vboxuser  0.9  0.5 tracker-extract
     40 root      0.7  0.0 kworker/u17:0-events_unbound
 
===== Топ-10 по памяти =====
    PID USER     %MEM %CPU COMMAND
   2725 vboxuser  9.8 36.9 firefox
   2071 vboxuser  7.3 38.6 gnome-shell
   3450 vboxuser  6.7 21.3 Isolated Web Co
   2911 vboxuser  2.2  0.1 Privileged Cont
   3267 vboxuser  1.5  0.0 WebExtensions
   3447 vboxuser  1.5  0.2 Isolated Servic
   3628 vboxuser  1.1  0.0 Web Content
   3718 vboxuser  1.1  0.0 Web Content
   3712 vboxuser  1.1  0.0 Web Content
   2621 vboxuser  1.0  0.1 gjs
 
===== Диски: место (df -h) =====
Filesystem      Size  Used Avail Use% Mounted on
tmpfs           581M  1.8M  579M   1% /run
/dev/sda2        20G  8.7G  9.9G  47% /
tmpfs           2.9G     0  2.9G   0% /dev/shm
tmpfs           5.0M  8.0K  5.0M   1% /run/lock
tmpfs           581M  120K  580M   1% /run/user/1000
 
===== Диски: inode (df -i) =====
Filesystem      Inodes  IUsed   IFree IUse% Mounted on
tmpfs           742518   1116  741402    1% /run
/dev/sda2      1310720 216623 1094097   17% /
tmpfs           742518      1  742517    1% /dev/shm
tmpfs           742518      4  742514    1% /run/lock
tmpfs           148503    166  148337    1% /run/user/1000
```
 
## 8. Разбор полученного отчёта
 
Так инженер поддержки прочитал бы этот файл.
 
- **Система.** Ubuntu 24.04.3, 4 ядра, 4 потока, гипервизор KVM, то есть это виртуальная машина. Аптайм 13 минут, load average 1.15 / 2.35 / 1.77: нагрузка за последние минуты падала.
- **vmstat.** В первой строке `wa` = 60, но она показывает среднее с момента загрузки, а не текущее состояние. В остальных четырёх строках `wa` равен 0–2, а `id` (простой процессора) 62–92 %. Значит, в момент замера диск не был узким местом, а процессор был свободен. Столбец `b` (заблокированные на вводе-выводе) везде 0, `r` в первой строке 9, то есть в начале была очередь на процессор.
- **Топ по CPU и памяти.** Больше всего процессора и памяти используют `gnome-shell` (38,6 % CPU, 7,3 % MEM) и `firefox` (36,9 % CPU, 9,8 % MEM), то есть графическая оболочка и браузер. Нагрузку от них можно считать нормальной для рабочего стола.
- **Строка `ps` с 100 % CPU.** Это артефакт измерения: `%CPU` в `ps` считается как среднее за время жизни процесса, а сам `ps` существует доли секунды и всё это время работает. Это один из пунктов раздела 6.
- **Диски.** Корневой раздел `/dev/sda2` занят на 47 % (8,7 из 20 ГБ), inode использованы на 17 %. Переполнения нет ни по месту, ни по inode.
- **Вывод.** Явной причины «тормозов» в данных нет: диск и inode в порядке, `wa` в замерах низкий, свободной памяти по `vmstat` около 640 МБ при большом кэше (около 3,6 ГБ). Единственный заметный потребитель ресурсов — рабочий стол с браузером.
