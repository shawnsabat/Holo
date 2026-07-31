# Holo acceptance audit

Reviewed July 16, 2026. The user-overridden topology is four broad zones: rear and front on the left of the MacBook, and rear and front on the right. Evaluation remains balanced at 15 held-out taps per zone, 60 total.

## Evidence status

| Requirement | Current evidence | Status |
| --- | --- | --- |
| Native macOS MVP | `Holo` builds in Debug and Release as a sandboxed, single-window SwiftUI macOS application targeting macOS 14+. Closing its only window terminates capture with the app. | Automated build verified |
| Built-in MacBook audio only | Core Audio default-route IDs and transport types are checked before capture. External inputs are rejected; Active/Hybrid also reject external output. The non-GUI route check reports this Mac's microphone and speakers as built-in, and five policy tests cover valid and invalid routes. | Automated policy and current route verified |
| Four desk zones | The model contains exactly LR, LF, RR, and RF. Topology and session-order tests pin rear and front zones to each side. | Automated verified |
| Native anti-slop interface | Standard macOS navigation, lists, forms, tables, toolbars, and controls are used. The desk is two continuous two-zone rails around a MacBook silhouette rather than four card tiles; Liquid Glass is limited to functional primary controls on macOS 26. | Source and build verified; visual review pending |
| Diagnostic recorder | Diagnostics reports selected input/output routes and built-in status, exposed channels, sample rate, buffer timing/jitter, frequency response, signal quality, and labeled feature captures. | Implemented; live capture output pending |
| Passive versus active sensing | Passive, active-probe, and hybrid feature schemas are implemented. A 36-sample guided comparison measures cross-validation accuracy and latency, and selection logic is tested. Results are profile-scoped, and an injected-chirp regression verifies active correlation and delay recovery. | Automated logic verified; physical comparison pending |
| Guided calibration | Ten spatially varied taps per zone after explicit setup consent, automatic disarmed transitions between zones, visible re-arm fallback, actionable weak/noisy/clipped retry guidance, undo, zone redo, recommended Talking negatives plus other optional negatives, and weakest-zone consistency review. | Protocol and quality policy automated; physical workflow pending |
| Reusable desk profile | Feature-only versioned JSON stores the trained classifier and desk/laptop notes. Legacy action fields remain decodable for compatibility but are not dispatched by the environmental interface. Legacy six-zone and nine-zone files are skipped by version before zone decoding; current files are checked for four-zone classifier structure and matching calibration counts. | Persistence automated |
| Real-time recognition path | Streaming onset detection, 90 ms capture, a full-event sustained-sound gate, one shared spectrum analysis, regularized linear zone scoring, nearest-example novelty/negative checks, and confidence gates are connected. Capture generations discard observations queued before a stop or strategy change. A synthetic chunked pipeline test covers all four zones. | Synthetic integration and build verified; live input pending |
| Environmental tap outputs | Accepted Desk taps map to air quality, weather and UV, environmental alerts, or water and rain. Outputs pair plain-language meaning with guidance and local speech. Current location is optional, city/ZIP search is available, modeled Open-Meteo conditions and official U.S. NWS alerts are retrieved, and the combined snapshot is cached with attribution and timestamps. NWS failure never becomes a false all-clear. Arbitrary local actions are not dispatched. | Source and live endpoint shapes verified; signed-app location flow pending |
| False-trigger rejection | Weak, noisy, clipped, OOD, schema-mismatched, calibrated-negative, and meaningfully ambiguous observations are rejected. Onset learns the room for 0.75 seconds and requires a brief impact; complete candidates with sustained speech-like duration and energy are dropped before classification. Deterministic regressions reject a plosive-plus-voiced speech candidate and elevated background while preserving short and resonant taps. Talking can also be captured as a profile-specific negative. The active probe is filtered out of onset detection. | Automated verified; representative live conversation pending |
| Local processing and privacy | Signal processing is local. Raw audio is discarded unless debug capture is explicitly enabled; retained WAVs remain visible and deletable after relaunch. | Source and persistence verified; runtime privacy observation pending |
| Immediate pause and recalibration | Toolbar pause stops input/probe and disarms guided capture. Pause remains sticky. Recalibration preserves the desk classifier and environmental workflow. | Build verified; runtime interaction pending |
| Balanced 60-tap evaluation | Accuracy Test enforces 15 taps for each of four zones. Rejections count as incorrect. | Protocol automated; physical session pending |
| Per-zone output and confusion matrix | JSON/CSV and UI reporting include overall/per-zone accuracy, four-by-four confusion matrix, rejected counts, confidence, and latency. Saved history is restored only for its profile and topology, and save failures are labeled memory-only. | Automated verified |
| At least 80% physical accuracy | No real held-out report exists for the target MacBook and desk. | Pending—no claim made |
| Median response below 200 ms | Response latency is mapped from each audio buffer's monotonic `AVAudioTime` host timestamp through feature extraction, main-thread delivery, and classification, with sample-offset and elapsed-time regression coverage. Invalid timing is never converted to zero and prevents the latency gate from passing. No real 60-tap report exists. | Instrumentation automated; physical result pending |
| Continuous 30-minute stability | An earlier all-positive synthetic DSP run completed 17,186/17,186 correct with RSS 6.7 → 6.4 MB, but predates the current four-zone topology. The current four-zone mixed runner passes its accelerated 5,000-event gate with RSS 6.7 → 7.0 MB. Neither exercises AVAudioEngine, permissions, UI, or actions. | Historical synthetic evidence; current live soak pending |
| Automated core tests | 68 unhosted tests pass with zero failures. | Verified |
| Documentation | README covers build/setup, calibration, architecture, evaluation, surfaces, privacy, limitations, and exact automated results. | Verified |

## Remaining completion gates

The MVP must not be called physically validated until all of the following are captured on the target MacBook and desk:

1. A passive/active/hybrid comparison using real taps.
2. A fresh four-zone calibration in the final laptop position.
3. A balanced 60-tap held-out report with at least 80% accuracy and median response below 200 ms.
4. A 30-minute live microphone/environmental-output run including taps, conversation, typing, laptop touches, representative background noise, location denial, offline use, and stale cached data.
5. A visual interaction review of every screen at normal and minimum window sizes.

The GUI was intentionally not launched during the latest iteration, per user instruction.
