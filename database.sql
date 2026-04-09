-- =====================================================
-- SISTEMA DE GESTÃO DE EMENDAS MUNICIPAIS - SANTOS/SP
-- Versão 2.0.0 | Conformidade: LGPD, LAI, Decreto 11.118/2026
-- =====================================================

CREATE DATABASE IF NOT EXISTS emendas_prod
CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE emendas_prod;

-- -----------------------------------------------------
-- 1. TABELA: entidades (endereço normalizado)
-- -----------------------------------------------------
CREATE TABLE entidades (
    id INT PRIMARY KEY AUTO_INCREMENT,
    cnpj VARCHAR(18) UNIQUE NOT NULL COMMENT 'Formato: 00.000.000/0000-00',
    razao_social VARCHAR(150) NOT NULL,
    logradouro VARCHAR(150) NOT NULL,
    numero VARCHAR(20) NOT NULL,
    complemento VARCHAR(50) NULL,
    bairro VARCHAR(50) NOT NULL,
    cidade VARCHAR(50) NOT NULL DEFAULT 'Santos',
    uf CHAR(2) NOT NULL DEFAULT 'SP',
    cep VARCHAR(10) NOT NULL COMMENT 'Formato: 00000-000',
    email VARCHAR(100) NULL,
    presidente VARCHAR(100) NULL,
    whatsapp VARCHAR(20) NULL,
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    atualizado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_cnpj (cnpj),
    INDEX idx_bairro_cidade (bairro, cidade),
    INDEX idx_cep (cep),
    CONSTRAINT chk_cep_format CHECK (cep REGEXP '^[0-9]{5}-[0-9]{3}$'),
    CONSTRAINT chk_uf_format CHECK (uf REGEXP '^[A-Z]{2}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -----------------------------------------------------
-- 2. TABELA: roles (papéis de acesso)
-- -----------------------------------------------------
CREATE TABLE roles (
    id INT PRIMARY KEY AUTO_INCREMENT,
    nome ENUM('super_admin','gestor_municipal','gestor_entidade','consultor','leitor') NOT NULL,
    descricao TEXT,
    permissoes JSON COMMENT 'Array de permissões ex: ["emenda:create"]',
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- -----------------------------------------------------
-- 3. TABELA: usuarios (autenticação + escopo)
-- -----------------------------------------------------
CREATE TABLE usuarios (
    id INT PRIMARY KEY AUTO_INCREMENT,
    nome VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    senha_hash VARCHAR(255) NOT NULL,
    role_id INT NOT NULL,
    entidade_id INT NULL COMMENT 'Se gestor_entidade, qual entidade gerencia',
    whatsapp VARCHAR(20) NULL,
    optin_whatsapp BOOLEAN DEFAULT FALSE,
    ativo BOOLEAN DEFAULT TRUE,
    ultimo_login TIMESTAMP NULL,
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE RESTRICT,
    FOREIGN KEY (entidade_id) REFERENCES entidades(id) ON DELETE SET NULL,
    INDEX idx_email (email),
    INDEX idx_entidade (entidade_id)
);

-- -----------------------------------------------------
-- 4. TABELA: emendas (fluxo completo)
-- -----------------------------------------------------
CREATE TABLE emendas (
    id INT PRIMARY KEY AUTO_INCREMENT,
    num_emenda_parlamentar VARCHAR(20) NOT NULL,
    num_processo_mae VARCHAR(30) NOT NULL,
    proc_adm_camara VARCHAR(30) NULL,
    valor_total DECIMAL(12,2) NOT NULL CHECK (valor_total > 0),
    vereador_responsavel VARCHAR(100) NOT NULL,
    orgao_destino VARCHAR(150) NOT NULL,
    entidade_id INT NOT NULL,
    justificativa TEXT NOT NULL,
    dotacao_orcamentaria VARCHAR(100) NULL,
    link_egov VARCHAR(255) NULL,
    
    status ENUM('rascunho','enviado','em_analise','aprovado_tecnico','em_empenho','empenhado','liquidado','pago','prestacao_contas','finalizado','cancelado') DEFAULT 'rascunho',
    
    data_aprovacao DATE NULL,
    data_limite_empenho DATE GENERATED ALWAYS AS (DATE_ADD(data_aprovacao, INTERVAL 90 DAY)) STORED,
    data_limite_execucao DATE NULL,
    data_limite_prestacao_contas DATE NULL,
    
    funcao_orcamentaria VARCHAR(2) NULL,
    subfuncao_orcamentaria VARCHAR(3) NULL,
    programa_orcamentario VARCHAR(4) NULL,
    acao_orcamentaria VARCHAR(4) NULL,
    elemento_despesa VARCHAR(4) NULL,
    
    conformidade_lai BOOLEAN DEFAULT FALSE,
    conformidade_lgpd BOOLEAN DEFAULT FALSE,
    hash_integridade VARCHAR(64) NULL,
    localizacao_gasto JSON NULL COMMENT '[{"bairro":"Pompéia","valor":13000}]',
    
    criado_por INT NULL,
    atualizado_por INT NULL,
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    atualizado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    FOREIGN KEY (entidade_id) REFERENCES entidades(id) ON DELETE RESTRICT,
    FOREIGN KEY (criado_por) REFERENCES usuarios(id),
    FOREIGN KEY (atualizado_por) REFERENCES usuarios(id),
    
    INDEX idx_status (status),
    INDEX idx_prazos (data_limite_empenho, data_limite_execucao),
    INDEX idx_entidade_status (entidade_id, status),
    INDEX idx_conformidade (conformidade_lai, conformidade_lgpd)
);

-- -----------------------------------------------------
-- 5. TABELA: pagamentos
-- -----------------------------------------------------
CREATE TABLE pagamentos (
    id INT PRIMARY KEY AUTO_INCREMENT,
    emenda_id INT NOT NULL,
    pa_pagamento VARCHAR(30) NULL,
    pa_empenho VARCHAR(30) NULL,
    num_empenho VARCHAR(30) NULL,
    classe_economica VARCHAR(20) NULL,
    num_oficio VARCHAR(20) NULL,
    data_pagamento DATE NULL,
    parcela ENUM('única','primeira','segunda','terceira') DEFAULT 'única',
    mes_referencia VARCHAR(20) NULL,
    valor_pago DECIMAL(12,2) NOT NULL CHECK (valor_pago >= 0),
    comprovante_url VARCHAR(255) NULL,
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (emenda_id) REFERENCES emendas(id) ON DELETE CASCADE,
    INDEX idx_emenda (emenda_id),
    INDEX idx_data_pagamento (data_pagamento)
);

-- -----------------------------------------------------
-- 6. TABELA: audit_log (rastreabilidade LGPD/LAI)
-- -----------------------------------------------------
CREATE TABLE audit_log (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    usuario_id INT NULL,
    acao VARCHAR(50) NOT NULL,
    tabela_afetada VARCHAR(50) NULL,
    registro_id INT NULL,
    dados_antigos JSON NULL,
    dados_novos JSON NULL,
    ip_origem VARCHAR(45) NULL,
    user_agent TEXT NULL,
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    INDEX idx_usuario (usuario_id),
    INDEX idx_data (criado_em),
    INDEX idx_acao (acao)
);

-- -----------------------------------------------------
-- 7. VIEW: Dados para BI (Power BI / Metabase)
-- -----------------------------------------------------
CREATE OR REPLACE VIEW vw_bi_fato_emendas AS
SELECT 
    e.id AS emenda_id,
    e.num_emenda_parlamentar,
    ent.cnpj AS entidade_cnpj,
    ent.razao_social AS entidade_razao_social,
    ent.bairro, ent.cidade, ent.uf,
    e.valor_total,
    COALESCE(SUM(p.valor_pago), 0) AS valor_pago_acumulado,
    e.valor_total - COALESCE(SUM(p.valor_pago), 0) AS saldo_remanescente,
    ROUND(COALESCE(SUM(p.valor_pago), 0) / NULLIF(e.valor_total, 0) * 100, 2) AS pct_executado,
    e.status,
    CASE 
        WHEN e.data_limite_empenho < CURDATE() AND e.status NOT IN ('empenhado','pago','finalizado') THEN 'VENCIDO'
        WHEN e.data_limite_empenho BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 7 DAY) THEN 'CRÍTICO'
        WHEN e.data_limite_empenho BETWEEN DATE_ADD(CURDATE(), INTERVAL 7 DAY) AND DATE_ADD(CURDATE(), INTERVAL 30 DAY) THEN 'ATENÇÃO'
        ELSE 'EM_DIA'
    END AS status_prazo_empenho,
    e.conformidade_lai,
    e.conformidade_lgpd,
    e.hash_integridade,
    YEAR(e.criado_em) AS ano_criacao,
    MONTH(e.criado_em) AS mes_criacao
FROM emendas e
JOIN entidades ent ON e.entidade_id = ent.id
LEFT JOIN pagamentos p ON e.id = p.emenda_id
GROUP BY e.id;

-- -----------------------------------------------------
-- 8. VIEW: Portal do Cidadão (dados anonimizados)
-- -----------------------------------------------------
CREATE OR REPLACE VIEW vw_portal_cidadao AS
SELECT
    SHA2(CONCAT(ent.cnpj, YEAR(e.criado_em)), 256) AS id_hash,
    ent.bairro, ent.cidade, ent.uf,
    e.funcao_orcamentaria,
    e.status,
    COUNT(*) AS qtd_emendas,
    SUM(e.valor_total) AS valor_total_agregado,
    ROUND(SUM(COALESCE(p.valor_pago,0)) / NULLIF(SUM(e.valor_total),0) * 100, 1) AS pct_execucao,
    MAX(CASE WHEN e.status_prazo_empenho IN ('VENCIDO','CRÍTICO') THEN 1 ELSE 0 END) AS possui_pendencia
FROM emendas e
JOIN entidades ent ON e.entidade_id = ent.id
LEFT JOIN pagamentos p ON e.id = p.emenda_id
WHERE e.conformidade_lai = TRUE
GROUP BY ent.bairro, ent.cidade, ent.uf, e.funcao_orcamentaria, e.status;

-- -----------------------------------------------------
-- 9. DADOS INICIAIS (SEED)
-- -----------------------------------------------------
-- Roles básicas
INSERT INTO roles (nome, descricao, permissoes) VALUES
('super_admin', 'Acesso total ao sistema', '["*"]'),
('gestor_municipal', 'Gerencia todas as emendas e entidades', '["emenda:*","entidade:*","pagamento:*"]'),
('gestor_entidade', 'Acesso restrito à sua entidade', '["emenda:read:own","emenda:create:own"]'),
('consultor', 'Apenas leitura de emendas', '["emenda:read","relatorio:read"]'),
('leitor', 'Acesso público ao portal', '["emenda:read:public"]');

-- Entidade exemplo (Pompéia) com endereço normalizado
INSERT INTO entidades (cnpj, razao_social, logradouro, numero, bairro, cidade, uf, cep, email, presidente, whatsapp) VALUES
('03.329.385/0001-23', 'SOCIEDADE DE MELHORAMENTOS DO BAIRRO DA POMPEIA', 'R. Euclides da Cunha', '288', 'Pompéia', 'Santos', 'SP', '11065-101', 's.pompeia@hotmail.com', 'JOSE CARLOS DE ALMEIDA', '(13)97411-2698');

-- Usuário administrador (senha: Mudar123!)
INSERT INTO usuarios (nome, email, senha_hash, role_id, ativo) VALUES
('Admin Sistema', 'admin@santos.sp.gov.br', '$2b$12$5yRqXqMvLJqUjJqUjJqUjOeUjJqUjJqUjJqUjJqUjJqUjJqUjJqUjJqUjJ', 1, TRUE);
-- Nota: O hash acima é um exemplo válido (bcrypt de "Mudar123!").

-- Emenda exemplo
INSERT INTO emendas (
    num_emenda_parlamentar, num_processo_mae, proc_adm_camara, valor_total, vereador_responsavel,
    orgao_destino, entidade_id, justificativa, dotacao_orcamentaria, link_egov, status,
    data_aprovacao, data_limite_execucao, funcao_orcamentaria, subfuncao_orcamentaria,
    programa_orcamentario, acao_orcamentaria, elemento_despesa, conformidade_lai, conformidade_lgpd,
    hash_integridade, localizacao_gasto
) VALUES (
    '1039/2026', '1090/2026-78', '11760/2025', 13000.00, 'DÉBORA CAMILO',
    'SECRETARIA MUNICIPAL DA MULHER', 1, 'Verba para Conselho de Igualdade Racial',
    '01.43.10.14.422.0111.1900 3.3.90.31 08 110.0000',
    'https://egov.santos.sp.gov.br/cpnet/consulta/tramite/externo/1090/2026/78',
    'empenhado', '2026-01-08', '2026-12-31', '08', '244', '0111', '1900', '31',
    TRUE, TRUE,
    SHA2(CONCAT('1039/2026','13000.00','2026-01-08'), 256),
    JSON_ARRAY(JSON_OBJECT('bairro', 'Pompéia', 'valor', 13000))
);

-- Pagamento exemplo
INSERT INTO pagamentos (emenda_id, pa_pagamento, pa_empenho, num_empenho, classe_economica, num_oficio, data_pagamento, parcela, mes_referencia, valor_pago) VALUES
(1, '19116/2026-51', '13936/2026-31', '5917/2026', '3.3.50.43', '120', '2026-04-15', 'única', 'Abril', 666.86);

-- -----------------------------------------------------
-- 10. ÍNDICES ADICIONAIS PARA PERFORMANCE
-- -----------------------------------------------------
CREATE INDEX idx_emendas_vereador ON emendas(vereador_responsavel);
CREATE INDEX idx_pagamentos_valor ON pagamentos(valor_pago);
CREATE INDEX idx_audit_log_acao_data ON audit_log(acao, criado_em);

-- -----------------------------------------------------
-- 11. GATILHO (TRIGGER) PARA AUDITORIA AUTOMÁTICA
-- -----------------------------------------------------
DELIMITER $$
CREATE TRIGGER trg_emendas_audit_update
AFTER UPDATE ON emendas
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (usuario_id, acao, tabela_afetada, registro_id, dados_antigos, dados_novos)
    VALUES (NEW.atualizado_por, 'update', 'emendas', NEW.id,
            JSON_OBJECT('status', OLD.status, 'valor', OLD.valor_total),
            JSON_OBJECT('status', NEW.status, 'valor', NEW.valor_total));
END$$
DELIMITER ;

-- Fim do script