# Developer & Agent Guide: Best Practices for Workflow Orchestration and Task Management

## Workflow Orchestration

### 1. Plan Node Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately - don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One tack per subagent for focused execution

### 3. Self-Improvement Loop
- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

### 4. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 5. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes - don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests - then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

## Task Management
1. **Plan First**: Write plan to `tasks/todo.md` with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to `tasks/todo.md`
6. **Capture Lessons**: Update `tasks/lessons.md` after corrections

## Core Principles
- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.

---

# FadCam iOS — Project-Specific Rules

## Logging
- Use `import OSLog` + `Logger(subsystem: "com.fadseclab.fadcam", category: "...")`
- File-level private logger: `private let log = Logger(subsystem: "com.fadseclab.fadcam", category: "camera")`
- Categories: `app`, `camera`, `recorder`, `storage`, `trash`, `onboarding`
- Methods: `log.info(...)`, `log.error(...)`, `log.debug(...)`, `log.fault(...)`
- Watch live: Xcode console (Cmd+Shift+Y) or Mac Console.app
- Pre-made categories in `FadCam/Helpers/Log.swift` — use `FadCamLog.camera.info(...)` etc.

## Tech Stack
- iOS 15.6+, SwiftUI + AVFoundation
- Red theme (`.tint(.red)`), forced dark mode, status bar hidden
- AVAssetWriter for recording (not AVCaptureMovieFileOutput)
- `@AppStorage` for persistence, `Notification.Name` for cross-VM sync
- `DispatchWorkItem` pattern to avoid CMSampleBuffer Sendable warnings

## Code Style
- Write descriptive comments for all public APIs, complex logic, and non-obvious behavior
- Follow Swift best practices, clean architecture, MVVM pattern
- Use `context7` MCP to fetch current Apple/AVFoundation/SwiftUI documentation before writing code
- Check existing imports before adding new libraries
- `.tint(.red)` for buttons, not manual red where avoidable
- LinearGradient for cards that need color (red theme)

## Building & Testing
- If using XcodeBuildMCP, use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.
- Use `xcode_BuildProject` MCP tool to build the project (compile only, no install/launch)
- Verify zero errors and zero warnings after every change
- Use `xcode_GetBuildLog` to check for warnings after build
- To build, install, and launch on connected iPhone:
  ```
  xcodebuildmcp device build-and-run --project-path FadCam.xcodeproj --scheme FadCam --device-id <UDID>
  ```
- Get device UDID: `xcodebuildmcp device list`
- If debug launch stalls on device: uncheck "Debug executable" in Scheme → Run

## Architecture
- `CameraService` owns `VideoRecorder`, routes samples in `captureOutput` delegate
- `CameraViewModel` is `@MainActor ObservableObject`, manages UI state
- `RecordsViewModel` handles file listing, selection, batch ops
- `TrashViewModel` handles soft-delete with metadata JSON
- `.fadCamMediaChanged` notification keeps VMs in sync
- Recording saved to `Documents/FadCam/{Back,Front}/`
- Screenshots saved to `Documents/FadCam/FadShot/{Back,Front}/`

## Recording Orientation & Watermark
- Both cameras use the same `AVAssetWriterInput` portrait rotation.
- Keep `AVCaptureVideoDataOutput` unmirrored. Its raw horizontal mirror becomes
  a displayed vertical flip after the portrait writer rotation.
- Mirror only front camera pixels on the raw vertical axis before watermark
  compositing when a displayed left/right mirror is requested.
- Watermark text/corner must never be mirrored by the front-camera flip.
- Final watermark placement must concatenate a world-space translation; using
  `translatedBy` after rotation moves it in the rotated local coordinate space.

## Simplicity First
- Minimal code changes, no over-engineering
- Don't refactor unrelated code when fixing bugs
- 3-line fix better than 30-line refactor
- Build and verify after every change
