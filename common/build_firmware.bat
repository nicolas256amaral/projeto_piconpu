@echo off
C:\riscv\bin\riscv-none-elf-gcc.exe -march=rv32i -mabi=ilp32 -O2 -g -ffreestanding -nostdlib -nostartfiles -Wall -I. -Wl,-T,linker.ld -Wl,--gc-sections -o firmware.elf crt0.S main.c npu_test.c
if errorlevel 1 goto :error

C:\riscv\bin\riscv-none-elf-objcopy.exe -O binary firmware.elf firmware.bin
if errorlevel 1 goto :error

python bin2memh_word32.py firmware.bin firmware.hex
if errorlevel 1 goto :error

copy /Y firmware.hex ..\firmware.hex >nul
if errorlevel 1 goto :error

echo.
echo Firmware gerado com sucesso:
echo   common\firmware.hex
echo   ..\firmware.hex
goto :eof

:error
echo.
echo Erro na geracao do firmware.
exit /b 1
