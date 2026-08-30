# LEGO Batman Remote Play Together Fix

Небольшой launcher, который даёт запускать локальный кооператив LEGO Batman через Steam Remote Play Together. В качестве бесплатной игры-донора используется **BlastZone 2 Demo** (`AppID 349620`).

Готовый ZIP лежит в [Releases](../../releases/latest). Файлов LEGO Batman, crack или оригинальных файлов BlastZone в репозитории и релизе нет.

## Установка

1. Установить [BlastZone 2 Demo](steam://install/349620) в Steam, один раз запустить и закрыть.
2. Распаковать ZIP и запустить `INSTALL.cmd`.
3. Если игра не найдена автоматически, указать её папку или `LEGOBatmanLotDK-Win64-Shipping.exe`.
4. Запускать в Steam именно BlastZone 2 Demo, после чего приглашать друга через Remote Play Together.

### Если кнопка Download Demo не работает

Отдельная страница демо может не отображаться в поиске Steam. Запустите клиент Steam, нажмите `Win + R`, вставьте `steam://install/349620` и нажмите Enter. Если окно установки не появилось, полностью перезапустите Steam и повторите команду. Демо также доступно с [официальной страницы BlastZone 2](https://store.steampowered.com/app/349260/BlastZone_2/) через кнопку **Download Demo**.

Для удаления запустить `UNINSTALL.cmd`. Оригинальный EXE донора восстанавливается из резервной копии.

## Как это работает

Установщик сохраняет оригинальный `BlastZone2Demo.exe` и ставит на его место launcher. Launcher запускает LEGO Batman дочерним процессом и остаётся активным, поэтому Steam продолжает видеть запущенный AppID донора и показывает Remote Play Together.

Пути к Steam и игре не зашиты: они ищутся в библиотеках Steam и в типичных папках, а при необходимости вводятся вручную.

## Совместимость

Фикс проверялся на структуре раздачи InsaneRamZes:

`https://rutracker.org/forum/viewtopic.php?t=6861577`

SHA-256 проверенного `LEGOBatmanLotDK-Win64-Shipping.exe`:

```text
07535E4FC4B78D5C3B9F8F299A41C69CC6AD423366FDA4EAF58BD8E3A3F64041
```

Для запуска игры нужен Microsoft Visual C++ Redistributable x64 14.38 или новее. Установщик проверяет его до изменения файлов донора.

## Исходники

- `src/launcher/Program.cs` — launcher;
- `src/installer` — установка, поиск путей, backup и удаление;
- `src/package` — командные файлы и официальная ссылка на Visual C++ Runtime;
- `BUILD.md` — команда сборки launcher.

Проект не связан с Valve, TT Games, Warner Bros., LEGO Group или разработчиком BlastZone 2.
