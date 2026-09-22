@echo off
title DUDELOCK - Parry Trainer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0parry_trainer.ps1"
if errorlevel 1 pause
