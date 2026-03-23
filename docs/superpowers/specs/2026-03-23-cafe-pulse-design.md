# CafePulse — Design Spec

## Hypothesis

Cafes increase background music volume as crowd density increases, to accelerate customer turnover.

## System Overview

Two components:

1. **CafePulse Menu Bar App** (Swift/macOS) — the data collector
2. **CafePulse Web Dashboard** (React + Supabase) — the data viewer & collaboration hub

---

## Component 1: macOS Menu Bar App

### Purpose

Runs silently in the menu bar. Continuously samples ambient audio levels from the MacBook mic. Periodically prompts the user for a crowd estimate. Uploads all data to Supabase.

### Audio Analysis

- Uses `AVAudioEngine` with an input tap on the mic
- Samples audio levels every **5 seconds** (configurable)
- Records two key metrics per sample:
  - **Overall dB level** (SPL — Sound Pressure Level)
  - **Music-dominant dB** vs **Voice-dominant dB** — using frequency band separation:
    - Music tends to be fuller spectrum with prominent low-end (bass) and mid frequencies
    - Voices cluster in the 300Hz–3kHz range with harmonic patterns
    - A simple FFT-based band split gives a rough but useful separation
- Stores a rolling buffer of the last N minutes locally before batching uploads

### Crowd Estimation Prompts

- Every **15 minutes** (configurable), a macOS notification or small popup appears:
  - "How full is the cafe?" → Slider or buttons: **Empty / Quarter / Half / Three-quarters / Full**
  - "Estimated people count?" → Number stepper (optional, for precision)
- Prompt is non-blocking — if dismissed/ignored, that interval just has no crowd data
- User can also manually trigger a crowd estimate from the menu bar icon

### Session Management

- User starts a session when arriving at a cafe:
  - Clicks menu bar icon → "Start Session"
  - Enters cafe name (with autocomplete from previous sessions) and optionally location
  - Optionally tags the session (e.g., "morning rush", "evening chill")
- Session ends when user clicks "End Session" or after 4 hours of inactivity
- All data within a session is grouped together

### Data Model (per session)

```
Session {
  id: UUID
  user_id: UUID
  cafe_name: String
  location: String? (city or coordinates)
  started_at: Timestamp
  ended_at: Timestamp?
  tags: [String]
}

AudioSample {
  id: UUID
  session_id: UUID
  timestamp: Timestamp
  overall_db: Float
  music_band_db: Float      // Low + mid frequency energy
  voice_band_db: Float      // 300Hz-3kHz energy
  peak_db: Float
}

CrowdEstimate {
  id: UUID
  session_id: UUID
  timestamp: Timestamp
  fullness: Enum (empty, quarter, half, three_quarters, full)
  people_count: Int?
}
```

### Menu Bar UI

- Idle: simple waveform icon
- Recording: pulsing green dot
- Click to reveal dropdown:
  - Current session info (cafe name, duration, samples collected)
  - "Start Session" / "End Session"
  - "Log Crowd Estimate Now"
  - "Open Dashboard" → opens web dashboard in browser
  - Settings (sample interval, prompt interval, Supabase URL)

---

## Component 2: Web Dashboard

### Purpose

Visualize collected data, share with friends, prove or disprove the hypothesis.

### Tech Stack

- **Frontend**: React (Lovable-deployable) or plain HTML/JS
- **Backend**: Supabase (Postgres + Auth + Realtime)
- **Charts**: Chart.js or Recharts

### Features

1. **Session Timeline View**
   - X-axis: time
   - Y-axis (left): dB levels (overall, music-band, voice-band as separate lines)
   - Y-axis (right): crowd fullness overlay
   - Clear visual showing: does music go up when crowd goes up?

2. **Correlation Analysis**
   - Scatter plot: crowd fullness vs. music-band dB
   - Pearson correlation coefficient displayed
   - Per-cafe breakdown

3. **Cafe Leaderboard**
   - Which cafes show the strongest correlation?
   - Ranked by correlation strength

4. **Multi-User Data**
   - Friends sign up, install the app, collect data
   - All data is pooled
   - Filter by user, cafe, time range

5. **Export**
   - CSV export for further analysis in Python/R/Excel

### Auth

- Simple Supabase email auth or magic link
- Each user sees all pooled data (this is collaborative science)

---

## Frequency Band Separation (the "intelligence")

Full source separation (like Demucs) is overkill and too CPU-heavy for continuous background sampling. Instead, a pragmatic approach:

1. Run FFT on each 5-second audio buffer
2. Split into bands:
   - **Sub-bass** (20-60Hz): Music signature
   - **Bass** (60-250Hz): Music signature
   - **Low-mid** (250-500Hz): Mixed
   - **Mid** (500Hz-2kHz): Voice-dominant
   - **Upper-mid** (2kHz-4kHz): Voice-dominant
   - **Presence** (4kHz-6kHz): Mixed
   - **Brilliance** (6kHz+): Mixed (cymbals, sibilance)
3. Compute energy in each band
4. **Music indicator**: energy in sub-bass + bass bands (cafe music almost always has bass; voices don't)
5. **Voice indicator**: energy in mid + upper-mid bands minus the music bleed estimate

This won't perfectly separate a singer's voice from crowd chatter, but that's fine — the hypothesis is about **music volume vs crowd size**, not music vs speech. The bass-heavy bands are a reliable proxy for "how loud is the cafe's sound system right now."

---

## Privacy Considerations

- **No audio is recorded or stored** — only numerical dB levels and frequency band energies
- Raw audio never leaves the device
- Only aggregate metrics are uploaded
- Users control when sessions start and stop

---

## MVP Scope

### Phase 1: Validate Locally
- Menu bar app with audio sampling + crowd prompts
- Local CSV export (no backend needed)
- Manually analyze in a spreadsheet

### Phase 2: Shared Backend
- Supabase integration
- Web dashboard with timeline + correlation charts
- Multi-user support

### Phase 3: Polish
- Cafe autocomplete / location lookup
- Statistical significance testing
- iOS companion (if the theory holds and friends want in)
