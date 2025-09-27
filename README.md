# Yandex Disk UI для Synology DSM

Интеграция официального [Консольного клиента Яндекс Диск для Linux](https://yandex.ru/support/yandex-360/customers/disk/desktop/linux/ru/) в Synology DSM.  
Авторизация и синхронизация выполняются через оригинальную утилиту `yandex-disk` адаптированную для использования в среде Synology DSM.  

## 🖼 Интерфейс
<p align="center">
  <img width="48%" alt="status" src="https://github.com/user-attachments/assets/0eb2f74b-d614-423b-973c-418b881b7947" />
  <img width="48%" alt="log" src="https://github.com/user-attachments/assets/fe684ab1-3751-4887-94b1-5c6aeb1cbda2" />
</p>

## 🚀 Возможности
- Простая установка как `.spk`-пакет
- Первоначальная настройка через SSH
- Графический интерфейс с возможностью:
   - Отображения статуса Yandex Disk
   - Логирования состояния
   - Очистки логов
 
## 📋 Требования
- DSM **7.x**  
- Устройства **x86_64**  
- Доступ по **SSH** для первоначальной настройки

---

## 🔧 УСТАНОВКА
### [🎥 Видео-инструкция на Youtube](https://youtu.be/KB_YwQbxSW8)

1. При установке **отметьте чекбокс** `Запустить после установки`.

2. После установки **выдайте права на папку синхронизации**:
   - Перейдите в: `Панель управления → Папка общего доступа → [ваша папка] → Редактировать → Разрешения`
   - В разделе **Внутренний пользователь системы** найдите пользователя `sc-yandexdisk`
   - Выдайте права на **чтение и запись**

---

## 🖥 ПЕРВОНАЧАЛЬНАЯ НАСТРОЙКА

1. Подключитесь к NAS по **SSH**:
   - `Панель управления → Терминал и SNMP → Включить службу SSH`
   - Подключитесь по SSH

2. Найдите путь к папке для синхронизации, например:
   ```bash
   /volume1/yandexsync

3. Выполните команду:
   ```bash
   sudo -u sc-yandexdisk yandex-disk setup

4. Ответы на вопросы установщика:
   - Использовать прокси? Нет
   ```bash
   Would you like to use a proxy server? [y/N]: N
   ```
  
   - Авторизуйтесь в браузере, где выполнен вход в Яндекс.Диск 
   
   - Укажите путь к директории для синхронизации (оберните путь в кавычки если есть пробелы):
   ```bash
     Enter path to Yandex.Disk folder (Leave empty to use default folder '/var/packages/YandexDisk/home/Yandex.Disk'): "/volume1/yandex sync"
   ```
   
   - Не создавайте демон автозапуска (DSM самостоятельно управляет службами и обеспечит автозапуск):
   ```bash
     Would you like Yandex.Disk to launch on startup? [Y/n]: n
   ```

5. Завершение:
   ```bash
   Starting daemon process...Done
   ```

   - Обновите страницу DSM (F5)
   - Откройте приложение Yandex Disk в интерфейсе DSM
   - Проверьте статус и лог в приложении

---
## 🗂️ Исключение некоторых директорий из синхронизации (опционально)  
### [🎥 Видео-инструкция на Youtube](https://youtu.be/g0zbFXbrKWA)

1. Подключаемся к NAS по **SSH**
2. Повышаем привилегии:
   ```
   sudo -i
   ```
3. Открываем конфиг и добавляем строку вида `exclude-dirs=DIR1,DIR2,DIR3`  
   ```
   vim /var/packages/YandexDisk/home/.config/yandex-disk/config.cfg
   ```
   Например `exclude-dirs=DoNotSync,Не синхронизировать,учёба,работа`  
   Чтобы настройка действовала корректно, названия исключаемых директорий нужно перечислять через запятую, без пробелов.

---
## 🐞 Обратная связь
Связаться можно [в комментариях на YouTube](https://youtu.be/KB_YwQbxSW8) или в [Issue](https://github.com/VitalityV1nT/yandexdisk-dsm-app/issues).

---
## 🙏 Благодарности
Проект вдохновлён инструкцией от Александра Linux: [Установка WireGuard на Synology NAS](https://bafista.ru/ustanovka-wireguard-na-synology-nas-v-dsm-7-i-dsm-6/)
