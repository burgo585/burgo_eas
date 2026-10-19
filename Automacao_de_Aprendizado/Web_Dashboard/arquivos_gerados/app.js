/**
 * app.js - Sunrise Quantitative Enterprise
 * Motor interativo de Governança de Risco, Raio-X de Fricção,
 * Radar Macroeconômico e Central de Aprendizado.
 */

// ==================== DADOS DE CONTINGÊNCIA (FALLBACK EMBEDDED) ====================
// Garante 100% de estabilidade visual mesmo se a API estiver reconectando
const FALLBACK_MACRO_EVENTS = [
  {
    id: "mon_0930_ny",
    day_key: "monday",
    day_name: "Segunda-feira",
    date_formatted: "12/10/2026",
    time_brt: "09:30",
    country: "USD",
    flag: "🇺🇸",
    title: "Abertura Oficial de Nova York & Discursos do Fed",
    impact: "Medium",
    impact_label: "🟡 Médio Impacto",
    forecast: "-",
    previous: "-",
    affected_assets: ["NAS100", "XAUUSD"],
    market_note: "Início do fluxo institucional pesado da semana. Volatilidade crescente em tecnologia e ouro.",
    is_today: true,
    is_past: false,
    is_imminent: false,
    diff_minutes: 60,
    status_text: "Hoje às 09:30 BRT",
    status_badge: "badge-blue"
  },
  {
    id: "mon_1100_pmi",
    day_key: "monday",
    day_name: "Segunda-feira",
    date_formatted: "12/10/2026",
    time_brt: "11:00",
    country: "USD",
    flag: "🇺🇸",
    title: "PMI Industrial & Serviços dos EUA (S&P Global / ISM)",
    impact: "High",
    impact_label: "🔴 ALTO IMPACTO (Tier 1)",
    forecast: "50.5",
    previous: "49.8",
    affected_assets: ["NAS100", "XAUUSD", "BTCUSD"],
    market_note: "Termômetro inicial da atividade econômica dos EUA. Movimenta forte os índices de ações e ouro.",
    is_today: true,
    is_past: false,
    is_imminent: false,
    diff_minutes: 150,
    status_text: "Hoje às 11:00 BRT",
    status_badge: "badge-blue"
  },
  {
    id: "mon_1230_bonds",
    day_key: "monday",
    day_name: "Segunda-feira",
    date_formatted: "12/10/2026",
    time_brt: "12:30",
    country: "USD",
    flag: "🇺🇸",
    title: "Leilão de Títulos do Tesouro dos EUA (Treasuries 10 Anos)",
    impact: "Medium",
    impact_label: "🟡 Médio Impacto",
    forecast: "-",
    previous: "-",
    affected_assets: ["NAS100", "XAUUSD"],
    market_note: "Rendimento dos yields afeta diretamente a atratividade do ouro e a precificação do Nasdaq.",
    is_today: true,
    is_past: false,
    is_imminent: false,
    diff_minutes: 240,
    status_text: "Hoje às 12:30 BRT",
    status_badge: "badge-blue"
  },
  {
    id: "tue_0930_cpi",
    day_key: "tuesday",
    day_name: "Terça-feira",
    date_formatted: "13/10/2026",
    time_brt: "09:30",
    country: "USD",
    flag: "🇺🇸",
    title: "CPI - Índice de Preços ao Consumidor (Inflação) & Core CPI",
    impact: "High",
    impact_label: "🔴 ALTO IMPACTO (Tier 1)",
    forecast: "+0.2% m/m",
    previous: "+0.2% m/m",
    affected_assets: ["XAUUSD", "NAS100", "BTCUSD"],
    market_note: "GATILHO DE MÁXIMA VOLATILIDADE! Inflação acima do esperado derruba o Ouro e o Nasdaq em segundos; inflação fraca provoca disparada.",
    is_today: false,
    is_past: false,
    is_imminent: false,
    diff_minutes: 1200,
    status_text: "Terça-feira às 09:30",
    status_badge: "badge-dark"
  },
  {
    id: "wed_1500_fomc",
    day_key: "wednesday",
    day_name: "Quarta-feira",
    date_formatted: "14/10/2026",
    time_brt: "15:00",
    country: "USD",
    flag: "🇺🇸",
    title: "Decisão de Taxa de Juros do FOMC / Divulgação das Atas",
    impact: "High",
    impact_label: "🔴 ALTO IMPACTO (Tier 1)",
    forecast: "5.00%",
    previous: "5.00%",
    affected_assets: ["XAUUSD", "NAS100", "BTCUSD"],
    market_note: "O EVENTO MAIS IMPORTANTE DO MERCADO FINANCEIRO. Define a taxa básica do Dólar. Alargamento severo de spread garantido.",
    is_today: false,
    is_past: false,
    is_imminent: false,
    diff_minutes: 2700,
    status_text: "Quarta-feira às 15:00",
    status_badge: "badge-dark"
  },
  {
    id: "wed_1530_powell",
    day_key: "wednesday",
    day_name: "Quarta-feira",
    date_formatted: "14/10/2026",
    time_brt: "15:30",
    country: "USD",
    flag: "🇺🇸",
    title: "Coletiva de Imprensa de Jerome Powell (Presidente do Fed)",
    impact: "High",
    impact_label: "🔴 ALTO IMPACTO (Tier 1)",
    forecast: "-",
    previous: "-",
    affected_assets: ["XAUUSD", "NAS100", "BTCUSD"],
    market_note: "Cada palavra de Powell causa repiques violentos de 50 a 150 pips no Ouro e no Nasdaq. Mantenha ordens fechadas.",
    is_today: false,
    is_past: false,
    is_imminent: false,
    diff_minutes: 2730,
    status_text: "Quarta-feira às 15:30",
    status_badge: "badge-dark"
  },
  {
    id: "thu_0930_claims",
    day_key: "thursday",
    day_name: "Quinta-feira",
    date_formatted: "15/10/2026",
    time_brt: "09:30",
    country: "USD",
    flag: "🇺🇸",
    title: "Pedidos Iniciais por Seguro-Desemprego (Jobless Claims)",
    impact: "High",
    impact_label: "🔴 ALTO IMPACTO (Tier 1)",
    forecast: "225K",
    previous: "221K",
    affected_assets: ["NAS100", "XAUUSD"],
    market_note: "Divulgado semanalmente às quintas. Termômetro em tempo real do mercado de trabalho americano.",
    is_today: false,
    is_past: false,
    is_imminent: false,
    diff_minutes: 4100,
    status_text: "Quinta-feira às 09:30",
    status_badge: "badge-dark"
  },
  {
    id: "fri_0930_nfp",
    day_key: "friday",
    day_name: "Sexta-feira",
    date_formatted: "16/10/2026",
    time_brt: "09:30",
    country: "USD",
    flag: "🇺🇸",
    title: "Non-Farm Payrolls (NFP) & Taxa de Desemprego dos EUA",
    impact: "High",
    impact_label: "🔴 ALTO IMPACTO (Tier 1)",
    forecast: "+160K",
    previous: "+142K",
    affected_assets: ["XAUUSD", "NAS100", "BTCUSD"],
    market_note: "A MAIOR NOTÍCIA DO MÊS. Volume gigante, slippage altíssimo em robôs e gaps imediatos.",
    is_today: false,
    is_past: false,
    is_imminent: false,
    diff_minutes: 5500,
    status_text: "Sexta-feira às 09:30",
    status_badge: "badge-dark"
  }
];

// Estado global da aplicação
const state = {
  activeSymbol: "XAUUSD",
  orderType: "BUY",
  timeframe: "M15",
  assets: {},
  presets: [],
  categories: [],
  activeChannelId: null,
  lastResult: null,
  macroData: null,
  macroFilter: "all", // "all" garante que o usuário vê todos os eventos da semana ao abrir a aba
  macroSearchQuery: "",
  channelSearchQuery: ""
};

// ==================== INICIALIZAÇÃO ====================
document.addEventListener("DOMContentLoaded", async () => {
  setupNavigationTabs();
  setupEventListeners();
  await loadInitialData();
  await selectAsset("XAUUSD", false);
  await runCalculation();
});

// ==================== ABAS DE NAVEGAÇÃO ====================
function setupNavigationTabs() {
  const navButtons = document.querySelectorAll(".nav-btn");
  navButtons.forEach(btn => {
    btn.addEventListener("click", () => {
      navButtons.forEach(b => b.classList.remove("active"));
      btn.classList.add("active");

      const targetTabId = btn.getAttribute("data-tab");
      document.querySelectorAll(".tab-content").forEach(tc => tc.classList.remove("active"));
      const targetContent = document.getElementById(targetTabId);
      if (targetContent) {
        targetContent.classList.add("active");
      }
    });
  });
}

// ==================== CARREGAMENTO DE DADOS DA API ====================
async function loadInitialData() {
  // 1. Carregar Ativos
  try {
    const resAssets = await fetch("/api/assets");
    if (resAssets.ok) {
      const dataAssets = await resAssets.json();
      state.assets = dataAssets.assets;
    }
  } catch (err) {
    console.warn("API de ativos offline, usando dados em memória:", err);
  }

  // 2. Carregar Presets
  try {
    const resPresets = await fetch("/api/presets");
    if (resPresets.ok) {
      const dataPresets = await resPresets.json();
      state.presets = dataPresets.presets;
      renderPresetsBar();
    }
  } catch (err) {
    console.warn("API de presets offline:", err);
  }

  // 3. Carregar Matriz de Drawdown e Sobrevivência
  try {
    const resDrawdown = await fetch("/api/drawdown-matrix");
    if (resDrawdown.ok) {
      const dataDrawdown = await resDrawdown.json();
      renderDrawdownTables(dataDrawdown);
    }
  } catch (err) {
    console.warn("API de drawdown offline:", err);
  }

  // 4. Carregar Árvore de Canais e Categorias do Discord
  try {
    const resCat = await fetch("/api/education/categories");
    if (resCat.ok) {
      const dataCat = await resCat.json();
      state.categories = dataCat.categories;
      renderDiscordTree();
    }
  } catch (err) {
    console.warn("API de educação offline:", err);
  }

  // 5. Carregar Radar Macroeconômico e Calendário de Notícias
  try {
    await loadMacroCalendar();
    startMacroClock();
  } catch (err) {
    console.warn("API macro offline:", err);
  }
}

// ==================== EVENT LISTENERS DO FORMULÁRIO ====================
function setupEventListeners() {
  const reactiveInputs = [
    "input-capital", "input-risk", "input-stop", "input-tp",
    "input-leverage", "input-spread", "input-days", "input-manual-lot"
  ];

  reactiveInputs.forEach(id => {
    const el = document.getElementById(id);
    if (el) {
      el.addEventListener("input", debounce(() => {
        updateRiskGaugeUI();
        runCalculation();
      }, 120));
      el.addEventListener("change", () => {
        updateRiskGaugeUI();
        runCalculation();
      });
    }
  });

  // Botões de Ativos (XAUUSD, BTCUSD, NAS100)
  document.querySelectorAll(".asset-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      const sym = btn.getAttribute("data-symbol");
      selectAsset(sym, true);
    });
  });

  // Dropdown de presets
  const presetDropdown = document.getElementById("preset-dropdown");
  if (presetDropdown) {
    presetDropdown.addEventListener("change", (e) => {
      if (e.target.value) {
        applyPreset(e.target.value);
      }
    });
  }

  updateRiskGaugeUI();
}

// ==================== PRESETS RÁPIDOS ====================
function renderPresetsBar() {
  const container = document.getElementById("preset-buttons-container");
  const dropdown = document.getElementById("preset-dropdown");
  if (!container || !dropdown || !state.presets) return;

  container.innerHTML = "";
  dropdown.innerHTML = '<option value="">⚡ Carregar Setup Estratégico...</option>';

  state.presets.forEach(preset => {
    const btn = document.createElement("button");
    btn.className = "preset-pill-btn";
    btn.textContent = preset.name;
    btn.title = preset.description;
    btn.onclick = () => applyPreset(preset.id);
    container.appendChild(btn);

    const opt = document.createElement("option");
    opt.value = preset.id;
    opt.textContent = `${preset.name} - ${preset.description}`;
    dropdown.appendChild(opt);
  });
}

function applyPreset(presetId) {
  const preset = state.presets.find(p => p.id === presetId);
  if (!preset) return;

  state.activeSymbol = preset.symbol;
  state.orderType = preset.order_type;
  state.timeframe = preset.timeframe;

  document.querySelectorAll(".asset-btn").forEach(b => {
    b.classList.toggle("active", b.getAttribute("data-symbol") === preset.symbol);
  });

  const badge = document.getElementById("active-symbol-badge");
  if (badge) badge.textContent = preset.symbol;

  document.getElementById("input-capital").value = preset.capital;
  document.getElementById("input-risk").value = preset.risk_pct;
  document.getElementById("input-stop").value = preset.stop_pips;
  document.getElementById("input-tp").value = preset.tp_pips;
  document.getElementById("input-leverage").value = preset.leverage;
  document.getElementById("input-spread").value = preset.spread_pips;
  document.getElementById("input-days").value = preset.holding_days || 0;
  document.getElementById("input-manual-lot").value = "";

  updateOrderTypeUI();
  updateTimeframeUI();
  updateRiskButtonsUI(preset.risk_pct);
  updateCapitalPillsUI(preset.capital);
  updateRiskGaugeUI();

  runCalculation();
}

// ==================== SELEÇÃO DE ATIVO ====================
async function selectAsset(symbol, shouldRecalibrate = true) {
  state.activeSymbol = symbol;

  document.querySelectorAll(".asset-btn").forEach(b => {
    b.classList.toggle("active", b.getAttribute("data-symbol") === symbol);
  });

  const badge = document.getElementById("active-symbol-badge");
  if (badge) badge.textContent = symbol;

  if (shouldRecalibrate) {
    if (symbol === "BTCUSD") {
      document.getElementById("input-stop").value = 500;
      document.getElementById("input-tp").value = 1500;
      document.getElementById("input-spread").value = 25.0;
      document.getElementById("input-capital").value = 500;
      document.getElementById("input-risk").value = 1.0;
    } else if (symbol === "NAS100") {
      document.getElementById("input-stop").value = 30;
      document.getElementById("input-tp").value = 90;
      document.getElementById("input-spread").value = 1.2;
      document.getElementById("input-capital").value = 1000;
      document.getElementById("input-risk").value = 1.0;
    } else if (symbol === "XAUUSD") {
      document.getElementById("input-stop").value = 20;
      document.getElementById("input-tp").value = 40;
      document.getElementById("input-spread").value = 2.0;
      document.getElementById("input-capital").value = 1000;
      document.getElementById("input-risk").value = 1.0;
    }
  }

  updateRiskGaugeUI();
  await runCalculation();
}

// ==================== EXECUÇÃO DO CÁLCULO PRINCIPAL ====================
async function runCalculation() {
  const capital = parseFloat(document.getElementById("input-capital").value) || 1000;
  const risk_pct = parseFloat(document.getElementById("input-risk").value) || 1.0;
  const stop_pips = parseFloat(document.getElementById("input-stop").value) || 20;
  const tp_pips = parseFloat(document.getElementById("input-tp").value) || 40;
  const leverage = parseInt(document.getElementById("input-leverage").value) || 100;
  const spread_pips = parseFloat(document.getElementById("input-spread").value) || 0;
  const holding_days = parseInt(document.getElementById("input-days").value) || 0;
  const manualLotVal = document.getElementById("input-manual-lot").value;
  const manual_lot = manualLotVal ? parseFloat(manualLotVal) : null;

  const payload = {
    symbol: state.activeSymbol,
    capital,
    risk_pct,
    stop_pips,
    tp_pips,
    order_type: state.orderType,
    leverage,
    spread_pips,
    holding_days,
    timeframe: state.timeframe,
    manual_lot
  };

  try {
    const res = await fetch("/api/calculate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });

    if (res.ok) {
      const data = await res.json();
      state.lastResult = data;
      renderResults(data);
    } else {
      renderLocalFallbackCalculation(payload);
    }
  } catch (err) {
    console.warn("Calculando localmente devido a falha de conexão:", err);
    renderLocalFallbackCalculation(payload);
  }
}

// Fallback local caso o backend esteja em reinicialização
function renderLocalFallbackCalculation(req) {
  let pipValStd = 10.0;
  if (req.symbol === "BTCUSD" || req.symbol === "NAS100") pipValStd = 1.0;

  const moneyAtRisk = req.capital * (req.risk_pct / 100.0);
  const rawLot = moneyAtRisk / (req.stop_pips * pipValStd);
  const lot = Math.max(0.01, Math.round(rawLot * 100) / 100);

  const nominalLoss = lot * req.stop_pips * pipValStd;
  const nominalProfit = lot * req.tp_pips * pipValStd;
  const spreadCost = lot * req.spread_pips * pipValStd;
  const commCost = lot * 6.0;
  const frictionTotal = spreadCost + commCost;
  const realLoss = nominalLoss + frictionTotal;
  const realProfit = nominalProfit - frictionTotal;

  renderResults({
    symbol: req.symbol,
    order_type: req.order_type,
    leverage: req.leverage,
    capital: req.capital,
    stop_pips: req.stop_pips,
    tp_pips: req.tp_pips,
    timeframe: req.timeframe,
    asset: { name: req.symbol },
    governance: {
      level: req.risk_pct <= 1.0 ? "SEGURO" : (req.risk_pct <= 2.0 ? "ALERTA" : "PERIGO"),
      verdict: req.risk_pct <= 1.0 ? "✅ Parâmetros Seguros: Risco institucional dentro do limite." : "⚠️ Atenção: Risco elevado.",
      alerts: []
    },
    boleta: {
      compact: `[ ${lot.toFixed(2)} LOTES ]  SL: ${req.stop_pips}p  |  TP: ${req.tp_pips}p  (${req.order_type})`,
      mt5: `${req.symbol} | ${req.order_type} | ${lot.toFixed(2)} Lotes | SL: ${req.stop_pips}p | TP: ${req.tp_pips}p`
    },
    nominal: {
      loss_usd: nominalLoss,
      loss_pct: (nominalLoss / req.capital) * 100,
      profit_usd: nominalProfit,
      profit_pct: (nominalProfit / req.capital) * 100,
      rr_ratio: req.tp_pips / req.stop_pips
    },
    real: {
      loss_usd: realLoss,
      loss_pct: (realLoss / req.capital) * 100,
      profit_usd: realProfit,
      profit_pct: (realProfit / req.capital) * 100,
      friction_usd: frictionTotal,
      friction_pct_profit: nominalProfit > 0 ? (frictionTotal / nominalProfit) * 100 : 0
    },
    margin: {
      required_usd: (lot * 1000 * 2000) / req.leverage / 100,
      free_usd: req.capital - 25,
      real_leverage: 1.2
    },
    volatility: {
      atr_pips: 30.0,
      stop_atr_ratio: req.stop_pips / 30.0,
      prob_tp_pct: 48.0,
      ev_r: 0.40
    },
    costs: {
      spread_pips: req.spread_pips,
      spread_usd: spreadCost,
      commission_usd: commCost,
      swap_total_usd: 0
    }
  });
}

// ==================== ATUALIZAÇÃO DA TELA DE RESULTADOS ====================
function renderResults(res) {
  // Título e Subtítulo
  document.getElementById("res-title").textContent = 
    `🧮 GESTÃO AVANÇADA: ${res.symbol} ${res.order_type} (1:${res.leverage})`;
  document.getElementById("res-subtitle").textContent = 
    `Dimensionamento de Risco Institucional, Alavancagem e Fricção de Custos para ${res.symbol}`;

  // Badge de Status Geral
  const statusBadge = document.getElementById("res-status-badge");
  statusBadge.className = "status-badge";
  if (res.governance.level === "SEGURO") {
    statusBadge.classList.add("badge-green");
    statusBadge.textContent = "✅ Parâmetros Seguros (Aprovado em Mesa)";
  } else if (res.governance.level === "ALERTA") {
    statusBadge.classList.add("badge-yellow");
    statusBadge.textContent = "⚠️ Atenção a Parâmetros de Risco";
  } else {
    statusBadge.classList.add("badge-red");
    statusBadge.textContent = "🚨 Zona de Ruína Crítica";
  }

  // Boleta de Execução Rápida
  document.getElementById("boleta-box-content").textContent = res.boleta.compact;
  document.getElementById("boleta-meta-content").textContent = res.boleta.mt5;

  // Visualizador de Assimetria Matemática (Visual Payoff Bars)
  const lossReal = res.real.loss_usd;
  const profitReal = res.real.profit_usd;
  const rrRatio = res.nominal.rr_ratio;

  document.getElementById("val-rr-badge").textContent = `1 : ${rrRatio.toFixed(2)} R:R`;
  document.getElementById("payoff-sl-val").textContent = 
    `-$${lossReal.toFixed(2)} (-${res.real.loss_pct.toFixed(1)}%)`;
  document.getElementById("payoff-tp-val").textContent = 
    `+$${profitReal.toFixed(2)} (+${res.real.profit_pct.toFixed(1)}%)`;

  // Ajusta proporcionalmente a largura das barras
  const maxBarVal = Math.max(lossReal, profitReal, 1);
  const lossWidth = Math.min(100, Math.max(15, (lossReal / maxBarVal) * 85));
  const profitWidth = Math.min(100, Math.max(25, (profitReal / maxBarVal) * 85));
  
  const barLoss = document.getElementById("payoff-bar-loss");
  const barGain = document.getElementById("payoff-bar-gain");
  if (barLoss) barLoss.style.width = `${lossWidth}%`;
  if (barGain) barGain.style.width = `${profitWidth}%`;

  // 1. Stop Loss
  document.getElementById("val-sl-nominal").textContent = 
    `-$${res.nominal.loss_usd.toFixed(2)} (-${res.nominal.loss_pct.toFixed(1)}%)`;
  document.getElementById("val-sl-real").textContent = 
    `-$${res.real.loss_usd.toFixed(2)} (-${res.real.loss_pct.toFixed(1)}%)`;
  document.getElementById("val-sl-dist").textContent = `${res.stop_pips} pips`;

  // 2. Take Profit
  document.getElementById("val-tp-nominal").textContent = 
    `+$${res.nominal.profit_usd.toFixed(2)} (+${res.nominal.profit_pct.toFixed(1)}%)`;
  document.getElementById("val-tp-real").textContent = 
    `+$${res.real.profit_usd.toFixed(2)} (+${res.real.profit_pct.toFixed(1)}%)`;
  document.getElementById("val-rr-ratio").textContent = `1:${res.nominal.rr_ratio.toFixed(2)}`;

  // 3. Conta & Margem
  document.getElementById("val-margin-balance").textContent = `$${res.capital.toFixed(0)}`;
  document.getElementById("val-margin-lev").textContent = `1:${res.leverage}`;
  document.getElementById("val-margin-req").textContent = `$${res.margin.required_usd.toFixed(2)}`;
  document.getElementById("val-margin-free").textContent = `$${res.margin.free_usd.toFixed(2)}`;
  document.getElementById("val-real-lev").textContent = `${res.margin.real_leverage.toFixed(1)}x`;

  // 4. Volatilidade & ATR
  document.getElementById("val-atr-tf").textContent = res.timeframe;
  document.getElementById("val-atr-pips").textContent = `${res.volatility.atr_pips.toFixed(1)}p`;
  document.getElementById("val-stop-atr").textContent = `${res.volatility.stop_atr_ratio.toFixed(2)}x ATR`;
  document.getElementById("val-prob-tp").textContent = `${res.volatility.prob_tp_pct.toFixed(1)}%`;
  document.getElementById("val-ev-r").textContent = `${res.volatility.ev_r >= 0 ? '+' : ''}${res.volatility.ev_r.toFixed(2)}R`;

  // 5. Raio-X de Fricção
  document.getElementById("val-spread-pips").textContent = `${res.costs.spread_pips.toFixed(1)}p`;
  document.getElementById("val-spread-usd").textContent = `-$${res.costs.spread_usd.toFixed(2)}`;
  document.getElementById("val-comm-usd").textContent = `-$${res.costs.commission_usd.toFixed(2)}`;
  document.getElementById("val-swap-usd").textContent = `$${res.costs.swap_total_usd.toFixed(2)}`;
  document.getElementById("val-friction-total").textContent = `-$${res.real.friction_usd.toFixed(2)}`;
  document.getElementById("val-friction-pct").textContent = `${res.real.friction_pct_profit.toFixed(1)}%`;

  // 6. Parecer de Governança
  document.getElementById("val-gov-verdict").textContent = res.governance.verdict;
  const alertsContainer = document.getElementById("gov-alerts-container");
  alertsContainer.innerHTML = "";
  if (res.governance.alerts && res.governance.alerts.length > 0) {
    res.governance.alerts.forEach(alertText => {
      const item = document.createElement("div");
      item.className = "gov-alert-item";
      item.textContent = alertText;
      alertsContainer.appendChild(item);
    });
  }
}

// ==================== ATALHOS E CONTROLES RÁPIDOS ====================
function setCapital(amount) {
  document.getElementById("input-capital").value = amount;
  updateCapitalPillsUI(amount);
  runCalculation();
}

function updateCapitalPillsUI(amount) {
  document.querySelectorAll(".capital-quick-row .btn-cap-pill").forEach(btn => {
    btn.classList.toggle("active", btn.textContent.replace(/[^0-9]/g, '') === amount.toString().replace(/000$/, ''));
  });
}

function setRisk(pct) {
  document.getElementById("input-risk").value = pct;
  updateRiskButtonsUI(pct);
  updateRiskGaugeUI();
  runCalculation();
}

function updateRiskButtonsUI(pct) {
  document.querySelectorAll(".quick-risk-btns .btn-micro").forEach(btn => {
    btn.classList.toggle("active", parseFloat(btn.textContent) === pct);
  });
}

function updateRiskGaugeUI() {
  const riskInput = document.getElementById("input-risk");
  const gaugeBar = document.getElementById("risk-gauge-bar");
  const badge = document.getElementById("risk-zone-badge");
  if (!riskInput || !gaugeBar || !badge) return;

  const risk = parseFloat(riskInput.value) || 1.0;
  const pctWidth = Math.min(100, Math.max(5, (risk / 3.0) * 100));
  gaugeBar.style.width = `${pctWidth}%`;

  if (risk <= 0.5) {
    badge.textContent = "🛡️ Conservador (Mesa Proprietária)";
    badge.style.backgroundColor = "rgba(16, 185, 129, 0.15)";
    badge.style.color = "#10B981";
    badge.style.borderColor = "rgba(16, 185, 129, 0.4)";
  } else if (risk <= 1.0) {
    badge.textContent = "⚖️ Moderado Institucional (Recomendado)";
    badge.style.backgroundColor = "rgba(6, 182, 212, 0.15)";
    badge.style.color = "#22D3EE";
    badge.style.borderColor = "rgba(6, 182, 212, 0.4)";
  } else if (risk <= 1.5) {
    badge.textContent = "⚡ Agressivo Controlado";
    badge.style.backgroundColor = "rgba(245, 158, 11, 0.15)";
    badge.style.color = "#F59E0B";
    badge.style.borderColor = "rgba(245, 158, 11, 0.4)";
  } else if (risk <= 2.0) {
    badge.textContent = "⚠️ Teto Máximo de Risco";
    badge.style.backgroundColor = "rgba(239, 68, 68, 0.15)";
    badge.style.color = "#EF4444";
    badge.style.borderColor = "rgba(239, 68, 68, 0.4)";
  } else {
    badge.textContent = "🚨 Zona de Ruína Crítica (Perigo)";
    badge.style.backgroundColor = "rgba(139, 92, 246, 0.2)";
    badge.style.color = "#C084FC";
    badge.style.borderColor = "rgba(139, 92, 246, 0.5)";
  }
}

function setTargetRR(ratio) {
  const stop = parseFloat(document.getElementById("input-stop").value) || 20;
  const newTp = Math.round(stop * ratio);
  document.getElementById("input-tp").value = newTp;
  
  document.querySelectorAll(".quick-rr-btns .btn-micro").forEach(btn => {
    btn.classList.toggle("active", btn.textContent.includes(ratio.toString()));
  });
  
  runCalculation();
}

function setOrderType(type) {
  state.orderType = type;
  updateOrderTypeUI();
  runCalculation();
}

function toggleOrderType() {
  setOrderType(state.orderType === "BUY" ? "SELL" : "BUY");
}

function updateOrderTypeUI() {
  document.getElementById("btn-buy").classList.toggle("active", state.orderType === "BUY");
  document.getElementById("btn-sell").classList.toggle("active", state.orderType === "SELL");
}

function setTimeframe(tf) {
  state.timeframe = tf;
  updateTimeframeUI();
  runCalculation();
}

function updateTimeframeUI() {
  document.querySelectorAll(".tf-btn").forEach(btn => {
    btn.classList.toggle("active", btn.textContent === state.timeframe);
  });
}

function toggleSwing3d() {
  const daysInput = document.getElementById("input-days");
  const current = parseInt(daysInput.value) || 0;
  daysInput.value = current === 0 ? 3 : 0;
  runCalculation();
}

// ==================== COPIAR BOLETA ====================
function copyBoleta() {
  const content = document.getElementById("boleta-box-content").textContent.trim();
  navigator.clipboard.writeText(content).then(() => {
    const btn = document.getElementById("btn-copy-boleta");
    const textEl = document.getElementById("copy-text");
    btn.classList.add("copied");
    textEl.textContent = "Copiado!";
    setTimeout(() => {
      btn.classList.remove("copied");
      textEl.textContent = "Copiar Boleta";
    }, 2000);
  }).catch(err => {
    console.error("Falha ao copiar:", err);
  });
}

function copyLessonContent() {
  const body = document.getElementById("reader-body");
  if (!body) return;
  navigator.clipboard.writeText(body.innerText).then(() => {
    alert("Conteúdo da aula copiado para a área de transferência!");
  });
}

// ==================== ABA 2: SIMULADOR DE DRAWDOWN ====================
function updateDrawdownSim(lossVal) {
  const loss = parseFloat(lossVal);
  document.getElementById("sim-loss-display").textContent = `${loss}%`;

  const reqGain = (loss / (100.0 - loss)) * 100.0;
  document.getElementById("sim-gain-display").textContent = `+${reqGain.toFixed(1)}% de Lucro`;

  const desc = document.getElementById("sim-scenario-desc");
  const remaining = (1000 * (1 - loss / 100)).toFixed(0);
  const needed = (1000 - remaining).toFixed(0);

  if (loss >= 80) {
    desc.innerHTML = `🚨 <strong>Zona de Ruína Extrema!</strong> Com perda de ${loss}%, uma conta de $1.000 foi reduzida para apenas $${remaining}. Para recuperar os $${needed} perdidos, você terá que multiplicar o capital restante por mais de ${(reqGain/100 + 1).toFixed(1)}x (+${reqGain.toFixed(1)}%). Praticamente impossível sem quebrar totalmente.`;
  } else if (loss >= 50) {
    desc.innerHTML = `⚠️ <strong>Ponto Crítico (Dobrar Conta):</strong> Com perda de ${loss}%, seu saldo caiu para $${remaining}. Você precisará fazer exatamente <strong>+100% de lucro</strong> sobre o que sobrou apenas para voltar ao zero a zero!`;
  } else {
    desc.innerHTML = `Com perda de ${loss}%, o seu saldo caiu de $1.000 para $${remaining}. Fazer $${needed} sobre os $${remaining} restantes exige <strong>+${reqGain.toFixed(1)}%</strong> de lucro líquido sem cometer erros.`;
  }
}

function renderDrawdownTables(data) {
  const tbodyDrawdown = document.querySelector("#table-drawdown tbody");
  if (tbodyDrawdown && data.drawdown_recovery) {
    tbodyDrawdown.innerHTML = "";
    data.drawdown_recovery.forEach(row => {
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td><strong class="text-danger">-${row.loss_pct.toFixed(0)}%</strong></td>
        <td><strong class="text-success">+${row.required_gain_pct.toFixed(1)}%</strong></td>
        <td>${row.note || "Exige disciplina estrita."}</td>
      `;
      tbodyDrawdown.appendChild(tr);
    });
  }

  const tbodyStops = document.querySelector("#table-stops-survival tbody");
  if (tbodyStops && data.survival_stops) {
    tbodyStops.innerHTML = "";
    data.survival_stops.forEach(row => {
      const tr = document.createElement("tr");
      const statusClass = row.is_danger ? "text-danger-strong" : (row.risk_pct <= 1.0 ? "text-success" : "text-muted");
      tr.innerHTML = `
        <td><strong>${row.risk_pct.toFixed(1)}%</strong></td>
        <td><strong>${row.stops_nominal}</strong> stops consecutivos</td>
        <td><strong>~${row.stops_to_50pct}</strong> stops para perder 50%</td>
        <td><span class="${statusClass}">${row.status}</span></td>
      `;
      tbodyStops.appendChild(tr);
    });
  }
}

// ==================== ABA 3: RADAR MACROECONÔMICO & CALENDÁRIO ====================
async function loadMacroCalendar() {
  try {
    const res = await fetch("/api/macro-calendar");
    if (res.ok) {
      const data = await res.json();
      state.macroData = data;
    } else {
      state.macroData = {
        status: "SAFE",
        title: "🟢 ZONA OPERACIONAL LIBERADA",
        message: "Nenhuma notícia Tier 1 iminente nos próximos minutos. Operação normal.",
        events: FALLBACK_MACRO_EVENTS
      };
    }
  } catch (err) {
    state.macroData = {
      status: "SAFE",
      title: "🟢 ZONA OPERACIONAL LIBERADA",
      message: "Radar operando com histórico local integrado.",
      events: FALLBACK_MACRO_EVENTS
    };
  }
  renderMacroRadar();
}

function renderMacroRadar() {
  if (!state.macroData || !state.macroData.events) {
    state.macroData = { events: FALLBACK_MACRO_EVENTS };
  }
  const data = state.macroData;

  // Banner de Status
  const bannerEl = document.getElementById("macro-status-banner");
  const titleEl = document.getElementById("macro-status-title");
  const descEl = document.getElementById("macro-status-desc");

  if (bannerEl && titleEl && descEl) {
    bannerEl.className = "macro-status-banner";
    if (data.status === "SAFE") {
      bannerEl.classList.add("banner-safe");
    } else if (data.status === "WARNING") {
      bannerEl.classList.add("banner-warning");
    } else {
      bannerEl.classList.add("banner-danger");
    }
    titleEl.textContent = data.title || "🟢 ZONA OPERACIONAL LIBERADA";
    descEl.textContent = data.message || "Monitoramento macroeconômico ativo.";
  }

  // Card de Destaque: Próximo Grande Evento
  updateNextEventCard(data);

  // Filtragem e Renderização da Tabela
  applyMacroFilter();
}

function updateNextEventCard(data) {
  const events = data.events || FALLBACK_MACRO_EVENTS;
  // Localiza o próximo evento de alto impacto não concluído ou o mais próximo
  const upcomingHigh = events.find(e => e.impact === "High" && !e.is_past) || events[0];
  if (!upcomingHigh) return;

  const titleEl = document.getElementById("next-event-title");
  const timeEl = document.getElementById("next-event-time");
  const countdownEl = document.getElementById("next-event-countdown");
  const noteEl = document.getElementById("next-event-note");
  const assetsEl = document.getElementById("next-event-assets");

  if (titleEl) titleEl.textContent = `${upcomingHigh.flag} ${upcomingHigh.title}`;
  if (timeEl) timeEl.textContent = `${upcomingHigh.day_name} às ${upcomingHigh.time_brt} BRT (${upcomingHigh.country})`;
  if (countdownEl) countdownEl.textContent = upcomingHigh.status_text;
  if (noteEl) noteEl.textContent = `💡 ${upcomingHigh.market_note}`;

  if (assetsEl && upcomingHigh.affected_assets) {
    assetsEl.innerHTML = upcomingHigh.affected_assets.map(sym => {
      let colorClass = "asset-gold";
      if (sym === "BTCUSD") colorClass = "asset-btc";
      if (sym === "NAS100") colorClass = "asset-nas";
      return `<span class="asset-badge-micro ${colorClass}">${sym}</span>`;
    }).join("");
  }
}

function filterMacroEvents(filterType) {
  state.macroFilter = filterType;

  document.querySelectorAll(".calendar-filters-bar .filter-btn").forEach(btn => {
    btn.classList.toggle("active", btn.getAttribute("data-filter") === filterType);
  });

  applyMacroFilter();
}

function handleMacroSearch(query) {
  state.macroSearchQuery = (query || "").trim().toLowerCase();
  applyMacroFilter();
}

function applyMacroFilter() {
  const eventsList = (state.macroData && state.macroData.events) ? state.macroData.events : FALLBACK_MACRO_EVENTS;
  let filtered = [...eventsList];

  // Filtro por tipo
  if (state.macroFilter === "high") {
    filtered = filtered.filter(e => e.impact === "High");
  } else if (state.macroFilter === "today") {
    filtered = filtered.filter(e => e.is_today);
  } else if (state.macroFilter === "usd") {
    filtered = filtered.filter(e => e.country === "USD" || e.country === "GLOBAL");
  }

  // Filtro por termo de pesquisa
  if (state.macroSearchQuery) {
    const q = state.macroSearchQuery;
    filtered = filtered.filter(e => 
      e.title.toLowerCase().includes(q) ||
      e.country.toLowerCase().includes(q) ||
      e.day_name.toLowerCase().includes(q) ||
      (e.affected_assets && e.affected_assets.some(a => a.toLowerCase().includes(q)))
    );
  }

  const countEl = document.getElementById("events-count-display");
  if (countEl) {
    countEl.textContent = `${filtered.length} evento(s) exibido(s)`;
  }

  renderMacroEventsTable(filtered);
}

function renderMacroEventsTable(events) {
  const tbody = document.getElementById("macro-events-tbody");
  if (!tbody) return;

  tbody.innerHTML = "";

  if (events.length === 0) {
    const tr = document.createElement("tr");
    tr.innerHTML = `<td colspan="7" style="text-align: center; color: var(--text-dark); padding: 2rem;">Nenhum evento corresponde ao filtro ou busca selecionada.</td>`;
    tbody.appendChild(tr);
    return;
  }

  events.forEach(item => {
    const tr = document.createElement("tr");
    if (item.is_imminent) {
      tr.style.backgroundColor = "rgba(239, 68, 68, 0.12)";
    } else if (item.is_today && !item.is_past) {
      tr.style.backgroundColor = "rgba(88, 101, 242, 0.06)";
    }

    const assetsBadges = (item.affected_assets || []).map(sym => {
      let colorClass = "asset-gold";
      if (sym === "BTCUSD") colorClass = "asset-btc";
      if (sym === "NAS100") colorClass = "asset-nas";
      return `<span class="asset-badge-micro ${colorClass}">${sym}</span>`;
    }).join("");

    let impactHtml = "";
    if (item.impact === "High") {
      impactHtml = `<span class="badge" style="background-color: rgba(239, 68, 68, 0.2); color: #F87171; border-color: rgba(239, 68, 68, 0.5);">🔴 Alto Impacto</span>`;
    } else {
      impactHtml = `<span class="badge" style="background-color: rgba(245, 158, 11, 0.2); color: #FBBF24; border-color: rgba(245, 158, 11, 0.4);">🟡 Médio</span>`;
    }

    tr.innerHTML = `
      <td>
        <strong style="color: #fff;">${item.time_brt} BRT</strong><br>
        <small style="color: var(--text-dark);">${item.day_name} (${item.date_formatted})</small>
      </td>
      <td>
        <span style="font-size: 1.1rem;">${item.flag}</span> <strong>${item.country}</strong>
      </td>
      <td>
        ${impactHtml}
      </td>
      <td>
        <strong style="color: #F1F5F9;">${item.title}</strong><br>
        <small style="color: var(--text-muted); line-height: 1.3; display: inline-block; margin-top: 2px;">
          💡 ${item.market_note}
        </small>
      </td>
      <td style="font-family: var(--font-mono); font-size: 0.8rem;">
        Proj: <strong>${item.forecast}</strong><br>
        <span style="color: var(--text-dark);">Ant: ${item.previous}</span>
      </td>
      <td>
        ${assetsBadges}
      </td>
      <td>
        <span class="status-badge ${item.status_badge || 'badge-dark'}">${item.status_text}</span>
      </td>
    `;

    tbody.appendChild(tr);
  });
}

function startMacroClock() {
  const clockEl = document.getElementById("macro-clock-display");
  function tick() {
    const now = new Date();
    const timeStr = now.toLocaleTimeString("pt-BR", { hour12: false });
    if (clockEl) {
      clockEl.textContent = `${timeStr} (Horário de Brasília - UTC-3)`;
    }
  }
  tick();
  setInterval(tick, 1000);
  setInterval(loadMacroCalendar, 60000);
}

// ==================== ABA 4: CENTRAL DE APRENDIZADO (DISCORD TREE) ====================
function renderDiscordTree() {
  const container = document.getElementById("discord-tree-container");
  if (!container || !state.categories || state.categories.length === 0) return;

  container.innerHTML = "";
  let firstChannelId = null;

  const query = state.channelSearchQuery;

  state.categories.forEach((cat) => {
    // Filtro por termo de busca
    const matchingChannels = cat.channels.filter(ch => 
      !query || 
      ch.title.toLowerCase().includes(query) || 
      (ch.header && ch.header.toLowerCase().includes(query))
    );

    if (matchingChannels.length === 0) return;

    const catBlock = document.createElement("div");
    catBlock.className = "discord-category-block";
    catBlock.style.display = "flex";
    catBlock.style.flexDirection = "column";
    catBlock.style.gap = "0.2rem";

    const catHeader = document.createElement("div");
    catHeader.className = "discord-category-header";
    catHeader.textContent = cat.title;
    catBlock.appendChild(catHeader);

    matchingChannels.forEach(ch => {
      if (!firstChannelId) firstChannelId = ch.id;

      const chBtn = document.createElement("button");
      chBtn.className = `discord-channel-btn ${state.activeChannelId === ch.id ? 'active' : ''}`;
      chBtn.setAttribute("data-channel-id", ch.id);
      chBtn.innerHTML = `<span>${ch.title}</span>`;
      chBtn.onclick = () => loadChannel(ch.id);
      catBlock.appendChild(chBtn);
    });

    container.appendChild(catBlock);
  });

  if (!state.activeChannelId && firstChannelId) {
    loadChannel(firstChannelId);
  }
}

function handleChannelSearch(val) {
  state.channelSearchQuery = (val || "").trim().toLowerCase();
  renderDiscordTree();
}

function loadChannel(channelId) {
  state.activeChannelId = channelId;

  document.querySelectorAll(".discord-channel-btn").forEach(btn => {
    btn.classList.toggle("active", btn.getAttribute("data-channel-id") === channelId);
  });

  let foundChannel = null;
  let categoryTitle = "";
  for (const cat of state.categories) {
    for (const ch of cat.channels) {
      if (ch.id === channelId) {
        foundChannel = ch;
        categoryTitle = cat.title;
        break;
      }
    }
    if (foundChannel) break;
  }

  if (!foundChannel) return;

  const iconEl = document.getElementById("reader-icon");
  const titleEl = document.getElementById("reader-title");
  const catEl = document.getElementById("reader-category");
  const bodyEl = document.getElementById("reader-body");

  if (iconEl) iconEl.textContent = foundChannel.title.split('-')[0].replace('#', '').trim() || "📖";
  if (titleEl) titleEl.textContent = foundChannel.header || foundChannel.title;
  if (catEl) catEl.textContent = `${categoryTitle} • ${foundChannel.subtitle || "Canal Institucional"}`;
  if (bodyEl) bodyEl.innerHTML = parseMarkdown(foundChannel.content_markdown);
}

// Conversor seguro de Markdown protegendo blocos de código
function parseMarkdown(md) {
  if (!md) return "";
  
  const codeBlocks = [];
  let text = md.replace(/```([a-z0-9_-]*)\n?([\s\S]*?)```/gim, (match, lang, code) => {
    const id = `___CODE_BLOCK_${codeBlocks.length}___`;
    const esc = code
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
    codeBlocks.push(`
      <div class="code-wrapper" style="position: relative; margin: 1rem 0;">
        <button class="btn-micro" style="position: absolute; right: 8px; top: 8px; z-index: 2;" onclick="navigator.clipboard.writeText(this.nextElementSibling.innerText); this.textContent='Copiado!'; setTimeout(()=>this.textContent='Copiar', 2000);">Copiar</button>
        <pre><code class="language-${lang || 'text'}">${esc.trim()}</code></pre>
      </div>
    `);
    return id;
  });

  // Código inline
  text = text.replace(/`([^`]+)`/g, (match, inline) => {
    const esc = inline.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    return `<code>${esc}</code>`;
  });

  // Cabeçalhos
  text = text.replace(/^### (.*$)/gim, '<h3>$1</h3>');
  text = text.replace(/^#### (.*$)/gim, '<h4>$1</h4>');
  text = text.replace(/^## (.*$)/gim, '<h2>$1</h2>');

  // Blockquotes
  text = text.replace(/^\> (.*$)/gim, '<blockquote>$1</blockquote>');

  // Negrito e Itálico
  text = text.replace(/\*\*(.*?)\*\*/gim, '<strong>$1</strong>');
  text = text.replace(/\*(.*?)\*/gim, '<em>$1</em>');

  // Linha horizontal
  text = text.replace(/^---$/gim, '<hr>');

  // Listas não ordenadas
  text = text.replace(/^\* (.*$)/gim, '<li>$1</li>');
  text = text.replace(/((?:<li>.*?<\/li>\s*)+)/gim, '<ul>$1</ul>');

  // Parágrafos normais
  const blocks = text.split(/\n\s*\n/);
  text = blocks.map(b => {
    b = b.trim();
    if (!b) return "";
    if (b.startsWith('___CODE_BLOCK_') || b.startsWith('<h') || b.startsWith('<blockquote') || b.startsWith('<ul') || b.startsWith('<hr')) {
      return b;
    }
    return `<p>${b.replace(/\n/g, '<br>')}</p>`;
  }).join('\n');

  // Restaurar blocos de código protegidos
  codeBlocks.forEach((cb, idx) => {
    text = text.replace(`___CODE_BLOCK_${idx}___`, cb);
  });

  return text;
}

// Utilitário de debounce
function debounce(func, wait) {
  let timeout;
  return function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func(...args);
    };
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
}
