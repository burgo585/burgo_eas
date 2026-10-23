"""
Script de Teste de Conexão e Autenticação com o Terminal MT5 Configurado.
Verifica se a conta de demonstração foi conectada com sucesso no executável especificado.
"""

from config.settings import carregar_presets
from src.data.mt5_feed import MT5TickFeed
from src.utils.logger import obter_logger

logger = obter_logger("TesteConexaoMT5")


def testar_conexao_terminal():
    config = carregar_presets()
    logger.info("=================================================================")
    logger.info("INICIANDO TESTE DE CONEXÃO E LOGIN NO METATRADER 5")
    logger.info(f"Caminho do Terminal: {config.mt5.path}")
    logger.info(f"Conta: {config.mt5.account} | Servidor: {config.mt5.server}")
    logger.info("=================================================================")

    feed = MT5TickFeed(config.mt5)
    sucesso = feed.inicializar_conexao()

    if sucesso:
        import MetaTrader5 as mt5
        acc = mt5.account_info()
        term = mt5.terminal_info()

        logger.info("=================================================================")
        logger.info("[OK] CONEXÃO COM O METATRADER 5 ESTABELECIDA COM SUCESSO!")
        logger.info(f"  -> Terminal: {term.name} (Build {term.build})")
        logger.info(f"  -> Caminho: {term.path}")
        logger.info(f"  -> Conta Ativa: #{acc.login} ({acc.name})")
        logger.info(f"  -> Servidor: {acc.server}")
        logger.info(f"  -> Moeda: {acc.currency} | Saldo: ${acc.balance:,.2f} | Margem Livre: ${acc.margin_free:,.2f}")
        logger.info(f"  -> Alavancagem: 1:{acc.leverage}")
        logger.info(f"  -> Negociação Automatizada Permitida no Terminal: {term.trade_allowed}")
        logger.info("=================================================================")

        # Testa verificação de símbolos da cesta mapeados para o broker
        for chave, preset in config.assets.items():
            sim = preset.mt5_symbol
            info = mt5.symbol_info(sim)
            if info:
                logger.info(f"  -> Ativo [{chave}] -> Broker '{sim}' localizado e ativo! Bid: {info.bid} | Ask: {info.ask}")
            else:
                similares = [s.name for s in mt5.symbols_get() if chave in s.name][:5]
                logger.warning(f"  -> Ativo [{chave}] -> Broker '{sim}' não encontrado. Sugestões: {similares}")

        feed.desconectar()
    else:
        logger.error("[FALHA] Não foi possível autenticar ou conectar ao terminal especificado.")


if __name__ == "__main__":
    testar_conexao_terminal()
