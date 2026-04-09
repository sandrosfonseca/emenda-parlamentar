from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    # Database
    DATABASE_URL: str = "postgresql://user:password@localhost:5432/emendas_santos"
    
    # Security
    SECRET_KEY: str = "sua-chave-secreta-muito-forte-aqui"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    
    # WhatsApp Business API
    WHATSAPP_API_URL: str = "https://graph.facebook.com/v18.0"
    WHATSAPP_TOKEN: str = ""
    WHATSAPP_PHONE_ID: str = ""
    
    # ViaCEP
    VIACEP_URL: str = "https://viacep.com.br/ws/{}/json/"
    
    # Auditoria
    AUDIT_LOG_ENABLED: bool = True
    
    class Config:
        env_file = ".env"


settings = Settings()
