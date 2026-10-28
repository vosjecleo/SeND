-- SeND media accounting, PostgreSQL only. Run inside one transaction.
-- No existing media, events, keys or users are changed by this migration.
CREATE TABLE IF NOT EXISTS send_storage_policy (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    default_bytes BIGINT NOT NULL CHECK (default_bytes > 0),
    enforce_all BOOLEAN NOT NULL DEFAULT TRUE,
    classification_since BIGINT NOT NULL DEFAULT (EXTRACT(EPOCH FROM clock_timestamp()) * 1000)::BIGINT
);
ALTER TABLE send_storage_policy ADD COLUMN IF NOT EXISTS classification_since BIGINT
    NOT NULL DEFAULT (EXTRACT(EPOCH FROM clock_timestamp()) * 1000)::BIGINT;
ALTER TABLE send_storage_policy ADD COLUMN IF NOT EXISTS enforce_all BOOLEAN NOT NULL DEFAULT TRUE;
INSERT INTO send_storage_policy(id,default_bytes) VALUES (1, 12884901888) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS send_storage_limits (
    user_id TEXT PRIMARY KEY,
    quota_bytes BIGINT NOT NULL CHECK (quota_bytes > 0)
);
CREATE TABLE IF NOT EXISTS send_storage_labels (
    media_id TEXT PRIMARY KEY, owner TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('images','videos','gifs','audio','other')),
    source TEXT NOT NULL CHECK (source IN ('upload','klipy','asset')),
    protected BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS send_storage_labels_owner ON send_storage_labels(owner);
CREATE TABLE IF NOT EXISTS send_storage_prune_jobs (
    token_hash TEXT PRIMARY KEY, owner TEXT NOT NULL,
    media_ids TEXT NOT NULL, expires BIGINT NOT NULL
);

CREATE OR REPLACE FUNCTION send_check_media_quota() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE allowance BIGINT; used BIGINT;
BEGIN
    IF NEW.user_id IS NULL OR NEW.media_length IS NULL OR NEW.url_cache IS NOT NULL THEN
        RETURN NEW;
    END IF;
    IF NOT (SELECT enforce_all FROM send_storage_policy WHERE id=1)
       AND NOT EXISTS (SELECT 1 FROM send_storage_limits WHERE user_id=NEW.user_id) THEN
        RETURN NEW;
    END IF;
    -- Serialize admission for this owner across all Synapse workers. The sum
    -- runs after the lock, in the same transaction as the admitted media row.
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.user_id, 531853));
    SELECT COALESCE((SELECT quota_bytes FROM send_storage_limits WHERE user_id=NEW.user_id),
                   (SELECT default_bytes FROM send_storage_policy WHERE id=1)) INTO allowance;
    IF allowance IS NULL THEN
        RAISE EXCEPTION 'SeND media policy is missing';
    END IF;
    SELECT COALESCE(SUM(media_length),0) INTO used FROM local_media_repository
      WHERE user_id=NEW.user_id AND media_id<>NEW.media_id AND url_cache IS NULL;
    -- Allow metadata-only changes to existing over-quota accounts. Never
    -- remove existing uploads to bring an account below its allowance.
    IF TG_OP='UPDATE' AND OLD.user_id=NEW.user_id AND OLD.media_length IS NOT NULL
       AND NEW.media_length<=OLD.media_length THEN RETURN NEW; END IF;
    IF used+NEW.media_length>allowance THEN
        RAISE EXCEPTION 'SeND media allowance exceeded'
          USING ERRCODE='23514', CONSTRAINT='send_storage_quota';
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS send_storage_quota ON local_media_repository;
CREATE TRIGGER send_storage_quota BEFORE INSERT OR UPDATE ON local_media_repository
    FOR EACH ROW EXECUTE FUNCTION send_check_media_quota();
