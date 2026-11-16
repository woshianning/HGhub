@echo off
rem Double-click entry point: builds the HGhub Windows installer and portable zip.
rem Equivalent to:
rem   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\build.ps1
setlocal
pushd "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\build.ps1" %*
set "HG_CODE=%ERRORLEVEL%"
popd
if not "%HG_CODE%"=="0" (
  echo.
  echo Build failed with exit code %HG_CODE%.
  echo See the messages above and docs\windows.md.
  pause
)
exit /b %HG_CODE%
