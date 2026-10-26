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

---

## 2. Ticks Reais de Bitcoin (BTCUSD) - XM Global

| Propriedade | Detalhe |
| :--- | :--- |
| **Ativo** | `BTCUSD` / `Bitcoin` |
| **Corretora** | `XM Global` |
| **Período Coberto** | **04/08/2023 00:01:00** até **26/10/2026 04:28:51** (~3 Anos Reais) |
| **Tamanho** | **4,51 GB (4.844.142.297 bytes)** |
| **Formato** | CSV Tabulado (`\t`) com microsegundos |
| **Campos** | `<DATE>`, `<TIME>`, `<BID>`, `<ASK>`, `<LAST>`, `<VOLUME>`, `<FLAGS>` |
| **Localização de Origem** | `C:\Users\Vini_Burgo\OneDrive\Documents\Robo\Marcus\BTCUSD_202308040001_202610260428ticksXM.csv` |

> [!NOTE]
> Devido ao limite de 100 MB por arquivo do GitHub, os arquivos binários/CSVs de 8,39 GB e 4,51 GB são mantidos em armazenamento local seguro do usuário (OneDrive / disco local) e referenciados via streaming nos scripts de auditoria quantitativa (`xm_ticks_reader.py`).
