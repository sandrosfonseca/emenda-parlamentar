from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, ForeignKey, Text, Boolean, Enum as SQLEnum
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship
from datetime import datetime
import re
from app.core.config import settings
from app.core.enums import Role, StatusEmenda

Base = declarative_base()

engine = create_engine(settings.DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# Funções de validação de formato
def validate_cnpj(cnpj: str) -> bool:
    """Valida formato do CNPJ: 00.000.000/0000-00"""
    pattern = r"^\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}$"
    return bool(re.match(pattern, cnpj))


def validate_cep(cep: str) -> bool:
    """Valida formato do CEP: 00000-000"""
    pattern = r"^\d{5}-\d{3}$"
    return bool(re.match(pattern, cep))


def validate_whatsapp(phone: str) -> bool:
    """Valida formato do WhatsApp: (00)00000-0000"""
    pattern = r"^\(\d{2}\)\d{5}-\d{4}$"
    return bool(re.match(pattern, phone))


def validate_uf(uf: str) -> bool:
    """Valida UF: 2 letras maiúsculas"""
    return bool(re.match(r"^[A-Z]{2}$", uf))


class Usuario(Base):
    __tablename__ = "usuarios"
    
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    senha_hash = Column(String, nullable=False)
    nome = Column(String, nullable=False)
    role = Column(SQLEnum(Role), nullable=False, default=Role.LEITOR)
    entidade_id = Column(Integer, ForeignKey("entidades.id"), nullable=True)
    ativo = Column(Boolean, default=True)
    criado_em = Column(DateTime, default=datetime.utcnow)
    
    entidade = relationship("Entidade", back_populates="usuarios")


class Entidade(Base):
    __tablename__ = "entidades"
    
    id = Column(Integer, primary_key=True, index=True)
    cnpj = Column(String, unique=True, index=True, nullable=False)
    razao_social = Column(String, nullable=False)
    logradouro = Column(String, nullable=False)
    numero = Column(String, nullable=False)
    complemento = Column(String, nullable=True)
    bairro = Column(String, nullable=False)
    cidade = Column(String, default="Santos", nullable=False)
    uf = Column(String, default="SP", nullable=False)
    cep = Column(String, nullable=False)
    email = Column(String, nullable=False)
    presidente = Column(String, nullable=False)
    whatsapp = Column(String, nullable=False)
    whatsapp_opt_in = Column(Boolean, default=False)
    criado_em = Column(DateTime, default=datetime.utcnow)
    atualizado_em = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    usuarios = relationship("Usuario", back_populates="entidade")
    emendas = relationship("Emenda", back_populates="entidade_beneficiaria")
    
    @classmethod
    def validate(cls, cnpj: str, cep: str, uf: str, whatsapp: str, logradouro: str, 
                 numero: str, bairro: str) -> dict:
        """Valida todos os campos da entidade"""
        errors = []
        
        if not validate_cnpj(cnpj):
            errors.append("CNPJ inválido. Formato esperado: 00.000.000/0000-00")
        
        if not validate_cep(cep):
            errors.append("CEP inválido. Formato esperado: 00000-000")
        
        if not validate_uf(uf):
            errors.append("UF inválida. Deve ter 2 letras maiúsculas")
        
        if not validate_whatsapp(whatsapp):
            errors.append("WhatsApp inválido. Formato esperado: (00)00000-0000")
        
        if not all([logradouro, numero, bairro]):
            errors.append("Endereço completo é obrigatório (logradouro, número, bairro)")
        
        return {"valid": len(errors) == 0, "errors": errors}


class Emenda(Base):
    __tablename__ = "emendas"
    
    id = Column(Integer, primary_key=True, index=True)
    numero_emenda = Column(String, unique=True, index=True, nullable=False)
    processo_mae = Column(String, nullable=False)
    valor_total = Column(Float, nullable=False)
    vereador_responsavel = Column(String, nullable=False)
    orgao_destinatario = Column(String, nullable=False)
    entidade_beneficiaria_id = Column(Integer, ForeignKey("entidades.id"), nullable=False)
    justificativa = Column(Text, nullable=False)
    status = Column(SQLEnum(StatusEmenda), default=StatusEmenda.RASCUNHO)
    data_aprovacao = Column(DateTime, nullable=True)
    data_empenho = Column(DateTime, nullable=True)
    data_pagamento = Column(DateTime, nullable=True)
    data_prestacao_contas = Column(DateTime, nullable=True)
    hash_integridade = Column(String, nullable=True)
    criado_em = Column(DateTime, default=datetime.utcnow)
    atualizado_em = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    entidade_beneficiaria = relationship("Entidade", back_populates="emendas")
    
    @property
    def prazo_empenho(self) -> datetime:
        """Calcula prazo de empenho: 90 dias após aprovação"""
        if self.data_aprovacao:
            from datetime import timedelta
            return self.data_aprovacao + timedelta(days=90)
        return None
    
    @property
    def prazo_execucao(self) -> datetime:
        """Prazo de execução: até 31 de dezembro do ano do exercício"""
        if self.criado_em:
            return datetime(self.criado_em.year, 12, 31)
        return None
    
    @property
    def prazo_prestacao_contas(self) -> datetime:
        """Prazo de prestação de contas: 60 dias após pagamento"""
        if self.data_pagamento:
            from datetime import timedelta
            return self.data_pagamento + timedelta(days=60)
        return None
    
    @property
    def limite_remanescente(self) -> float:
        """Limite de remanescente: 25% do valor total"""
        return self.valor_total * 0.25
    
    @classmethod
    def can_transition(cls, current_status: StatusEmenda, new_status: StatusEmenda) -> bool:
        """Verifica se a transição de status é válida"""
        from app.core.enums import VALID_TRANSITIONS
        allowed = VALID_TRANSITIONS.get(current_status, [])
        return new_status in allowed
