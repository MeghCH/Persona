-- =====================================================================
-- Persona - schéma de la base partagée
-- C'est le "contrat" entre la personne A (chat/auth) et B (news/envoi).
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- hash des mots de passe (bcrypt) + UUID

-- un seul fuseau invalide en base fait planter l'envoi de B pour tout le monde
CREATE FUNCTION is_valid_timezone(tz TEXT) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = tz)
$$;

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
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- un email avec un retour à la ligne peut rediriger la newsletter (ex. "\r\nBcc: ...")
    CONSTRAINT users_email_valid CHECK (
        length(email) <= 254
        AND email ~ '^[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$')
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
-- Étape en cours de l'inscription / connexion guidée (A)
-- On n'y stocke jamais le mot de passe.
-- ---------------------------------------------------------------------
CREATE TABLE auth_pending (
    chat_session_id TEXT PRIMARY KEY,
    step            TEXT NOT NULL CHECK (step IN ('register_email', 'register_consent', 'register_password',
                                                  'login_email', 'login_password')),
    email           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Préférences de newsletter (B)
-- ---------------------------------------------------------------------
CREATE TABLE preferences (
    user_id          UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    interests        TEXT[] NOT NULL DEFAULT '{}',
    send_hour        SMALLINT NOT NULL DEFAULT 8 CHECK (send_hour BETWEEN 0 AND 23),
    send_days        SMALLINT[] NOT NULL DEFAULT '{1,2,3,4,5,6,7}',
    timezone         TEXT NOT NULL DEFAULT 'Europe/Paris',
    language         TEXT NOT NULL DEFAULT 'fr',
    max_articles     SMALLINT NOT NULL DEFAULT 5 CHECK (max_articles BETWEEN 1 AND 20),
    is_active        BOOLEAN NOT NULL DEFAULT true,
    last_sent_at     TIMESTAMPTZ,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- ton et format de la newsletter, sources que l'utilisateur ne veut plus
    tone             TEXT NOT NULL DEFAULT 'neutre'
                     CHECK (tone IN ('neutre', 'decontracte', 'formel', 'humoristique')),
    format           TEXT NOT NULL DEFAULT 'resume'
                     CHECK (format IN ('titres', 'resume', 'detaille')),
    excluded_sources TEXT[] NOT NULL DEFAULT '{}'
                     CHECK (cardinality(excluded_sources) <= 10),
    -- RGPD : date de désinscription, remplie par le trigger plus bas
    unsubscribed_at  TIMESTAMPTZ,

    CONSTRAINT preferences_timezone_valid CHECK (is_valid_timezone(timezone)),
    CONSTRAINT preferences_send_days_valid
        CHECK (send_days <@ ARRAY[1,2,3,4,5,6,7]::smallint[] AND cardinality(send_days) >= 1)
);

-- unsubscribed_at se remplit tout seul (lien de l'email ou pause dans le chat)
-- et se vide si l'utilisateur se réabonne
CREATE FUNCTION set_unsubscribed_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.is_active THEN
        NEW.unsubscribed_at := NULL;
    ELSIF OLD.is_active THEN
        NEW.unsubscribed_at := now();
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER preferences_unsubscribed_at BEFORE UPDATE OF is_active ON preferences
    FOR EACH ROW EXECUTE FUNCTION set_unsubscribed_at();

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
-- Retours des utilisateurs sur leurs newsletters (A)
-- Texte libre : si on le donne à l'IA, c'est une donnée, pas une consigne.
-- ---------------------------------------------------------------------
CREATE TABLE feedback (
    id         BIGSERIAL PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message    TEXT NOT NULL CHECK (length(message) BETWEEN 1 AND 1000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_feedback_user ON feedback (user_id, created_at);

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
-- Rétention RGPD : appelée chaque nuit par le workflow [Commun] Maintenance RGPD
-- ---------------------------------------------------------------------
CREATE FUNCTION persona_cleanup() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
    -- comptes désabonnés depuis plus de 6 mois : supprimés en entier (CASCADE)
    WITH gone AS (
        DELETE FROM users
        WHERE id IN (SELECT user_id FROM preferences
                     WHERE NOT is_active AND unsubscribed_at < now() - INTERVAL '6 months')
        RETURNING id
    )
    INSERT INTO audit_log (event, user_id, details)
    SELECT 'account_deleted', id, '{"raison": "désabonné depuis plus de 6 mois"}'::jsonb FROM gone;

    DELETE FROM sessions         WHERE expires_at < now();
    DELETE FROM articles         WHERE fetched_at < now() - INTERVAL '30 days';
    DELETE FROM sent_newsletters WHERE sent_at    < now() - INTERVAL '6 months';
    DELETE FROM audit_log        WHERE created_at < now() - INTERVAL '1 year';
    DELETE FROM feedback         WHERE created_at < now() - INTERVAL '1 year';
    DELETE FROM auth_pending     WHERE created_at < now() - INTERVAL '1 hour';
$$;
GRANT EXECUTE ON FUNCTION persona_cleanup() TO persona_app;
