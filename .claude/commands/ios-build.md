# iOS Build — Parsec SwiftGodotKit

You are helping with the iOS Xcode build for the Parsec step-rogue game.
The iOS app lives at `ios_app/ParsecApp.xcodeproj`. It wraps a Godot 4.6
PCK (`Parsec.pck` at the repo root) inside a native Swift/SwiftUI app using
SwiftGodotKit. HealthKit is bridged via a native `HealthKitBridge` Swift class
registered with Godot's ClassDB.

## Key files

| File | Purpose |
|------|---------|
| `ios_app/ParsecApp/ParsecApp.swift` | `@main` app; registers `HealthKitBridge` via `initHookCb` |
| `ios_app/ParsecApp/ContentView.swift` | Presents Godot via `UIViewControllerRepresentable` |
| `ios_app/ParsecApp/HealthKitBridge.swift` | Native HealthKit bridge (`@Godot`, `@Callable`, `@Signal`) |
| `ios_app/ParsecApp/ParsecApp.entitlements` | `com.apple.developer.healthkit = true` |
| `ios_app/ParsecApp/Info.plist` | `NSHealthShareUsageDescription`, portrait, iOS 17+ |
| `ios_app/ParsecApp.xcodeproj/project.pbxproj` | Project config; SPM pins SwiftGodotKit to branch `main` |
| `Parsec.pck` | Game content; re-export from Godot whenever GDScript changes |

## Normal build steps

```
1. git pull origin main                    # sync latest from GitHub
2. Open ios_app/ParsecApp.xcodeproj        # in Xcode
3. Product → Clean Build Folder (⌘⇧K)
4. Select iPhone as run destination
5. ⌘R  (build + run)
```

First-time SPM resolve downloads ~600 MB Godot binaries — wait 5–15 min.

## Re-export the PCK (after GDScript changes)

```
1. Open Godot editor with this project
2. Project → Export → iOS preset
3. Export PCK/Zip → save as  Parsec.pck  (repo root)
4. git add Parsec.pck && git commit && git push
5. Rebuild in Xcode
```

## Common errors and fixes

### "No such module 'SwiftGodotKit'" in editor
**False alarm** — SourceKit indexer only. Xcode builds fine; ignore it.

### "Missing package product 'SwiftGodotKit'"
Stale package resolution. Fix:
```
File → Packages → Reset Package Caches
Product → Clean Build Folder
(Close and reopen project if still failing)
```
Do NOT use `XCLocalSwiftPackageReference` in project.pbxproj — causes this error in Xcode 26.

### "Entitlement com.apple.developer.healthkit.capabilities not found"
Remove the `capabilities` key from `ParsecApp.entitlements`. Keep only:
```xml
<key>com.apple.developer.healthkit</key>
<true/>
```

### "Conflicting provisioning … Apple Distribution"
In `project.pbxproj`, both Debug and Release `CODE_SIGN_IDENTITY` must be `"Apple Development"` for device testing.

### SignalWith1Argument / macro expansion errors
Old SwiftGodot API. Correct syntax for 0.75.0+:
```swift
@Signal var stepsReady: SignalWithArguments<Int>
@Signal var healthUnavailable: SimpleSignal

stepsReady.emit(count)
healthUnavailable.emit()
```
If errors persist after fixing: **Product → Clean Build Folder** (clears macro cache).

### Buttons/touch not responding on device
The game renders but taps do nothing — this is the `UIGodotAppView` coordinate bug.
`ContentView.swift` must use `UIViewControllerRepresentable`, NOT bare `GodotAppView()`:

```swift
// ContentView.swift — correct pattern
private final class GodotViewController: UIViewController {
    override func loadView() {
        let gv = UIGodotAppView()   // no-arg — UIGodotAppView(frame:) is internal
        gv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        gv.contentScaleFactor = UIScreen.main.scale
        gv.isMultipleTouchEnabled = true
        godotApp.configureLaunch(source: nil, scene: nil)
        godotApp.start()
        gv.app = godotApp
        view = gv
    }
}
```

UIKit sets the root view frame to `{0,0,screenW,screenH}` so
`UIGodotAppView`'s internal touch check (which compares local coords to
parent-frame coords) always passes.

### Touch debug: checking if Godot receives input
`scenes/menu/menu.gd` has `_input` print statements. Run with iPhone connected
and check Xcode's debug console:
- `[Menu] _ready` → scene loading OK
- `[Menu] Input event: …` → Godot is receiving touches → button logic issue
- silence → touches not reaching Godot → UIViewControllerRepresentable fix above

## SwiftGodot 0.75.0 cheat sheet

```swift
// Registration (in ParsecApp.init())
initHookCb = { level in
    if level == .scene { register(type: HealthKitBridge.self) }
}

// Class definition
@Godot class HealthKitBridge: RefCounted {
    @Signal var stepsReady: SignalWithArguments<Int>
    @Signal var healthUnavailable: SimpleSignal
    required init(_ context: InitContext) { super.init(context) }
    @Callable func requestAndFetch() { … }
}

// Emitting
stepsReady.emit(count)
healthUnavailable.emit()
```

## GitHub push

```bash
# SSH is configured at ~/.ssh/github_parsec
git add <files>
git commit -m "message"
git push origin main
```

## Architecture note: how HealthKit bridge works

`sync_steps.gd` calls `ClassDB.class_exists("HealthKitBridge")` — returns `true`
because `ParsecApp.swift` registers `HealthKitBridge` with Godot's ClassDB
via `initHookCb` before the engine starts. GDScript then calls
`bridge.request_and_fetch()` and connects `steps_ready` / `health_unavailable`
signals. No xcframework or GDExtension needed — the Swift class is compiled
directly into the app binary.
