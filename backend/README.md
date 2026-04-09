# Backend - Sistema de Gestão de Emendas Municipais

API RESTful desenvolvida em Python/FastAPI para gerenciamento de emendas parlamentares com conformidade LAI e LGPD.

## Funcionalidades Implementadas

### 1. Validações de Dados
- **CNPJ**: Formato 00.000.000/0000-00
- **CEP**: Formato 00000-000 com validação via API ViaCEP
- **WhatsApp**: Formato (00)00000-0000
- **UF**: 2 letras maiúsculas
- **Endereço completo**: Obrigatório (logradouro, número, bairro)

### 2. Máquina de Estados para Emendas
Transições válidas implementadas:
- `rascunho` → `enviado` → `em_analise` ↔ `pendente_documentacao` → `aprovado_tecnico` → `em_empenho` → `empenhado` → `em_liquidacao` → `liquidado` → `pago` → `prestacao_contas` → `finalizado`
- Estados terminais: `indeferido`, `cancelado`, `finalizado`
- Transições inválidas são bloqueadas automaticamente

### 3. Prazos Legais (Decreto Municipal 11.118/2026)
- **Prazo de empenho**: 90 dias após aprovação (calculado automaticamente)
- **Prazo de execução**: Até 31 de dezembro do ano do exercício
- **Prestação de contas**: 60 dias após pagamento
- **Limite de remanescente**: 25% do valor total

### 4. Autenticação e Autorização (RBAC)
5 níveis de acesso:
- `super_admin`: Acesso total
- `gestor_municipal`: Gerencia todas as emendas e entidades
- `gestor_entidade`: Acesso restrito à sua entidade
- `consultor`: Apenas leitura
- `leitor`: Acesso público

### 5. Conformidade Legal
- **LAI**: Endpoints preparados para exportação CSV/JSON
- **LGPD**: Funções de anonimização de dados sensíveis
- **Hash de integridade**: SHA-256 gerado para emendas finalizadas
- **Audit log**: Middleware registra todas as requisições

### 6. Integrações
- **ViaCEP**: Validação automática de endereços
- **WhatsApp Business**: Envio de alertas de prazo (com opt-in)

## Estrutura do Projeto

```
backend/
├── app/
│   ├── core/
│   │   ├── config.py        # Configurações e variáveis de ambiente
│   │   ├── security.py      # JWT, hashing de senhas
│   │   └── enums.py         # Roles e Status das emendas
│   ├── models/
│   │   └── database.py      # Modelos SQLAlchemy e validações
│   ├── services/
│   │   ├── viacep.py        # Integração ViaCEP
│   │   └── notifications.py # WhatsApp e anonimização
│   ├── routers/
│   │   ├── auth.py          # Login e registro
│   │   └── emendas.py       # CRUD de emendas e entidades
│   └── main.py              # Aplicação FastAPI
├── tests/
├── requirements.txt
├── Dockerfile
├── docker-compose.yml
└── .env.example
```

## Como Executar

### Opção 1: Docker (Recomendado)

```bash
cd backend

# Copia arquivo de ambiente
cp .env.example .env

# Sobe os containers
docker-compose up -d

# Acessa a API
# http://localhost:8000/docs
```

### Opção 2: Localmente

```bash
cd backend

# Cria ambiente virtual
python -m venv venv
source venv/bin/activate  # Linux/Mac
# ou
venv\Scripts\activate  # Windows

# Instala dependências
pip install -r requirements.txt

# Configura variáveis de ambiente
cp .env.example .env
# Edite .env com suas configurações

# Executa a API
uvicorn app.main:app --reload

# Acessa a documentação
# http://localhost:8000/docs
```

## Endpoints Principais

### Autenticação
- `POST /api/auth/register` - Registrar novo usuário
- `POST /api/auth/login` - Login e obtenção de token JWT

### Entidades
- `POST /api/entidades` - Cadastrar entidade (valida CNPJ, CEP via ViaCEP)
- `GET /api/entidades` - Listar entidades
- `GET /api/entidades/{id}` - Obter entidade específica

### Emendas
- `POST /api/emendas` - Criar nova emenda
- `GET /api/emendas` - Listar emendas (com filtro por status)
- `PUT /api/emendas/{id}/status` - Atualizar status (valida transições)

## Exemplo de Uso

### 1. Registrar um gestor municipal
```bash
curl -X POST "http://localhost:8000/api/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "gestor@santos.sp.gov.br",
    "senha": "senha123",
    "nome": "Gestor Municipal",
    "role": "gestor_municipal"
  }'
```

### 2. Cadastrar entidade
```bash
curl -X POST "http://localhost:8000/api/entidades" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer SEU_TOKEN" \
  -d '{
    "cnpj": "12.345.678/0001-90",
    "razao_social": "Associação Comunitária",
    "logradouro": "Rua XV de Novembro",
    "numero": "100",
    "bairro": "Centro",
    "cep": "11010-000",
    "email": "contato@assoc.org.br",
    "presidente": "João Silva",
    "whatsapp": "(13) 99999-9999",
    "whatsapp_opt_in": true
  }'
```

### 3. Criar emenda
```bash
curl -X POST "http://localhost:8000/api/emendas" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer SEU_TOKEN" \
  -d '{
    "numero_emenda": "EMD-2026-001",
    "processo_mae": "PROC-2026-1234",
    "valor_total": 150000.00,
    "vereador_responsavel": "Vereador João",
    "orgao_destinatario": "Secretaria de Saúde",
    "entidade_beneficiaria_id": 1,
    "justificativa": "Aquisição de equipamentos médicos"
  }'
```

### 4. Atualizar status da emenda
```bash
curl -X PUT "http://localhost:8000/api/emendas/1/status" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer SEU_TOKEN" \
  -d '{
    "novo_status": "aprovado_tecnico"
  }'
```

## Próximos Passos Recomendados

1. **Frontend Administrativo**: Desenvolver interface React/Vue para gestão interna
2. **Portal do Cidadão**: Criar site público com dados anonimizados
3. **Exportação LAI/TCE**: Implementar endpoints de exportação CSV/JSON assinados
4. **Scheduler de Alertas**: Criar tarefa agendada para verificação de prazos
5. **Testes Automatizados**: Implementar testes unitários e de integração
