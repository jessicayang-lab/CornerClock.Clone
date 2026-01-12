# Corner Clock(Clone)

**Corner Clock** is a lightweight, native macOS utility designed for users who prefer "Auto-hide Menu Bar" or full-screen workflows. It elegantly displays the time in the top-right corner of your screen and intelligently hides itself to avoid overlapping with the system menu bar.


## The Problem
macOS offers a great "Auto-hide and show menu bar" feature to maximize screen real estate. However, this creates a problem: **you lose track of time.** To check the clock, you have to interrupt your workflow and move the mouse to the top of the screen.

Existing solutions often require intrusive system permissions, look out of place (non-native UI), or clash visually when the system menu bar reappears.

## Key Features

### Smart Geometry Detection
Unlike other tools that rely on buggy system permissions or `UserDefaults`, Corner Clock uses a **pure physics-based approach**:
* **Automatic Avoidance:** If the system Menu Bar occupies the top space (Gap > 22px), the clock hides instantly.
* **Mouse Awareness:** If your mouse moves to the top edge (intent to open the menu), the clock hides to prevent obstruction.
* **Sandboxing Friendly:** Zero special permissions required. It works strictly by calculating available screen geometry.

### Native macOS Aesthetic
Designed to look like it belongs in macOS:
* **HUD Material:** Uses Apple's native `NSVisualEffectView` with `.hudWindow` material and `.vibrantDark` appearance—the same frosted glass used in native overlays.
* **Monospaced Typography:** Uses the system font with `.monospacedDigit()` to ensure the clock width remains stable as seconds tick.

### Zero-Overhead Performance
Optimized for battery life and negligible CPU usage:
* **TimelineView:** Replaces traditional Timers with SwiftUI's `TimelineView`, allowing the system to pause rendering when the window is obscured.
* **State Caching:** The app remembers its last visibility state. If the mouse hasn't moved into a danger zone, the app executes **zero UI updates**, keeping CPU usage near 0%.

### Dual Display Modes
Easily toggle via the menu bar icon:
* **Background Mode (Default):** A rounded, dark frosted glass background for maximum readability.
* **Transparent Mode:** Pure white text with a subtle shadow for a minimalist look.

## Technical Specifications

* **Language:** Swift 5
* **Frameworks:** SwiftUI, AppKit, Combine
* **Requirements:** macOS 12.0+
* **Architecture:** `NSWindow` (floating level), `NSVisualEffectView`, `TimelineView`

## How to Use

1.  Download and run the app.
2.  The clock appears in the top-right corner.
3.  **Click** the menu bar icon (clock symbol) to:
    * **Hide/Show Clock:** Toggle the display.
    * **Hide/Show Background:** Toggle the frosted glass background.
    * **Quit:** Exit the application.

## 📝 License

This project is open-source and available under the MIT License.
