# 🎛️ Arquivos de Configuração (.set / Presets)

Esta pasta é destinada ao armazenamento de arquivos de parâmetros pré-configurados (`.set`) para o **Burgo Scalpe Pro**.

---

## 📖 Como utilizar arquivos `.set` no MetaTrader 5

1. **Abrir a janela de parâmetros do EA**:
   - No MetaTrader 5, abra o gráfico desejado (ex: **XAUUSD M1**).
   - Arraste o EA `Burgo Scalpe Pro V43 XAUUSD M1.mq5` (ou pressione `F7` no gráfico com o EA ativo).

2. **Carregar a Configuração**:
   - Na aba **Propriedades (Inputs)**, clique no botão **Carregar (Load)** no canto inferior direito.
   - Navegue até a pasta `presets/` deste repositório e selecione o arquivo `.set` desejado.
   - Clique em **OK**.

3. **Salvar suas próprias personalizações**:
   - Após ajustar os parâmetros de acordo com o tamanho de sua banca e apetite a risco, clique no botão **Salvar (Save)**.
   - Salve o arquivo `.set` nesta pasta `presets/` com uma nomenclatura clara (exemplo: `XAUUSD_M1_Banca1k_Conservador.set`).

---

## 📌 Convenção de Nomenclatura Sugerida para Presets

```
[ATIVO]_[TIMEFRAME]_[VERSÃO]_[PERFIL].set
```

**Exemplos**:
- `XAUUSD_M1_V43_ScalperFast.set`
- `EURUSD_M5_V42_Conservador.set`
- `GBPUSD_M15_V43_Moderado.set`
