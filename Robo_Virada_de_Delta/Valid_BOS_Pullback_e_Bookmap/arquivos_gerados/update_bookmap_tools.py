# -*- coding: utf-8 -*-
import os
import shutil
import subprocess

MT5_DATA_DIR = r"C:\Users\Vini_Burgo\AppData\Roaming\MetaQuotes\Terminal\9AF8328437A6A393B2016FC9156E6753\MQL5"
METAEDITOR = r"C:\Program Files\MetaTrader 5\metaeditor64.exe"

def update_files():
    ea_file = r"c:\Robo Virada de Delta\Valid_BOS_Pullback\Valid_BOS_Bookmap_EA.mq5"
    ind_file = r"c:\Robo Virada de Delta\Valid_BOS_Pullback\Valid_BOS_Bookmap_Ind.mq5"

    with open(ea_file, "r", encoding="utf-8") as f:
        ea_code = f.read()

    with open(ind_file, "r", encoding="utf-8") as f:
        ind_code = f.read()

    # 1. Atualizar EA
    # Adiciona variáveis globais de estado
    if "bool g_botActive = true;" not in ea_code:
        idx = ea_code.find("SBookmapData g_bmData;")
        if idx != -1:
            var_decl = "\nbool g_botActive = true;       // Estado de ativacao do robo via botao do painel\nbool g_bookmapActive = true;   // Estado de ativacao das marcacoes Bookmap via botao\n"
            ea_code = ea_code[:idx] + var_decl + ea_code[idx:]

    # Bloqueio de ordens se bot pausado
    if "if(!g_botActive) return;" not in ea_code:
        idx = ea_code.find("void ExecuteRealOrder(")
        if idx != -1:
            body_start = ea_code.find("{", idx)
            if body_start != -1:
                block_code = "\n   if(!g_botActive)\n   {\n      Print(\"[VALID BOS EA] Ordem bloqueada: Robo PAUSADO pelo usuario no botao do painel.\");\n      return;\n   }\n"
                ea_code = ea_code[:body_start+1] + block_code + ea_code[body_start+1:]

    # 2. Atualizar Indicador
    if "bool g_signalsActive = true;" not in ind_code:
        idx = ind_code.find("SBookmapData g_bmData;")
        if idx != -1:
            var_decl = "\nbool g_signalsActive = true;   // Estado de ativacao dos sinais via botao do painel\nbool g_bookmapActive = true;   // Estado de ativacao das marcacoes Bookmap via botao\n"
            ind_code = ind_code[:idx] + var_decl + ind_code[idx:]

    print("Variaveis de controle adicionadas.")

if __name__ == "__main__":
    update_files()
