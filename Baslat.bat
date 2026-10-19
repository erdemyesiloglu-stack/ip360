@echo off
cd /d "%~dp0"
echo Akis IPTV: tarayicinizda http://localhost:4173 adresini acin.
echo Durdurmak icin Ctrl+C basin. Python 3 kurulu olmalidir.
py -3 -m http.server 4173 --directory dist
pause
