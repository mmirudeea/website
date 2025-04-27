@echo off
setlocal enabledelayedexpansion

REM Check if SLIDES_OUTPUT_FOLDER is set
if "%SLIDES_OUTPUT_FOLDER%"=="" (
    set SLIDES_OUTPUT_FOLDER=.\dist
    if not exist "%SLIDES_OUTPUT_FOLDER%" (
        mkdir "%SLIDES_OUTPUT_FOLDER%"
    )
)

REM Start main logic

set "series=%~1"

if not "%series%"=="acs_cc" if not "%series%"=="fils_en" (
    echo Please use one of the series acs_cc or fils_en
    exit /b 1
)

if not "%~2"=="" (
    call :build %1 %2 %3
) else (
    for /d %%S in (lectures\%series%\*) do (
        set "slides=%%~nS"
        if /i not "!slides!"=="assets" if /i not "!slides!"=="resources" (
            call :build %series% !slides!
            set "fail=!errorlevel!"
            if not "!fail!"=="0" (
                echo Failed to build slides %series%\!slides!
                exit /b !fail!
            )
        )
    )
)

REM Define a build function
:build
set "series=%~1"
set "slides=%~2"

if "%FAKE_SLIDES%"=="" (
    echo Building slides %slides%
    mklink "lectures\%series%\%slides%\global-bottom.vue" "..\..\assets\global-bottom.vue" >nul
    call npm run build -- "lectures/%series%/%slides%/slides.md" --base /slides/%series%/%slides% --out "..\..\..\%SLIDES_OUTPUT_FOLDER%\%series%\%slides%"
    set "fail=%errorlevel%"
    del "lectures\%series%\%slides%\global-bottom.vue"
    exit /b %fail%
) else (
    echo %SLIDES_OUTPUT_FOLDER%\%series%\%slides%
    mkdir "%SLIDES_OUTPUT_FOLDER%\%series%\%slides%"
    type nul > "%SLIDES_OUTPUT_FOLDER%\%series%\%slides%\index.html"
    type nul > "%SLIDES_OUTPUT_FOLDER%\%series%\%slides%\%FAKE_SLIDES%-%slides%.pdf"
    exit /b 0
)

endlocal
