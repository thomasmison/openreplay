\set previous_version 'v1.16.0-ee'
\set next_version 'v1.17.0-ee'
SELECT openreplay_version()                       AS current_version,
       openreplay_version() = :'previous_version' AS valid_previous,
       openreplay_version() = :'next_version'     AS is_next
\gset

\if :valid_previous
\echo valid previous DB version :'previous_version', starting DB upgrade to :'next_version'
BEGIN;
SELECT format($fn_def$
CREATE OR REPLACE FUNCTION openreplay_version()
    RETURNS text AS
$$
SELECT '%1$s'
$$ LANGUAGE sql IMMUTABLE;
$fn_def$, :'next_version')
\gexec

--

ALTER TABLE IF EXISTS public.sessions
    ADD COLUMN IF NOT EXISTS has_ut_test boolean DEFAULT FALSE;

-- !!! The following query takes a lot of time
CREATE INDEX IF NOT EXISTS sessions_session_id_has_ut_test_idx ON public.sessions (session_id, has_ut_test);

UPDATE public.sessions
SET has_ut_test= TRUE
WHERE session_id IN (SELECT session_id FROM public.ut_tests_signals);

ALTER TABLE IF EXISTS public.projects
    ADD COLUMN IF NOT EXISTS conditional_capture boolean DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS public.projects_conditions
(
    condition_id integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    project_id   integer      NOT NULL REFERENCES public.projects (project_id) ON DELETE CASCADE,
    name         varchar(255) NOT NULL,
    capture_rate integer      NOT NULL CHECK (capture_rate >= 0 AND capture_rate <= 100),
    filters      jsonb        NOT NULL DEFAULT '[]'::jsonb
);

CREATE TABLE IF NOT EXISTS public.tags
(
        tag_id               serial       NOT NULL PRIMARY KEY,
        name                 text         NOT NULL,
        project_id           integer      NOT NULL REFERENCES public.projects (project_id) ON DELETE CASCADE,
        selector             text         NOT NULL,
        ignore_click_rage    boolean      NOT NULL,
        ignore_dead_click    boolean      NOT NULL,
        deleted_at           timestamp without time zone NULL DEFAULT NULL
);
CREATE INDEX tags_project_id_idx ON public.tags (project_id);

CREATE TABLE IF NOT EXISTS events.tags
(
        session_id bigint  NOT NULL REFERENCES public.sessions (session_id) ON DELETE CASCADE,
        timestamp  bigint  NOT NULL,
        seq_index  integer NOT NULL,
        tag_id     integer  NOT NULL REFERENCES public.tags (tag_id) ON DELETE CASCADE,
        PRIMARY KEY (session_id, timestamp, seq_index)
);
CREATE INDEX IF NOT EXISTS tags_session_id_idx ON events.tags (session_id);
CREATE INDEX IF NOT EXISTS tags_timestamp_idx ON events.tags (timestamp);

COMMIT;

\elif :is_next
\echo new version detected :'next_version', nothing to do
\else
\warn skipping DB upgrade of :'next_version', expected previous version :'previous_version', found :'current_version'
\endif
