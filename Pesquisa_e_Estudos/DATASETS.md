# Catálogo de Datasets e Históricos Forenses - burgo_eas

Este documento cataloga os datasets de alta fidelidade microestrutural arquivados para backtests e simulações.

---

## 1. Ticks Reais de Ouro (XAUUSD / GOLD) - XM Global

| Propriedade | Detalhe |
| :--- | :--- |
| **Ativo** | `XAUUSD` / `GOLD` |
| **Corretora** | `XM Global` |
| **Período Coberto** | **20/12/2023 12:06:50** até **26/10/2026 03:30:05** (~3 Anos Reais) |
| **Tamanho** | **8,39 GB (9.009.655.893 bytes)** |
| **Formato** | CSV Tabulado (`\t`) com microsegundos |
| **Campos** | `<DATE>`, `<TIME>`, `<BID>`, `<ASK>`, `<LAST>`, `<VOLUME>`, `<FLAGS>` |
| **Localização de Origem** | `C:\Users\Vini_Burgo\OneDrive\Documents\Robo\Marcus\GOLD_202312201206_202610260330ticksXM.csv` |
| **Script Leitor** | `C:\Users\Vini_Burgo\.gemini\config\skills\quant-forensic-auditor\scripts\xm_gold_ticks_reader.py` |

> [!NOTE]
> Devido ao limite de 100 MB por arquivo do GitHub, o arquivo binário/CSV de 8,39 GB é mantido em armazenamento local seguro do usuário (OneDrive / disco local) e referenciado via streaming nos scripts de auditoria quantitativa.
