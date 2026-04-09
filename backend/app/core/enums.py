from enum import Enum


class Role(str, Enum):
    SUPER_ADMIN = "super_admin"
    GESTOR_MUNICIPAL = "gestor_municipal"
    GESTOR_ENTIDADE = "gestor_entidade"
    CONSULTOR = "consultor"
    LEITOR = "leitor"


class StatusEmenda(str, Enum):
    RASCUNHO = "rascunho"
    ENVIADO = "enviado"
    EM_ANALISE = "em_analise"
    PENDENTE_DOCUMENTACAO = "pendente_documentacao"
    APROVADO_TECNICO = "aprovado_tecnico"
    EM_EMPENHO = "em_empenho"
    EMPENHADO = "empenhado"
    EM_LIQUIDACAO = "em_liquidacao"
    LIQUIDADO = "liquidado"
    PAGO = "pago"
    PRESTACAO_CONTAS = "prestacao_contas"
    FINALIZADO = "finalizado"
    INDEFERIDO = "indeferido"
    CANCELADO = "cancelado"


# Matriz de transições válidas de status
VALID_TRANSITIONS = {
    StatusEmenda.RASCUNHO: [StatusEmenda.ENVIADO, StatusEmenda.CANCELADO],
    StatusEmenda.ENVIADO: [StatusEmenda.EM_ANALISE, StatusEmenda.INDEFERIDO, StatusEmenda.CANCELADO],
    StatusEmenda.EM_ANALISE: [StatusEmenda.PENDENTE_DOCUMENTACAO, StatusEmenda.APROVADO_TECNICO, StatusEmenda.INDEFERIDO],
    StatusEmenda.PENDENTE_DOCUMENTACAO: [StatusEmenda.EM_ANALISE, StatusEmenda.INDEFERIDO],
    StatusEmenda.APROVADO_TECNICO: [StatusEmenda.EM_EMPENHO, StatusEmenda.CANCELADO],
    StatusEmenda.EM_EMPENHO: [StatusEmenda.EMPENHADO, StatusEmenda.CANCELADO],
    StatusEmenda.EMPENHADO: [StatusEmenda.EM_LIQUIDACAO, StatusEmenda.CANCELADO],
    StatusEmenda.EM_LIQUIDACAO: [StatusEmenda.LIQUIDADO, StatusEmenda.CANCELADO],
    StatusEmenda.LIQUIDADO: [StatusEmenda.PAGO, StatusEmenda.CANCELADO],
    StatusEmenda.PAGO: [StatusEmenda.PRESTACAO_CONTAS],
    StatusEmenda.PRESTACAO_CONTAS: [StatusEmenda.FINALIZADO],
    StatusEmenda.FINALIZADO: [],  # Estado terminal
    StatusEmenda.INDEFERIDO: [],  # Estado terminal
    StatusEmenda.CANCELADO: [],   # Estado terminal
}
