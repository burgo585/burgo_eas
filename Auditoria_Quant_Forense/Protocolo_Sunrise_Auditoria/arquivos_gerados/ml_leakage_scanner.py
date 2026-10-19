import sys
import re
import ast

PATTERNS = [
    (r"train_test_split\s*\([^)]*(?!shuffle\s*=\s*False)[^)]*\)", 
     "CRITICAL [ML-LEAK-01]: train_test_split chamado sem 'shuffle=False' explícito em série temporal."),
    (r"\.(fit|fit_transform)\s*\(\s*(df|X|data)\b", 
     "WARNING [ML-LEAK-02]: Possível chamada de .fit() ou .fit_transform() na matriz completa (X/df) antes da separação temporal."),
    (r"\.shift\s*\(\s*-\d+\s*\)", 
     "CRITICAL [LOOKAHEAD-01]: Uso de .shift(-k) negativo detectado. Verifique se não está vazando dados futuros em features."),
    (r"\.ewm\s*\([^)]*\)\.mean\s*\(\s*\)(?!\s*\.shift\s*\(\s*1\s*\))", 
     "CRITICAL [LOOKAHEAD-02]: Média Exponencial (.ewm().mean()) calculada sem .shift(1). Se lida na abertura da barra, vaza o Close futuro da barra!"),
    (r"\.rolling\s*\([^)]*\)\.(mean|std|max|min)\s*\(\s*\)(?!\s*\.shift\s*\(\s*1\s*\))", 
     "CRITICAL [LOOKAHEAD-03]: Indicador rolling() calculado sem .shift(1). Se lido intrabarra, vaza High/Low/Close futuros da própria barra!"),
    (r"balance\s*\+=\s*(buy_profit|sell_profit|total_floating)", 
     "CRITICAL [MICRO-BUG-01]: Teletransporte de Take Profit para o Pavio! 'balance += floating_profit' credita o lucro na máxima/mínima da vela em vez de travar no TargetUSD exato."),
    (r"for\s+\w+\s+in\s+\(\[o,\s*l,\s*h,\s*c\]\s+if\s+c\s*>=\s*o", 
     "CRITICAL [MICRO-BUG-02]: Loop intrabarra ingênuo [o, l, h, c] detectado. Compra no fundo exato do pavio Low e vende no topo High na mesma vela!")
]

def scan_file(filepath):
    print(f"=== SCANNER FORENSE DE DATA LEAKAGE & MICROESTRUTURA: {filepath} ===")
    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()

    findings = 0
    for idx, line in enumerate(lines, start=1):
        for pat, msg in PATTERNS:
            if re.search(pat, line):
                findings += 1
                print(f"  [Linha {idx:4d}] {msg}")
                print(f"               Código: {line.strip()}")

    if findings == 0:
        print("  [OK] Nenhuma assinatura óbvia de vazamento ou teletransporte intrabarra detectada pelo scanner estático.")
    else:
        print(f"\n  [FALHA FORENSE] Total de violações críticas encontradas: {findings}")
    return findings

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Uso: python ml_leakage_scanner.py <caminho_do_script.py>")
        sys.exit(1)
    for arg in sys.argv[1:]:
        scan_file(arg)
