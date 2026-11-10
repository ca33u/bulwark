# Выпуск новой версии

Сборку и выкладку делает GitHub Actions (BigWigsMods/packager, файл `.github/workflows/release.yml`).
Он собирает zip без тестов и служебных файлов (список — в `.pkgmeta`) и выкладывает его
на **CurseForge**, **Wago Addons** и в **GitHub Releases** как файл для WoW Forever 1.60.1
(Interface 16001 в `Bulwark.toc` распознаётся автоматически).

## Один раз: подключить площадки

1. **CurseForge**: создать проект на https://authors.curseforge.com, взять его **Project ID**
   (справа на странице проекта) и API-токен на https://legacy.curseforge.com/account/api-tokens.
2. **Wago**: создать проект на https://addons.wago.io/developers, взять его **ID** из адреса проекта
   и API-ключ на https://addons.wago.io/account/apikeys.
3. Вписать ID в `Bulwark.toc`:
   ```
   ## X-Curse-Project-ID: 123456
   ## X-Wago-ID: abcd1234
   ```
4. На GitHub: **Settings → Secrets and variables → Actions → New repository secret**:
   `CF_API_KEY` = токен CurseForge, `WAGO_API_TOKEN` = ключ Wago.

Площадка без ID или без ключа просто пропускается, релиз на GitHub всё равно создаётся.

## Каждый выпуск

1. Поднять `## Version:` в `Bulwark.toc` (и версию в коде, если она там тоже записана).
2. Закоммитить и отправить в `main`.
3. Поставить тег и отправить его:
   ```
   git tag v1.2.3
   git push origin v1.2.3
   ```
4. Через пару минут версия появится на всех площадках. Ход сборки — во вкладке **Actions** на GitHub.

Список изменений собирается из сообщений коммитов с прошлого тега.
