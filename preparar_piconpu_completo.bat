@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem  AUTOMACAO COMPLETA - PICONPU
rem ============================================================

title PicoNPU - Preparar modelo, imagem e firmware

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "DATASET=%ROOT%\dataset"
set "COMMON=%ROOT%\common"

set "TRAIN_SCRIPT=%DATASET%\train_traffic_light_export_v5.py"
set "IMAGE_SCRIPT=%DATASET%\image_to_uart_features.py"

rem ============================================================
rem Detecta automaticamente image.jpg, image.jpeg, image.png,
rem image.bmp ou image.webp dentro da pasta dataset.
rem ============================================================
set "IMAGE_FILE="

for %%E in (jpg jpeg png bmp webp) do (
    if not defined IMAGE_FILE (
        if exist "%DATASET%\image.%%E" (
            set "IMAGE_FILE=%DATASET%\image.%%E"
        )
    )
)

set "MODEL_DATASET=%DATASET%\traffic_light_model.h"
set "PREPROCESS_JSON=%DATASET%\traffic_light_preprocess.json"
set "UART_SAMPLE_DATASET=%DATASET%\uart_sample.hex"
set "UART_PACKET_DATASET=%DATASET%\uart_packet.hex"
set "UART_REPORT_DATASET=%DATASET%\uart_image_report.csv"

set "MODEL_COMMON=%COMMON%\traffic_light_model.h"
set "BUILD_FIRMWARE=%COMMON%\build_firmware.bat"
set "FIRMWARE_COMMON=%COMMON%\firmware.hex"

set "MODEL_ROOT=%ROOT%\traffic_light_model.h"
set "PREPROCESS_ROOT=%ROOT%\traffic_light_preprocess.json"
set "UART_SAMPLE_ROOT=%ROOT%\uart_sample.hex"
set "UART_PACKET_ROOT=%ROOT%\uart_packet.hex"
set "UART_REPORT_ROOT=%ROOT%\uart_image_report.csv"
set "FIRMWARE_ROOT=%ROOT%\firmware.hex"

set "NUM_SAMPLES=8"
set "BOOT_MEM_WORDS=1024"

echo.
echo ============================================================
echo  PICONPU - GERACAO AUTOMATICA
echo ============================================================
echo  Raiz: %ROOT%
echo.

call :require_file "%TRAIN_SCRIPT%" "Script de treinamento V5"
if errorlevel 1 goto :fail

call :require_file "%IMAGE_SCRIPT%" "Conversor de imagem para UART"
if errorlevel 1 goto :fail

if not defined IMAGE_FILE (
    echo [ERRO] Nenhuma imagem de entrada foi encontrada.
    echo.
    echo Coloque na pasta dataset um arquivo com um destes nomes:
    echo   image.jpg
    echo   image.jpeg
    echo   image.png
    echo   image.bmp
    echo   image.webp
    goto :fail
)

echo [OK] Imagem detectada:
echo      !IMAGE_FILE!
echo.

call :require_file "%BUILD_FIRMWARE%" "Compilador common\build_firmware.bat"
if errorlevel 1 goto :fail

call :require_file "%ROOT%\run_modelsim.do" "Script run_modelsim.do"
if errorlevel 1 goto :fail

where py >nul 2>&1
if errorlevel 1 (
    echo [ERRO] O comando "py" nao foi encontrado.
    echo        Instale o Python Launcher ou altere este BAT para usar python.
    goto :fail
)

echo [OK] Arquivos obrigatorios encontrados.
echo.

echo [1/7] Verificando dependencias Python...
py -c "import numpy, cv2, sklearn" >nul 2>&1
if errorlevel 1 (
    echo [ERRO] Dependencias Python ausentes.
    echo Instale com:
    echo   py -m pip install numpy opencv-python scikit-learn
    goto :fail
)
echo [OK] Dependencias Python disponiveis.
echo.

echo [2/7] Treinando e exportando o modelo V5...
pushd "%DATASET%" >nul

py "%TRAIN_SCRIPT%" ^
    --dataset "%DATASET%" ^
    --out "%MODEL_DATASET%" ^
    --preprocess-out "%PREPROCESS_JSON%" ^
    --samples %NUM_SAMPLES%

if errorlevel 1 (
    popd >nul
    echo [ERRO] Falha na geracao do traffic_light_model.h.
    goto :fail
)

popd >nul

call :require_file "%MODEL_DATASET%" "traffic_light_model.h gerado"
if errorlevel 1 goto :fail

call :require_file "%PREPROCESS_JSON%" "traffic_light_preprocess.json gerado"
if errorlevel 1 goto :fail

echo [OK] Modelo e JSON gerados.
echo.

echo [3/7] Convertendo a imagem para entrada UART...
pushd "%DATASET%" >nul

py "%IMAGE_SCRIPT%" ^
    --image "!IMAGE_FILE!" ^
    --config "%PREPROCESS_JSON%" ^
    --sample-id 0 ^
    --sample-out "%UART_SAMPLE_DATASET%" ^
    --packet-out "%UART_PACKET_DATASET%" ^
    --report-out "%UART_REPORT_DATASET%"

if errorlevel 1 (
    popd >nul
    echo [ERRO] Falha na conversao da imagem para features UART.
    goto :fail
)

popd >nul

call :require_file "%UART_SAMPLE_DATASET%" "uart_sample.hex gerado"
if errorlevel 1 goto :fail

call :require_file "%UART_PACKET_DATASET%" "uart_packet.hex gerado"
if errorlevel 1 goto :fail

for /f %%N in ('powershell -NoProfile -Command "(Get-Content -LiteralPath '%UART_SAMPLE_DATASET%' | Where-Object { $_.Trim() -ne '' }).Count"') do set "UART_LINES=%%N"

if not "!UART_LINES!"=="63" (
    echo [ERRO] uart_sample.hex possui !UART_LINES! linhas; eram esperadas 63.
    goto :fail
)

echo [OK] Imagem convertida em 63 features.
echo.

echo [4/7] Atualizando arquivos do projeto...

copy /Y "%MODEL_DATASET%" "%MODEL_COMMON%" >nul
if errorlevel 1 (
    echo [ERRO] Nao foi possivel copiar o modelo para common\.
    goto :fail
)

copy /Y "%MODEL_DATASET%" "%MODEL_ROOT%" >nul
if errorlevel 1 goto :copy_error

copy /Y "%PREPROCESS_JSON%" "%PREPROCESS_ROOT%" >nul
if errorlevel 1 goto :copy_error

copy /Y "%UART_SAMPLE_DATASET%" "%UART_SAMPLE_ROOT%" >nul
if errorlevel 1 goto :copy_error

copy /Y "%UART_PACKET_DATASET%" "%UART_PACKET_ROOT%" >nul
if errorlevel 1 goto :copy_error

copy /Y "%UART_REPORT_DATASET%" "%UART_REPORT_ROOT%" >nul
if errorlevel 1 goto :copy_error

echo [OK] Modelo e entrada UART atualizados.
echo.

echo [5/7] Gerando firmware RISC-V...
pushd "%COMMON%" >nul

call "%BUILD_FIRMWARE%"
if errorlevel 1 (
    popd >nul
    echo [ERRO] common\build_firmware.bat terminou com erro.
    goto :fail
)

popd >nul

call :require_file "%FIRMWARE_COMMON%" "common\firmware.hex"
if errorlevel 1 goto :fail

echo [OK] Firmware gerado em common\firmware.hex.
echo.

echo [6/7] Copiando e validando firmware.hex...

copy /Y "%FIRMWARE_COMMON%" "%FIRMWARE_ROOT%" >nul
if errorlevel 1 (
    echo [ERRO] Nao foi possivel copiar firmware.hex para a raiz.
    goto :fail
)

for /f %%N in ('powershell -NoProfile -Command "(Get-Content -LiteralPath '%FIRMWARE_ROOT%' | Where-Object { $_.Trim() -ne '' }).Count"') do set "FIRMWARE_WORDS=%%N"

if not defined FIRMWARE_WORDS (
    echo [ERRO] Nao foi possivel contar as words do firmware.
    goto :fail
)

echo       Firmware: !FIRMWARE_WORDS! words
echo       Bootloader: %BOOT_MEM_WORDS% words

if !FIRMWARE_WORDS! GTR %BOOT_MEM_WORDS% (
    echo.
    echo [ERRO] O firmware ultrapassa a capacidade do bootloader.
    echo        Firmware  = !FIRMWARE_WORDS! words
    echo        MEM_WORDS = %BOOT_MEM_WORDS% words
    echo.
    echo Aumente MEM_WORDS em soc_top.v, boot_manager.v e
    echo uart_rom_receiver.v.
    goto :fail
)

echo [OK] firmware.hex copiado para a raiz.
echo.

echo [7/7] Conferencia final...

call :require_file "%FIRMWARE_ROOT%" "firmware.hex na raiz"
if errorlevel 1 goto :fail

call :require_file "%UART_SAMPLE_ROOT%" "uart_sample.hex na raiz"
if errorlevel 1 goto :fail

call :require_file "%ROOT%\run_modelsim.do" "run_modelsim.do na raiz"
if errorlevel 1 goto :fail

echo.
echo ============================================================
echo  PROCESSO CONCLUIDO COM SUCESSO
echo ============================================================
echo.
echo Imagem utilizada:
echo   !IMAGE_FILE!
echo.
echo Arquivos prontos na raiz:
echo   firmware.hex                 !FIRMWARE_WORDS! words
echo   uart_sample.hex              !UART_LINES! bytes
echo   uart_packet.hex
echo   uart_image_report.csv
echo   traffic_light_model.h
echo   traffic_light_preprocess.json
echo   run_modelsim.do
echo.
echo Agora, no ModelSim, execute:
echo.
echo   do run_modelsim.do
echo.
echo ============================================================
exit /b 0

:copy_error
echo [ERRO] Falha ao copiar um dos arquivos gerados para a raiz.
goto :fail

:require_file
if not exist "%~1" (
    echo [ERRO] %~2 nao encontrado:
    echo        %~1
    exit /b 1
)
exit /b 0

:fail
echo.
echo ============================================================
echo  PROCESSO INTERROMPIDO
echo ============================================================
echo Verifique a mensagem de erro acima.
echo.
pause
exit /b 1
