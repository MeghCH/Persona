-- =====================================================================
-- Persona - schéma de la base partagée
-- Seul fichier SQL du projet. Docker le lance à la création de la base,
-- et scripts/setup.sh le relance à chaque démarrage pour mettre à jour
-- une base existante (il ne recrée pas ce qui existe déjà).
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- hash des mots de passe (bcrypt) + UUID


CREATE OR REPLACE FUNCTION is_valid_timezone(tz TEXT) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = tz)
$$;

-- ---------------------------------------------------------------------
-- Utilisateurs
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
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
-- Sessions du chatbot
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sessions (
    chat_session_id  TEXT PRIMARY KEY,
    user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at       TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '2 hours'
);

-- ---------------------------------------------------------------------
-- Étape en cours de l'inscription / connexion guidée
-- On n'y stocke jamais le mot de passe en clair ni le code en clair :
-- seulement leurs hash (password_hash, otp_hash). Le compte n'est créé
-- qu'une fois le code reçu par email tapé dans le chat.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auth_pending (
    chat_session_id TEXT PRIMARY KEY,
    step            TEXT NOT NULL,
    email           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    password_hash   TEXT,
    otp_hash        TEXT,
    otp_attempts    INTEGER NOT NULL DEFAULT 0,
    otp_sent_count  INTEGER NOT NULL DEFAULT 0
);

-- Pour une base déjà créée : colonnes du code et nouvelle étape register_otp.
ALTER TABLE auth_pending ADD COLUMN IF NOT EXISTS password_hash  TEXT;
ALTER TABLE auth_pending ADD COLUMN IF NOT EXISTS otp_hash       TEXT;
ALTER TABLE auth_pending ADD COLUMN IF NOT EXISTS otp_attempts   INTEGER NOT NULL DEFAULT 0;
ALTER TABLE auth_pending ADD COLUMN IF NOT EXISTS otp_sent_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE auth_pending DROP CONSTRAINT IF EXISTS auth_pending_step_check;
ALTER TABLE auth_pending ADD CONSTRAINT auth_pending_step_check
    CHECK (step IN ('register_email', 'register_consent', 'register_password', 'register_otp',
                    'login_email', 'login_password'));

-- ---------------------------------------------------------------------
-- Préférences de newsletter
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS preferences (
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
    tone             TEXT NOT NULL DEFAULT 'neutre'
                     CHECK (tone IN ('neutre', 'decontracte', 'formel', 'humoristique')),
    format           TEXT NOT NULL DEFAULT 'resume'
                     CHECK (format IN ('titres', 'resume', 'detaille')),
    excluded_sources TEXT[] NOT NULL DEFAULT '{}'
                     CHECK (cardinality(excluded_sources) <= 10),
    unsubscribed_at  TIMESTAMPTZ,

    CONSTRAINT preferences_timezone_valid CHECK (is_valid_timezone(timezone)),
    CONSTRAINT preferences_send_days_valid
        CHECK (send_days <@ ARRAY[1,2,3,4,5,6,7]::smallint[] AND cardinality(send_days) >= 1)
);

-- unsubscribed_at se remplit tout seul (lien de l'email ou pause dans le chat)
-- et se vide si l'utilisateur se réabonne
CREATE OR REPLACE FUNCTION set_unsubscribed_at() RETURNS trigger
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

DROP TRIGGER IF EXISTS preferences_unsubscribed_at ON preferences;
CREATE TRIGGER preferences_unsubscribed_at BEFORE UPDATE OF is_active ON preferences
    FOR EACH ROW EXECUTE FUNCTION set_unsubscribed_at();

-- ---------------------------------------------------------------------
-- Articles collectés
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS articles (
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
CREATE INDEX IF NOT EXISTS idx_articles_fetched_at ON articles (fetched_at);
CREATE INDEX IF NOT EXISTS idx_articles_tags ON articles USING GIN (tags);

-- ---------------------------------------------------------------------
-- Historique des envois
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sent_newsletters (
    id           BIGSERIAL PRIMARY KEY,
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    article_ids  BIGINT[] NOT NULL,
    sent_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sent_user ON sent_newsletters (user_id, sent_at);

-- ---------------------------------------------------------------------
-- Retours des utilisateurs sur leurs newsletters
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS feedback (
    id         BIGSERIAL PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message    TEXT NOT NULL CHECK (length(message) BETWEEN 1 AND 1000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_feedback_user ON feedback (user_id, created_at);

-- ---------------------------------------------------------------------
-- Journal de sécurité
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log (
    id          BIGSERIAL PRIMARY KEY,
    event       TEXT NOT NULL,

    user_id     UUID,
    details     JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Messages envoyés à l'IA (Gemini)
-- Une ligne par message qui passe par l'IA. Elle sert à refuser les envois
-- trop rapides ou trop nombreux (voir docs/protection-deni-of-service.md).
-- On n'y stocke jamais le texte du message.
-- Quand un compte est supprimé, ses lignes restent jusqu'au nettoyage de nuit (user_id passe
-- à NULL) : sinon, supprimer son compte remettrait à zéro le comptage de la journée.
-- connecte garde le fait que le message venait d'un utilisateur connecté, même après la suppression.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS chat_ai_requests (
    id          BIGSERIAL PRIMARY KEY,
    session_id  TEXT NOT NULL,
    user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
    connecte    BOOLEAN NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Base créée avec la première version de la table (ON DELETE CASCADE, sans connecte).
-- Sur une base déjà à jour, ces lignes ne changent rien.
ALTER TABLE chat_ai_requests ADD COLUMN IF NOT EXISTS connecte BOOLEAN;
UPDATE chat_ai_requests SET connecte = (user_id IS NOT NULL) WHERE connecte IS NULL;
ALTER TABLE chat_ai_requests ALTER COLUMN connecte SET NOT NULL;
ALTER TABLE chat_ai_requests DROP CONSTRAINT IF EXISTS chat_ai_requests_user_id_fkey,
    ADD CONSTRAINT chat_ai_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS chat_ai_requests_created_at_idx ON chat_ai_requests (created_at);
CREATE INDEX IF NOT EXISTS chat_ai_requests_session_idx    ON chat_ai_requests (session_id, created_at);

-- Compte les messages déjà envoyés à l'IA et réserve la place du nouveau, en une seule fois.
-- Le verrou fait passer les messages un par un : sans lui, dix messages envoyés au même
-- moment lisent tous le même comptage et passent tous la limite.
-- Les comptages rendus ne comptent pas le nouveau message. S'il est refusé, le workflow
-- supprime sa réservation (reservation_id).
CREATE OR REPLACE FUNCTION reserver_appel_ia(p_session TEXT, p_user UUID)
RETURNS TABLE (reservation_id BIGINT, session_minute BIGINT, session_jour BIGINT,
               user_jour BIGINT, anonymes_jour BIGINT, total_jour BIGINT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
#variable_conflict use_column
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('chat_ai_requests'));

    RETURN QUERY
    WITH avant AS (
        SELECT
          count(*) FILTER (WHERE r.session_id = p_session AND r.created_at > now() - INTERVAL '1 minute') AS a,
          count(*) FILTER (WHERE r.session_id = p_session) AS b,
          count(*) FILTER (WHERE r.user_id = p_user) AS c,
          count(*) FILTER (WHERE NOT r.connecte) AS d,
          count(*) AS e
        FROM chat_ai_requests r
        WHERE r.created_at > now() - INTERVAL '1 day'
    ), nouveau AS (
        INSERT INTO chat_ai_requests (session_id, user_id, connecte) VALUES (p_session, p_user, p_user IS NOT NULL)
        RETURNING chat_ai_requests.id
    )
    SELECT nouveau.id, avant.a, avant.b, avant.c, avant.d, avant.e FROM nouveau, avant;
END
$$;

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
CREATE OR REPLACE FUNCTION persona_cleanup() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
    -- comptes désabonnés depuis plus de 6 mois
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
    DELETE FROM chat_ai_requests WHERE created_at < now() - INTERVAL '2 days';
$$;
GRANT EXECUTE ON FUNCTION persona_cleanup() TO persona_app;
GRANT EXECUTE ON FUNCTION reserver_appel_ia(TEXT, UUID) TO persona_app;
