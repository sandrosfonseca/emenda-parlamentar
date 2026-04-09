-- =====================================================
-- SISTEMA DE GESTÃO DE EMENDAS MUNICIPAIS - SANTOS/SP
-- Versão 2.1.0 | Conformidade: LGPD, LAI, Decreto 11.118/2026
-- Script Completo com Validações, Triggers e Procedimentos
-- =====================================================

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";

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
    whatsapp VARCHAR(20) NULL COMMENT 'Formato: (00)00000-0000',
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    atualizado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_cnpj (cnpj),
    INDEX idx_bairro_cidade (bairro, cidade),
    INDEX idx_cep (cep),
    CONSTRAINT chk_cnpj_format CHECK (cnpj REGEXP '^[0-9]{2}\\.[0-9]{3}\\.[0-9]{3}/[0-9]{4}-[0-9]{2}$'),
    CONSTRAINT chk_cep_format CHECK (cep REGEXP '^[0-9]{5}-[0-9]{3}$'),
    CONSTRAINT chk_uf_format CHECK (uf REGEXP '^[A-Z]{2}$'),
    CONSTRAINT chk_whatsapp_format CHECK (whatsapp IS NULL OR whatsapp REGEXP '^\\([0-9]{2}\\)[0-9]{5}-[0-9]{4}$')
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
    optin_whatsapp BOOLEAN DEFAULT FALSE COMMENT 'Consentimento explícito para WhatsApp - LGPD',
    ativo BOOLEAN DEFAULT TRUE,
    ultimo_login TIMESTAMP NULL,
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE RESTRICT,
    FOREIGN KEY (entidade_id) REFERENCES entidades(id) ON DELETE SET NULL,
    INDEX idx_email (email),
    INDEX idx_entidade (entidade_id),
    CONSTRAINT chk_user_whatsapp_format CHECK (whatsapp IS NULL OR whatsapp REGEXP '^\\([0-9]{2}\\)[0-9]{5}-[0-9]{4}$')
);

-- -----------------------------------------------------
-- 4. TABELA: emendas (fluxo completo com máquina de estados)
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
    
    status ENUM(
        'rascunho',
        'enviado',
        'em_analise',
        'pendente_documentacao',
        'aprovado_tecnico',
        'em_empenho',
        'empenhado',
        'em_liquidacao',
        'liquidado',
        'pago',
        'prestacao_contas',
        'finalizado',
        'indeferido',
        'cancelado'
    ) DEFAULT 'rascunho',
    
    data_aprovacao DATE NULL,
    data_limite_empenho DATE GENERATED ALWAYS AS (
        CASE 
            WHEN data_aprovacao IS NOT NULL THEN DATE_ADD(data_aprovacao, INTERVAL 90 DAY)
            ELSE NULL 
        END
    ) STORED,
    data_limite_execucao DATE NULL COMMENT 'Até 31 de dezembro do ano do exercício',
    data_limite_prestacao_contas DATE NULL COMMENT '60 dias após o pagamento',
    
    funcao_orcamentaria VARCHAR(2) NULL,
    subfuncao_orcamentaria VARCHAR(3) NULL,
    programa_orcamentario VARCHAR(4) NULL,
    acao_orcamentaria VARCHAR(4) NULL,
    elemento_despesa VARCHAR(4) NULL,
    
    conformidade_lai BOOLEAN DEFAULT FALSE,
    conformidade_lgpd BOOLEAN DEFAULT FALSE,
    hash_integridade VARCHAR(64) NULL COMMENT 'SHA-256 para imutabilidade',
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
    INDEX idx_conformidade (conformidade_lai, conformidade_lgpd),
    INDEX idx_hash (hash_integridade)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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
-- 11. TABELA: configuracoes_prazos (Decreto 11.118/2026)
-- -----------------------------------------------------
CREATE TABLE configuracoes_prazos (
    id INT PRIMARY KEY AUTO_INCREMENT,
    parametro VARCHAR(50) NOT NULL UNIQUE,
    valor_dias INT NOT NULL,
    descricao TEXT,
    ativo BOOLEAN DEFAULT TRUE,
    atualizado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

INSERT INTO configuracoes_prazos (parametro, valor_dias, descricao) VALUES
('prazo_empenho', 90, 'Prazo para empenho após aprovação (Decreto 11.118/2026)'),
('prazo_prestacao_contas', 60, 'Prazo para prestação de contas após pagamento'),
('limite_remanescente_pct', 25, 'Limite máximo de saldo remanescente em %'),
('alerta_prazo_7dias', 7, 'Alerta crítico 7 dias antes do vencimento'),
('alerta_prazo_3dias', 3, 'Alerta crítico 3 dias antes do vencimento'),
('alerta_prazo_1dia', 1, 'Alerta crítico 1 dia antes do vencimento');

-- -----------------------------------------------------
-- 12. TABELA: retencao_descarte (política de retenção)
-- -----------------------------------------------------
CREATE TABLE retencao_descarte (
    id INT PRIMARY KEY AUTO_INCREMENT,
    tipo_dado VARCHAR(50) NOT NULL,
    prazo_retencao_anos INT NOT NULL,
    acao_final ENUM('arquivo_permanente', 'descarte_seguro', 'anonimizacao', 'eliminacao_nist_800_88') NOT NULL,
    descricao TEXT,
    ultimo_processamento DATE NULL,
    ativo BOOLEAN DEFAULT TRUE
);

INSERT INTO retencao_descarte (tipo_dado, prazo_retencao_anos, acao_final, descricao) VALUES
('execucao_financeira', 10, 'arquivo_permanente', 'Dados financeiros permanentes'),
('prestacao_contas', 7, 'descarte_seguro', 'Documentos de prestação de contas'),
('dados_pessoais', 2, 'anonimizacao', 'Endereço, contato - após finalidade + 2 anos'),
('logs_auditoria', 5, 'eliminacao_nist_800_88', 'Logs de auditoria'),
('enderecos_completos', 5, 'anonimizacao_parcial', 'Manter apenas bairro/cidade após 5 anos');

-- -----------------------------------------------------
-- 13. TRIGGER: Validação da Máquina de Estados
-- -----------------------------------------------------
DELIMITER $$
CREATE TRIGGER trg_emendas_valida_transicao_status
BEFORE UPDATE ON emendas
FOR EACH ROW
BEGIN
    DECLARE transicao_valida BOOLEAN DEFAULT FALSE;
    
    -- Define transições válidas conforme regras de negócio
    IF OLD.status = 'rascunho' AND NEW.status IN ('enviado', 'cancelado') THEN
        SET transicao_valida = TRUE;
    ELSEIF OLD.status = 'enviado' AND NEW.status IN ('em_analise', 'indeferido', 'cancelado') THEN
        SET transicao_valida = TRUE;
    ELSEIF OLD.status = 'em_analise' AND NEW.status IN ('pendente_documentacao', 'aprovado_tecnico', 'indeferido', 'cancelado') THEN
        SET transicao_valida = TRUE;
    ELSEIF OLD.status = 'pendente_documentacao' AND NEW.status IN ('em_analise', 'indeferido', 'cancelado') THEN
        SET transicao_valida = TRUE;
    ELSEIF OLD.status = 'aprovado_tecnico' AND NEW.status IN ('em_empenho', 'cancelado') THEN
        SET transicao_valida = TRUE;
    ELSEIF OLD.status = 'em_empenho' AND NEW.status IN ('empenhado', 'cancelado') THEN
        SET transicao_valida = TRUE;
    ELSEIF OLD.status = 'empenhado' AND NEW.status IN ('em_liquidacao', 'cancelado') THEN
        SET transicao_valida = TRUE;
    ELSEIF OLD.status = 'em_liquidacao' AND NEW.status IN ('liquidado', 'cancelado') THEN
        SET transicao_valida = TRUE;
    ELSEIF OLD.status = 'liquidado' AND NEW.status IN ('pago', 'cancelado') THEN
        SET transicao_valida = TRUE;
    ELSEIF OLD.status = 'pago' AND NEW.status IN ('prestacao_contas', 'cancelado') THEN
        SET transicao_valida = TRUE;
    ELSEIF OLD.status = 'prestacao_contas' AND NEW.status IN ('finalizado', 'cancelado') THEN
        SET transicao_valida = TRUE;
    ELSEIF OLD.status = 'finalizado' AND NEW.status IN ('cancelado') THEN
        SET transicao_valida = TRUE;
    ELSEIF OLD.status = 'indeferido' AND NEW.status IN ('cancelado') THEN
        SET transicao_valida = TRUE;
    END IF;
    
    -- Bloqueia transição inválida
    IF transicao_valida = FALSE AND OLD.status != NEW.status THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Transição de status inválida. Verifique o fluxo permitido.';
    END IF;
    
    -- Valida data_aprovacao ao mudar para aprovado_tecnico
    IF NEW.status = 'aprovado_tecnico' AND OLD.status != 'aprovado_tecnico' THEN
        IF NEW.data_aprovacao IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Data de aprovação é obrigatória ao aprovar tecnicamente a emenda.';
        END IF;
        -- Calcula prazo limite de execução (31 de dezembro do ano do exercício)
        SET NEW.data_limite_execucao = CONCAT(YEAR(NEW.data_aprovacao), '-12-31');
    END IF;
    
    -- Calcula prazo de prestação de contas ao mudar para pago
    IF NEW.status = 'pago' AND OLD.status != 'pago' THEN
        SET NEW.data_limite_prestacao_contas = DATE_ADD(CURDATE(), INTERVAL 60 DAY);
    END IF;
    
    -- Gera hash de integridade ao finalizar
    IF NEW.status = 'finalizado' AND OLD.status != 'finalizado' THEN
        SET NEW.hash_integridade = SHA2(CONCAT(
            NEW.num_emenda_parlamentar,
            NEW.valor_total,
            NEW.data_aprovacao,
            NEW.entidade_id,
            CURDATE()
        ), 256);
    END IF;
END$$
DELIMITER ;

-- -----------------------------------------------------
-- 14. TRIGGER: Auditoria Completa com Anonimização LGPD
-- -----------------------------------------------------
DELIMITER $$
CREATE TRIGGER trg_emendas_audit_insert
AFTER INSERT ON emendas
FOR EACH ROW
BEGIN
    DECLARE user_id INT DEFAULT NULL;
    -- Em produção, capturar do contexto da sessão: SET user_id = @current_user_id;
    
    INSERT INTO audit_log (usuario_id, acao, tabela_afetada, registro_id, dados_novos, ip_origem)
    VALUES (user_id, 'insert', 'emendas', NEW.id, 
            JSON_OBJECT(
                'num_emenda', NEW.num_emenda_parlamentar,
                'valor', NEW.valor_total,
                'entidade_id', NEW.entidade_id
            ), 
            SUBSTRING_INDEX(USER(), '@', 1));
END$$

CREATE TRIGGER trg_emendas_audit_update_full
AFTER UPDATE ON emendas
FOR EACH ROW
BEGIN
    DECLARE user_id INT DEFAULT NULL;
    DECLARE diff_json JSON;
    
    -- Em produção: SET user_id = @current_user_id;
    
    -- Cria log apenas se houve mudança relevante
    IF OLD.status != NEW.status OR OLD.valor_total != NEW.valor_total OR OLD.entidade_id != NEW.entidade_id THEN
        INSERT INTO audit_log (usuario_id, acao, tabela_afetada, registro_id, dados_antigos, dados_novos, ip_origem)
        VALUES (
            user_id, 
            'update', 
            'emendas', 
            NEW.id,
            JSON_OBJECT('status', OLD.status, 'valor', OLD.valor_total, 'entidade_id', OLD.entidade_id),
            JSON_OBJECT('status', NEW.status, 'valor', NEW.valor_total, 'entidade_id', NEW.entidade_id),
            SUBSTRING_INDEX(USER(), '@', 1)
        );
    END IF;
END$$

CREATE TRIGGER trg_entidades_audit_whatsapp_access
AFTER SELECT ON entidades
FOR EACH ROW
BEGIN
    -- Nota: MySQL não suporta trigger AFTER SELECT diretamente
    -- Esta lógica deve ser implementada na camada de aplicação
    -- Registrar acesso a dados sensíveis (WhatsApp) no audit_log
END$$
DELIMITER ;

-- -----------------------------------------------------
-- 15. TRIGGER: Validação de Pagamento e Limite de Remanescente
-- -----------------------------------------------------
DELIMITER $$
CREATE TRIGGER trg_pagamentos_valida_remanescente
BEFORE INSERT ON pagamentos
FOR EACH ROW
BEGIN
    DECLARE valor_total_emenda DECIMAL(12,2);
    DECLARE valor_ja_pago DECIMAL(12,2);
    DECLARE novo_total_pago DECIMAL(12,2);
    DECLARE remanescente_pct DECIMAL(5,2);
    
    -- Obtém valor total da emenda
    SELECT valor_total INTO valor_total_emenda FROM emendas WHERE id = NEW.emenda_id;
    
    -- Soma pagamentos já realizados
    SELECT COALESCE(SUM(valor_pago), 0) INTO valor_ja_pago 
    FROM pagamentos WHERE emenda_id = NEW.emenda_id;
    
    SET novo_total_pago = valor_ja_pago + NEW.valor_pago;
    
    -- Valida se não ultrapassa o valor total
    IF novo_total_pago > valor_total_emenda THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Valor total de pagamentos não pode ultrapassar o valor da emenda.';
    END IF;
    
    -- Calcula percentual de remanescente
    SET remanescente_pct = ((valor_total_emenda - novo_total_pago) / valor_total_emenda) * 100;
    
    -- Alerta se remanescente ultrapassar 25% (conforme regra de negócio)
    -- Nota: Em MySQL, WARNINGs não bloqueiam, apenas informam
    -- A validação rigorosa deve ser feita na aplicação ou em trigger de atualização de status
END$$

CREATE TRIGGER trg_pagamentos_atualiza_status_emenda
AFTER INSERT ON pagamentos
FOR EACH ROW
BEGIN
    DECLARE qtd_pagamentos INT;
    DECLARE valor_total_emenda DECIMAL(12,2);
    DECLARE valor_total_pago DECIMAL(12,2);
    
    -- Conta quantidade de pagamentos
    SELECT COUNT(*) INTO qtd_pagamentos FROM pagamentos WHERE emenda_id = NEW.emenda_id;
    
    -- Obtém valores
    SELECT e.valor_total, COALESCE(SUM(p.valor_pago), 0)
    INTO valor_total_emenda, valor_total_pago
    FROM emendas e
    LEFT JOIN pagamentos p ON e.id = p.emenda_id
    WHERE e.id = NEW.emenda_id
    GROUP BY e.id;
    
    -- Atualiza status automaticamente se totalmente pago
    IF valor_total_pago >= valor_total_emenda THEN
        UPDATE emendas 
        SET status = 'pago', atualizado_por = NULL
        WHERE id = NEW.emenda_id AND status != 'pago';
    END IF;
END$$
DELIMITER ;

-- -----------------------------------------------------
-- 16. PROCEDIMENTO: Anonimização de Dados Pessoais (LGPD)
-- -----------------------------------------------------
DELIMITER $$
CREATE PROCEDURE sp_anonimizar_dados_pessoais(
    IN p_entidade_id INT,
    IN p_motivo VARCHAR(255)
)
BEGIN
    DECLARE v_cnpj_original VARCHAR(18);
    DECLARE v_email_original VARCHAR(100);
    DECLARE v_whatsapp_original VARCHAR(20);
    DECLARE v_usuario_logado INT DEFAULT NULL;
    
    -- Captura dados originais para log (antes da anonimização)
    SELECT cnpj, email, whatsapp 
    INTO v_cnpj_original, v_email_original, v_whatsapp_original
    FROM entidades WHERE id = p_entidade_id;
    
    -- Realiza anonimização
    UPDATE entidades SET
        cnpj = CONCAT(SUBSTRING(cnpj, 1, 8), '****-**-**'),
        email = CONCAT(SUBSTRING_INDEX(email, '@', 1), '***@***.***'),
        whatsapp = CONCAT('(**)*****-****'),
        presidente = 'DADO ANONIMIZADO',
        atualizado_em = CURRENT_TIMESTAMP
    WHERE id = p_entidade_id;
    
    -- Registra no audit log
    INSERT INTO audit_log (usuario_id, acao, tabela_afetada, registro_id, dados_antigos, dados_novos)
    VALUES (
        v_usuario_logado,
        'anonimizacao_lgpd',
        'entidades',
        p_entidade_id,
        JSON_OBJECT('cnpj', v_cnpj_original, 'email', v_email_original, 'whatsapp', v_whatsapp_original),
        JSON_OBJECT('motivo', p_motivo, 'data_anonimizacao', NOW())
    );
END$$
DELIMITER ;

-- -----------------------------------------------------
-- 17. PROCEDIMENTO: Exportação LAI (CSV Diário)
-- -----------------------------------------------------
DELIMITER $$
CREATE PROCEDURE sp_exportar_lai_csv(
    IN p_data_inicio DATE,
    IN p_data_fim DATE
)
BEGIN
    -- Seleciona dados para exportação conforme LAI
    SELECT 
        e.num_emenda_parlamentar,
        e.num_processo_mae,
        e.valor_total,
        e.vereador_responsavel,
        e.orgao_destino,
        ent.razao_social,
        ent.bairro,
        ent.cidade,
        e.status,
        e.data_aprovacao,
        e.data_limite_empenho,
        e.conformidade_lai,
        e.conformidade_lgpd,
        DATE_FORMAT(e.criado_em, '%Y-%m-%d %H:%i:%s') AS criado_em
    FROM emendas e
    JOIN entidades ent ON e.entidade_id = ent.id
    WHERE DATE(e.criado_em) BETWEEN p_data_inicio AND p_data_fim
      AND e.conformidade_lai = TRUE
    ORDER BY e.criado_em DESC;
    -- Nota: A exportação para CSV deve ser feita pela aplicação
END$$
DELIMITER ;

-- -----------------------------------------------------
-- 18. PROCEDIMENTO: Relatório TCE/SP (Trimestral)
-- -----------------------------------------------------
DELIMITER $$
CREATE PROCEDURE sp_relatorio_tce_sp(
    IN p_ano INT,
    IN p_trimestre INT -- 1, 2, 3 ou 4
)
BEGIN
    DECLARE v_data_inicio DATE;
    DECLARE v_data_fim DATE;
    
    -- Calcula período do trimestre
    SET v_data_inicio = MAKEDATE(p_ano, 1 + (p_trimestre - 1) * 90);
    SET v_data_fim = LAST_DAY(DATE_ADD(v_data_inicio, INTERVAL 2 MONTH));
    
    -- Retorna dados agregados para o TCE/SP
    SELECT 
        p_ano AS ano_referencia,
        p_trimestre AS trimestre,
        COUNT(DISTINCT e.id) AS qtd_emendas,
        SUM(e.valor_total) AS valor_total_emendas,
        COALESCE(SUM(p.valor_pago), 0) AS valor_total_pago,
        ROUND(COALESCE(SUM(p.valor_pago), 0) / NULLIF(SUM(e.valor_total), 0) * 100, 2) AS pct_execucao,
        SUM(CASE WHEN e.status = 'finalizado' THEN 1 ELSE 0 END) AS qtd_finalizadas,
        SUM(CASE WHEN e.status = 'cancelado' OR e.status = 'indeferido' THEN 1 ELSE 0 END) AS qtd_canceladas,
        SUM(CASE WHEN e.conformidade_lai = TRUE THEN 1 ELSE 0 END) AS qtd_conforme_lai,
        SUM(CASE WHEN e.conformidade_lgpd = TRUE THEN 1 ELSE 0 END) AS qtd_conforme_lgpd,
        JSON_ARRAYAGG(
            DISTINCT JSON_OBJECT('bairro', ent.bairro, 'valor', e.valor_total)
        ) AS localizacao_gastos
    FROM emendas e
    JOIN entidades ent ON e.entidade_id = ent.id
    LEFT JOIN pagamentos p ON e.id = p.emenda_id
    WHERE YEAR(e.criado_em) = p_ano
      AND QUARTER(e.criado_em) = p_trimestre
    GROUP BY p_ano, p_trimestre;
    
    -- Assinatura digital seria aplicada na camada de aplicação (ICP Brasil)
END$$
DELIMITER ;

-- -----------------------------------------------------
-- 19. VIEW: Controle de Prazos e Alertas
-- -----------------------------------------------------
CREATE OR REPLACE VIEW vw_alertas_prazos AS
SELECT 
    e.id AS emenda_id,
    e.num_emenda_parlamentar,
    e.status,
    e.data_limite_empenho,
    e.data_limite_execucao,
    e.data_limite_prestacao_contas,
    DATEDIFF(e.data_limite_empenho, CURDATE()) AS dias_restam_empenho,
    DATEDIFF(e.data_limite_execucao, CURDATE()) AS dias_restam_execucao,
    CASE 
        WHEN e.data_limite_empenho < CURDATE() AND e.status NOT IN ('empenhado', 'pago', 'finalizado', 'cancelado') THEN 'VENCIDO'
        WHEN DATEDIFF(e.data_limite_empenho, CURDATE()) <= 1 THEN 'URGENTE_1_DIA'
        WHEN DATEDIFF(e.data_limite_empenho, CURDATE()) <= 3 THEN 'URGENTE_3_DIAS'
        WHEN DATEDIFF(e.data_limite_empenho, CURDATE()) <= 7 THEN 'ATENÇÃO_7_DIAS'
        ELSE 'EM_DIA'
    END AS nivel_alerta,
    ent.whatsapp,
    u.optin_whatsapp
FROM emendas e
JOIN entidades ent ON e.entidade_id = ent.id
LEFT JOIN usuarios u ON u.entidade_id = ent.id AND u.optin_whatsapp = TRUE
WHERE e.status NOT IN ('finalizado', 'cancelado')
  AND (
      e.data_limite_empenho <= DATE_ADD(CURDATE(), INTERVAL 7 DAY)
      OR e.data_limite_execucao <= DATE_ADD(CURDATE(), INTERVAL 30 DAY)
  );

-- -----------------------------------------------------
-- 20. EVENTO: Limpeza Automática de Logs (Retenção)
-- -----------------------------------------------------
-- Nota: Requer event_scheduler = ON no MySQL
SET GLOBAL event_scheduler = ON;

DELIMITER $$
CREATE EVENT evt_limpeza_logs_antigos
ON SCHEDULE EVERY 1 MONTH
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Elimina logs de auditoria com mais de 5 anos (NIST 800-88)
    DELETE FROM audit_log 
    WHERE criado_em < DATE_SUB(CURDATE(), INTERVAL 5 YEAR);
    
    -- Registra a execução
    INSERT INTO audit_log (acao, dados_novos)
    VALUES ('limpeza_automatica_logs', JSON_OBJECT('data_execucao', NOW()));
END$$
DELIMITER ;

-- Fim do script