@echo off
REM Exit immediately if a command fails
setlocal enabledelayedexpansion

cd slides || exit /b 1
call npm install || exit /b 1
call npx playwright install-deps || exit /b 1

REM Remove slides folder
if exist ..\website\static\slides (
    rmdir /s /q ..\website\static\slides
)

echo Building Slides for ACS CC
set SLIDES_OUTPUT_FOLDER=..\website\static\slides
call build.bat acs_cc || exit /b 1

echo Building Slides for FILS English
set SLIDES_OUTPUT_FOLDER=..\website\static\slides
call build.bat fils_en || exit /b 1

cd ..
cd website || exit /b 1
call npm install || exit /b 1
call npm run clear || exit /b 1
call npm run build || exit /b 1
