# CafePulse Phase 2 — Supabase Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add multi-user Supabase sync to the CafePulse menu bar app — magic link auth, batch upload every 2 minutes, offline-first.

**Architecture:** URLSession-based REST client talking to Supabase PostgREST API. SyncManager batches unsynced records. Local JSON store remains source of truth.

**Tech Stack:** Swift 5.9+, URLSession, Keychain, Supabase PostgREST API

**Spec:** `docs/superpowers/specs/2026-03-23-phase2-supabase-sync-design.md`

---

## File Structure

```
CafePulse/Sources/
  Storage/
    SupabaseClient.swift      # NEW — REST client, auth, JWT management
    SyncManager.swift          # NEW — batch sync timer, retry logic
    KeychainHelper.swift       # NEW — simple Keychain wrapper for JWT
    LocalStore.swift           # MODIFY — add syncedAt tracking
    CSVExporter.swift          # MODIFY — add new columns
  Models/
    Session.swift              # MODIFY — add syncedAt, userId
    AudioSample.swift          # MODIFY — add syncedAt
    CrowdEstimate.swift        # MODIFY — add syncedAt
    AppSettings.swift          # MODIFY — add auth state, supabase config
  App/
    AppModel.swift             # MODIFY — wire SyncManager, auth flow
    CafePulseApp.swift         # MODIFY — handle deep link callback
  Views/
    MainWindowView.swift       # MODIFY — add auth section
    MenuBarContentView.swift   # MODIFY — sync status indicator
    AuthView.swift             # NEW — email input + magic link status
  Config/
    Info.plist                 # MODIFY — add URL scheme
    SupabaseConfig.swift       # NEW — URL + key constants
supabase/
  migrations/
    001_initial_schema.sql     # NEW — tables, indexes, RLS
```

---

### Task 1: Database Schema

**Files:**
- Create: `supabase/migrations/001_initial_schema.sql`

- [ ] **Step 1: Write the migration SQL**

```sql
-- Sessions table
CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    cafe_name TEXT NOT NULL,
    location TEXT,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at TIMESTAMPTZ,
    tags TEXT[] DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Audio samples table
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

-- Crowd estimates table
CREATE TABLE crowd_estimates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    timestamp TIMESTAMPTZ NOT NULL,
    fullness TEXT NOT NULL CHECK (fullness IN ('empty','quarter','half','three_quarters','full')),
    people_count INTEGER,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX idx_audio_samples_session_ts ON audio_samples(session_id, timestamp);
CREATE INDEX idx_crowd_estimates_session_ts ON crowd_estimates(session_id, timestamp);
CREATE INDEX idx_sessions_user ON sessions(user_id);

-- RLS
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE audio_samples ENABLE ROW LEVEL SECURITY;
ALTER TABLE crowd_estimates ENABLE ROW LEVEL SECURITY;

-- Everyone can read all data (collaborative science)
CREATE POLICY "All authenticated users can read sessions"
    ON sessions FOR SELECT TO authenticated USING (true);
CREATE POLICY "All authenticated users can read audio_samples"
    ON audio_samples FOR SELECT TO authenticated USING (true);
CREATE POLICY "All authenticated users can read crowd_estimates"
    ON crowd_estimates FOR SELECT TO authenticated USING (true);

-- Users can only write their own data
CREATE POLICY "Users can insert own sessions"
    ON sessions FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "Users can update own sessions"
    ON sessions FOR UPDATE TO authenticated USING (user_id = auth.uid());
CREATE POLICY "Users can delete own sessions"
    ON sessions FOR DELETE TO authenticated USING (user_id = auth.uid());

CREATE POLICY "Users can insert samples for own sessions"
    ON audio_samples FOR INSERT TO authenticated
    WITH CHECK (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));
CREATE POLICY "Users can update samples for own sessions"
    ON audio_samples FOR UPDATE TO authenticated
    USING (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));
CREATE POLICY "Users can delete samples for own sessions"
    ON audio_samples FOR DELETE TO authenticated
    USING (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));

CREATE POLICY "Users can insert estimates for own sessions"
    ON crowd_estimates FOR INSERT TO authenticated
    WITH CHECK (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));
CREATE POLICY "Users can update estimates for own sessions"
    ON crowd_estimates FOR UPDATE TO authenticated
    USING (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));
CREATE POLICY "Users can delete estimates for own sessions"
    ON crowd_estimates FOR DELETE TO authenticated
    USING (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));
```

- [ ] **Step 2: Run in Supabase SQL Editor**

Go to Supabase Dashboard → SQL Editor → paste and run.
Expected: All tables, indexes, and policies created.

- [ ] **Step 3: Verify tables exist**

Run: `curl -s -H "apikey: $ANON_KEY" -H "Authorization: Bearer $JWT" $SUPABASE_URL/rest/v1/sessions`
Expected: Empty array `[]`

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/001_initial_schema.sql
git commit -m "Add Supabase schema migration for multi-user sync"
```

---

### Task 2: Supabase Config + Keychain Helper

**Files:**
- Create: `CafePulse/Sources/Config/SupabaseConfig.swift`
- Create: `CafePulse/Sources/Storage/KeychainHelper.swift`

- [ ] **Step 1: Create SupabaseConfig with URL and key constants**

Hardcoded constants (this is a compiled app, not a web frontend):
```swift
enum SupabaseConfig {
    static let url = URL(string: "https://mbaqltknevqygpvuystl.supabase.co")!
    static let publishableKey = "sb_publishable__A9e9KT8y8Vjb3cQBkd__A_vgjGwF62"
    static let callbackScheme = "cafepulse"
}
```

- [ ] **Step 2: Create KeychainHelper for JWT storage**

Simple wrapper: `save(key:data:)`, `load(key:)`, `delete(key:)` using Security framework.

- [ ] **Step 3: Build and verify**

Run: `xcodegen generate && xcodebuild ...`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add CafePulse/Sources/Config/SupabaseConfig.swift CafePulse/Sources/Storage/KeychainHelper.swift
git commit -m "Add Supabase config constants and Keychain helper"
```

---

### Task 3: SupabaseClient — Auth + REST

**Files:**
- Create: `CafePulse/Sources/Storage/SupabaseClient.swift`

- [ ] **Step 1: Build the REST client**

URLSession-based client with:
- `signIn(email:)` — POST to `/auth/v1/magiclink`
- `verifyOTP(email:token:)` — POST to `/auth/v1/verify` (for deep link token)
- `refreshToken()` — POST to `/auth/v1/token?grant_type=refresh_token`
- `signOut()` — clear JWT from Keychain
- `currentUserId` — decode JWT to extract user ID
- Common headers: `apikey`, `Authorization: Bearer`, `Content-Type: application/json`

- [ ] **Step 2: Add CRUD methods**

- `uploadSession(_ session:)` — POST to `/rest/v1/sessions`
- `uploadAudioSamples(_ samples:)` — POST to `/rest/v1/audio_samples` (batch array)
- `uploadCrowdEstimate(_ estimate:)` — POST to `/rest/v1/crowd_estimates`
- Use `Prefer: return=minimal` header for inserts
- JSONEncoder with `.convertToSnakeCase` and `.iso8601` date strategy

- [ ] **Step 3: Build and verify**

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add CafePulse/Sources/Storage/SupabaseClient.swift
git commit -m "Add SupabaseClient with auth and PostgREST methods"
```

---

### Task 4: Add syncedAt to Models

**Files:**
- Modify: `CafePulse/Sources/Models/Session.swift`
- Modify: `CafePulse/Sources/Models/AudioSample.swift`
- Modify: `CafePulse/Sources/Models/CrowdEstimate.swift`

- [ ] **Step 1: Add `syncedAt: Date?` to all three models**

Default to nil. Add to init with default nil. Keep Codable conformance.

- [ ] **Step 2: Add `userId: String?` to Session**

Set when creating a session while authenticated.

- [ ] **Step 3: Build and verify**

Expected: BUILD SUCCEEDED (existing code uses default params, so no breakage)

- [ ] **Step 4: Commit**

```bash
git add CafePulse/Sources/Models/
git commit -m "Add syncedAt tracking and userId to models"
```

---

### Task 5: SyncManager

**Files:**
- Create: `CafePulse/Sources/Storage/SyncManager.swift`

- [ ] **Step 1: Build SyncManager**

```swift
@MainActor
final class SyncManager: ObservableObject {
    @Published var syncState: SyncState = .idle  // idle, syncing, error(String), offline

    private let client: SupabaseClient
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 120  // 2 minutes

    func startSync()    // start 2-min timer
    func stopSync()     // stop timer, final flush
    func syncNow()      // immediate sync of unsynced records
}
```

Logic per sync tick:
1. Get unsynced sessions → upload → mark synced
2. Get unsynced audio samples → batch upload → mark synced
3. Get unsynced crowd estimates → upload → mark synced
4. If any upload fails, set state to .error, retry next tick

- [ ] **Step 2: Build and verify**

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add CafePulse/Sources/Storage/SyncManager.swift
git commit -m "Add SyncManager with 2-minute batch sync"
```

---

### Task 6: Auth UI

**Files:**
- Create: `CafePulse/Sources/Views/AuthView.swift`
- Modify: `CafePulse/Sources/Views/MainWindowView.swift`
- Modify: `CafePulse/Sources/App/CafePulseApp.swift`
- Modify: `CafePulse/Config/Info.plist`

- [ ] **Step 1: Create AuthView**

Simple view: email text field + "Send Magic Link" button + status text.
After sending: "Check your email for the login link."

- [ ] **Step 2: Register URL scheme in Info.plist**

Add `CFBundleURLTypes` with scheme `cafepulse`.

- [ ] **Step 3: Handle deep link in CafePulseApp**

Use `.onOpenURL { url in }` to capture `cafepulse://auth/callback#access_token=...`
Parse the token, pass to SupabaseClient.

- [ ] **Step 4: Add auth gate to MainWindowView**

If not logged in → show AuthView. If logged in → show current content.

- [ ] **Step 5: Build and test**

Expected: BUILD SUCCEEDED. Can enter email and see "check email" message.

- [ ] **Step 6: Commit**

```bash
git add CafePulse/Sources/Views/AuthView.swift CafePulse/Sources/Views/MainWindowView.swift CafePulse/Sources/App/CafePulseApp.swift CafePulse/Config/Info.plist
git commit -m "Add magic link auth flow with deep link callback"
```

---

### Task 7: Wire Everything Together

**Files:**
- Modify: `CafePulse/Sources/App/AppModel.swift`
- Modify: `CafePulse/Sources/Views/MenuBarContentView.swift`

- [ ] **Step 1: Add SyncManager to AppModel**

- Create SyncManager in init
- Start sync when session starts (if authenticated)
- Stop sync + final flush when session ends
- Pass auth state through to views

- [ ] **Step 2: Add sync status to menu bar popup**

Show indicator: synced (checkmark), syncing (arrow), offline (cloud.slash), error (exclamation).

- [ ] **Step 3: Update session creation to include userId**

When creating a Session, set `userId` from SupabaseClient.currentUserId.

- [ ] **Step 4: Build, test end-to-end**

1. Launch app → sign in with email → receive magic link → click → authenticated
2. Start session → audio samples collect → every 2 min batch uploads to Supabase
3. Check Supabase dashboard → Table Editor → verify rows appear
4. End session → final flush → all data synced

- [ ] **Step 5: Commit**

```bash
git add CafePulse/Sources/App/AppModel.swift CafePulse/Sources/Views/MenuBarContentView.swift
git commit -m "Wire SyncManager into AppModel, add sync status to menu bar"
```

---

### Task 8: Run Schema + End-to-End Test

- [ ] **Step 1: Run migration in Supabase SQL Editor**
- [ ] **Step 2: Build and launch app**
- [ ] **Step 3: Sign in with email, verify magic link flow**
- [ ] **Step 4: Start session, wait for 2-minute sync**
- [ ] **Step 5: Verify data in Supabase Table Editor**
- [ ] **Step 6: Push to git**

```bash
git push origin main
```
