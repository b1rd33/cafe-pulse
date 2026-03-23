# CafePulse Phase 2 — Supabase Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add multi-user Supabase sync to the CafePulse menu bar app — magic link auth, batch upload every 2 minutes, offline-first.

**Architecture:** URLSession-based REST client talking to Supabase PostgREST API. AppModel is the single writer for local state. SyncManager reads unsynced records through AppModel and triggers upserts. Local JSON store remains source of truth.

**Tech Stack:** Swift 5.9+, URLSession, Keychain (Security framework), Supabase PostgREST + GoTrue Auth API

**Spec:** `docs/superpowers/specs/2026-03-23-phase2-supabase-sync-design.md`

**Review fixes applied:** 10 issues from Codex review (6 high, 4 medium) — see "Design Decisions" section.

---

## Design Decisions (from Codex review)

1. **Upsert, not insert** — All uploads use `POST` with `Prefer: resolution=merge-duplicates` (Supabase upsert). Idempotent: retries after timeout won't cause duplicate-key errors.
2. **Session re-sync on end** — Sessions are upserted on creation AND on end (to sync `ended_at`). `syncedAt` alone is insufficient for mutable records.
3. **Correct auth flow** — Use `/auth/v1/otp` (signInWithOTP) to send magic link. Parse `access_token` + `refresh_token` from deep link callback. Store both in Keychain.
4. **Store access + refresh tokens** — Keychain stores: access token, refresh token, expiry timestamp. Auto-refresh before expiry. Without refresh token, background sync silently dies.
5. **Sync runs until queue is empty** — SyncManager starts on app launch (if authenticated + unsynced records exist), not just during active sessions. Handles offline-at-session-end case.
6. **AppModel is the single writer** — SyncManager does NOT write to LocalStore directly. It calls `AppModel.markSynced(ids:)` which updates in-memory state and persists. Prevents race conditions with incoming audio samples.
7. **Auth required everywhere** — Both menu bar "Start Session" and main window gate on auth. Can still use app locally without auth, but sync requires login.
8. **Auth state lives in Keychain only** — NOT in AppSettings/AppSnapshot. SupabaseClient checks Keychain on init. AppSettings stays for user preferences only.
9. **No `userId` in client model** — SQL uses `user_id DEFAULT auth.uid()`. Client omits `user_id` from upload payload. Supabase fills it from the JWT automatically.
10. **Supabase dashboard config required** — Task 1 includes configuring redirect URLs in Supabase Auth settings. Task 6 includes sign-out UI.

---

## File Structure

```
CafePulse/Sources/
  Storage/
    SupabaseClient.swift      # NEW — REST client, auth (OTP + token refresh), upsert CRUD
    SyncManager.swift          # NEW — batch sync timer, reads through AppModel, retry logic
    KeychainHelper.swift       # NEW — Keychain wrapper for access token, refresh token, expiry
    LocalStore.swift           # MODIFY — no changes needed (AppModel remains single writer)
  Models/
    Session.swift              # MODIFY — add syncedAt: Date?
    AudioSample.swift          # MODIFY — add syncedAt: Date?
    CrowdEstimate.swift        # MODIFY — add syncedAt: Date?
    AppSettings.swift          # NO CHANGE — auth state stays in Keychain, not here
  App/
    AppModel.swift             # MODIFY — wire SyncManager, add markSynced(), auth state, gate sessions on auth
    CafePulseApp.swift         # MODIFY — handle deep link callback, start sync on launch
  Views/
    MainWindowView.swift       # MODIFY — add auth gate + sign-out button
    MenuBarContentView.swift   # MODIFY — sync status indicator, gate Start Session on auth
    AuthView.swift             # NEW — email input + magic link status + resend
  Config/
    Info.plist                 # MODIFY — add URL scheme (cafepulse://)
    SupabaseConfig.swift       # NEW — URL + publishable key constants
supabase/
  migrations/
    001_initial_schema.sql     # NEW — tables, indexes, RLS
```

---

### Task 1: Database Schema + Supabase Dashboard Config

**Files:**
- Create: `supabase/migrations/001_initial_schema.sql`

- [ ] **Step 1: Write the migration SQL**

```sql
-- Sessions table (user_id defaults to auth.uid() — client omits it)
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

-- RLS (NOTE: all data is visible to all authenticated users — this is collaborative science)
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE audio_samples ENABLE ROW LEVEL SECURITY;
ALTER TABLE crowd_estimates ENABLE ROW LEVEL SECURITY;

-- Read: everyone sees everything
CREATE POLICY "read_sessions" ON sessions FOR SELECT TO authenticated USING (true);
CREATE POLICY "read_audio_samples" ON audio_samples FOR SELECT TO authenticated USING (true);
CREATE POLICY "read_crowd_estimates" ON crowd_estimates FOR SELECT TO authenticated USING (true);

-- Write: only your own data
CREATE POLICY "insert_sessions" ON sessions FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());
CREATE POLICY "update_sessions" ON sessions FOR UPDATE TO authenticated
    USING (user_id = auth.uid());
CREATE POLICY "delete_sessions" ON sessions FOR DELETE TO authenticated
    USING (user_id = auth.uid());

CREATE POLICY "insert_audio_samples" ON audio_samples FOR INSERT TO authenticated
    WITH CHECK (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));
CREATE POLICY "update_audio_samples" ON audio_samples FOR UPDATE TO authenticated
    USING (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));
CREATE POLICY "delete_audio_samples" ON audio_samples FOR DELETE TO authenticated
    USING (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));

CREATE POLICY "insert_crowd_estimates" ON crowd_estimates FOR INSERT TO authenticated
    WITH CHECK (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));
CREATE POLICY "update_crowd_estimates" ON crowd_estimates FOR UPDATE TO authenticated
    USING (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));
CREATE POLICY "delete_crowd_estimates" ON crowd_estimates FOR DELETE TO authenticated
    USING (session_id IN (SELECT id FROM sessions WHERE user_id = auth.uid()));
```

- [ ] **Step 2: Run in Supabase SQL Editor**

Dashboard → SQL Editor → paste and run.
Expected: All tables, indexes, and policies created.

- [ ] **Step 3: Configure Supabase Auth redirect URLs**

Dashboard → Authentication → URL Configuration:
- Site URL: `cafepulse://auth/callback`
- Redirect URLs: add `cafepulse://auth/callback`

This is REQUIRED for magic link deep links to work with the native app.

- [ ] **Step 4: Verify tables exist**

Dashboard → Table Editor → confirm sessions, audio_samples, crowd_estimates appear.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/001_initial_schema.sql
git commit -m "Add Supabase schema migration with RLS for multi-user sync"
```

---

### Task 2: Supabase Config + Keychain Helper

**Files:**
- Create: `CafePulse/Sources/Config/SupabaseConfig.swift`
- Create: `CafePulse/Sources/Storage/KeychainHelper.swift`

- [ ] **Step 1: Create SupabaseConfig**

```swift
enum SupabaseConfig {
    static let url = URL(string: "https://mbaqltknevqygpvuystl.supabase.co")!
    static let publishableKey = "sb_publishable__A9e9KT8y8Vjb3cQBkd__A_vgjGwF62"
    static let callbackScheme = "cafepulse"
    static let callbackURL = "cafepulse://auth/callback"
}
```

- [ ] **Step 2: Create KeychainHelper**

Store THREE items (not just JWT):
```swift
struct KeychainHelper {
    static func save(key: String, data: Data) -> Bool
    static func load(key: String) -> Data?
    static func delete(key: String)
}

// Keys:
// "com.cafepulse.accessToken"  — JWT for API calls
// "com.cafepulse.refreshToken" — for auto-refresh
// "com.cafepulse.tokenExpiry"  — Date encoded as Data, for proactive refresh
```

Uses Security framework (`SecItemAdd`, `SecItemCopyMatching`, `SecItemDelete`).

- [ ] **Step 3: Build and verify**

Run: `xcodegen generate && xcodebuild ...`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add CafePulse/Sources/Config/SupabaseConfig.swift CafePulse/Sources/Storage/KeychainHelper.swift
git commit -m "Add Supabase config constants and Keychain helper for token storage"
```

---

### Task 3: SupabaseClient — Auth + REST

**Files:**
- Create: `CafePulse/Sources/Storage/SupabaseClient.swift`

- [ ] **Step 1: Build auth methods**

Use correct Supabase GoTrue endpoints:
- `sendMagicLink(email:)` — POST to `/auth/v1/otp` with `{"email": "...", "data": {}, "create_user": true}`
  - Include `redirectTo` pointing to `cafepulse://auth/callback`
- `handleCallback(url:)` — Parse URL fragment for `access_token`, `refresh_token`, `expires_in`
  - Store all three in Keychain
- `refreshTokenIfNeeded()` — Check expiry, POST to `/auth/v1/token?grant_type=refresh_token`
  - Send `{"refresh_token": "..."}`, update Keychain with new tokens
- `signOut()` — Clear all three Keychain entries
- `isAuthenticated: Bool` — true if access token exists in Keychain
- `currentAccessToken: String?` — load from Keychain (refresh first if expired)
- Common headers: `apikey: <publishableKey>`, `Authorization: Bearer <accessToken>`, `Content-Type: application/json`

- [ ] **Step 2: Build CRUD methods with upsert**

All uploads use upsert (idempotent — safe for retries):
- `upsertSession(_ session:)` — POST to `/rest/v1/sessions` with headers:
  - `Prefer: resolution=merge-duplicates,return=minimal`
  - Body: JSON with id, cafe_name, location, started_at, ended_at, tags (NO user_id — DB defaults it)
- `upsertAudioSamples(_ samples:)` — POST to `/rest/v1/audio_samples` (batch array)
  - Same Prefer header
- `upsertCrowdEstimates(_ estimates:)` — POST to `/rest/v1/crowd_estimates` (batch array)
  - Same Prefer header
- JSONEncoder: `.convertToSnakeCase`, `.iso8601` date strategy
- Handle HTTP 409 (conflict) as success (already exists)

- [ ] **Step 3: Build and verify**

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add CafePulse/Sources/Storage/SupabaseClient.swift
git commit -m "Add SupabaseClient with OTP auth and idempotent upsert CRUD"
```

---

### Task 4: Add syncedAt to Models

**Files:**
- Modify: `CafePulse/Sources/Models/Session.swift`
- Modify: `CafePulse/Sources/Models/AudioSample.swift`
- Modify: `CafePulse/Sources/Models/CrowdEstimate.swift`

- [ ] **Step 1: Add `syncedAt: Date?` to all three models**

Default to nil in init. Keep Codable conformance.
Do NOT add `userId` to Session — the DB handles it via `DEFAULT auth.uid()`.

- [ ] **Step 2: Add `markSynced()` methods to AppModel**

```swift
// AppModel.swift additions:
func markSessionSynced(id: UUID) {
    if let idx = sessions.firstIndex(where: { $0.id == id }) {
        sessions[idx].syncedAt = .now
    }
    persistCurrentState()
}

func markAudioSamplesSynced(ids: Set<UUID>) {
    for i in audioSamples.indices where ids.contains(audioSamples[i].id) {
        audioSamples[i].syncedAt = .now
    }
    persistCurrentState()
}

func markCrowdEstimatesSynced(ids: Set<UUID>) {
    for i in crowdEstimates.indices where ids.contains(crowdEstimates[i].id) {
        crowdEstimates[i].syncedAt = .now
    }
    persistCurrentState()
}

// Query helpers for SyncManager:
var unsyncedSessions: [Session] {
    sessions.filter { $0.syncedAt == nil }
}
var unsyncedAudioSamples: [AudioSample] {
    audioSamples.filter { $0.syncedAt == nil }
}
var unsyncedCrowdEstimates: [CrowdEstimate] {
    crowdEstimates.filter { $0.syncedAt == nil }
}
var hasUnsyncedRecords: Bool {
    !unsyncedSessions.isEmpty || !unsyncedAudioSamples.isEmpty || !unsyncedCrowdEstimates.isEmpty
}

// Sessions need re-sync when ended (endedAt changed after initial sync)
var sessionsNeedingUpdate: [Session] {
    sessions.filter { $0.syncedAt != nil && $0.endedAt != nil && $0.syncedAt! < $0.endedAt! }
}
```

- [ ] **Step 3: Build and verify**

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add CafePulse/Sources/Models/ CafePulse/Sources/App/AppModel.swift
git commit -m "Add syncedAt tracking to models, markSynced and query helpers to AppModel"
```

---

### Task 5: SyncManager

**Files:**
- Create: `CafePulse/Sources/Storage/SyncManager.swift`

- [ ] **Step 1: Build SyncManager**

```swift
enum SyncState: Equatable {
    case idle
    case syncing
    case synced
    case error(String)
    case offline
}

@MainActor
final class SyncManager: ObservableObject {
    @Published var syncState: SyncState = .idle

    private let client: SupabaseClient
    private weak var appModel: AppModel?
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 120  // 2 minutes

    init(client: SupabaseClient, appModel: AppModel) { ... }

    /// Start periodic sync. Call on app launch if authenticated + unsynced records exist.
    func startPeriodicSync()

    /// Stop timer. Does NOT do a final flush (call syncNow() first if needed).
    func stopPeriodicSync()

    /// Immediate sync of all unsynced records. Call on session end.
    func syncNow() async

    /// Drain: run on app launch until queue is empty, then stop.
    func drainUnsyncedQueue() async
}
```

Sync logic per tick:
1. Check `client.isAuthenticated` — if not, set `.offline`, return
2. Refresh token if needed
3. Upsert unsynced sessions → on success, call `appModel.markSessionSynced(id:)` for each
4. Upsert sessions needing update (endedAt changed) → mark synced with new timestamp
5. Batch upsert unsynced audio samples (max 100 per request) → mark synced
6. Batch upsert unsynced crowd estimates → mark synced
7. If all succeed: set `.synced`. If any fail: set `.error(message)`, retry next tick.
8. If no unsynced records remain and no active session: stop timer.

- [ ] **Step 2: Build and verify**

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add CafePulse/Sources/Storage/SyncManager.swift
git commit -m "Add SyncManager with durable upsert sync and drain queue on launch"
```

---

### Task 6: Auth UI + Deep Link Handler

**Files:**
- Create: `CafePulse/Sources/Views/AuthView.swift`
- Modify: `CafePulse/Sources/Views/MainWindowView.swift`
- Modify: `CafePulse/Sources/Views/MenuBarContentView.swift`
- Modify: `CafePulse/Sources/App/CafePulseApp.swift`
- Modify: `CafePulse/Config/Info.plist`

- [ ] **Step 1: Register URL scheme in Info.plist**

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>cafepulse</string>
        </array>
        <key>CFBundleURLName</key>
        <string>com.christiannikolov.CafePulse</string>
    </dict>
</array>
```

- [ ] **Step 2: Create AuthView**

- Email text field + "Send Magic Link" button
- After sending: "Check your email and click the link to sign in."
- Resend button (visible after 30 seconds)
- Error display if send fails

- [ ] **Step 3: Handle deep link in CafePulseApp**

```swift
// In CafePulseApp body:
.onOpenURL { url in
    // url = cafepulse://auth/callback#access_token=...&refresh_token=...&expires_in=...
    Task {
        await model.supabaseClient.handleCallback(url: url)
        model.authState = model.supabaseClient.isAuthenticated ? .authenticated : .unauthenticated
        // Drain any unsynced records from previous offline sessions
        if model.supabaseClient.isAuthenticated {
            await model.syncManager.drainUnsyncedQueue()
        }
    }
}
```

- [ ] **Step 4: Add auth gate to MainWindowView**

If not authenticated → show AuthView at top. Rest of UI still visible but "Start Session" disabled.
Add sign-out button in settings section.

- [ ] **Step 5: Gate menu bar "Start Session" on auth**

In MenuBarContentView, the "Start Session..." button should:
- If authenticated → open window + start session form (current behavior)
- If not authenticated → open window showing AuthView

- [ ] **Step 6: Build and test**

Expected: BUILD SUCCEEDED. Can enter email, see "check email" message. Deep link not testable without real email.

- [ ] **Step 7: Commit**

```bash
git add CafePulse/Sources/Views/AuthView.swift CafePulse/Sources/Views/MainWindowView.swift \
    CafePulse/Sources/Views/MenuBarContentView.swift CafePulse/Sources/App/CafePulseApp.swift \
    CafePulse/Config/Info.plist
git commit -m "Add magic link auth UI, deep link handler, auth gate on session start"
```

---

### Task 7: Wire SyncManager into AppModel

**Files:**
- Modify: `CafePulse/Sources/App/AppModel.swift`

- [ ] **Step 1: Add SyncManager + SupabaseClient to AppModel**

```swift
// New properties:
let supabaseClient = SupabaseClient()
lazy var syncManager = SyncManager(client: supabaseClient, appModel: self)
@Published var authState: AuthState = .unknown  // .unknown, .authenticated, .unauthenticated

// On init:
authState = supabaseClient.isAuthenticated ? .authenticated : .unauthenticated
if authState == .authenticated && hasUnsyncedRecords {
    Task { await syncManager.drainUnsyncedQueue() }
}
```

- [ ] **Step 2: Start sync on session start**

In `startSession(using:)`, after `audioEngine.start()`:
```swift
if authState == .authenticated {
    syncManager.startPeriodicSync()
}
```

- [ ] **Step 3: Final flush + re-sync session on end**

In `endSession()`:
```swift
// Re-upsert the session with endedAt set
if let idx = sessions.firstIndex(where: { $0.id == activeSession.id }) {
    sessions[idx].endedAt = .now
    sessions[idx].syncedAt = nil  // force re-sync
}
// Final flush
Task { await syncManager.syncNow() }
syncManager.stopPeriodicSync()
```

- [ ] **Step 4: Add sync status to menu bar popup**

In MenuBarContentView, below the session status:
```swift
// Sync indicator
HStack(spacing: 4) {
    switch model.syncManager.syncState {
    case .synced:  Image(systemName: "checkmark.icloud").foregroundStyle(.green)
    case .syncing: Image(systemName: "arrow.triangle.2.circlepath.icloud").foregroundStyle(.blue)
    case .error:   Image(systemName: "exclamationmark.icloud").foregroundStyle(.red)
    case .offline: Image(systemName: "icloud.slash").foregroundStyle(.secondary)
    case .idle:    Image(systemName: "icloud").foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 5: Build and verify**

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add CafePulse/Sources/App/AppModel.swift CafePulse/Sources/Views/MenuBarContentView.swift
git commit -m "Wire SyncManager into AppModel, sync status in menu bar, flush on session end"
```

---

### Task 8: End-to-End Test + Push

- [ ] **Step 1: Verify Supabase dashboard config**

Confirm redirect URL `cafepulse://auth/callback` is in Auth → URL Configuration.

- [ ] **Step 2: Build and launch**

```bash
xcodegen generate && xcodebuild -project CafePulse.xcodeproj -scheme CafePulse \
    -configuration Debug -derivedDataPath .build/DerivedData build
open .build/DerivedData/Build/Products/Debug/CafePulse.app
```

- [ ] **Step 3: Test auth flow**

1. Enter email in AuthView → click "Send Magic Link"
2. Check email → click the magic link
3. App should activate, parse tokens, show authenticated state
4. Verify Keychain has access + refresh tokens

- [ ] **Step 4: Test sync flow**

1. Start session (should be enabled now that auth is done)
2. Wait 5 seconds for first audio sample
3. Wait 2 minutes for first sync tick
4. Check Supabase Table Editor → sessions table should have 1 row
5. audio_samples table should have ~24 rows
6. End session → verify ended_at is synced

- [ ] **Step 5: Test offline resilience**

1. Disconnect WiFi
2. Start new session, collect samples for 1 minute
3. Reconnect WiFi
4. Verify sync catches up (menu bar goes from offline → syncing → synced)

- [ ] **Step 6: Push to git**

```bash
git push origin main
```
