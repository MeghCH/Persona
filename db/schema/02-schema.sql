-- =====================================================================
-- Persona - schéma de la base partagée
-- C'est le "contrat" entre la personne A (chat/auth) et B (news/envoi).
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- hash des mots de passe (bcrypt) + UUID

-- ---------------------------------------------------------------------
-- Utilisateurs (A)
-- ---------------------------------------------------------------------
CREATE TABLE users (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email                 TEXT NOT NULL UNIQUE,
    password_hash         TEXT NOT NULL,
    role                  TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin')),
    -- RGPD : preuve du consentement
    consent_given_at      TIMESTAMPTZ NOT NULL,
    consent_version       TEXT NOT NULL,
    -- RGPD : désinscription en un clic depuis l'email
    unsubscribe_token     UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    -- Sécurité : anti brute-force
    failed_login_attempts INT NOT NULL DEFAULT 0,
    locked_until          TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Sessions du chatbot (A)
-- ---------------------------------------------------------------------
CREATE TABLE sessions (
    chat_session_id  TEXT PRIMARY KEY,
    user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at       TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '2 hours'
);

-- ---------------------------------------------------------------------
-- Préférences de newsletter (B)
-- ---------------------------------------------------------------------
CREATE TABLE preferences (
    user_id       UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    interests     TEXT[] NOT NULL DEFAULT '{}',
    send_hour     SMALLINT NOT NULL DEFAULT 8 CHECK (send_hour BETWEEN 0 AND 23),
    send_days     SMALLINT[] NOT NULL DEFAULT '{1,2,3,4,5,6,7}',
    timezone      TEXT NOT NULL DEFAULT 'Europe/Paris',
    language      TEXT NOT NULL DEFAULT 'fr',
    max_articles  SMALLINT NOT NULL DEFAULT 5 CHECK (max_articles BETWEEN 1 AND 20),
    is_active     BOOLEAN NOT NULL DEFAULT true,
    last_sent_at  TIMESTAMPTZ,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Articles collectés (B)
-- ---------------------------------------------------------------------
CREATE TABLE articles (
    id            BIGSERIAL PRIMARY KEY,
    url           TEXT NOT NULL UNIQUE,
    title         TEXT NOT NULL,
    source        TEXT NOT NULL,
    content       TEXT,
    summary       TEXT,
    tags          TEXT[] NOT NULL DEFAULT '{}',
    published_at  TIMESTAMPTZ,
    fetched_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_articles_fetched_at ON articles (fetched_at);
CREATE INDEX idx_articles_tags ON articles USING GIN (tags);

-- ---------------------------------------------------------------------
-- Historique des envois (B)
-- Sert à ne pas renvoyer deux fois le même article et au futur feedback.
-- ---------------------------------------------------------------------
CREATE TABLE sent_newsletters (
    id           BIGSERIAL PRIMARY KEY,
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    article_ids  BIGINT[] NOT NULL,
    sent_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_sent_user ON sent_newsletters (user_id, sent_at);

-- ---------------------------------------------------------------------
-- Journal de sécurité (A et B)
-- Utile pour l'audit et la démo. On évite d'y stocker des données personnelles en clair (pas de mot de passe, pas de message complet).
-- ---------------------------------------------------------------------
CREATE TABLE audit_log (
    id          BIGSERIAL PRIMARY KEY,
    event       TEXT NOT NULL,          -- 'login_failed', 'login_ok', 'account_locked',
                                        -- 'injection_suspected', 'account_deleted', ...
    user_id     UUID,                   -- volontairement sans FK : survit à la suppression
    details     JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Droits du compte applicatif utilisé par n8n
-- Il peut lire/écrire les données, mais pas modifier ou supprimer le schéma.
-- ---------------------------------------------------------------------
GRANT CONNECT ON DATABASE persona TO persona_app;
GRANT USAGE ON SCHEMA public TO persona_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO persona_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO persona_app;
REVOKE UPDATE, DELETE ON audit_log FROM persona_app;

-- ---------------------------------------------------------------------
-- Rétention RGPD : à appeler chaque nuit par un Schedule Trigger n8n
-- ---------------------------------------------------------------------
CREATE FUNCTION persona_cleanup() RETURNS void
LANGUAGE sql SECURITY DEFINER AS $$
    DELETE FROM sessions         WHERE expires_at < now();
    DELETE FROM articles         WHERE fetched_at < now() - INTERVAL '30 days';
    DELETE FROM sent_newsletters WHERE sent_at    < now() - INTERVAL '6 months';
    DELETE FROM audit_log        WHERE created_at < now() - INTERVAL '1 year';
$$;
GRANT EXECUTE ON FUNCTION persona_cleanup() TO persona_app;