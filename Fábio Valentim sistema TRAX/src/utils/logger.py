"""
Módulo de Telemetria e Registro de Logs Institucional.
Fornece formatação estruturada de eventos com suporte a cores para terminal Windows/PowerShell.
"""

import logging
import sys
from typing import Optional


class FormatadorInstitucional(logging.Formatter):
    """
    Formatador de logs com suporte a esquemas de cores ANSI
    otimizado para terminais PowerShell e interfaces institucionais.
    """

    RESET = "\033[0m"
    CORES = {
        logging.DEBUG: "\033[36m",     # Ciano
        logging.INFO: "\033[32m",      # Verde
        logging.WARNING: "\033[33m",   # Amarelo
        logging.ERROR: "\033[31m",     # Vermelho
        logging.CRITICAL: "\033[35;1m" # Magenta Negrito
    }

    def format(self, record: logging.LogRecord) -> str:
        cor = self.CORES.get(record.levelno, self.RESET)
        timestamp = self.formatTime(record, "%Y-%m-%d %H:%M:%S")
        prefixo_modulo = f"[{record.name}]"
        nivel = f"[{record.levelname}]"
        mensagem = record.getMessage()

        return f"{cor}{timestamp} {nivel:<10} {prefixo_modulo:<22} {mensagem}{self.RESET}"


def obter_logger(nome: str, nivel: str = "INFO") -> logging.Logger:
    """
    Retorna uma instância configurada do logger institucional.

    :param nome: Identificador do módulo ou componente.
    :param nivel: Nível mínimo de log (DEBUG, INFO, WARNING, ERROR).
    :return: Objeto logging.Logger configurado.
    """
    logger = logging.getLogger(nome)
    
    # Evita duplicação de handlers caso a função seja chamada múltiplas vezes
    if not logger.handlers:
        # Configura stream com suporte a UTF-8 no Windows
        try:
            if hasattr(sys.stdout, "reconfigure"):
                sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

        logger.setLevel(getattr(logging, nivel.upper(), logging.INFO))
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(FormatadorInstitucional())
        logger.addHandler(handler)
        logger.propagate = False

    return logger
