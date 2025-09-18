//! Artemis GUI v0.1.0 - Reactive UI Toolkit
//!
//! A Ripple.js-inspired reactive GUI toolkit for Zig game development.

const std = @import("std");
const artemis = @import("artemis-engine");

/// Main GUI system
pub const Gui = struct {
    allocator: std.mem.Allocator,
    components: std.ArrayList(ComponentId),
    
    pub fn init(allocator: std.mem.Allocator) !Gui {
        return .{
            .allocator = allocator,
            .components = std.ArrayList(ComponentId).init(allocator),
        };
    }
    
    pub fn deinit(self: *Gui) void {
        self.components.deinit();
    }
    
    pub fn render(self: *Gui) !void {
        _ = self;
        // Placeholder rendering
    }
};

/// Component identifier
pub const ComponentId = u32;

/// UI Color
pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
    
    pub fn init(r: f32, g: f32, b: f32, a: f32) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }
    
    pub fn red() Color {
        return init(1.0, 0.0, 0.0, 1.0);
    }
    
    pub fn green() Color {
        return init(0.0, 1.0, 0.0, 1.0);
    }
    
    pub fn blue() Color {
        return init(0.0, 0.0, 1.0, 1.0);
    }
};

/// 2D Vector
pub const Vec2 = struct {
    x: f32,
    y: f32,
    
    pub fn init(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }
};

/// Button builder
pub fn button(gui_system: *Gui) ButtonBuilder {
    _ = gui_system;
    return ButtonBuilder{};
}

/// Button builder struct
pub const ButtonBuilder = struct {
    pos_x: f32 = 0,
    pos_y: f32 = 0,
    size_w: f32 = 100,
    size_h: f32 = 30,
    button_text: []const u8 = "",
    
    pub fn position(self: ButtonBuilder, x: f32, y: f32) ButtonBuilder {
        var builder = self;
        builder.pos_x = x;
        builder.pos_y = y;
        return builder;
    }
    
    pub fn size(self: ButtonBuilder, w: f32, h: f32) ButtonBuilder {
        var builder = self;
        builder.size_w = w;
        builder.size_h = h;
        return builder;
    }
    
    pub fn text(self: ButtonBuilder, txt: []const u8) ButtonBuilder {
        var builder = self;
        builder.button_text = txt;
        return builder;
    }
    
    pub fn build(self: ButtonBuilder) !ComponentId {
        _ = self;
        return 1; // Placeholder component ID
    }
};

/// Panel builder
pub fn panel(gui_system: *Gui) PanelBuilder {
    _ = gui_system;
    return PanelBuilder{};
}

/// Panel builder struct
pub const PanelBuilder = struct {
    pos_x: f32 = 0,
    pos_y: f32 = 0,
    size_w: f32 = 100,
    size_h: f32 = 100,
    bg_color: Color = Color.init(0.5, 0.5, 0.5, 1.0),
    
    pub fn position(self: PanelBuilder, x: f32, y: f32) PanelBuilder {
        var builder = self;
        builder.pos_x = x;
        builder.pos_y = y;
        return builder;
    }
    
    pub fn size(self: PanelBuilder, w: f32, h: f32) PanelBuilder {
        var builder = self;
        builder.size_w = w;
        builder.size_h = h;
        return builder;
    }
    
    pub fn background(self: PanelBuilder, color: Color) PanelBuilder {
        var builder = self;
        builder.bg_color = color;
        return builder;
    }
    
    pub fn build(self: PanelBuilder) !ComponentId {
        _ = self;
        return 2; // Placeholder component ID
    }
};

test "gui initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    var gui_system = try Gui.init(gpa.allocator());
    defer gui_system.deinit();
    
    try std.testing.expect(gui_system.components.items.len == 0);
}