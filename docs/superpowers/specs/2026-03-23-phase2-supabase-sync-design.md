# CafePulse Phase 2 — Multi-User Supabase Sync

## Goal

Pool audio + crowd data from multiple users into a shared Supabase database. Everyone sees everyone's data. Magic link auth, batch sync every 2 minutes.

## Auth

- Magic link (email) — zero friction, no passwords
- User opens app → enters email in main window → Supabase sends magic link → user clicks → app receives JWT via deep link callback (`cafepulse://auth/callback`)
- JWT stored in Keychain, refreshed automatically by the client
- All API calls use the JWT. No anonymous access.
- User stays logged in until explicit sign out

## Data Sync

- **Offline-first**: Local JSON store remains source of truth
- **SyncManager** runs a 2-minute timer during active sessions
- Each record gets `syncedAt: Date?` — nil means unsynced
- On each tick: query local store for unsynced records → batch POST to Supabase → mark synced
- On session end: final flush of all remaining records
- If upload fails: log error, retry next cycle. No data loss.

## Database Schema

### sessions
| Column | Type | Constraints |
|--------|------|------------|
| id | UUID | PK, default gen_random_uuid() |
| user_id | UUID | NOT NULL, FK auth.users |
| cafe_name | text | NOT NULL |
| location | text | nullable |
| started_at | timestamptz | NOT NULL, default now() |
| ended_at | timestamptz | nullable |
| tags | text[] | default '{}' |
| created_at | timestamptz | default now() |

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
- SELECT: all authenticated users can read all rows (collaborative science)
- INSERT/UPDATE/DELETE on sessions: only where `user_id = auth.uid()`
- INSERT/UPDATE/DELETE on audio_samples/crowd_estimates: only where session belongs to `auth.uid()`

## Swift Architecture

### New Files
- `SupabaseClient.swift` — URLSession-based REST client (no external deps)
  - Auth: `signIn(email:)`, `verifyOTP(email:token:)`, `refreshToken()`, `signOut()`
  - CRUD: `uploadSession()`, `uploadAudioSamples([])`, `uploadCrowdEstimate()`
  - JWT management: store in Keychain, auto-refresh
- `SyncManager.swift` — background batch sync
  - 2-minute timer during active sessions
  - Tracks unsynced records via `syncedAt` field
  - Batch upload → mark synced
  - Retry on failure, no data loss

### Modified Files
- `AppModel.swift` — add SyncManager dependency, start/stop sync with sessions
- `AudioSample.swift` — add `syncedAt: Date?`
- `Session.swift` — add `syncedAt: Date?`
- `CrowdEstimate.swift` — add `syncedAt: Date?`
- `AppSettings.swift` — add Supabase URL/key, user email, auth state
- `MainWindowView.swift` — add login/signup section
- `MenuBarContentView.swift` — show sync status indicator
- `Info.plist` — register `cafepulse://` URL scheme for magic link callback

### Config
- Supabase URL and publishable key stored as constants (not in .env at runtime — this is a compiled macOS app)
- JWT stored in Keychain

## Out of Scope
- Web dashboard (Phase 3)
- Real-time live updates between users
- Conflict resolution (each user owns their data)
- Cafe autocomplete from shared data
- Offline queue persistence across app restarts (stretch goal)
