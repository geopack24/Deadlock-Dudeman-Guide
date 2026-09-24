@echo off
title DUDELOCK - Lobby Watcher
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lobby-watcher.ps1" %*
if errorlevel 1 pause
