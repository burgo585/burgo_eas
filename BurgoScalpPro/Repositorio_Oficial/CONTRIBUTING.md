# 🤝 Guia de Contribuição e Desenvolvimento - Burgo Scalpe Pro

Agradecemos o interesse em contribuir para a evolução do **Burgo Scalpe Pro**! Este guia define os padrões de código, controle de versão e fluxo de teste exigidos para manter a integridade e qualidade do software.

---

## 📋 Diretrizes de Código (MQL5)

1. **Inclusão de Parâmetros (`input`)**:
   - Todo novo parâmetro deve pertencer a um `input group` claramente definido.
   - Use nomes descritivos iniciando com o prefixo `Inp` (ex: `InpMyNewParameter`).
   - Forneça comentários ao lado do tipo/nome para que o texto apareça de forma amigável na janela de propriedades do MetaTrader 5.

2. **Gerenciamento de Manipuladores (`Handles`)**:
   - Inicialize manipuladores de indicadores (`iATR`, `iADX`, `iMA`, `iCHOP`, `iRSI`) na função `OnInit()`.
   - Lembre-se **obrigatoriamente** de liberar os handles na função `OnDeinit(const int reason)` utilizando `IndicatorRelease(handle)`.

3. **Cálculo de Pontos (Digits & Pips)**:
   - Sempre utilize a variável global `PM` (`Point Multiplier`) calculada no `OnInit()` para adequação automática a corretoras de 3/5 dígitos.

4. **Tratamento de Erros e Logs**:
   - Valide os retornos de funções de negociação (`trade.Buy()`, `trade.Sell()`, `trade.PositionClose()`).
   - Em caso de falha de envio de ordem, utilize `PrintFormat` registrando o código de erro retornado por `GetLastError()`.

---

## 🧪 Fluxo de Validação e Testes

Antes de submeter alterações ou criar novas versões:

1. **Compilação sem Avisos**:
   - O código deve compilar no **MetaEditor (F7)** com **0 erros e 0 avisos (warnings)**.

2. **Testes no Strategy Tester (MT5)**:
   - Execute o Strategy Tester nos seguintes cenários mínimos:
     - **Ativo**: `XAUUSD` / `EURUSD` / `GBPUSD`.
     - **Período de Teste**: Mínimo de 6 meses de dados de ticks reais (*Every tick based on real ticks*).
     - **Condições de Estresse**: Teste durante eventos de alta volatilidade e notícias para garantir o disparo do `Hard Equity Stop`.

3. **Verificação da Interface Gráfica**:
   - Teste a criação, atualização e exclusão dos objetos gráficos (`PREFIX="BSP_"`) garantindo que a remoção do EA do gráfico limpe perfeitamente todos os elementos (`OnDeinit`).

---

## 🔀 Fluxo de Trabalho do Git (Git Workflow)

- **Código Fonte Principal**: As versões finais estáveis devem ser armazenadas exclusivamente na pasta `src/`.
- **Convenção de Nomenclatura de Versões**:
  - `src/Burgo Scalpe Pro V43 XAUUSD M1.mq5` (Versão principal ativa).
- **Mensagens de Commit**:
  Utilize o padrão *Conventional Commits*:
  - `feat: Adicionado filtro X`
  - `fix: Correção no cálculo do Trailing Stop`
  - `docs: Atualização da documentação de parâmetros`
  - `refactor: Otimização do gerenciador de painel`
