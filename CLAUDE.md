# CafePulse

## What This Is

A scientific experiment to test the hypothesis: **cafes increase background music volume as crowd density increases, to drive customer turnover.**

## Architecture

Two components:

1. **macOS Menu Bar App** (Swift, SwiftUI) — passive audio level sampling + periodic crowd estimate prompts
2. **Web Dashboard** (React + Supabase) — collaborative data visualization and correlation analysis

## Key Design Decisions

- **No raw audio is stored** — only dB levels and frequency band energies (privacy-first)
- **Frequency band separation over ML source separation** — use FFT band splitting (sub-bass/bass = music proxy, mid/upper-mid = voice proxy). Demucs is overkill for continuous background sampling.
- **Supabase as backend** — Postgres + Auth + Realtime, easy for multi-user data pooling
- **Phase 1 is local-only** — CSV export, validate the concept before building the web layer

## Tech Stack

### Menu Bar App
- Swift 5.9+, SwiftUI for popup UI
- AVAudioEngine for mic input tap
- Accelerate framework for FFT
- Target: macOS 14+

### Web Dashboard
- React + TypeScript
- Supabase client SDK
- Chart.js or Recharts for visualization
- Deployable via Lovable or Vercel

## Project Structure

```
cafe-pulse/
  CafePulse/              # Xcode project — macOS menu bar app
    Sources/
      App/                # App entry point, menu bar setup
      Audio/              # AudioEngine, FFT analysis, band separation
      Models/             # Session, AudioSample, CrowdEstimate
      Views/              # SwiftUI popup views
      Storage/            # Local persistence + Supabase sync
  dashboard/              # Web dashboard (React)
  docs/                   # Design specs
```

## Spec

Full design spec: `docs/superpowers/specs/2026-03-23-cafe-pulse-design.md`

## Conventions

- Swift: follow Apple's API Design Guidelines
- Web: standard React + TypeScript conventions
- Commits: short imperative messages describing the "why"
- Start with Phase 1 (local menu bar app + CSV export) before building the web layer
