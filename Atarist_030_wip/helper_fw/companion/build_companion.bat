@echo off
REM Builds FPGA-Companion for the AE350 (ST_HELPER build, docs\ST_HELPER.md
REM section 7, port steps 1-3). Output: output\helper_companion.bin.
REM Flash it at 0x0600000 (leading 0, not 0x6000000) with programmer_cli
REM op 56 --mcuFile --spiaddr 0x600000. Never write 0x500000 (TOS slot).
REM Same toolchain, BSP, start-up files and linker script as
REM ..\mailbox\build_mailbox.bat: loader.c holds the BUILD_BURN boot_loader
REM (.bootloader at 0x80000000) that copies the DDR-linked image out of flash.
REM Sources: ..\fpga-companion\src (FPGA-Companion, Till Harbaum and the
REM MiSTle-Dev contributors, Apache-2.0) with the AE350 layer in src\ae350.
setlocal
set "HERE=%~dp0"
if exist "%HERE%env.bat" call "%HERE%env.bat"
if not defined FALCON_TC set "FALCON_TC=C:\Dev\AndeSight_RDS_v511\toolchains\nds32le-elf-newlib-v5\bin"
if not defined FALCON_SDK set "FALCON_SDK=C:\Dev\RiscV_AE350_SOC_V1.3"
if not defined FALCON_CYGBIN set "FALCON_CYGBIN=C:\Dev\AndeSight_RDS_v511\cygwin\bin"
set "PATH=%FALCON_TC%;%FALCON_CYGBIN%;%PATH%"
set "GCC=%FALCON_TC%\riscv32-elf-gcc.exe"
set "OBJCOPY=%FALCON_TC%\riscv32-elf-objcopy.exe"
set "OBJDUMP=%FALCON_TC%\riscv32-elf-objdump.exe"
set "SIZE=%FALCON_TC%\riscv32-elf-size.exe"
set "BSP=%FALCON_SDK%\library\bsp"
set "S=%HERE%..\fpga-companion\src"
set "OUT=%HERE%output"
if not exist "%OUT%" mkdir "%OUT%"
set INC=-I"%S%\ae350\rtos_shim" -I"%S%\ae350" -I"%S%" -I"%S%\fatfs\source" -I"%BSP%\ae350" -I"%BSP%\config" -I"%BSP%\driver\ae350" -I"%BSP%\driver\include" -I"%BSP%\lib"
set CFLAGS=-DREF_TEST_CLK %INC% -O2 -mcmodel=medium -g3 -Wall -Wno-unused-function -mcpu=a25 -ffunction-sections -fdata-sections -fno-builtin -fomit-frame-pointer
set LDFLAGS=-mcpu=a25 -O2 -nostartfiles -static -T"%BSP%\sag\ae350-ddr.ld" -Wl,--gc-sections -Wl,-Map="%OUT%\helper_companion.map"
set BSPSRC="%BSP%\ae350\start.S" "%BSP%\ae350\ae350.c" "%BSP%\ae350\cache.c" "%BSP%\ae350\initfini.c" "%BSP%\ae350\interrupt.c" "%BSP%\ae350\loader.c" "%BSP%\ae350\reset.c" "%BSP%\ae350\trap.c"
set PORTSRC="%S%\ae350\main.c" "%S%\ae350\mcu_hw.c" "%S%\ae350\console.c" "%S%\ae350\stubs.c" "%S%\ae350\tinyprintf.c"
set COMPSRC="%S%\sdc.c" "%S%\sysctrl.c" "%S%\inifile.c" "%S%\config.c" "%S%\xml.c" "%S%\puff.c" "%S%\fatfs\source\ff.c" "%S%\fatfs\source\ffunicode.c"
"%GCC%" %CFLAGS% %LDFLAGS% %BSPSRC% %PORTSRC% %COMPSRC% -o "%OUT%\helper_companion.adx" -lc -lgcc
if errorlevel 1 exit /b 1
"%OBJCOPY%" -S -O binary "%OUT%\helper_companion.adx" "%OUT%\helper_companion.bin"
"%OBJDUMP%" -h "%OUT%\helper_companion.adx" | findstr /i ".bootloader" >nul
if errorlevel 1 echo WARNING: no .bootloader section. Do not flash.
"%OBJDUMP%" -h "%OUT%\helper_companion.adx" | findstr /i ".text .data .bss .bootloader .loader"
"%SIZE%" "%OUT%\helper_companion.adx"
echo Flash output\helper_companion.bin at 0x0600000. Leading 0. Not 0x6000000.
endlocal
