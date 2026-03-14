@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" -no_logo -arch=x64 -host_arch=x64
set PATH=%USERPROFILE%\.cargo\bin;%PATH%
"C:\Program Files\Elixir\bin\mix.bat" test test/soundboard/uploads_path_test.exs test/soundboard/sounds/uploads_test.exs
