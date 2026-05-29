# Changelog — ARM-сборка

Все изменения ARM64-версии пакета. Базовый пакет — x86_64
`0.1.6.1080-3` (ветка `main`).

## [0.1.6.1080-4] (ARM) — 2026-05-29

### Added
- **Поддержка ARM64 / aarch64** (Synology DS124, RTD1619B и другие aarch64-модели).
- Нативный движок **rclone v1.74.2** (`linux-arm64`, статически слинкован) с
  встроенным бэкендом Yandex Disk — вместо проприетарного `yandex-disk` CLI,
  который не имеет ARM-сборки.
- Обёртка `yandex-disk` (POSIX sh): `start|stop|status|sync|setup|version|rclone`,
  реализованная поверх `rclone bisync` (двусторонняя синхронизация). Сохраняет
  совместимость с UI пакета и скриптами `yandex-logger` / `yandex-cleaner`
  (в т.ч. строку `Error: daemon not started` для статуса).
- `rclone` добавлен в `conf/resource` (`usr-local-linker`) → доступен как
  `/usr/local/bin/rclone`.
- Документация: `README-ARM.md`, `RELEASE-INFO-ARM.txt`, `build_notes.txt`.
- Скрипты ручной проверки на NAS: `test-on-nas-install.sh`,
  `test-on-nas-functional.sh`.
- `.gitattributes` — фиксирует `eol=lf` для shell-скриптов (защита от
  CRLF при `core.autocrlf=true`).
- Контрольная сумма `YandexDisk-ARM.spk.sha256`.

### Changed
- `INFO`:
  - `displayname`: `Yandex Disk` → `Yandex Disk (ARM)`
  - `version`: `0.1.6.1080-3` → `0.1.6.1080-4` (числовая ревизия — требование DSM; «ARM» вынесено в `displayname`)
  - `arch`: список x86 (apollolake, broadwell, …) → `rtd1619b rtd1296 armada37xx armada38x alpine4k`
  - `description`: дополнено про ARM64 / DS124 / rclone.
  - Поля `package`, `os_min_ver`, `maintainer`, `dsmuidir`, `dsmappname` — без изменений.
- `spk/package/yandex-disk`: бинарник x86_64 заменён обёрткой над rclone
  (оригинал сохранён как `spk/package/yandex-disk.x86_64.backup`, в `.spk` не входит).

### Fixed
- Нормализованы окончания строк **CRLF → LF** во всех shell-скриптах
  (`start-stop-status`, `yandex-logger`, `yandex-cleaner`, `ui/scripts/*.cgi`).
  CRLF (появлявшийся из-за `core.autocrlf=true`) ломал бы `#!/bin/sh` и
  разбор `case/if` при запуске на DSM.
- **Исправлена ошибка установки «Неверный формат файла»** в DSM:
  - `INFO` и `conf/*` нормализованы в LF (CRLF ломал разбор управляющих файлов);
  - версия приведена к числовой ревизии (`-arm`-суффикс отвергался валидатором DSM);
  - `.spk` пересобран с владельцем `root` и без PAX-заголовков (формат GNU tar).

### Notes
- 32-битные платформы `armada38x` / `alpine4k` присутствуют в `arch` для широты
  установки, но нативный arm64-бинарник на них не запустится — нужна отдельная
  armv7-сборка rclone.
- Функциональная синхронизация с реальным аккаунтом Yandex Disk проверяется на
  NAS (скрипты `test-on-nas-*.sh`); на этапе сборки проверяются структура
  пакета, архитектура бинарника и корректность скриптов.
