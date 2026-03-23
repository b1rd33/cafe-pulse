# CafePulse Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-only macOS menu bar app that samples ambient audio levels, separates music vs voice frequencies via FFT, collects crowd density estimates, and exports all data as CSV.

**Architecture:** XcodeGen-based macOS 14+ SwiftUI app using `MenuBarExtra(.window)`. AVAudioEngine captures mic input, vDSP performs FFT band analysis every 5 seconds. All data persists to Application Support as JSON; CSV export via NSSavePanel. No backend — Phase 1 validates the concept locally.

**Tech Stack:** Swift 5.9+, SwiftUI, AVAudioEngine, Accelerate/vDSP, XcodeGen

**Status:** Implementation complete via Codex xhigh. Build succeeded. Needs manual verification and code review.

---

## File Structure

```
CafePulse/
  Config/
    Info.plist                         # LSUIElement=true, NSMicrophoneUsageDescription
    CafePulse.entitlements             # app-sandbox, audio-input, user-selected.read-write
  Sources/
    App/
      CafePulseApp.swift               # @main, MenuBarExtra(.window), wires AppModel + CrowdEstimatePanelController
      AppModel.swift                   # Central @MainActor ObservableObject — session lifecycle, audio, CSV, persistence
      CrowdEstimatePanelController.swift  # NSPanel-based floating window for crowd prompts
    Audio/
      AudioCaptureEngine.swift         # AVAudioEngine mic tap, MetricsAccumulator, 5s sampling, permission handling
      FFTBandAnalyzer.swift            # vDSP.DiscreteFourierTransform, Hann window, 7-band power extraction
    Models/
      Session.swift                    # UUID, cafeName, location, startedAt, endedAt, tags
      AudioSample.swift                # UUID, sessionId, timestamp, overallDB, musicBandDB, voiceBandDB, peakDB
      CrowdEstimate.swift              # UUID, sessionId, timestamp, CrowdFullness enum, peopleCount
      AppSettings.swift                # sampleIntervalSeconds, crowdPromptIntervalSeconds, StartSessionDraft, CrowdEstimateDraft
      AppSnapshot.swift                # Codable container for all persisted state
    Views/
      MenuBarContentView.swift         # Main popup: session info, live dB display, settings, privacy note
      StartSessionFormView.swift       # Cafe name (with autocomplete), location, tags
      CrowdEstimatePromptView.swift    # Fullness picker (segmented), optional people count stepper
    Storage/
      LocalStore.swift                 # Actor-isolated JSON persistence to ~/Library/Application Support/CafePulse/
      CSVExporter.swift                # Builds CSV with session_id, cafe_name, timestamp, dB values, crowd data
project.yml                            # XcodeGen spec — generates .xcodeproj
.gitignore                             # Ignores .xcodeproj and .build
```

---

## What Was Built (Codex xhigh output)

### Task 1: Project Scaffold
- [x] `project.yml` — XcodeGen config targeting macOS 14.0, Swift 5.9
- [x] `Info.plist` — `LSUIElement=true` (menu bar only), `NSMicrophoneUsageDescription`
- [x] `CafePulse.entitlements` — app-sandbox, audio-input, user-selected.read-write (for CSV save)
- [x] `.gitignore` — excludes generated `.xcodeproj` and `.build`
- [x] `xcodegen generate` → builds successfully

### Task 2: Data Models
- [x] `Session` — Identifiable, Codable, Hashable, Sendable. `isActive` computed property.
- [x] `AudioSample` — all dB fields as Float
- [x] `CrowdEstimate` + `CrowdFullness` enum (empty/quarter/half/threeQuarters/full with snake_case rawValues)
- [x] `AppSettings` — configurable intervals with defaults (5s sample, 15min crowd prompt)
- [x] `StartSessionDraft` / `CrowdEstimateDraft` — form state types with validation
- [x] `AppSnapshot` — Codable wrapper for all persisted state

### Task 3: Audio Engine + FFT Core
- [x] `AudioCaptureEngine` — AVAudioEngine with `installTap` on inputNode
  - Mic permission check via `AVCaptureDevice.authorizationStatus(for: .audio)`
  - Async permission request with `withCheckedContinuation`
  - Buffer processing on dedicated `DispatchQueue` (off real-time audio thread)
  - `MetricsAccumulator` — accumulates samples, runs FFT with 50% hop overlap, emits measurement every N seconds
  - Multi-channel → mono downmix
  - Configurable sample interval (default 5s)
- [x] `FFTBandAnalyzer` — `vDSP.DiscreteFourierTransform` (4096-point, complexComplex)
  - Hand-built Hann window
  - 7-band power extraction: sub-bass(20-60), bass(60-250), lowMid(250-500), mid(500-2k), upperMid(2k-4k), presence(4k-6k), brilliance(6k+)
  - `FFTBandPower` — accumulator struct with `musicProxyPower` (subBass+bass) and `voiceProxyPower` (mid+upperMid)
  - dB conversion: `20*log10` for amplitude (overall/peak), `10*log10` for power (band energies)

### Task 4: App Entry Point + State Management
- [x] `CafePulseApp` — `@main`, `MenuBarExtra(.window)` with dynamic icon (green waveform when sampling, orange dot for pending crowd prompt)
- [x] `AppModel` — `@MainActor ObservableObject` managing:
  - Session start/end lifecycle
  - Audio engine start/stop
  - Crowd prompt timer (configurable interval)
  - Measurement → AudioSample conversion and storage
  - CSV export via NSSavePanel
  - JSON persistence via LocalStore
  - Previous cafe name autocomplete
- [x] `CrowdEstimatePanelController` — floating `NSPanel` for crowd prompts (appears above all windows)

### Task 5: Views
- [x] `MenuBarContentView` — main popup with:
  - Header (sampling status, mic permission)
  - Idle state → "Start Session" button → inline form
  - Active state → cafe name, duration, sample/crowd counts, live dB readings (StatCard grid)
  - Settings section (sample interval stepper 5-60s, crowd prompt interval stepper 5-60min)
  - Privacy note
- [x] `StartSessionFormView` — cafe name (with autocomplete suggestions), location, tags
- [x] `CrowdEstimatePromptView` — segmented fullness picker, optional people count stepper

### Task 6: Storage + CSV Export
- [x] `LocalStore` — actor-isolated, JSON encode/decode with snake_case keys and ISO8601 dates
- [x] `CSVExporter` — merges audio samples and crowd estimates by timestamp, proper CSV escaping

---

## Remaining: Manual Verification Tasks

### Task 7: Run the App and Verify Core Flow

- [ ] **Step 1: Launch the app**

Run: `open .build/DerivedData/Build/Products/Debug/CafePulse.app`
Expected: Waveform icon appears in menu bar

- [ ] **Step 2: Grant microphone permission**

Click menu bar icon → Start Session → enter cafe name → Start
Expected: macOS microphone permission dialog appears. Grant it.

- [ ] **Step 3: Verify audio sampling**

Wait 10 seconds after starting a session.
Expected: "Latest Sample" section shows dB readings updating. Overall, Music, Voice values should be reasonable (-60 to -10 dB range for ambient cafe noise).

- [ ] **Step 4: Verify crowd estimate prompt**

Click "Log Crowd Estimate Now" button.
Expected: Floating panel appears with fullness picker and people count option.

- [ ] **Step 5: Test CSV export**

Click "Export CSV" → save to Desktop.
Expected: CSV file with headers `session_id,cafe_name,timestamp,overall_db,music_band_db,voice_band_db,peak_db,crowd_fullness,people_count`

- [ ] **Step 6: Verify persistence**

End session → Quit app → Relaunch.
Expected: Previous session data is preserved. Cafe name appears in autocomplete suggestions.

### Task 8: Code Review Items to Verify

- [ ] FFT normalization: `power / fftSize` — should this be `/ (fftSize * fftSize)` for proper Parseval's theorem compliance? Test with known tones.
- [ ] `EventKey` in CSVExporter uses `(sessionId, timestamp)` as unique key — if two samples and a crowd estimate share the same timestamp, they'll collide. Consider using separate rows or a different merge strategy.
- [ ] `MetricsAccumulator` uses `removeFirst(hopSize)` which is O(n). For 5 seconds of audio at 44.1kHz (~220k samples), this could be slow. Consider ring buffer or index-based approach.
- [ ] `AppModel.deinit` — called from non-`@MainActor` context but accesses `crowdPromptTimer` and `audioEngine`. May need `MainActor.assumeIsolated` or restructuring.
- [ ] Thread safety: `AudioCaptureEngine.isRunning` is read/written from multiple threads without synchronization.

### Task 9: Polish (Optional, Post-Verification)

- [ ] Add menu bar icon asset (currently uses SF Symbol `waveform.circle`)
- [ ] Add auto-end session after 4 hours of inactivity (per spec)
- [ ] Add macOS notification for crowd prompts (in addition to the floating panel)
- [ ] Consider adding a simple in-popup chart showing dB trends over time
