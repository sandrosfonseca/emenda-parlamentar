import httpx
import hashlib
import logging
from datetime import datetime
from typing import Optional
from app.core.config import settings

logger = logging.getLogger(__name__)


async def send_whatsapp_message(phone: str, message: str) -> dict:
    """Envia mensagem via WhatsApp Business API (com opt-in)"""
    # Verifica se o usuário deu opt-in
    # Esta função deve ser chamada apenas após verificar whatsapp_opt_in no banco
    
    headers = {
        "Authorization": f"Bearer {settings.WHATSAPP_TOKEN}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "messaging_product": "whatsapp",
        "to": phone,
        "type": "text",
        "text": {
            "body": message
        }
    }
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{settings.WHATSAPP_API_URL}/{settings.WHATSAPP_PHONE_ID}/messages",
                headers=headers,
                json=payload
            )
            
            if response.status_code == 200:
                logger.info(f"Mensagem WhatsApp enviada para {phone}")
                return {"success": True, "message_id": response.json().get("messages", [{}])[0].get("id")}
            else:
                logger.error(f"Erro ao enviar WhatsApp: {response.status_code} - {response.text}")
                return {"success": False, "error": f"Status {response.status_code}"}
    except Exception as e:
        logger.error(f"Exceção ao enviar WhatsApp: {str(e)}")
        return {"success": False, "error": str(e)}


async def send_prazo_alert(emenda_numero: str, status: str, dias_restantes: int, phone: str) -> dict:
    """Envia alerta de prazo vencendo"""
    if dias_restantes == 7:
        mensagem = f"⚠️ Alerta de Prazo\n\nEmenda {emenda_numero} (Status: {status})\nFaltam 7 dias para o vencimento do prazo.\n\nAtenção necessária!"
    elif dias_restantes == 3:
        mensagem = f"🔴 URGENTE: Prazo\n\nEmenda {emenda_numero} (Status: {status})\nFaltam apenas 3 dias para o vencimento!\n\nTome providências imediatamente."
    elif dias_restantes == 1:
        mensagem = f"🚨 VENCIMENTO IMINENTE\n\nEmenda {emenda_numero} (Status: {status})\nVence amanhã!\n\nAção imediata requerida."
    else:
        return {"success": False, "error": "Dias restantes inválidos para alerta"}
    
    return await send_whatsapp_message(phone, mensagem)


def generate_integrity_hash(data: dict) -> str:
    """Gera hash SHA-256 para integridade da emenda"""
    # Ordena chaves para consistência
    sorted_data = sorted(data.items())
    data_string = "|".join([f"{k}:{v}" for k, v in sorted_data])
    return hashlib.sha256(data_string.encode()).hexdigest()


def anonymize_data(value: str, field_type: str) -> str:
    """Anonimiza dados sensíveis conforme LGPD"""
    if field_type == "cnpj":
        # Mantém apenas os últimos 4 dígitos
        clean = value.replace(".", "").replace("/", "").replace("-", "")
        return f"***.***/****-{clean[-2:]}" if len(clean) >= 2 else "***.***.***/****-**"
    elif field_type == "email":
        parts = value.split("@")
        if len(parts) == 2:
            user = parts[0]
            masked_user = user[0] + "***" if len(user) > 1 else "***"
            return f"{masked_user}@{parts[1]}"
        return "***@***.***"
    elif field_type == "phone":
        return "(**)*****-****"
    elif field_type == "endereco":
        # Mantém apenas bairro e cidade
        return "***, *** - ***"
    else:
        return "***"
