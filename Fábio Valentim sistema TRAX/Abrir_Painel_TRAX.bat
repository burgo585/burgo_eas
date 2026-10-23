@echo off
title TRAX Institutional Quant Terminal
color 0A
echo ================================================================
echo INICIANDO O PAINEL DE CONTROLE QUANTITATIVO TRAX
echo Ativos: MNQ (Nasdaq MOC/LOC), XAUUSD (Gold), BTCUSD (Crypto)
echo ================================================================
echo Abrindo o Terminal no seu navegador...
start http://localhost:8501
python main.py
pause
