from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel, EmailStr, field_validator
import re

from app.models.database import get_db, Entidade, Emenda, Usuario
from app.core.security import get_password_hash, create_access_token
from app.core.enums import Role, StatusEmenda
from app.services.viacep import validate_cep_via_api
from app.services.notifications import generate_integrity_hash

router = APIRouter()


# Schemas Pydantic
class EntidadeCreate(BaseModel):
    cnpj: str
    razao_social: str
    logradouro: str
    numero: str
    complemento: Optional[str] = None
    bairro: str
    cidade: str = "Santos"
    uf: str = "SP"
    cep: str
    email: str
    presidente: str
    whatsapp: str
    whatsapp_opt_in: bool = False
    
    @field_validator("cnpj")
    def validate_cnpj_format(cls, v):
        pattern = r"^\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}$"
        if not re.match(pattern, v):
            raise ValueError("CNPJ inválido. Formato esperado: 00.000.000/0000-00")
        return v
    
    @field_validator("cep")
    def validate_cep_format(cls, v):
        pattern = r"^\d{5}-\d{3}$"
        if not re.match(pattern, v):
            raise ValueError("CEP inválido. Formato esperado: 00000-000")
        return v
    
    @field_validator("whatsapp")
    def validate_whatsapp_format(cls, v):
        pattern = r"^\(\d{2}\)\d{5}-\d{4}$"
        if not re.match(pattern, v):
            raise ValueError("WhatsApp inválido. Formato esperado: (00)00000-0000")
        return v
    
    @field_validator("uf")
    def validate_uf_format(cls, v):
        if not re.match(r"^[A-Z]{2}$", v):
            raise ValueError("UF inválida. Deve ter 2 letras maiúsculas")
        return v


class EntidadeResponse(BaseModel):
    id: int
    cnpj: str
    razao_social: str
    logradouro: str
    numero: str
    complemento: Optional[str]
    bairro: str
    cidade: str
    uf: str
    cep: str
    email: str
    presidente: str
    whatsapp: str
    whatsapp_opt_in: bool
    
    class Config:
        from_attributes = True


class EmendaCreate(BaseModel):
    numero_emenda: str
    processo_mae: str
    valor_total: float
    vereador_responsavel: str
    orgao_destinatario: str
    entidade_beneficiaria_id: int
    justificativa: str


class EmendaResponse(BaseModel):
    id: int
    numero_emenda: str
    processo_mae: str
    valor_total: float
    vereador_responsavel: str
    orgao_destinatario: str
    entidade_beneficiaria_id: int
    status: StatusEmenda
    data_aprovacao: Optional[str]
    hash_integridade: Optional[str]
    
    class Config:
        from_attributes = True


class EmendaStatusUpdate(BaseModel):
    novo_status: StatusEmenda


# Endpoints
@router.post("/entidades", response_model=EntidadeResponse, status_code=status.HTTP_201_CREATED)
async def criar_entidade(entidade_data: EntidadeCreate, db: Session = Depends(get_db)):
    # Validação via CEP na API ViaCEP
    cep_validation = await validate_cep_via_api(entidade_data.cep)
    if not cep_validation["valid"]:
        raise HTTPException(status_code=400, detail=f"CEP inválido: {cep_validation['error']}")
    
    # Verifica se CNPJ já existe
    existing = db.query(Entidade).filter(Entidade.cnpj == entidade_data.cnpj).first()
    if existing:
        raise HTTPException(status_code=400, detail="CNPJ já cadastrado")
    
    # Cria entidade
    entidade = Entidade(**entidade_data.model_dump())
    db.add(entidade)
    db.commit()
    db.refresh(entidade)
    
    return entidade


@router.get("/entidades", response_model=List[EntidadeResponse])
async def listar_entidades(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    entidades = db.query(Entidade).offset(skip).limit(limit).all()
    return entidades


@router.get("/entidades/{entidade_id}", response_model=EntidadeResponse)
async def obter_entidade(entidade_id: int, db: Session = Depends(get_db)):
    entidade = db.query(Entidade).filter(Entidade.id == entidade_id).first()
    if not entidade:
        raise HTTPException(status_code=404, detail="Entidade não encontrada")
    return entidade


@router.post("/emendas", response_model=EmendaResponse, status_code=status.HTTP_201_CREATED)
async def criar_emenda(emenda_data: EmendaCreate, db: Session = Depends(get_db)):
    # Verifica se entidade existe
    entidade = db.query(Entidade).filter(Entidade.id == emenda_data.entidade_beneficiaria_id).first()
    if not entidade:
        raise HTTPException(status_code=404, detail="Entidade beneficiária não encontrada")
    
    # Verifica se número da emenda já existe
    existing = db.query(Emenda).filter(Emenda.numero_emenda == emenda_data.numero_emenda).first()
    if existing:
        raise HTTPException(status_code=400, detail="Número da emenda já cadastrado")
    
    # Cria emenda
    emenda = Emenda(**emenda_data.model_dump())
    db.add(emenda)
    db.commit()
    db.refresh(emenda)
    
    return emenda


@router.get("/emendas", response_model=List[EmendaResponse])
async def listar_emendas(
    skip: int = 0, 
    limit: int = 100, 
    status_filter: Optional[StatusEmenda] = None,
    db: Session = Depends(get_db)
):
    query = db.query(Emenda)
    if status_filter:
        query = query.filter(Emenda.status == status_filter)
    emendas = query.offset(skip).limit(limit).all()
    return emendas


@router.put("/emendas/{emenda_id}/status", response_model=EmendaResponse)
async def atualizar_status_emenda(
    emenda_id: int, 
    status_update: EmendaStatusUpdate,
    db: Session = Depends(get_db)
):
    emenda = db.query(Emenda).filter(Emenda.id == emenda_id).first()
    if not emenda:
        raise HTTPException(status_code=404, detail="Emenda não encontrada")
    
    # Verifica se a transição de status é válida
    if not Emenda.can_transition(emenda.status, status_update.novo_status):
        raise HTTPException(
            status_code=400, 
            detail=f"Transição inválida de {emenda.status.value} para {status_update.novo_status.value}"
        )
    
    # Atualiza status
    emenda.status = status_update.novo_status
    
    # Define datas automáticas conforme o status
    if status_update.novo_status == StatusEmenda.APROVADO_TECNICO and not emenda.data_aprovacao:
        from datetime import datetime
        emenda.data_aprovacao = datetime.utcnow()
    
    # Gera hash de integridade quando finalizada
    if status_update.novo_status == StatusEmenda.FINALIZADO:
        hash_data = {
            "numero_emenda": emenda.numero_emenda,
            "valor_total": emenda.valor_total,
            "status": emenda.status.value,
            "data_aprovacao": str(emenda.data_aprovacao) if emenda.data_aprovacao else None
        }
        emenda.hash_integridade = generate_integrity_hash(hash_data)
    
    db.commit()
    db.refresh(emenda)
    
    return emenda
