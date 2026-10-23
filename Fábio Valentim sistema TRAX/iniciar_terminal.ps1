# =====================================================================
# SCRIPT DE INICIALIZAÇÃO INSTITUCIONAL - ECOSSISTEMA TRAX HFT
# Executa o terminal quantitativo via PowerShell com Dark Mode nativo
# =====================================================================

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "INICIANDO ECOSSISTEMA QUANTITATIVO INSTITUCIONAL TRAX (PYTHON)" -ForegroundColor Green
Write-Host "Ativos: MNQ (Nasdaq MOC/LOC), XAUUSD (Gold Order Flow), BTCUSD (Crypto L2)" -ForegroundColor Yellow
Write-Host "=================================================================" -ForegroundColor Cyan

# Verifica versão do Python
$pythonVersion = python --version
Write-Host "Ambiente Python Detectado: $pythonVersion" -ForegroundColor Gray

# Inicia o Dashboard Streamlit
python main.py --gui
