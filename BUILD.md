# Сборка launcher

Сторонние библиотеки не нужны. На Windows 10/11 launcher собирается штатным компилятором .NET Framework:

```cmd
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe ^
  /nologo /target:winexe /platform:x64 /optimize+ /debug- /codepage:65001 ^
  /reference:System.Windows.Forms.dll /reference:System.Drawing.dll ^
  /out:BlastZone2Demo.exe src\launcher\Program.cs
```

При формировании ZIP собранный `BlastZone2Demo.exe` кладётся в папку `Launcher` внутри служебной папки пакета.
