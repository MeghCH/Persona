-- Proposition de A pour le schéma, à valider avec B avant de la mettre dans 02-schema.sql.
-- Pas lancé au démarrage : scripts/setup.sh l'applique.

-- ton et format de la newsletter, sources que l'utilisateur ne veut plus
ALTER TABLE preferences
    ADD COLUMN tone TEXT NOT NULL DEFAULT 'neutre'
        CHECK (tone IN ('neutre', 'decontracte', 'formel', 'humoristique')),
    ADD COLUMN format TEXT NOT NULL DEFAULT 'resume'
        CHECK (format IN ('titres', 'resume', 'detaille')),
    ADD COLUMN excluded_sources TEXT[] NOT NULL DEFAULT '{}'
        CHECK (cardinality(excluded_sources) <= 10);

-- retours des utilisateurs sur leurs newsletters
-- (texte libre : si on le donne à l'IA, c'est une donnée, pas une consigne)
CREATE TABLE feedback (
    id         BIGSERIAL PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message    TEXT NOT NULL CHECK (length(message) BETWEEN 1 AND 1000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_feedback_user ON feedback (user_id, created_at);

GRANT SELECT, INSERT, UPDATE, DELETE ON feedback TO persona_app;
GRANT USAGE, SELECT ON SEQUENCE feedback_id_seq TO persona_app;

-- étape en cours de l'inscription / connexion guidée (jamais le mot de passe)
CREATE TABLE auth_pending (
    chat_session_id TEXT PRIMARY KEY,
    step            TEXT NOT NULL CHECK (step IN ('register_email', 'register_consent', 'register_password',
                                                  'login_email', 'login_password')),
    email           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON auth_pending TO persona_app;

-- un seul fuseau invalide en base fait planter l'envoi de B pour tout le monde
CREATE FUNCTION is_valid_timezone(tz TEXT) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = tz)
$$;

-- un email avec un retour à la ligne peut rediriger la newsletter (ex. "\r\nBcc: ...")
ALTER TABLE users
    ADD CONSTRAINT users_email_valid CHECK (
        length(email) <= 254
        AND email ~ '^[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$');

ALTER TABLE preferences
    ADD CONSTRAINT preferences_timezone_valid CHECK (is_valid_timezone(timezone)),
    ADD CONSTRAINT preferences_send_days_valid
        CHECK (send_days <@ ARRAY[1,2,3,4,5,6,7]::smallint[] AND cardinality(send_days) >= 1);

-- même nettoyage qu'avant, plus feedback et auth_pending
CREATE OR REPLACE FUNCTION persona_cleanup() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
    DELETE FROM sessions WHERE expires_at < now();
    DELETE FROM articles WHERE fetched_at < now() - INTERVAL '30 days';
    DELETE FROM sent_newsletters WHERE sent_at < now() - INTERVAL '6 months';
    DELETE FROM audit_log WHERE created_at < now() - INTERVAL '1 year';
    DELETE FROM feedback WHERE created_at < now() - INTERVAL '1 year';
    DELETE FROM auth_pending WHERE created_at < now() - INTERVAL '1 hour';
$$;
