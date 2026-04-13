# Contributing to AllSpark iOS

The general Contribution Guide for all ARENA projects can be found [here](https://docs.arenaxr.org/content/contributing.html).

This document covers **development rules and conventions** specific to `AllSpark-ios`. These rules are mandatory for all contributors, including automated/agentic coding tools.

## Development Rules

### 1. View Lifecycle & Persistent Settings

Use `@AppStorage` for managing persistent user preferences and UI toggles.

**Critical:** You must ensure the camera pipelines (e.g. `AVCaptureSession`) are paused/terminated correctly when navigating away from the capturing views or moving to the background. Failing to do so can result in orphaned recordings, battery drain, and memory leaks.

### 2. Privacy Filtering Patterns

Any new computer vision pipelines must respect user privacy. We utilize Vision framework to automatically identify humans in the frame.
- **Camera Frames:** Real-time facial blurring must be applied to video/image captures before they are transmitted.

### 3. Code Style & Architecture

- **SwiftUI First:** All new views should be written using SwiftUI rather than storyboards.
- **Background Networking:** Ensure all WebSockets gracefully handle app backgrounding and foregrounding via proper suspend events.

### 4. Dependencies — Pin All Versions

**All dependencies must use exact, pegged versions** (no `^`, `~`, or `*` ranges). This prevents version drift across environments and ensures reproducible builds for security.

## Build & Test

To build the project locally, open `AllSpark-ios.xcodeproj` with Xcode.

The `AllSpark-ios` repository uses [Release Please](https://github.com/googleapis/release-please) to automate CHANGELOG generation and semantic versioning. Your PR titles *must* follow Conventional Commit standards (e.g., `feat:`, `fix:`, `chore:`). Fastlane is used to automate TestFlight deployments via `fastlane beta`.
