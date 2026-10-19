@echo off
chcp 65001 > nul
title Central de Gestao de Risco & Educacao Financeira
echo =======================================================================
echo   INICIANDO A CENTRAL DE GESTAO DE RISCO & EDUCACAO FINANCEIRA
echo   Foco: XAUUSD, BTCUSD & NAS100
echo =======================================================================
echo.
echo Iniciando servidor local na porta 8000...
echo O seu navegador sera aberto automaticamente em http://localhost:8000
echo.
echo Pressione Ctrl+C nesta janela caso queira encerrar o servidor.
echo =======================================================================
echo.

set PYTHONIOENCODING=utf-8
set PYTHONUTF8=1
python server.py

pause
