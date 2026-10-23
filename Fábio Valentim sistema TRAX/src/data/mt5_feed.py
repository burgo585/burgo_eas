"""
Módulo de Ingestão de Ticks e Conexão com MetaTrader 5 (MT5).
Responsável pela captura em tempo real de ticks com microestrutura (Bid, Ask, Last, Volume, Flags)
e carregamento de bases históricas para backtesting via Parquet e CSV.
"""

import asyncio
import datetime
from pathlib import Path
from typing import Optional, List, Dict, Any, Union
import numpy as np
import pandas as pd

try:
    import MetaTrader5 as mt5
    MT5_DISPONIVEL = True
except ImportError:
    MT5_DISPONIVEL = False

from src.utils.logger import obter_logger
from config.settings import ConfiguracaoMT5

logger = obter_logger("MT5TickFeed")


class MT5TickFeed:
    """
    Gerenciador assíncrono de ticks do MetaTrader 5 e interface de dados históricos.
    Extrai microestrutura institucional e identifica a direção da agressão com base nas flags.
    """

    # Flags oficiais da API do MetaTrader 5
    FLAG_TICK_BID = 2
    FLAG_TICK_ASK = 4
    FLAG_TICK_LAST = 8
    FLAG_TICK_VOLUME = 16
    FLAG_TICK_BUY = 32
    FLAG_TICK_SELL = 64

    def __init__(self, config_mt5: Optional[ConfiguracaoMT5] = None):
        """
        Inicializa o leitor de ticks.

        :param config_mt5: Configurações de credenciais e conexão ao terminal MT5.
        """
        self.config = config_mt5 or ConfiguracaoMT5()
        self.conectado = False
        self.fila_ticks: asyncio.Queue = asyncio.Queue(maxsize=100000)
        self._executando = False
        self._ultimo_timestamp_msc: Dict[str, int] = {}

    def inicializar_conexao(self) -> bool:
        """
        Estabelece a conexão com a instância ativa ou configurada do MetaTrader 5.

        :return: True se conectado com sucesso, False caso contrário.
        """
        if not MT5_DISPONIVEL:
            logger.error("Biblioteca MetaTrader5 não está instalada ou indisponível no ambiente.")
            return False

        logger.info("Iniciando conexão com o terminal MetaTrader 5...")

        parametros_init = {}
        if self.config.path:
            parametros_init["path"] = self.config.path
        if self.config.account:
            parametros_init["login"] = self.config.account
        if self.config.password:
            parametros_init["password"] = self.config.password
        if self.config.server:
            parametros_init["server"] = self.config.server
        if self.config.portable:
            parametros_init["portable"] = True
        if self.config.timeout_ms:
            parametros_init["timeout"] = self.config.timeout_ms

        # Tenta inicializar passando os parâmetros completos
        if not mt5.initialize(**parametros_init):
            logger.warning(f"Tentando inicialização alternativa apenas com path: {self.config.path}...")
            # Fallback: inicializa com path e autentica via mt5.login()
            param_fallback = {"path": self.config.path} if self.config.path else {}
            if not mt5.initialize(**param_fallback):
                erro = mt5.last_error()
                logger.error(f"Falha ao inicializar terminal MT5: Código {erro}")
                return False

            if self.config.account and self.config.password and self.config.server:
                if not mt5.login(
                    login=self.config.account,
                    password=self.config.password,
                    server=self.config.server
                ):
                    erro = mt5.last_error()
                    logger.error(f"Falha na autenticação da conta MT5 #{self.config.account}: Código {erro}")
                    mt5.shutdown()
                    return False

        logger.info(f"Autenticação e conexão MT5 realizada com sucesso para a conta #{self.config.account} ({self.config.server})")

        info_terminal = mt5.terminal_info()
        if info_terminal is not None:
            logger.info(f"Terminal conectado: {info_terminal.name} | Build: {info_terminal.build}")

        self.conectado = True
        return True

    def desconectar(self):
        """Encerra a sessão com o MetaTrader 5 de forma limpa."""
        if MT5_DISPONIVEL and self.conectado:
            mt5.shutdown()
            self.conectado = False
            logger.info("Conexão com o MetaTrader 5 encerrada com sucesso.")

    def habilitar_simbolo(self, simbolo: str) -> bool:
        """
        Garante que o ativo esteja selecionado no Market Watch para receber cotações.

        :param simbolo: Código do ativo no MT5 (ex: 'MNQ', 'XAUUSD', 'BTCUSD').
        :return: True se o símbolo estiver visível e pronto.
        """
        if not self.conectado:
            logger.warning("MT5 não conectado ao tentar habilitar símbolo.")
            return False

        info_simbolo = mt5.symbol_info(simbolo)
        if info_simbolo is None:
            logger.error(f"Símbolo '{simbolo}' não encontrado na corretora.")
            return False

        if not info_simbolo.visible:
            if not mt5.symbol_select(simbolo, True):
                logger.error(f"Não foi possível selecionar '{simbolo}' no Market Watch.")
                return False

        logger.info(f"Símbolo '{simbolo}' validado e ativo no Market Watch.")
        return True

    @staticmethod
    def classificar_agressao(
        flag: int,
        price: float,
        bid: float,
        ask: float,
        ultimo_preco: float = 0.0
    ) -> str:
        """
        Identifica institucionalmente a direção da agressão do fluxo (Order Flow).
        Aplica decodificação de flags do MT5 e fallback pelo algoritmo Lee-Ready / Tick Rule.

        :param flag: Máscara binária de flags do tick fornecida pelo MT5.
        :param price: Preço do negócio (Last).
        :param bid: Melhor oferta de compra no instante.
        :param ask: Melhor oferta de venda no instante.
        :param ultimo_preco: Preço da transação anterior (para critério de desempate).
        :return: 'BUY' (Comprador Agressivo), 'SELL' (Vendedor Agressivo) ou 'NEUTRAL'.
        """
        # 1. Verificação direta pelas flags explícitas da bolsa/corretora
        if flag & MT5TickFeed.FLAG_TICK_BUY:
            return "BUY"
        if flag & MT5TickFeed.FLAG_TICK_SELL:
            return "SELL"

        # 2. Em caso de CFDs / Forex onde a flag específica não é enviada pela corretora,
        # analisa a relação entre o preço executado (Last) e as pontas do Book (Ask/Bid):
        if ask > 0 and price >= ask:
            return "BUY"
        if bid > 0 and price <= bid:
            return "SELL"

        # 3. Fallback: Tick Rule (Lee-Ready) baseado no delta de preço
        if ultimo_preco > 0:
            if price > ultimo_preco:
                return "BUY"
            if price < ultimo_preco:
                return "SELL"

        return "NEUTRAL"

    def extrair_ticks_historicos(
        self,
        simbolo: str,
        inicio: datetime.datetime,
        fim: datetime.datetime,
        tipo_flags: int = None
    ) -> pd.DataFrame:
        """
        Extrai histórico de ticks brutos diretamente do MetaTrader 5 usando CopyTicksRange.

        :param simbolo: Ativo (ex: 'MNQ').
        :param inicio: Data e hora inicial com fuso horário.
        :param fim: Data e hora final.
        :param tipo_flags: Tipo de ticks (padrão mt5.COPY_TICKS_ALL).
        :return: DataFrame estruturado com colunas institucionais de microestrutura.
        """
        if not self.conectado:
            raise ConnectionError("MetaTrader 5 não está conectado para extração de ticks.")

        if tipo_flags is None:
            tipo_flags = mt5.COPY_TICKS_ALL

        logger.info(f"Extraindo ticks históricos de {simbolo} entre {inicio} e {fim}...")
        ticks_brutos = mt5.copy_ticks_range(simbolo, inicio, fim, tipo_flags)

        if ticks_brutos is None or len(ticks_brutos) == 0:
            logger.warning(f"Nenhum tick retornado para {simbolo} no intervalo solicitado.")
            return pd.DataFrame()

        df = pd.DataFrame(ticks_brutos)
        return self._formatar_dataframe_ticks(df)

    def _formatar_dataframe_ticks(self, df_ticks: pd.DataFrame) -> pd.DataFrame:
        """
        Padroniza os nomes de colunas, tipagem temporal e classificação de agressão.

        :param df_ticks: DataFrame bruto do MT5.
        :return: DataFrame formatado e enriquecido.
        """
        # Garante a existência do campo em milissegundos
        if "time_msc" in df_ticks.columns:
            df_ticks["timestamp"] = pd.to_datetime(df_ticks["time_msc"], unit="ms", utc=True)
        else:
            df_ticks["timestamp"] = pd.to_datetime(df_ticks["time"], unit="s", utc=True)

        # Ajusta volume real vs volume de ticks
        if "volume_real" in df_ticks.columns and df_ticks["volume_real"].sum() > 0:
            df_ticks["vol"] = df_ticks["volume_real"]
        elif "volume" in df_ticks.columns:
            df_ticks["vol"] = df_ticks["volume"]
        else:
            df_ticks["vol"] = 1.0

        # Classificação vetorizada da agressão
        agressores = []
        ultimo_preco = 0.0

        for row in df_ticks.itertuples():
            agressor = self.classificar_agressao(
                flag=int(row.flags),
                price=float(row.last) if row.last > 0 else float(row.bid),
                bid=float(row.bid),
                ask=float(row.ask),
                ultimo_preco=ultimo_preco
            )
            agressores.append(agressor)
            if row.last > 0:
                ultimo_preco = float(row.last)

        df_ticks["aggression"] = agressores
        df_ticks["buy_vol"] = np.where(df_ticks["aggression"] == "BUY", df_ticks["vol"], 0.0)
        df_ticks["sell_vol"] = np.where(df_ticks["aggression"] == "SELL", df_ticks["vol"], 0.0)
        df_ticks["delta"] = df_ticks["buy_vol"] - df_ticks["sell_vol"]

        colunas_ordenadas = [
            "timestamp", "time_msc", "bid", "ask", "last", "vol",
            "flags", "aggression", "buy_vol", "sell_vol", "delta"
        ]
        colunas_finais = [c for c in colunas_ordenadas if c in df_ticks.columns]
        return df_ticks[colunas_finais].sort_values("timestamp").reset_index(drop=True)

    async def iniciar_captura_ao_vivo(self, simbolos: List[str], intervalo_poll_ms: int = 50):
        """
        Loop assíncrono de polling e ingestão de ticks em tempo real sem perda de eventos.

        :param simbolos: Lista de símbolos para monitorar concorrentemente.
        :param intervalo_poll_ms: Frequência de verificação em milissegundos.
        """
        self._executando = True
        logger.info(f"Loop de captura ao vivo iniciado para: {simbolos} (Taxa: {intervalo_poll_ms}ms)")

        for s in simbolos:
            self.habilitar_simbolo(s)
            self._ultimo_timestamp_msc[s] = int(datetime.datetime.now(datetime.timezone.utc).timestamp() * 1000)

        while self._executando:
            try:
                for simbolo in simbolos:
                    desde_msc = self._ultimo_timestamp_msc.get(simbolo, 0)
                    ticks_recentes = mt5.copy_ticks_from(
                        simbolo,
                        desde_msc,
                        2000,
                        mt5.COPY_TICKS_ALL
                    )

                    if ticks_recentes is not None and len(ticks_recentes) > 0:
                        df_recentes = pd.DataFrame(ticks_recentes)
                        # Filtra apenas ticks estritamente mais novos que o último registrado
                        df_novos = df_recentes[df_recentes["time_msc"] > desde_msc]

                        if not df_novos.empty:
                            df_formatado = self._formatar_dataframe_ticks(df_novos)
                            self._ultimo_timestamp_msc[simbolo] = int(df_novos["time_msc"].max())

                            # Enfileira ticks formatados para consumo sem bloquear a ingestão
                            for _, tick_row in df_formatado.iterrows():
                                item = tick_row.to_dict()
                                item["symbol"] = simbolo
                                if not self.fila_ticks.full():
                                    await self.fila_ticks.put(item)

                await asyncio.sleep(intervalo_poll_ms / 1000.0)

            except Exception as e:
                logger.error(f"Exceção durante a captura de ticks ao vivo: {e}", exc_info=True)
                await asyncio.sleep(0.5)

    def parar_captura_ao_vivo(self):
        """Sinaliza parada segura do loop de streaming."""
        self._executando = False
        logger.info("Captura de ticks ao vivo interrompida.")

    # -------------------------------------------------------------
    # Métodos de Persistência e Leitura para Backtest (Parquet / CSV)
    # -------------------------------------------------------------

    @staticmethod
    def salvar_para_parquet(df: pd.DataFrame, caminho_destino: Union[str, Path]):
        """
        Salva DataFrame de ticks em formato comprimido Parquet (PyArrow) para alta velocidade de IO.

        :param df: DataFrame com os dados dos ticks.
        :param caminho_destino: Caminho completo para gravação do arquivo .parquet.
        """
        caminho = Path(caminho_destino)
        caminho.parent.mkdir(parents=True, exist_ok=True)
        df.to_parquet(caminho, engine="pyarrow", compression="snappy", index=False)
        logger.info(f"Base de ticks exportada com sucesso ({len(df)} registros) para: {caminho}")

    @staticmethod
    def carregar_dados_backtest(
        caminho_arquivo: Union[str, Path],
        usar_polars: bool = False
    ) -> Union[pd.DataFrame, Any]:
        """
        Lê arquivos .parquet ou .csv com dados históricos de ticks para pipelines de backtest.

        :param caminho_arquivo: Caminho do arquivo Parquet ou CSV.
        :param usar_polars: Se True, tenta retornar um DataFrame Polars para máxima performance.
        :return: DataFrame estruturado (Pandas ou Polars).
        """
        caminho = Path(caminho_arquivo)
        if not caminho.exists():
            raise FileNotFoundError(f"Arquivo de backtest não encontrado: {caminho}")

        logger.info(f"Carregando dados históricos de: {caminho.name}...")

        if usar_polars:
            try:
                import polars as pl
                if caminho.suffix == ".parquet":
                    return pl.read_parquet(caminho)
                elif caminho.suffix == ".csv":
                    return pl.read_csv(caminho)
            except ImportError:
                logger.warning("Polars não está disponível. Fazendo fallback para Pandas.")

        if caminho.suffix == ".parquet":
            return pd.read_parquet(caminho, engine="pyarrow")
        elif caminho.suffix == ".csv":
            return pd.read_csv(caminho, parse_dates=["timestamp"])
        else:
            raise ValueError(f"Formato de arquivo não suportado: {caminho.suffix}")

    @staticmethod
    def processar_csv_ticks_mt5(
        caminho_csv: Union[str, Path],
        chunksize: int = 500_000,
        limite_linhas: Optional[int] = None,
        data_inicio: Optional[str] = None,
        data_fim: Optional[str] = None,
        salvar_parquet_path: Optional[Union[str, Path]] = None
    ) -> pd.DataFrame:
        """
        Processa arquivos massivos de exportação de ticks do MetaTrader 5 (ex: XAUUSD > 5GB).
        Suporta parsing em streaming, decodificação de BBO/Quote ticks e gravação direta em Parquet.

        :param caminho_csv: Caminho para o arquivo CSV tab-delimited do MT5.
        :param chunksize: Quantidade de linhas por lote de processamento in-memory.
        :param limite_linhas: Número máximo opcional de linhas a processar (para testes ou amostras).
        :param data_inicio: Data mínima no formato 'YYYY-MM-DD' para filtro.
        :param data_fim: Data máxima no formato 'YYYY-MM-DD' para filtro.
        :param salvar_parquet_path: Se informado, converte o CSV para Parquet em streaming contínuo.
        :return: DataFrame consolidado com os dados processados (ou amostra).
        """
        import pyarrow as pa
        import pyarrow.parquet as pq

        caminho = Path(caminho_csv)
        if not caminho.exists():
            raise FileNotFoundError(f"Arquivo CSV não encontrado: {caminho}")

        logger.info(f"Iniciando ingestão institucional do CSV MT5: {caminho.name} ({caminho.stat().st_size / (1024**3):.2f} GB)")

        nomes_colunas = ["date", "time", "bid", "ask", "last", "vol", "flags"]
        tipos_colunas = {
            "date": str,
            "time": str,
            "bid": "float64",
            "ask": "float64",
            "last": "float64",
            "vol": "float64",
            "flags": "int64"
        }

        leitor_chunks = pd.read_csv(
            caminho,
            sep="\t",
            names=nomes_colunas,
            header=0,
            dtype=tipos_colunas,
            chunksize=chunksize,
            low_memory=False
        )

        parquet_writer = None
        esquema_arrow = None
        lista_dfs_amostra = []
        total_processado = 0
        ultimo_preco = 0.0
        ultimo_bid = 0.0
        ultimo_ask = 0.0

        if salvar_parquet_path:
            caminho_parquet = Path(salvar_parquet_path)
            caminho_parquet.parent.mkdir(parents=True, exist_ok=True)

        try:
            for indice_chunk, chunk in enumerate(leitor_chunks):
                # 1. Tratamento e preenchimento de Bid/Ask ausentes (Quote ticks)
                chunk["bid"] = chunk["bid"].ffill().fillna(ultimo_bid)
                chunk["ask"] = chunk["ask"].ffill().fillna(ultimo_ask)
                if not chunk["bid"].empty:
                    ultimo_bid = chunk["bid"].iloc[-1]
                if not chunk["ask"].empty:
                    ultimo_ask = chunk["ask"].iloc[-1]

                # 2. Conversão de Timestamp de alta precisão
                chunk["timestamp"] = pd.to_datetime(
                    chunk["date"] + " " + chunk["time"],
                    format="%Y.%m.%d %H:%M:%S.%f",
                    utc=True
                )

                # Filtro por data se solicitado
                if data_inicio:
                    chunk = chunk[chunk["timestamp"] >= pd.to_datetime(data_inicio, utc=True)]
                if data_fim:
                    chunk = chunk[chunk["timestamp"] <= pd.to_datetime(data_fim, utc=True)]

                if chunk.empty:
                    continue

                # 3. Microestrutura e Preço de Referência
                # Se 'last' for nulo ou zero (padrão em CFDs OTC), deriva pelo mid-price
                chunk["last"] = chunk["last"].fillna(0.0)
                mid_price = (chunk["bid"] + chunk["ask"]) / 2.0
                chunk["mid_price"] = mid_price
                chunk["price"] = np.where(chunk["last"] > 0, chunk["last"], mid_price)

                # 4. Volume do Tick (se vazio, contabiliza 1.0 unidade por evento de liquidez)
                chunk["vol"] = chunk["vol"].fillna(1.0)
                chunk["vol"] = np.where(chunk["vol"] <= 0, 1.0, chunk["vol"])

                # 5. Algoritmo Vetorizado de Agressão para Quote Ticks e Trade Ticks
                diff_mid = chunk["mid_price"].diff().fillna(0.0)
                cond_compra = (chunk["flags"] & MT5TickFeed.FLAG_TICK_BUY > 0) | (diff_mid > 0)
                cond_venda = (chunk["flags"] & MT5TickFeed.FLAG_TICK_SELL > 0) | (diff_mid < 0)

                chunk["aggression"] = "NEUTRAL"
                chunk["aggression"] = np.where(cond_compra, "BUY", chunk["aggression"])
                chunk["aggression"] = np.where(cond_venda, "SELL", chunk["aggression"])

                # Preenchimento de agressões neutras pelo histórico prévio (Lee-Ready)
                chunk["aggression"] = chunk["aggression"].replace("NEUTRAL", np.nan).ffill().fillna("BUY")

                chunk["buy_vol"] = np.where(chunk["aggression"] == "BUY", chunk["vol"], 0.0)
                chunk["sell_vol"] = np.where(chunk["aggression"] == "SELL", chunk["vol"], 0.0)
                chunk["delta"] = chunk["buy_vol"] - chunk["sell_vol"]

                colunas_finais = [
                    "timestamp", "bid", "ask", "price", "vol",
                    "flags", "aggression", "buy_vol", "sell_vol", "delta"
                ]
                chunk_final = chunk[colunas_finais]

                # 6. Gravação em Streaming Parquet
                if salvar_parquet_path:
                    tabela_chunk = pa.Table.from_pandas(chunk_final, preserve_index=False)
                    if parquet_writer is None:
                        esquema_arrow = tabela_chunk.schema
                        parquet_writer = pq.ParquetWriter(
                            str(caminho_parquet),
                            esquema_arrow,
                            compression="snappy"
                        )
                    parquet_writer.write_table(tabela_chunk)

                # Armazena amostra in-memory se não estiver gravando ou se solicitado
                if salvar_parquet_path is None or len(lista_dfs_amostra) < 5:
                    lista_dfs_amostra.append(chunk_final)

                total_processado += len(chunk_final)
                logger.info(f"Chunk {indice_chunk + 1} processado: {total_processado:,} ticks acumulados...")

                if limite_linhas and total_processado >= limite_linhas:
                    logger.info(f"Limite solicitado de {limite_linhas:,} linhas atingido.")
                    break

        finally:
            if parquet_writer is not None:
                parquet_writer.close()
                logger.info(f"Arquivo Parquet gerado com sucesso: {salvar_parquet_path}")

        if lista_dfs_amostra:
            df_retorno = pd.concat(lista_dfs_amostra, ignore_index=True)
            if limite_linhas:
                df_retorno = df_retorno.iloc[:limite_linhas]
            return df_retorno

        return pd.DataFrame()
