# CLAUDE.md — канон проекта yandexdisk-dsm-app

DSM-пакет (.spk) «Яндекс Диск» для ARM64 Synology NAS: POSIX-sh обёртка над rclone bisync.
Полные правила: docs/deterministic-result-guideline.md и -2.md. Здесь — обязательный минимум.

## Гейты (после любой нетривиальной правки, до сдачи)
    bash build.sh && bash test/run-hermetic.sh && sh test/check-coverage.sh && bash test/check-reproducible.sh
Мутационный гейт — `sh test/mutate.sh` (score ≥ YD_MUT_MIN, по умолч. 90; эквиваленты
в test/mutate.equiv). Тяжёлый (~2 мин), поэтому on-demand / ночью (CI mutation.yml),
а не на каждую правку. Пороги покрытия/мутации: YD_COV_MIN / YD_MUT_MIN.
Полный справочник по запуску — docs/ai-workflow.md §1.
Падает — чинить первопричину и перезапускать цепочку с начала. Глушить, ослаблять или
обходить проверки запрещено. Правки build.sh, test/, .github/workflows/ — только
отдельным PR, не вместе с кодом, который они проверяют.

## Жёсткие правила
- Скрипты пакета — только POSIX sh (#!/bin/sh, проходят dash -n). bash допустим только в
  build.sh и test-on-nas-*.sh. Новый sh-скрипт → сразу добавить в POSIX_SH в build.sh.
- Общие пути/парсер config.cfg/ротация/формат статуса — только из spk/package/common.sh;
  копировать значения в другие скрипты запрещено.
- Нет резидентного демона: синхронизацию запускает DSM Task Scheduler
  («yandex-disk sync»); start-stop-status держит только heartbeat yandex-logger.
- Контракты (менять только с синхронной правкой всех потребителей и явным одобрением):
  - маркеры лога rclone: «Queue copy to Path2» (отправлено), «Queue copy to Path1»
    (получено), «Copied (replaced existing)» (изменено), «Queue delete» (удалено);
    триггер recovery «cannot find prior» / «Must run --resync»;
    заголовок прогона «===== sync started»;
  - sync.state — 7 полей «status|timestamp|result|sent|received|modified|deleted»;
    старый 3-полевой формат обязан оставаться читаемым;
  - ключи вкладок UI = имена CGI: status / log / sync_log; имя remote: yandexdisk.
- Версия релиза меняется синхронно: spk/INFO + CHANGELOG-ARM.md + RELEASE-INFO-ARM.txt.
- Секреты (OAuth-токен, rclone.conf) — никогда в код, git или логи. Привилегии пакета
  (run-as: package) не повышать. --exclude-список в _bisync не урезать.
- Воспроизводимость build.sh (--sort, --mtime, --numeric-owner, gzip -n, пиннинг
  RCLONE_VERSION + 2×SHA256) не ломать.

## Периметр
- Рабочее дерево пакета: spk/ (+ build.sh, test/, docs/ по задаче).
- НЕ читать как источник истины и НЕ править: test_package/ (устаревшая x86-копия с
  другим набором скриптов), spk/package/*.backup, downloads/, готовые *.spk в корне.
  Это локальные артефакты вне git; правка в них — мёртвая правка.
- Среда: WSL2 / bash, POSIX-пути; никаких PowerShell-путей.

## Остановись и спроси человека, если задача требует
ослабить security-инвариант; сменить версию rclone (новые SHA256 + перепроверка
маркеров в бинаре); вернуть резидентный демон; изменить любой контракт из списка выше;
менять флаги воспроизводимости build.sh; внести изменение, которое проверяется только
на реальном NAS и не покрывается герметичным тестом.
