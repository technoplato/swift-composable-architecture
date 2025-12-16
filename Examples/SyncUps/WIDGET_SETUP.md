# Widget & Live Activity Setup Guide

This document explains how to complete the setup for widgets and Live Activities in Xcode.

## Files Created

The following files have been created and need to be added to the Xcode project:

### Main App Target (SyncUps)

Add these files to the SyncUps target:

1. **`SyncUps/AppRouter.swift`** - Deep link router using swift-url-routing
2. **`SyncUps/StopwatchAttributes.swift`** - ActivityAttributes model (also add to widget target)
3. **`SyncUps/Dependencies/ActivityKitClient.swift`** - TCA dependency for ActivityKit
4. **`SyncUps/Stopwatch+SharedKeys.swift`** - App Group shared keys

### Test Target (SyncUpsTests)

Add this file to the SyncUpsTests target:

1. **`SyncUpsTests/AppRouterTests.swift`** - Router unit tests

### Widget Extension Target (StopwatchWidgets) - NEW TARGET

Create a new Widget Extension target and add these files:

1. **`StopwatchWidgets/StopwatchWidgetBundle.swift`** - Widget bundle entry point
2. **`StopwatchWidgets/StopwatchWidget.swift`** - Home screen widgets
3. **`StopwatchWidgets/StopwatchLiveActivity.swift`** - Live Activity UI
4. **`StopwatchWidgets/StopwatchIntents.swift`** - App Intents for interactivity

### Shared Files (Both Targets)

These files must be added to BOTH the main app and widget extension:

1. **`SyncUps/StopwatchAttributes.swift`**
2. **`SyncUps/Stopwatch.swift`** (StopwatchItem model)
3. **`SyncUps/Stopwatch+SharedKeys.swift`**
4. **`StopwatchWidgets/StopwatchIntents.swift`**

## Xcode Setup Steps

### 1. Add swift-url-routing Dependency

1. File → Add Package Dependencies
2. Enter: `https://github.com/pointfreeco/swift-url-routing`
3. Add to SyncUps target

### 2. Create Widget Extension Target

1. File → New → Target
2. Select "Widget Extension"
3. Product Name: `StopwatchWidgets`
4. **Check** "Include Live Activity"
5. **Uncheck** "Include Configuration App Intent" (we have our own)
6. Finish

### 3. Configure App Groups

For **both** SyncUps and StopwatchWidgets targets:

1. Select target → Signing & Capabilities
2. Click "+ Capability"
3. Add "App Groups"
4. Click "+" and add: `group.syncups.stopwatch`

### 4. Enable Live Activities (Main App)

1. Select SyncUps target
2. Go to Info tab (or edit Info.plist directly)
3. Add key: `NSSupportsLiveActivities` = `YES` (Boolean)

### 5. Add Files to Targets

#### Main App (SyncUps):
- Right-click SyncUps folder → Add Files to "SyncUps"
- Select all new `.swift` files in `SyncUps/`
- Ensure "SyncUps" target is checked

#### Widget Extension (StopwatchWidgets):
- Right-click StopwatchWidgets folder → Add Files to "SyncUps"
- Select all `.swift` files in `StopwatchWidgets/`
- Ensure "StopwatchWidgetsExtension" target is checked

#### Shared Files:
For `StopwatchAttributes.swift`, `Stopwatch.swift`, `Stopwatch+SharedKeys.swift`:
- Select file in Project Navigator
- In File Inspector (right panel), under "Target Membership"
- Check BOTH "SyncUps" and "StopwatchWidgetsExtension"

### 6. Update Existing Stopwatch.swift

The existing `Stopwatch.swift` has shared keys that use documents directory.
Either:

**Option A**: Remove the old shared keys from `Stopwatch.swift` (lines 82-101)
and use only `Stopwatch+SharedKeys.swift`

**Option B**: Keep both, but ensure `Stopwatch+SharedKeys.swift` is imported
after `Stopwatch.swift` so the App Group versions take precedence.

Recommended: **Option A** for clarity.

## Verification

After setup, verify:

1. **Build both targets** - No compilation errors
2. **Run main app** - Stopwatch functionality works
3. **Add widget** - Long press Home Screen → Edit → + → Find "Stopwatch"
4. **Test Live Activity** - Create a favorite stopwatch, verify Live Activity appears

## Troubleshooting

### "App Group container not found"

- Verify App Group is added to BOTH targets
- Verify the identifier matches exactly: `group.syncups.stopwatch`
- Clean build folder (Cmd+Shift+K) and rebuild

### Widget shows placeholder data

- Verify shared files are in widget target membership
- Verify App Group is configured
- Check Console.app for widget extension logs

### Live Activity doesn't appear

- Verify `NSSupportsLiveActivities = YES` in Info.plist
- Check Settings → SyncUps → Live Activities is enabled
- Verify ActivityKit code is called when creating favorite

### Intents don't work

- Verify intent files are in widget target
- Verify `@main` is only on `StopwatchWidgetBundle`
- Check for intent parameter type mismatches

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Main App                              │
│  ┌─────────────────┐  ┌──────────────────┐                  │
│  │   AppFeature    │──│ ActivityKitClient│                  │
│  │   (Reducer)     │  │   (Dependency)   │                  │
│  └────────┬────────┘  └────────┬─────────┘                  │
│           │                    │                             │
│           ▼                    ▼                             │
│  ┌─────────────────────────────────────────┐                │
│  │     @Shared State (App Group)           │                │
│  │  - stopwatches: [StopwatchItem]         │                │
│  │  - favoriteStopwatchID: ID?             │                │
│  └─────────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────┘
                              │
                    (File Storage via App Group)
                              │
┌─────────────────────────────────────────────────────────────┐
│                    Widget Extension                          │
│  ┌─────────────────┐  ┌──────────────────┐                  │
│  │ StopwatchWidget │  │StopwatchLiveAct. │                  │
│  │ (TimelineProvider)│ │(ActivityConfig)  │                  │
│  └────────┬────────┘  └────────┬─────────┘                  │
│           │                    │                             │
│           ▼                    ▼                             │
│  ┌─────────────────────────────────────────┐                │
│  │         App Intents                      │                │
│  │  - ToggleStopwatchIntent                │                │
│  │  - UnfavoriteStopwatchIntent            │                │
│  │  - NavigateToStopwatchIntent            │                │
│  └─────────────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

## Next Steps

After completing setup:

1. **Integrate ActivityKitClient** into AppFeature to start/update/end Live Activities
2. **Implement TimelineProvider** to read actual @Shared state
3. **Wire up Intents** to modify @Shared state
4. **Add deep link handling** in App.swift using AppRouter
5. **Write integration tests** for ActivityKitClient


