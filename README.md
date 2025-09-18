# Artemis GUI

[![Zig Version](https://img.shields.io/badge/zig-0.15.1-orange)](https://ziglang.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)]()

**A Ripple.js-inspired reactive GUI toolkit for Zig game development, built on Artemis Engine ECS.**

> **🎮 Game-Optimized**: Designed specifically for real-time game UIs with ECS integration and high-performance rendering.

## ✨ What is Artemis GUI?

Artemis GUI brings the elegant, reactive programming model of [Ripple.js](https://www.ripplejs.com/) to Zig game development. It provides a component-based, reactive UI system that integrates seamlessly with the Artemis Engine's ECS architecture.

### Key Features

- **🎯 Ripple.js-inspired API** - Familiar component syntax adapted for Zig
- **⚡ ECS-Powered** - Built on Artemis Engine for maximum performance
- **🔄 Reactive State** - Automatic UI updates when data changes
- **🎮 Game-Optimized** - Immediate and retained mode rendering
- **🏗️ Component-Based** - Modular, reusable UI components
- **🎨 Built-in Styling** - Theme system with game-friendly styling
- **📱 Event System** - Comprehensive input and interaction handling
- **🚀 High Performance** - Optimized for 60fps+ game UIs

## 🚀 Quick Start

### Prerequisites
- **Zig 0.15.1+**
- **Artemis Engine** (automatically handled as dependency)

### Installation

Add to your `build.zig.zon`:

```zig
.{
    .name = "my-game",
    .version = "0.1.0",
    .dependencies = .{
        .artemis_gui = .{
            .url = "https://github.com/terminatable/artemis-gui/archive/main.tar.gz",
            .hash = "...", // zig will provide this
        },
    },
}
```

### Your First GUI

```zig
const std = @import("std");
const gui = @import("artemis-gui");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Create GUI system
    var gui_system = try gui.Gui.init(gpa.allocator());
    defer gui_system.deinit();

    // Create a simple button
    const button = try gui.button(&gui_system)
        .position(100, 100)
        .size(200, 50)
        .text("Click Me!")
        .build();

    std.debug.print("GUI system initialized with button: {}\n", .{button});
}
```

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---

**Artemis GUI** - Reactive Game UI for Zig  
*Part of the [Terminatable](https://github.com/terminatable) ecosystem*