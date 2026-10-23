"""
Ponto de Entrada Principal do Ecossistema Quantitativo TRAX.
Permite execução tanto em modo Headless (HFT Core sem interface) quanto modo Dashboard (Streamlit GUI).
"""

import sys
import argparse
import subprocess
from pathlib import Path

from config.settings import carregar_presets
from src.utils.logger import obter_logger

logger = obter_logger("TRAXMain")


def iniciar_dashboard():
    """Inicializa a interface gráfica institucional em Streamlit."""
    import webbrowser
    import time

    caminho_gui = Path(__file__).parent / "src" / "gui" / "app.py"
    logger.info(f"Iniciando Terminal Gráfico de Telemetria TRAX via Streamlit: {caminho_gui}...")

    # Abre o navegador automaticamente após 1 segundo
    def abrir_navegador():
        time.sleep(1.2)
        webbrowser.open("http://localhost:8501")

    import threading
    threading.Thread(target=abrir_navegador, daemon=True).start()

    subprocess.run([
        sys.executable,
        "-m", "streamlit", "run",
        str(caminho_gui)
    ])


def main():
    parser = argparse.ArgumentParser(description="TRAX Institutional HFT Ecosystem")
    parser.add_argument(
        "--gui",
        action="store_true",
        help="Inicia o Terminal Gráfico de Telemetria e Dashboard Streamlit"
    )
    args = parser.parse_args()

    config = carregar_presets()
    logger.info("=================================================================")
    logger.info(f"SISTEMA QUANTITATIVO INSTITUCIONAL TRAX - v{config.system.version}")
    logger.info(f"Ativos Ativos na Cesta: {list(config.assets.keys())}")
    logger.info(f"Limiar de Confiança da IA: {config.system.ai_confidence_threshold:.0%}")
    logger.info("=================================================================")

    if args.gui or len(sys.argv) == 1:
        iniciar_dashboard()


if __name__ == "__main__":
    main()
