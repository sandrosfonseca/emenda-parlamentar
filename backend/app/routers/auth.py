from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import Optional
from pydantic import BaseModel, EmailStr
from datetime import timedelta

from app.models.database import get_db, Usuario, Entidade
from app.core.security import get_password_hash, verify_password, create_access_token
from app.core.enums import Role
from app.core.config import settings

router = APIRouter()


class UsuarioCreate(BaseModel):
    email: EmailStr
    senha: str
    nome: str
    role: Role = Role.LEITOR
    entidade_id: Optional[int] = None


class UsuarioLogin(BaseModel):
    email: EmailStr
    senha: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: str


@router.post("/register", response_model=TokenResponse)
async def register(usuario_data: UsuarioCreate, db: Session = Depends(get_db)):
    # Verifica se email já existe
    existing = db.query(Usuario).filter(Usuario.email == usuario_data.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email já cadastrado")
    
    # Valida role para gestor_entidade (precisa de entidade_id)
    if usuario_data.role == Role.GESTOR_ENTIDADE and not usuario_data.entidade_id:
        raise HTTPException(status_code=400, detail="Gestor de entidade deve estar vinculado a uma entidade")
    
    # Verifica se entidade existe (se aplicável)
    if usuario_data.entidade_id:
        entidade = db.query(Entidade).filter(Entidade.id == usuario_data.entidade_id).first()
        if not entidade:
            raise HTTPException(status_code=404, detail="Entidade não encontrada")
    
    # Cria usuário
    usuario = Usuario(
        email=usuario_data.email,
        senha_hash=get_password_hash(usuario_data.senha),
        nome=usuario_data.nome,
        role=usuario_data.role,
        entidade_id=usuario_data.entidade_id
    )
    
    db.add(usuario)
    db.commit()
    db.refresh(usuario)
    
    # Gera token de acesso
    access_token = create_access_token(
        data={"sub": usuario.email, "role": usuario.role.value, "entidade_id": usuario.entidade_id},
        expires_delta=timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    
    return {"access_token": access_token, "token_type": "bearer", "role": usuario.role.value}


@router.post("/login", response_model=TokenResponse)
async def login(login_data: UsuarioLogin, db: Session = Depends(get_db)):
    usuario = db.query(Usuario).filter(Usuario.email == login_data.email).first()
    
    if not usuario or not verify_password(login_data.senha, usuario.senha_hash):
        raise HTTPException(status_code=401, detail="Credenciais inválidas")
    
    if not usuario.ativo:
        raise HTTPException(status_code=403, detail="Usuário inativo")
    
    # Gera token de acesso
    access_token = create_access_token(
        data={"sub": usuario.email, "role": usuario.role.value, "entidade_id": usuario.entidade_id},
        expires_delta=timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    
    return {"access_token": access_token, "token_type": "bearer", "role": usuario.role.value}
