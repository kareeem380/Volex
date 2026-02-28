# Volex (Velox) 🚀

Volex (formerly Velox) is a premium, high-performance macOS application launcher and clipboard manager designed with a modern "Liquid Glass" aesthetic. It replicates the "Windows + V" clipboard history experience with a native macOS feel.

## ✨ Features

- **Windows + V Experience**: Instant access to your clipboard history with auto-paste functionality.
- **Applications Search**: Fast and intelligent application launcher (Spotlight/Raycast style).
- **Premium Design**: 
    - Layered Glassmorphism (multi-level vibrancy).
    - Liquid Spring animations for all transitions.
    - modern "Pill" search bar and responsive card layouts.
- **Global Hotkey**: Summon Volex from anywhere using `Option + Space`.
- **Intelligent Truncation**: Gracefully handles long text copies with responsive previews.

## ⚡ Shortcuts

- **`Option + Space`**: Toggle Volex.
- **`Tab`**: Switch between **Clipboard** and **Apps** modes.
- **`Enter`**: Instant Paste (Clipboard) or Launch (Apps).
- **`Arrows`**: Navigate with smooth, spring-based scrolling.
- **`Cmd + Enter`**: Show selected application in Finder.
- **`Esc`**: Close Volex.

## 🛠️ Technical Details

- **Language**: Swift / SwiftUI.
- **Frameworks**: AppKit, Combine, Carbon (for hotkeys), CoreGraphics (for paste simulation).
- **Architecture**: MVVM with a centralized `ClipboardManager` and `NSMetadataQuery` for app indexing.

## 🚀 Getting Started

1. Clone the repository.
2. Open `Velox.xcodeproj` in Xcode.
3. Build and Run (`Cmd + R`).
4. **Important**: Volex requires **Accessibility Permissions** to simulate the "Paste" (`Cmd + V`) action.

---
*Created with ❤️ for macOS power users.*
