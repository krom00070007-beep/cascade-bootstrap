param([hashtable]$Config)

# 10-cascade-doctor — register Windows Task Scheduler для daily run

$ErrorActionPreference = 'Stop'
function Log { param([string]$M); Write-Host "[10] $M" -ForegroundColor Cyan }

$BatFile = "C:\Users\$($Config.WIN_USER)\cascade-doctor.bat"
$Hour = if ($Config.DOCTOR_RUN_HOUR) { $Config.DOCTOR_RUN_HOUR } else { '12' }
$TaskName = "cascade-doctor-daily"

# Create .bat wrapper
Log "Creating $BatFile..."
@"
@echo off
REM cascade-doctor.bat — Windows Task Scheduler wrapper
echo [%date% %time%] cascade-doctor start >> "%USERPROFILE%\cascade-doctor-wrap.log"
wsl.exe bash -lc "SSH_AUTH_SOCK=/tmp/ssh-agent.sock /home/$($Config.WSL_USER)/bin/cascade-doctor --quiet" >> "%USERPROFILE%\cascade-doctor-wrap.log" 2>&1
echo [%date% %time%] cascade-doctor done (exit=%ERRORLEVEL%) >> "%USERPROFILE%\cascade-doctor-wrap.log"
exit /b %ERRORLEVEL%
"@ | Out-File -Encoding ASCII -Force $BatFile

# Delete existing task if any
schtasks.exe /Delete /TN $TaskName /F 2>$null | Out-Null

# Register new task
$result = schtasks.exe /Create /TN $TaskName /TR $BatFile /SC DAILY /ST "${Hour}:00" /F 2>&1
Log "$result"

# Verify
$verify = schtasks.exe /Query /TN $TaskName /FO LIST 2>&1
Log "Verify:"
$verify | Out-String | Write-Host

# Optional test run
Log ""
Log "To test run сейчас (не ждать ${Hour}:00):"
Log "  schtasks.exe /Run /TN $TaskName"
Log ""
Log "Phase 10 done — cascade-doctor scheduled daily ${Hour}:00 Bangkok"
