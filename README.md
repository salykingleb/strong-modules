# Strong Play Integrity

Два модуля для одного результата: BASIC, DEVICE и STRONG.

| Файл | Куда ставить |
| --- | --- |
| [magisk-strong.zip](magisk-strong.zip) | Magisk 20.4 и новее, в том числе Magisk Alpha |
| [ksu-strong.zip](ksu-strong.zip) | KernelSU, только через приложение KernelSU |

Исходники лежат в папках `magisk/` и `kernelsu/`. Текст модулей на английском.

Оба модуля ставят или включают:

- [Play Integrity Fork](https://github.com/osm0sis/PlayIntegrityFork) от osm0sis
- [Tricky Store](https://github.com/5ec1cff/TrickyStore)
- [Zygisk Assistant](https://github.com/snake-4/Zygisk-Assistant)

Конфликтующие модули выключаются, но не удаляются

`spoofProvider` остаётся 0. Иначе аттестация обходит keybox.

## Magisk

Нужен [Magisk](https://github.com/topjohnwu/Magisk) 20.4 или новее. Используется встроенный Zygisk. ZygiskNext, ReZygisk и NeoZygisk, если они стоят, выключаются.

1. Скачайте `magisk-strong.zip`.
2. Откройте Magisk, вкладка «Модули», «Установить из хранилища».
3. Выберите `magisk-strong.zip`.
4. Нажать Action.
5. Если модуль поставил новые пакеты, перезагрузите телефон если он ен перезагрузился автоматически. Если Play Integrity Fork, Tricky Store и Zygisk Assistant уже стояли, перезагрузка не нужна.

Что делает установка:

- включает Zygisk;
- оставляет Enforce DenyList выключенным, иначе Play Integrity Fork не внедрится в GMS;
- добавляет Play Store, GMS, GSF, Gmail, Key Attestation, Play Integrity API Checker и Advanced Root Checker в список скрытия.

## KernelSU

Нужен [KernelSU](https://github.com/tiann/KernelSU). Recovery этот архив не прошивает. На телефон с Magisk и без `ksud` модуль ставить нельзя: скрипт остановится и ничего не изменит.

KernelSU не имеет встроенного Zygisk, поэтому модуль ставит [ZygiskNext](https://github.com/Dr-TSNG/ZygiskNext). ReZygisk и NeoZygisk выключаются.

1. Скачайте `ksu-strong.zip`.
2. Откройте приложение KernelSU, вкладка модулей, кнопка «+», выберите архив.
3. Дождитесь окончания установки и перезагрузите телефон.
4. После перезагрузки у модуля Strong Play Integrity появляется кнопка Action. Рядом открывается страница модуля, на ней кнопка Start. Обе запускают одну и ту же настройку.

До перезагрузки кнопки нет. Свежая установка лежит в `/data/adb/modules_update/ksustrong`, а приложение смотрит только `/data/adb/modules`. Перезагрузка переносит туда `action.sh` и страницу `webroot`.

Скрытие root на KernelSU делает Zygisk Assistant вместе с Umount modules для нужного приложения. Enforce DenyList у ZygiskNext остаётся выключенным.

## Автор https://t.me/Premium_SMS_Messenger

**If this work was useful to you, you can thank me with the help of USDT (TRC-20).:**

```
THSLZyomC5h7kmQSNPqBSCR6eD1YTD1RXr
```
