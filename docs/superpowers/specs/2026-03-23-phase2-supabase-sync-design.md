# CafePulse Phase 2 — Multi-User Supabase Sync

## Goal

Pool audio + crowd data from multiple users into a shared Supabase database. Everyone sees everyone's data. Magic link auth, batch sync every 2 minutes.

## Auth

- Magic link (email) via Supabase GoTrue `/auth/v1/otp` endpoint (signInWithOTP)
- User opens app → enters email → Supabase sends magic link with `redirectTo=cafepulse://auth/callback`
- User clicks link → app parses `access_token` + `refresh_token` + `expires_in` from URL fragment
- **Both access and refresh tokens** stored in Keychain (NOT AppSettings)
- Auto-refresh: check expiry before each API call, refresh proactively
- User stays logged in until explicit sign out (sign-out clears Keychain)
- Supabase dashboard must have `cafepulse://auth/callback` in Auth → URL Configuration → Redirect URLs

## Data Sync

- **Offline-first**: Local JSON store remains source of truth
- **AppModel is the single writer** for local state — SyncManager reads through AppModel, never writes to LocalStore directly
- **SyncManager** runs a 2-minute timer during active sessions AND on app launch until unsynced queue is drained
- Each record gets `syncedAt: Date?` — nil means unsynced
- **All uploads use upsert** (idempotent — `Prefer: resolution=merge-duplicates`). Safe for retries after timeouts.
- Sessions are upserted on creation AND re-upserted on end (to sync `ended_at`). `syncedAt` is reset to nil on end to force re-sync.
- On each tick: query AppModel for unsynced records → batch upsert to Supabase → call AppModel.markSynced()
- On session end: final flush of all remaining records
- If upload fails: log error, retry next cycle. No data loss.
- If app launches with unsynced records + valid auth: drain queue immediately

## Database Schema

### sessions
| Column | Type | Constraints |
|--------|------|------------|
| id | UUID | PK, default gen_random_uuid() |
| user_id | UUID | NOT NULL, DEFAULT auth.uid(), FK auth.users |
| cafe_name | text | NOT NULL |
| location | text | nullable |
| started_at | timestamptz | NOT NULL, default now() |
| ended_at | timestamptz | nullable |
| tags | text[] | default '{}' |
| created_at | timestamptz | default now() |

Note: `user_id DEFAULT auth.uid()` — client omits user_id from payload, DB fills it from JWT.

### audio_samples
| Column | Type | Constraints |
|--------|------|------------|
| id | UUID | PK, default gen_random_uuid() |
| session_id | UUID | NOT NULL, FK sessions(id) ON DELETE CASCADE |
| timestamp | timestamptz | NOT NULL |
| overall_db | real | NOT NULL |
| music_band_db | real | NOT NULL |
| voice_band_db | real | NOT NULL |
| peak_db | real | NOT NULL |
| spectral_flatness | real | NOT NULL, default 0 |
| self_talk_detected | boolean | NOT NULL, default false |
| voice_band_variance | real | NOT NULL, default -120 |
| created_at | timestamptz | default now() |

### crowd_estimates
| Column | Type | Constraints |
|--------|------|------------|
| id | UUID | PK, default gen_random_uuid() |
| session_id | UUID | NOT NULL, FK sessions(id) ON DELETE CASCADE |
| timestamp | timestamptz | NOT NULL |
| fullness | text | NOT NULL, CHECK in ('empty','quarter','half','three_quarters','full') |
| people_count | integer | nullable |
| created_at | timestamptz | default now() |

### Indexes
- `audio_samples(session_id, timestamp)`
- `crowd_estimates(session_id, timestamp)`
- `sessions(user_id)`

### Row Level Security
- All tables: RLS enabled
- SELECT: all authenticated users can read all rows (collaborative science — **privacy note:** all users see each other's audio levels, locations, and tags)
- INSERT/UPDATE/DELETE on sessions: only where `user_id = auth.uid()`
- INSERT/UPDATE/DELETE on audio_samples/crowd_estimates: only where session belongs to `auth.uid()`

## Swift Architecture

### New Files
- `SupabaseConfig.swift` — URL + publishable key constants
- `KeychainHelper.swift` — save/load/delete for access token, refresh token, expiry
- `SupabaseClient.swift` — URLSession-based REST client (no external deps)
  - Auth: `sendMagicLink(email:)`, `handleCallback(url:)`, `refreshTokenIfNeeded()`, `signOut()`
  - CRUD: `upsertSession()`, `upsertAudioSamples([])`, `upsertCrowdEstimates([])`
  - All CRUD uses `Prefer: resolution=merge-duplicates,return=minimal`
- `SyncManager.swift` — batch sync with durable queue
  - 2-minute timer during active sessions
  - Drain queue on app launch
  - Reads unsynced records from AppModel, calls AppModel.markSynced() on success
  - Handles session re-sync (endedAt update)
- `AuthView.swift` — email input + magic link status + resend button

### Modified Files
- `AppModel.swift` — add SyncManager + SupabaseClient, markSynced() methods, auth state, gate sessions on auth
- `AudioSample.swift` — add `syncedAt: Date?`
- `Session.swift` — add `syncedAt: Date?` (NO userId — DB handles it)
- `CrowdEstimate.swift` — add `syncedAt: Date?`
- `MainWindowView.swift` — auth gate + sign-out button
- `MenuBarContentView.swift` — sync status indicator, gate Start Session on auth
- `CafePulseApp.swift` — `.onOpenURL` deep link handler, start sync on launch
- `Info.plist` — register `cafepulse://` URL scheme

### What stays the same
- `AppSettings.swift` — NO auth state here (stays in Keychain only)
- `LocalStore.swift` — no changes (AppModel remains single writer)

## Out of Scope
- Web dashboard (Phase 3)
- Real-time live updates between users
- Conflict resolution (each user owns their data, no conflicts possible)
- Cafe autocomplete from shared data
