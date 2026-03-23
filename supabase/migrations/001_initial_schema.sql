-- CafePulse Phase 2: Multi-user schema
-- Run this in Supabase Dashboard → SQL Editor

-- =============================================================================
-- TABLES
-- =============================================================================

-- Sessions: one per cafe visit per user
CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
    cafe_name TEXT NOT NULL,
    location TEXT,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at TIMESTAMPTZ,
    tags TEXT[] DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Audio samples: one every 5 seconds during a session
CREATE TABLE audio_samples (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    timestamp TIMESTAMPTZ NOT NULL,
    overall_db REAL NOT NULL,
    music_band_db REAL NOT NULL,
    voice_band_db REAL NOT NULL,
    peak_db REAL NOT NULL,
    spectral_flatness REAL NOT NULL DEFAULT 0,
    self_talk_detected BOOLEAN NOT NULL DEFAULT false,
    voice_band_variance REAL NOT NULL DEFAULT -120,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Crowd estimates: manual user input every ~15 minutes
CREATE TABLE crowd_estimates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    timestamp TIMESTAMPTZ NOT NULL,
    fullness TEXT NOT NULL CHECK (fullness IN ('empty', 'quarter', 'half', 'three_quarters', 'full')),
    people_count INTEGER,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- =============================================================================
-- INDEXES
-- =============================================================================

CREATE INDEX idx_audio_samples_session_ts ON audio_samples(session_id, timestamp);
CREATE INDEX idx_crowd_estimates_session_ts ON crowd_estimates(session_id, timestamp);
CREATE INDEX idx_sessions_user ON sessions(user_id);

-- =============================================================================
-- ROW LEVEL SECURITY
-- All data is visible to all authenticated users (collaborative science).
-- Privacy note: users see each other's audio levels, locations, and tags.
-- Write access restricted to own data only.
-- =============================================================================

ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE audio_samples ENABLE ROW LEVEL SECURITY;
ALTER TABLE crowd_estimates ENABLE ROW LEVEL SECURITY;

-- Read: everyone sees everything
CREATE POLICY "read_sessions" ON sessions
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "read_audio_samples" ON audio_samples
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "read_crowd_estimates" ON crowd_estimates
    FOR SELECT TO authenticated USING (true);

-- Write sessions: only your own
CREATE POLICY "insert_sessions" ON sessions
    FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "update_sessions" ON sessions
    FOR UPDATE TO authenticated USING (user_id = auth.uid());
CREATE POLICY "delete_sessions" ON sessions
    FOR DELETE TO authenticated USING (user_id = auth.uid());

-- Write audio_samples: only for your own sessions
CREATE POLICY "insert_audio_samples" ON audio_samples
    FOR INSERT TO authenticated
    WITH CHECK (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));
CREATE POLICY "update_audio_samples" ON audio_samples
    FOR UPDATE TO authenticated
    USING (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));
CREATE POLICY "delete_audio_samples" ON audio_samples
    FOR DELETE TO authenticated
    USING (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));

-- Write crowd_estimates: only for your own sessions
CREATE POLICY "insert_crowd_estimates" ON crowd_estimates
    FOR INSERT TO authenticated
    WITH CHECK (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));
CREATE POLICY "update_crowd_estimates" ON crowd_estimates
    FOR UPDATE TO authenticated
    USING (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));
CREATE POLICY "delete_crowd_estimates" ON crowd_estimates
    FOR DELETE TO authenticated
    USING (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));
