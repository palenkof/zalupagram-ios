# ZalupaGram для iOS

Неофициальный форк [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS), iOS-версия ZalupaGram. Не связан с Telegram и не одобрен им.

Приложение ставится через AltStore или SideStore на бесплатный Apple ID: подпись продлевается раз в 7 дней, пуш-уведомлений и входящих звонков при закрытом приложении нет.

## Сборка

Собирается в GitHub Actions на раннере `xcode-27`: вкладка **Actions → Сборка ZalupaGram → Run workflow**.

- Без галочки получается тестовая сборка `build-N`, с галочкой — релиз `vX.Y.Z` из `zalupagram/version.json`.
- Готовый `.ipa` выкладывается в приватный репозиторий релизов, в этом репозитории его нет.
- Первая сборка идёт 1–3 часа, дальше быстрее за счёт кеша Bazel.

Нужные секреты репозитория:

| Секрет | Что это |
|---|---|
| `TELEGRAM_API_ID` | api_id с my.telegram.org |
| `TELEGRAM_API_HASH` | api_hash оттуда же |
| `RELEASES_TOKEN` | fine-grained токен с правом Contents: read and write на репозиторий релизов |

Подпись фейковая (самоподписанный сертификат из `build-system/fake-codesigning`, профили под наш bundle ID делает `zalupagram/ci/make_fake_codesigning.py`), настоящую ставит AltStore при установке.

## Код форка

- `zalupagram/` — версия, bundle ID, скрипты сборки.
- Правки в коде Telegram помечены комментарием `ZalupaGram`.
- Оригинальная инструкция по сборке: [docs/UPSTREAM_README.md](docs/UPSTREAM_README.md).

## Лицензия

GPL v2, как у Telegram-iOS.
