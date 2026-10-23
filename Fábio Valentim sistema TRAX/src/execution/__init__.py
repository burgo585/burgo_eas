"""
Pacote de Execução, Máquina de Estados, Roteamento e Kill-Switch do TRAX.
"""

from src.execution.signals import MotorSinaisQuantitativo, SinalTrade
from src.execution.kill_switch import KillSwitchMOC
from src.execution.order_router import OrderRouter

__all__ = ["MotorSinaisQuantitativo", "SinalTrade", "KillSwitchMOC", "OrderRouter"]
