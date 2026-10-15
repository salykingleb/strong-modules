# Strong Play Integrity

Два модуля для одного результата: BASIC, DEVICE и STRONG.

| Файл | Куда ставить |
| --- | --- |
| [magisk-strong.zip](magisk-strong.zip) | Magisk 20.4 и новее, в том числе Magisk Alpha |
| [ksu-strong.zip](ksu-strong.zip) | KernelSU, только через приложение KernelSU |

Исходники лежат в папках `magisk/` и `kernelsu/`. Текст модулей на английском.

Keybox в этот репозиторий не входит. Модуль его не скачивает. Свой файл нужно положить самому.

## Общее для обоих

Свой keybox кладётся в корень архива до прошивки. Файл должен называться `keybox.xml`. В модуле Magisk также подходит имя `Keybox.xml`. В модуле KernelSU имя только `keybox.xml`: регистр важен.

Если файла в архиве нет, модуль ищет его здесь:

- `/sdcard/Download/keybox.xml`
- `/sdcard/keybox.xml`

Модуль Magisk, если своего файла нет, оставляет уже установленный `/data/adb/tricky_store/keybox.xml`. Модуль KernelSU так не делает: без `keybox.xml` в архиве или в Download установка останавливается.

Программный AOSP keybox Strong не даёт. Нужен свой неотзывной аппаратный keybox.

Оба модуля ставят или включают:

- [Play Integrity Fork](https://github.com/osm0sis/PlayIntegrityFork) от osm0sis
- [Tricky Store](https://github.com/5ec1cff/TrickyStore)
- [Zygisk Assistant](https://github.com/snake-4/Zygisk-Assistant)

Конфликтующие модули выключаются, но не удаляются: Shamiko, старый SafetyNet Fix, PlayCurl, YuriKey, дополнения Tricky Store. YouTube, hosts и LSPosed не трогаются. LSPosed иногда ломает Strong.

`spoofProvider` остаётся 0. Иначе аттестация обходит keybox.

Root для `com.google.android.gms` не выдавать.

Проверка: [Play Integrity API Checker](https://github.com/1nikolas/play-integrity-checker-app). Ждите три отметки: BASIC, DEVICE и STRONG.

## Magisk

Нужен [Magisk](https://github.com/topjohnwu/Magisk) 20.4 или новее. Используется встроенный Zygisk. ZygiskNext, ReZygisk и NeoZygisk, если они стоят, выключаются.

1. Скачайте `magisk-strong.zip`.
2. Положите `keybox.xml` или `Keybox.xml` в корень архива. Не в подпапку. Этот шаг можно пропустить, если keybox уже лежит в `/data/adb/tricky_store/keybox.xml` или в `/sdcard/Download`.
3. Откройте Magisk, вкладка «Модули», «Установить из хранилища».
4. Выберите `magisk-strong.zip`.
5. Кнопка Action появляется сразу, без перезагрузки. Надпись кнопки в приложении Magisk — Action.
6. Если модуль поставил новые пакеты, перезагрузите телефон. Если Play Integrity Fork, Tricky Store и Zygisk Assistant уже стояли, перезагрузка не нужна.
7. Повторный запуск: кнопка Action у Strong Play Integrity.

Что делает установка:

- включает Zygisk;
- оставляет Enforce DenyList выключенным, иначе Play Integrity Fork не внедрится в GMS;
- добавляет Play Store, GMS, GSF, Gmail, Key Attestation, Play Integrity API Checker и Advanced Root Checker в список скрытия.

На этом телефоне модуль Magisk уже проверялся: после Action checker показал BASIC, DEVICE и STRONG.

## KernelSU

Нужен [KernelSU](https://github.com/tiann/KernelSU). Recovery этот архив не прошивает. На телефон с Magisk и без `ksud` модуль ставить нельзя: скрипт остановится и ничего не изменит.

KernelSU не имеет встроенного Zygisk, поэтому модуль ставит [ZygiskNext](https://github.com/Dr-TSNG/ZygiskNext). ReZygisk и NeoZygisk выключаются.

1. Скачайте `ksu-strong.zip`.
2. Положите `keybox.xml` в корень архива. Имя строго `keybox.xml`.
3. Откройте приложение KernelSU, вкладка модулей, кнопка «+», выберите архив.
4. Дождитесь окончания установки и перезагрузите телефон.
5. После перезагрузки у модуля Strong Play Integrity появляется кнопка Action. Рядом открывается страница модуля, на ней кнопка Start. Обе запускают одну и ту же настройку.

До перезагрузки кнопки нет. Свежая установка лежит в `/data/adb/modules_update/ksustrong`, а приложение смотрит только `/data/adb/modules`. Перезагрузка переносит туда `action.sh` и страницу `webroot`.

Скрытие root на KernelSU делает Zygisk Assistant вместе с Umount modules для нужного приложения. Enforce DenyList у ZygiskNext остаётся выключенным.

## Если GitHub недоступен с телефона

Рядом с модулем можно заранее положить официальные zip:

- `playintegrityfix.zip`
- `tricky_store.zip`
- `zygisk-assistant.zip`
- для KernelSU ещё `zygisksu.zip`

Модуль сначала пробует скачать свежий релиз, а при ошибке берёт этот локальный архив.

## Чего в репозитории нет

`keybox.xml` с рабочего стола и из локальных архивов сюда не загружен. Это закрытый ключ. Его добавляют в скачанный zip у себя, перед прошивкой.
