from fastapi import FastAPI, Depends, HTTPException, status, Request
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from jose import jwt
from app.core.config import settings
from app.models.database import get_db
from app.routers import emendas, auth

app = FastAPI(
    title="Sistema de Gestão de Emendas Municipais - Santos/SP",
    description="API para gerenciamento de emendas parlamentares com conformidade LAI e LGPD",
    version="1.0.0"
)

# CORS para permitir frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configurar para produção
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Dependência para verificar autenticação
async def get_current_user(request: Request, db: Session = Depends(get_db)):
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Não autorizado")
    
    token = auth_header.split(" ")[1]
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        return payload
    except Exception:
        raise HTTPException(status_code=401, detail="Token inválido")


# Dependência para verificar permissões RBAC
def require_role(required_roles: list):
    async def role_checker(current_user: dict = Depends(get_current_user)):
        user_role = current_user.get("role")
        if user_role not in required_roles:
            raise HTTPException(status_code=403, detail="Permissão insuficiente")
        return current_user
    return role_checker


# Middleware de auditoria (log de todas as requisições)
@app.middleware("http")
async def audit_log_middleware(request: Request, call_next):
    response = await call_next(request)
    
    # Log simplificado (sem PII)
    print(f"Audit: {request.method} {request.url.path} - Status: {response.status_code}")
    
    return response


# Rotas
app.include_router(auth.router, prefix="/api/auth", tags=["Autenticação"])
app.include_router(emendas.router, prefix="/api", tags=["Emendas e Entidades"])


@app.get("/")
async def root():
    return {
        "message": "Sistema de Gestão de Emendas Municipais - Santos/SP",
        "docs": "/docs",
        "version": "1.0.0"
    }


@app.get("/health")
async def health_check():
    return {"status": "healthy"}
