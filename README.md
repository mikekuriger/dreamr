# Dreamr

Dreamr is an AI-powered dream journal and analysis app for iOS and Android. Users record their dreams, get AI-generated interpretations from a choice of "interpreter" personas, and explore patterns across their dream history over time.

This repository contains the **mobile app** (client). The **back-end API and database code** lives in a separate repository: [github.com/mikekuriger/dreamr](https://github.com/mikekuriger/dreamr).

## Built with

- **[Flutter](https://flutter.dev)** / Dart — single codebase targeting iOS and Android
- Local persistence via SQLite (dream journal, offline cache)
- Apple/Google in-app subscriptions (StoreKit2 on iOS, Play Billing on Android)
- Push notifications (OneSignal) with scheduled reminders and inactivity nudges
- Sign in with Apple, Google, and Facebook

## Highlights

- **AI dream interpretation** — submit a dream and get an analysis from a selectable AI "interpreter," each with its own personality/style, plus AI-generated imagery for the dream
- **Dream Journal** — searchable, filterable journal of past dreams with swipe actions (hide/delete), full-screen dream view, and per-dream interpreter icons
- **Insights** — client-side pattern analysis across a user's dream history (recurring symbols, themes, tone trends) surfaced in a dedicated Insights tab
- **Image styles** — choose the visual style used to generate dream imagery, or let the AI decide
- **Offline support** — cached login/subscription state and locally stored dreams/images so the app remains usable without connectivity, with disabled/limited actions and an offline banner while offline
- **Subscriptions** — free vs. pro tiers, with pro-gated interpreters and image styles
- **Reporting** — AI-content reporting flow for flagging problematic generated content
- **Notifications** — daily/weekly scheduling, inactivity nudges, and reschedule-on-login with rotating message content

## Related repositories

- Back end (API + database): https://github.com/mikekuriger/dreamr
