@echo off
REM ============================================================================
REM  build_falcon_m28.bat -- m28 = m12g + WD1772 STEP-MOVEMENT fix (Fix A)
REM
REM  Paths live in env.bat (copy env.bat.example). Do not install AndeSight.
REM  See FIRST_TIME.md and COMPILE.md.
REM
REM  Produces:  output\falcon_m28.bin  (flash to 0x600000, firmware only)
REM ============================================================================
setlocal enabledelayedexpansion

set "HERE=%~dp0"

if exist "%HERE%env.bat" (
  call "%HERE%env.bat"
) else (
  echo NOTE: no env.bat in %HERE% -- using FALCON_* defaults from the example.
)

if not defined FALCON_TC set "FALCON_TC=C:\Dev\AndeSight_RDS_v511\toolchains\nds32le-elf-newlib-v5\bin"
if not defined FALCON_SDK set "FALCON_SDK=C:\Dev\RiscV_AE350_SOC_V1.3"
if not defined FALCON_CYGBIN set "FALCON_CYGBIN=C:\Dev\AndeSight_RDS_v511\cygwin\bin"
if not defined FALCON_MUSASHI set "FALCON_MUSASHI=%HERE%"

set "TC=%FALCON_TC%"
set "SDK=%FALCON_SDK%"
set "CYGBIN=%FALCON_CYGBIN%"
set "MUSASHI=%FALCON_MUSASHI%"
set "OUT=%HERE%output"

set "PATH=%TC%;%CYGBIN%;%PATH%"
set "GCC=%TC%\riscv32-elf-gcc.exe"
set "OBJCOPY=%TC%\riscv32-elf-objcopy.exe"
set "OBJDUMP=%TC%\riscv32-elf-objdump.exe"
set "SIZE=%TC%\riscv32-elf-size.exe"

set "BSP=%SDK%\library\bsp"
set "DEMO=%SDK%\library\demo"
set "REFDEMO=%SDK%\ref_design\MCU_RefDesign\ae350_demo\src\demo"
set "LDSCRIPT=%BSP%\sag\ae350-ddr.ld"

set INC=-I"%BSP%\ae350" -I"%BSP%\config" -I"%BSP%\driver\ae350" -I"%BSP%\driver\include" -I"%BSP%\lib" -I"%REFDEMO%" -I"%MUSASHI%"

REM Dave 2026-08-03: -O2 in BOTH CFLAGS and LDFLAGS (gcc honours the LAST -O).
set CFLAGS=-DREF_TEST_CLK %INC% -O2 -DBUILD_O2 -DFALCON_NO_FPU -mcmodel=medium -g3 -Wall -mcpu=a25 -ffunction-sections -fdata-sections -fmessage-length=0 -fno-builtin -fomit-frame-pointer -fno-strict-aliasing

set LDFLAGS=-mcpu=a25 -O2 -nostartfiles -static -T"%LDSCRIPT%" -Wl,--defsym=_heap_end=0x03000000 -Wl,--gc-sections -Wl,-Map,"%OUT%\falcon_m28.map"

if not exist "%OUT%" mkdir "%OUT%"

echo.
echo === Toolchain check ===
if not exist "%GCC%" ( echo ERROR: gcc not found at %GCC% -- fix FALCON_TC in env.bat. & exit /b 1 )
if not exist "%CYGBIN%\cygwin1.dll" ( echo ERROR: cygwin1.dll not found at %CYGBIN% -- fix FALCON_CYGBIN in env.bat. & exit /b 1 )
echo Found gcc and cygwin1.dll.
"%GCC%" -dumpversion

if not exist "%MUSASHI%\falcon_blitter.c" (
  echo ERROR: cannot find %MUSASHI%\falcon_blitter.c
  exit /b 1
)
if not exist "%MUSASHI%\falcon_m28.c" (
  echo ERROR: cannot find %MUSASHI%\falcon_m28.c
  exit /b 1
)
if not exist "%MUSASHI%\emutos_rom.c" (
  echo ERROR: cannot find %MUSASHI%\emutos_rom.c
  exit /b 1
)
if not exist "%MUSASHI%\m68kops.c" (
  echo ERROR: cannot find %MUSASHI%\m68kops.c
  exit /b 1
)

echo.
echo === Assembling source list ===
set SRCS=%BSP%\ae350\start.S
set SRCS=%SRCS% %BSP%\ae350\ae350.c %BSP%\ae350\cache.c %BSP%\ae350\initfini.c %BSP%\ae350\interrupt.c %BSP%\ae350\loader.c %BSP%\ae350\reset.c %BSP%\ae350\trap.c
set SRCS=%SRCS% %BSP%\driver\ae350\gpio_ae350.c %BSP%\driver\ae350\uart_ae350.c %BSP%\driver\ae350\pit_ae350.c %BSP%\driver\ae350\rtc_ae350.c %BSP%\driver\ae350\wdt_ae350.c %BSP%\driver\ae350\dma_ae350.c %BSP%\driver\ae350\i2c_ae350.c %BSP%\driver\ae350\pwm_ae350.c %BSP%\driver\ae350\spi_ae350.c
set SRCS=%SRCS% %BSP%\lib\printf.c %BSP%\lib\uart.c %BSP%\lib\delay.c %BSP%\lib\mm.c %BSP%\lib\read.c
set SRCS=%SRCS% %DEMO%\stubs\write.c %DEMO%\stubs\close.c %DEMO%\stubs\exit.c %DEMO%\stubs\fstat.c %DEMO%\stubs\isatty.c %DEMO%\stubs\lseek.c %DEMO%\stubs\sbrk.c %DEMO%\stubs\write_hex.c
set SRCS=%SRCS% "%MUSASHI%\m68kcpu.c" "%MUSASHI%\m68kops.c" "%MUSASHI%\m68kdasm.c" "%MUSASHI%\softfloat\softfloat.c"
set SRCS=%SRCS% "%MUSASHI%\emutos_rom.c"
set SRCS=%SRCS% "%MUSASHI%\falcon_m28.c"

echo.
echo === Compiling + linking ===
"%GCC%" %CFLAGS% %LDFLAGS% %SRCS% -o "%OUT%\falcon_m28.adx" -lc -lm -lgcc
if errorlevel 1 (
  echo BUILD FAILED. Copy ALL the error text above.
  exit /b 1
)

"%OBJCOPY%" -S -O binary "%OUT%\falcon_m28.adx" "%OUT%\falcon_m28.bin"
if errorlevel 1 ( echo objcopy failed & exit /b 1 )

"%OBJDUMP%" -h "%OUT%\falcon_m28.adx" | findstr /i ".text .data .bss .bootloader .loader .vector"
"%SIZE%" "%OUT%\falcon_m28.adx"
for %%F in ("%OUT%\falcon_m28.bin") do echo Output: %%~fF  (%%~zF bytes)
echo Flash .bin to 0x600000. TOS from SD. See HOWTO.md.
endlocal
