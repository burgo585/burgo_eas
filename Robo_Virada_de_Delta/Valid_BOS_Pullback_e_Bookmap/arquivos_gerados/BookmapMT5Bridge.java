package com.viniciusburgo.bridge;

import velox.api.layer1.annotations.Layer1ApiVersion;
import velox.api.layer1.annotations.Layer1ApiVersionValue;
import velox.api.layer1.annotations.Layer1SimpleAttachable;
import velox.api.layer1.annotations.Layer1StrategyName;
import velox.api.layer1.data.InstrumentInfo;
import velox.api.layer1.data.TradeInfo;
import velox.api.layer1.simplified.Api;
import velox.api.layer1.simplified.CustomModule;
import velox.api.layer1.simplified.DepthDataListener;
import velox.api.layer1.simplified.InitialState;
import velox.api.layer1.simplified.TradeDataListener;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentSkipListMap;
import java.util.concurrent.CopyOnWriteArrayList;

@Layer1SimpleAttachable
@Layer1StrategyName("Bookmap to MT5 Bridge Pro [@viniciusburgo]")
@Layer1ApiVersion(Layer1ApiVersionValue.VERSION2)
public class BookmapMT5Bridge implements CustomModule, TradeDataListener, DepthDataListener {

    private String alias = "";
    private InstrumentInfo info;

    // Métricas de Preço e Volume
    private volatile double lastPrice = 0.0;
    private volatile long totalVolume = 0;
    private volatile double totalVolumePriceProduct = 0.0;
    private volatile double sessionVwap = 0.0;
    private volatile long sessionDelta = 0;
    private volatile long cvd = 0;

    // Perfil de Volume para Nós (HVN / POC)
    private final ConcurrentHashMap<Long, Long> volumeProfile = new ConcurrentHashMap<>();

    // Livro de Ofertas para Paredes de Liquidez (Heatmap)
    private final ConcurrentSkipListMap<Long, Integer> bidBook = new ConcurrentSkipListMap<>();
    private final ConcurrentSkipListMap<Long, Integer> askBook = new ConcurrentSkipListMap<>();

    // Servidor TCP Socket Localhost
    private ServerSocket serverSocket;
    private final List<ClientHandler> clients = new CopyOnWriteArrayList<>();
    private final List<File> mt5FilesDirs = new ArrayList<>();
    private volatile boolean running = false;
    private Thread broadcastThread;

    @Override
    public void initialize(String alias, InstrumentInfo info, Api api, InitialState initialState) {
        this.alias = alias;
        this.info = info;
        this.running = true;

        System.out.println("[BookmapMT5Bridge] Iniciando ponte para: " + alias + " (Pips=" + (info != null ? info.pips : 0.1) + ")");

        // Descobre pastas MQL5/Files no computador
        discoverMt5Directories();

        // Inicia Servidor TCP na porta 5555
        startTcpServer(5555);

        // Inicia Thread de Broadcast (transmissão ultra-rápida a cada 30ms)
        broadcastThread = new Thread(this::broadcastLoop, "BM-MT5-Broadcast");
        broadcastThread.setDaemon(true);
        broadcastThread.start();
    }

    private void discoverMt5Directories() {
        mt5FilesDirs.clear();
        String appData = System.getenv("APPDATA");
        if (appData != null) {
            File termDir = new File(appData, "MetaQuotes/Terminal");
            if (termDir.exists() && termDir.isDirectory()) {
                File[] subs = termDir.listFiles();
                if (subs != null) {
                    for (File s : subs) {
                        File mql5Files = new File(s, "MQL5/Files");
                        if (mql5Files.exists() && mql5Files.isDirectory()) {
                            mt5FilesDirs.add(mql5Files);
                            System.out.println("[BookmapMT5Bridge] Pasta MT5 detectada: " + mql5Files.getAbsolutePath());
                        }
                    }
                }
            }
        }
    }

    @Override
    public void stop() {
        this.running = false;
        try {
            if (serverSocket != null && !serverSocket.isClosed()) {
                serverSocket.close();
            }
        } catch (Exception ignored) {}

        for (ClientHandler client : clients) {
            client.close();
        }
        clients.clear();
        System.out.println("[BookmapMT5Bridge] Ponte finalizada com sucesso.");
    }

    private boolean isCrypto() {
        if (alias == null) return false;
        String u = alias.toUpperCase();
        return u.contains("BTC") || u.contains("XBT") || u.contains("ETH") || u.contains("SOL") || u.contains("CRYPTO");
    }

    private double normalizePrice(double p) {
        double pips = (info != null && info.pips > 0.0) ? info.pips : 0.1;
        if (isCrypto()) {
            // Em criptoativos (BTC/ETH), preços normais ficam entre 1.000 e 500.000 USD
            // Se o feed enviar em inteiros/centavos (ex: 6800000 para $68,000), normaliza com pips
            if (p > 500000.0 && pips < 1.0) {
                return p * pips;
            }
            return p;
        } else {
            // Para futuros como Ouro (GC) onde 26500 ou 41988 significa 2650.0 ou 4198.80 USD
            if (p > 10000.0 && p < 100000.0 && pips < 1.0) {
                return p * pips;
            }
            return p;
        }
    }

    @Override
    public void onTrade(double price, int size, TradeInfo tradeInfo) {
        double pips = (info != null && info.pips > 0.0) ? info.pips : 0.1;
        // Normalização inteligente multi-ativo (Ouro, Bitcoin, etc.)
        double realPrice = normalizePrice(price);
        this.lastPrice = realPrice;
        this.totalVolume += size;
        this.totalVolumePriceProduct += (realPrice * size);
        if (this.totalVolume > 0) {
            this.sessionVwap = this.totalVolumePriceProduct / this.totalVolume;
        }

        // Cálculo de Delta Agressivo Real
        boolean isBuyAggressor = (tradeInfo != null && tradeInfo.isBidAggressor);
        long tradeDelta = isBuyAggressor ? (long) size : -(long) size;
        this.sessionDelta += tradeDelta;
        this.cvd += tradeDelta;

        // Acumulação no Perfil de Volume (usando chave inteira normalizada por tick)
        long priceKey = Math.round(realPrice / pips);
        volumeProfile.merge(priceKey, (long) size, Long::sum);
    }

    @Override
    public void onDepth(boolean isBid, int price, int size) {
        long pKey = (long) price;
        if (isBid) {
            if (size <= 0) {
                bidBook.remove(pKey);
            } else {
                bidBook.put(pKey, size);
            }
        } else {
            if (size <= 0) {
                askBook.remove(pKey);
            } else {
                askBook.put(pKey, size);
            }
        }
    }

    private void startTcpServer(int port) {
        Thread serverThread = new Thread(() -> {
            try {
                serverSocket = new ServerSocket(port);
                System.out.println("[BookmapMT5Bridge] Servidor TCP Localhost ouvindo na porta " + port);
                while (running) {
                    Socket socket = serverSocket.accept();
                    socket.setTcpNoDelay(true); // Latência ZERO
                    ClientHandler handler = new ClientHandler(socket);
                    clients.add(handler);
                    System.out.println("[BookmapMT5Bridge] MT5 conectado de: " + socket.getRemoteSocketAddress());
                }
            } catch (Exception e) {
                if (running) {
                    System.err.println("[BookmapMT5Bridge] Erro no servidor TCP: " + e.getMessage());
                }
            }
        }, "BM-MT5-Listener");
        serverThread.setDaemon(true);
        serverThread.start();
    }

    private void broadcastLoop() {
        long fileWriteTick = 0;
        while (running) {
            try {
                Thread.sleep(30); // 33 transmissões por segundo (latência de 30ms)
                if (lastPrice <= 0.0) continue;

                String json = buildMetricsJson();

                // 1. Transmissão Socket TCP em tempo real
                if (!clients.isEmpty()) {
                    for (ClientHandler client : clients) {
                        if (!client.send(json)) {
                            clients.remove(client);
                        }
                    }
                }

                // 2. Transmissão Dual-Fallback para MQL5/Files (a cada ~90ms)
                fileWriteTick++;
                if (fileWriteTick % 3 == 0 && !mt5FilesDirs.isEmpty()) {
                    byte[] bytes = json.getBytes(StandardCharsets.UTF_8);
                    for (File dir : mt5FilesDirs) {
                        File target = new File(dir, "bookmap_stream.json");
                        try (FileOutputStream fos = new FileOutputStream(target, false)) {
                            fos.write(bytes);
                        } catch (Exception ignored) {}
                    }
                }
            } catch (InterruptedException e) {
                break;
            } catch (Exception e) {
                System.err.println("[BookmapMT5Bridge] Erro no loop de broadcast: " + e.getMessage());
            }
        }
    }

    private String buildMetricsJson() {
        double pips = (info != null && info.pips > 0.0) ? info.pips : 0.1;

        // 1. Cálculo do POC (Point of Control), VAH (Value Area High), VAL (Value Area Low) e HVN
        long maxVol = 0;
        long pocKey = 0;
        long hvnKey = 0;
        long secondMaxVol = 0;
        long totalProfileVol = 0;
        long minKey = Long.MAX_VALUE;
        long maxKey = Long.MIN_VALUE;

        for (Map.Entry<Long, Long> entry : volumeProfile.entrySet()) {
            long k = entry.getKey();
            if (k < minKey) minKey = k;
            if (k > maxKey) maxKey = k;

            long vol = entry.getValue();
            totalProfileVol += vol;
            if (vol > maxVol) {
                secondMaxVol = maxVol;
                hvnKey = pocKey;
                maxVol = vol;
                pocKey = k;
            } else if (vol > secondMaxVol) {
                secondMaxVol = vol;
                hvnKey = k;
            }
        }

        // Cálculo da Value Area de 70% (VAH e VAL) expandindo a partir do POC
        long vahKey = (pocKey > 0) ? pocKey : Math.round(lastPrice / pips);
        long valKey = (pocKey > 0) ? pocKey : Math.round(lastPrice / pips);

        if (totalProfileVol > 0 && pocKey > 0) {
            long targetAreaVol = (long) (totalProfileVol * 0.70);
            long currentAreaVol = maxVol;
            long upKey = pocKey + 1;
            long downKey = pocKey - 1;

            int maxSteps = 3000;
            int step = 0;
            while (currentAreaVol < targetAreaVol && step < maxSteps) {
                step++;
                long upVol = volumeProfile.getOrDefault(upKey, 0L);
                long downVol = volumeProfile.getOrDefault(downKey, 0L);

                if (upVol == 0 && downVol == 0) {
                    Long nextUp = null;
                    Long nextDown = null;
                    for (Long k : volumeProfile.keySet()) {
                        if (k >= upKey && (nextUp == null || k < nextUp)) nextUp = k;
                        if (k <= downKey && (nextDown == null || k > nextDown)) nextDown = k;
                    }
                    if (nextUp == null && nextDown == null) break;

                    long nextUpVol = (nextUp != null) ? volumeProfile.getOrDefault(nextUp, 0L) : 0L;
                    long nextDownVol = (nextDown != null) ? volumeProfile.getOrDefault(nextDown, 0L) : 0L;

                    if (nextUp != null && (nextDown == null || nextUpVol >= nextDownVol)) {
                        currentAreaVol += nextUpVol;
                        vahKey = nextUp;
                        upKey = nextUp + 1;
                    } else if (nextDown != null) {
                        currentAreaVol += nextDownVol;
                        valKey = nextDown;
                        downKey = nextDown - 1;
                    }
                } else {
                    if (upVol >= downVol) {
                        currentAreaVol += upVol;
                        vahKey = upKey;
                        upKey++;
                    } else {
                        currentAreaVol += downVol;
                        valKey = downKey;
                        downKey--;
                    }
                }
            }
        }

        double pocPrice = (pocKey > 0) ? (pocKey * pips) : lastPrice;
        double vahPrice = (vahKey > 0) ? (vahKey * pips) : (pocPrice + (30 * pips));
        double valPrice = (valKey > 0) ? (valKey * pips) : (pocPrice - (30 * pips));
        double hvnPrice = (hvnKey > 0) ? (hvnKey * pips) : lastPrice;
        double profileHigh = (maxKey != Long.MIN_VALUE) ? (maxKey * pips) : lastPrice;
        double profileLow  = (minKey != Long.MAX_VALUE) ? (minKey * pips) : lastPrice;

        pocPrice    = normalizePrice(pocPrice);
        vahPrice    = normalizePrice(vahPrice);
        valPrice    = normalizePrice(valPrice);
        hvnPrice    = normalizePrice(hvnPrice);
        profileHigh = normalizePrice(profileHigh);
        profileLow  = normalizePrice(profileLow);

        // 2. Identificação da Maior Parede de Compra (Bid Wall) dentro de 100 ticks
        double bidWallPrice = 0.0;
        int maxBidSize = 0;
        long currentPriceKey = Math.round(lastPrice / pips);

        for (Map.Entry<Long, Integer> entry : bidBook.descendingMap().entrySet()) {
            long k = entry.getKey();
            double p = normalizePrice(k * pips);
            long pKey = Math.round(p / pips);

            if (pKey < currentPriceKey && pKey >= (currentPriceKey - 100)) {
                if (entry.getValue() > maxBidSize) {
                    maxBidSize = entry.getValue();
                    bidWallPrice = p;
                }
            }
        }

        // 3. Identificação da Maior Parede de Venda (Ask Wall) dentro de 100 ticks
        double askWallPrice = 0.0;
        int maxAskSize = 0;
        for (Map.Entry<Long, Integer> entry : askBook.entrySet()) {
            long k = entry.getKey();
            double p = normalizePrice(k * pips);
            long pKey = Math.round(p / pips);

            if (pKey > currentPriceKey && pKey <= (currentPriceKey + 100)) {
                if (entry.getValue() > maxAskSize) {
                    maxAskSize = entry.getValue();
                    askWallPrice = p;
                }
            }
        }

        double vwapPrice = (this.sessionVwap > 0.0) ? normalizePrice(this.sessionVwap) : pocPrice;

        // Formatação do JSON ultraleve em 1 linha com VPVR (Range, VAH, VAL, POC)
        Locale loc = Locale.US;
        return String.format(loc,
                "{\"sym\":\"%s\",\"lp\":%.2f,\"vwap\":%.2f,\"poc\":%.2f,\"vah\":%.2f,\"val\":%.2f,\"hvn\":%.2f,\"prh\":%.2f,\"prl\":%.2f,\"bwp\":%.2f,\"bwv\":%d,\"awp\":%.2f,\"awv\":%d,\"del\":%d,\"cvd\":%d,\"vol\":%d}\n",
                alias, lastPrice, vwapPrice, pocPrice, vahPrice, valPrice, hvnPrice, profileHigh, profileLow, bidWallPrice, maxBidSize, askWallPrice, maxAskSize, sessionDelta, cvd, totalVolume
        );
    }

    private static class ClientHandler {
        private final Socket socket;
        private final PrintWriter out;

        public ClientHandler(Socket socket) throws Exception {
            this.socket = socket;
            this.out = new PrintWriter(new OutputStreamWriter(socket.getOutputStream(), StandardCharsets.UTF_8), true);
        }

        public boolean send(String data) {
            if (out.checkError()) {
                close();
                return false;
            }
            out.print(data);
            out.flush();
            return !out.checkError();
        }

        public void close() {
            try {
                socket.close();
            } catch (Exception ignored) {}
        }
    }
}
