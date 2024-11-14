::   __________                      __   __                __________ 
::   \______   \_____ ____________  |  | |  | _____  ___  __\______   \
::    |     ___/\__  \\_  __ \__  \ |  | |  | \__  \ \  \/  /|       _/
::    |    |     / __ \|  | \// __ \|  |_|  |__/ __ \_>    < |    |   \
::    |____|    (____  /__|  (____  /____/____(____  /__/\_ \|____|_  /
::                   \/           \/               \/      \/       \/ 
::                                                 by gavwhittaker

:: THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE

:: Changelog - Nexus Published
:: ---------------------------

:: v1.0		- Initial Release

:: Thanks and Credit
:: -----------------

:: MSFT for TexConv
:: ImageMagick Studio LLC (see License.txt)
:: amushrow for deconvolution
:: BRC under non-commercial use license agreement
:: torum for Image-viewer
:: TheGuardianDovahkiin for testing and feedback

:: Variables and Temp Files
::-------------------------

::TempDir	= The temporary directory where files are copied to and processed
::fchoose	= The user selected folder for processing (used twice)
::ModName	= The main folder (name) of the mod to process
::moddir.tmp	= Temporary file for modname processing for output folder name
::ModDir	= The readied folder prior to copying and processing
::nCount	= Count of normal maps in ModDir
::pCount	= Count of height maps in ModDir
::cCount	= # of height maps to be created (nCount-pCount)

::-----------------------------------------------------------------------------------------------

@echo off
cd tools
taskkill /f /im powershell.exe >NUL 2>&1
setlocal enabledelayedexpansion
imageviewer -f on title.jpg
color 8F
title ParallaxR
mkdir ptemp
cd ptemp
set TempDir="%CD%"
start /min /low powershell.exe -ExecutionPolicy Bypass -File .\AntiSleep.ps1
cls
echo.
echo ParallaxR session started at %time%

echo.
echo In the pop up window, find the mod to process inside your Mod Manager\Mods folder
echo Be sure to highlight the TEXTURES subfolder and then click OK to continue
echo.

title Select Folder
set "psCommand="(new-object -COM 'Shell.Application')^
.BrowseForFolder(0,'IMPORTANT: Find the mod inside your Mod Manager\Mods folder. Be sure to highlight the TEXTURES subfolder and then click OK to continue',0,0).self.path""
call :OpenFolderBox
if "%fchoose%" == "" goto :Terminate

cd /d !fchoose! >NUL 2>&1
cd ..
set ModName="%CD%"

for /f "delims=" %%i IN (%ModName%) do (
 echo %%~ni>%TEMP%\moddir.tmp
 set /p ModName=<%TEMP%\moddir.tmp
 )

title ParallaxR
set ModName=%ModName: =%

cd /d %TempDir%
mkdir %ModName%
cd /d %ModName%
mkdir textures
cd textures
set ModDir="%CD%"

cd /d !fchoose! >NUL 2>&1

set /a nCount=0
set /a pCount=0
set /a cCount=0
for /F "delims=" %%g in ('dir/s/b/a-d ".\*_n.dds"2^>nul') do (set /a nCount=nCount+1)
for /F "delims=" %%g in ('dir/s/b/a-d ".\*_p.dds"2^>nul') do (set /a pCount=pCount+1)

if %pCount% LSS %nCount% goto GoParallaxR
color 4F
title Error
echo ERROR - Your selected mod does not appear to need any parallax files creating
echo.
echo ParallaxR will now exit
echo.
taskkill /f /im powershell.exe >NUL 2>&1
cd /d %TempDir%
cd ..
rd /s /q .\temp
mkdir temp
pause
exit

::---------------

:GoParallaxR
echo Copying files
robocopy .\ %ModDir% *.dds /MT:8 /S >NUL 2>&1
cd /d %TempDir%
rename %ModName% ParallaxR-%ModName%

echo Cleansing files
attrib +r *_n.dds /s >NUL 2>&1
attrib +r *_p.dds /s >NUL 2>&1
del *.* /s /q >NUL 2>&1
attrib -r *_n.dds /s >NUL 2>&1
attrib -r *_p.dds /s >NUL 2>&1
for /f "delims=" %%d in ('dir /s /b /ad ^| sort /r') do rd "%%d" >NUL 2>&1

::---------------

echo Preparing %nCount% Normal Maps
for /r %%g in (*_n.dds) do ..\convert "%%g" -alpha off -background rgba(0,0,0,0) -resize 2048x2048 "%%~dpng.png" >NUL 2>&1 | title Resizing Normal :- %%~ng
del *_n.dds /s /q >NUL 2>&1

echo Preserving %pCount% Existing Parallax Maps
title Please Wait
..\texconv -r:keep -pow2 -ft TIF -sepalpha -nologo -h 2048 *_p.dds >NUL 2>&1
del *_p.dds /s /q >NUL 2>&1

..\brc64 /pattern:*_n.png /removelastn:2 /recursive /quiet /execute
..\brc64 /pattern:*_N.png /removelastn:2 /recursive /quiet /execute >NUL 2>&1
..\brc64 /pattern:*_p.tif /removelastn:2 /recursive /quiet /execute >NUL 2>&1
..\brc64 /pattern:*_P.tif /removelastn:2 /recursive /quiet /execute >NUL 2>&1

::---------------

for /r %%g in (*.png) do if exist "%%~dpng.tif" del "%%g" >NUL 2>&1 | del "%%~dpng.tif" >NUL 2>&1 | title Filtering :- %%~ng

set /a cCount=nCount-pCount
echo Creating %cCount% Parallax Height Maps
for /r %%g in (*.png) do ..\NormalToHeight "%%g" "%%~dpng_p.png" -scale 100.00 -numPasses 32 -normalScale 1.00 -maxStepHeight 1 -mapping XrYfgZb -zrange full -edgeMode Wrap >NUL 2>&1 | title Writing Height Data :- %%~ng

for /r %%g in (*_p.png) do ..\convert -brightness-contrast -25X-88 "%%g" "%%~dpng.png" >NUL 2>&1 | title Optimising :- %%~ng

echo Preparing 1k DDS Parallax Height Maps
..\texconv -r:keep -pow2 -f BC4_UNORM -sepalpha -nologo -y -h 1024 *_p.png >NUL 2>&1
del *.png /s /q >NUL 2>&1

::------------------------------------

title Select Folder

echo.
echo In the pop up window, highlight the folder where to put your ParallaxR Output

set fchoose=
set "psCommand="(new-object -COM 'Shell.Application')^
.BrowseForFolder(0,'Highlight the drive and folder where you want your ParallaxR ready mod to be stored',0,0).self.path""
call :OpenFolderBox
if "%fchoose%" == "" goto :Terminate
xcopy .\* !fchoose! /s /v >NUL 2>&1
explorer !fchoose!
cd /d %TempDir%
cd ..
rd /s /q .\ptemp

::------------------------------------

:Completed
title Complete
color 20
echo.
echo Completed at %time%
echo.
echo Drag and drop or ZIP the ParallaxR-%ModName% folder into your mod manager
echo.
echo Consider if you should run ParallaxGen to update your meshes for compatibility
echo.
taskkill /f /im powershell.exe >NUL 2>&1
pause
exit

::----------------------------------------------------------------------------------------------------------------------------------------

:OpenFolderBox
rundll32 user32.dll,MessageBeep
for /f "usebackq delims=" %%I in (`powershell %psCommand%`) do set "fchoose=%%I"
exit /B

::----------------------------------------------------------------------------------------------------------------------------------------

:Terminate
taskkill /f /im powershell.exe >NUL 2>&1
exit