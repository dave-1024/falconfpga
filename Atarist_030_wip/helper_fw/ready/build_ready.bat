@echo off
REM Builds the AE350 ready stub. Flash the bin at 0x0600000, C Bin,
REM Program Without Erasure. Do not erase the bitstream or the TOS slot.
setlocal
set "HERE=%~dp0"
if exist "%HERE%env.bat" call "%HERE%env.bat"
if not defined FALCON_TC set "FALCON_TC=C:\Dev\AndeSight_RDS_v511\toolchains\nds32le-elf-newlib-v5\bin"
if not defined FALCON_SDK set "FALCON_SDK=C:\Dev\RiscV_AE350_SOC_V1.3"
if not defined FALCON_CYGBIN set "FALCON_CYGBIN=C:\Dev\AndeSight_RDS_v511\cygwin\bin"
set "PATH=%FALCON_TC%;%FALCON_CYGBIN%;%PATH%"
set "GCC=%FALCON_TC%\riscv32-elf-gcc.exe"
set "OBJCOPY=%FALCON_TC%\riscv32-elf-objcopy.exe"
set "BSP=%FALCON_SDK%\library\bsp"
set "OUT=%HERE%output"
if not exist "%OUT%" mkdir "%OUT%"
set INC=-I"%BSP%\ae350" -I"%BSP%\config" -I"%BSP%\driver\ae350" -I"%BSP%\driver\include" -I"%BSP%\lib"
set CFLAGS=%INC% -O2 -mcmodel=medium -g3 -Wall -mcpu=a25 -ffunction-sections -fdata-sections -fno-builtin -fomit-frame-pointer
set LDFLAGS=-mcpu=a25 -O2 -nostartfiles -static -T"%BSP%\sag\ae350-ddr.ld" -Wl,--gc-sections
"%GCC%" %CFLAGS% %LDFLAGS% "%BSP%\ae350\start.S" "%BSP%\ae350\ae350.c" "%BSP%\ae350\initfini.c" "%HERE%ready.c" -o "%OUT%\ready.adx" -lc -lgcc
if errorlevel 1 exit /b 1
"%OBJCOPY%" -S -O binary "%OUT%\ready.adx" "%OUT%\ready.bin"
echo Flash output\ready.bin at 0x0600000. Leading 0. Not 0x6000000.
endlocal
