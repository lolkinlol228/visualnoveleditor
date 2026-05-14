@echo off
cd /d "%~dp0"
echo Installing dependencies...
call npm config set strict-ssl false
call npm install
echo.
echo Starting VN Editor...
start "" http://localhost:3333
node server.js
pause
