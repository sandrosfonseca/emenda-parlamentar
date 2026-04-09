import httpx
from app.core.config import settings


async def validate_cep_via_api(cep: str) -> dict:
    """Valida CEP usando API ViaCEP"""
    # Remove formatação para consulta
    cep_clean = cep.replace("-", "")
    
    if len(cep_clean) != 8:
        return {"valid": False, "error": "CEP deve ter 8 dígitos"}
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(settings.VIACEP_URL.format(cep_clean))
            
            if response.status_code != 200:
                return {"valid": False, "error": "CEP não encontrado na base dos Correios"}
            
            data = response.json()
            
            if "erro" in data:
                return {"valid": False, "error": "CEP não encontrado"}
            
            return {
                "valid": True,
                "logradouro": data.get("logradouro", ""),
                "bairro": data.get("bairro", ""),
                "cidade": data.get("localidade", ""),
                "uf": data.get("uf", "").upper()
            }
    except Exception as e:
        return {"valid": False, "error": f"Erro ao consultar ViaCEP: {str(e)}"}
