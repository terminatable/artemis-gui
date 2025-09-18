const std = @import("std");
const gui = @import("../gui.zig");
const Component = @import("component.zig").Component;
const Style = @import("../style.zig").Style;
const Event = @import("../events.zig").Event;
const Rect = @import("../geometry.zig").Rect;
const Color = @import("../graphics.zig").Color;

/// Button states for visual feedback
pub const ButtonState = enum {
    normal,
    hover,
    active,
    disabled,
    
    pub fn getStyleModifier(self: ButtonState) []const u8 {
        return switch (self) {
            .normal => "",
            .hover => ":hover",
            .active => ":active",
            .disabled => ":disabled",
        };
    }
};

/// Button component properties
pub const ButtonProps = struct {
    /// Button text content
    text: []const u8 = "",
    
    /// Icon to display (optional)
    icon: ?[]const u8 = null,
    
    /// Icon position relative to text
    icon_position: IconPosition = .left,
    
    /// Current button state
    state: ButtonState = .normal,
    
    /// Whether button is enabled
    enabled: bool = true,
    
    /// Callback for click events
    on_click: ?*const fn(*Button) void = null,
    
    /// Callback for hover events
    on_hover: ?*const fn(*Button, bool) void = null,
    
    /// Custom styling
    style: Style = Style{},
    
    /// Tooltip text
    tooltip: ?[]const u8 = null,
    
    /// Accessibility label
    aria_label: ?[]const u8 = null,
};

pub const IconPosition = enum {
    left,
    right,
    top,
    bottom,
};

/// Button component with interactive states
pub const Button = struct {
    /// Base component
    component: Component,
    
    /// Button properties
    props: ButtonProps,
    
    /// Internal state tracking
    is_pressed: bool = false,
    is_hovered: bool = false,
    
    /// Animation state for transitions
    animation_progress: f32 = 0.0,
    target_progress: f32 = 0.0,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, props: ButtonProps) !*Self {
        var button = try allocator.create(Self);
        button.* = Self{
            .component = Component.init(.button),
            .props = props,
        };
        
        // Set initial state
        button.updateState();
        
        return button;
    }
    
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.component.deinit(allocator);
        allocator.destroy(self);
    }
    
    /// Update button properties
    pub fn setProps(self: *Self, props: ButtonProps) void {
        const old_enabled = self.props.enabled;
        self.props = props;
        
        // Update state if enabled status changed
        if (old_enabled != props.enabled) {
            self.updateState();
        }
        
        self.component.markDirty();
    }
    
    /// Handle mouse events
    pub fn handleMouseEvent(self: *Self, event: Event.MouseEvent) bool {
        if (!self.props.enabled) return false;
        
        const bounds = self.component.getBounds();
        const is_inside = bounds.contains(event.x, event.y);
        
        switch (event.type) {
            .move => {
                const was_hovered = self.is_hovered;
                self.is_hovered = is_inside;
                
                if (was_hovered != self.is_hovered) {
                    self.updateState();
                    if (self.props.on_hover) |callback| {
                        callback(self, self.is_hovered);
                    }
                }
            },
            .press => {
                if (is_inside and event.button == .left) {
                    self.is_pressed = true;
                    self.updateState();
                    return true; // Consume event
                }
            },
            .release => {
                if (self.is_pressed and event.button == .left) {
                    self.is_pressed = false;
                    self.updateState();
                    
                    // Trigger click if mouse is still over button
                    if (is_inside and self.props.on_click) |callback| {
                        callback(self);
                    }
                    return true;
                }
            },
        }
        
        return false;
    }
    
    /// Handle keyboard events
    pub fn handleKeyEvent(self: *Self, event: Event.KeyEvent) bool {
        if (!self.props.enabled or !self.component.has_focus) return false;
        
        switch (event.key) {
            .space, .enter => {
                if (event.type == .press) {
                    self.is_pressed = true;
                    self.updateState();
                } else if (event.type == .release) {
                    self.is_pressed = false;
                    self.updateState();
                    
                    if (self.props.on_click) |callback| {
                        callback(self);
                    }
                }
                return true;
            },
            else => return false,
        }
    }
    
    /// Update button visual state
    fn updateState(self: *Self) void {
        if (!self.props.enabled) {
            self.props.state = .disabled;
            self.target_progress = 0.0;
        } else if (self.is_pressed) {
            self.props.state = .active;
            self.target_progress = 1.0;
        } else if (self.is_hovered) {
            self.props.state = .hover;
            self.target_progress = 0.5;
        } else {
            self.props.state = .normal;
            self.target_progress = 0.0;
        }
        
        self.component.markDirty();
    }
    
    /// Update animations
    pub fn update(self: *Self, delta_time: f32) void {
        // Smooth animation transitions
        const animation_speed = 8.0; // Speed of state transitions
        const diff = self.target_progress - self.animation_progress;
        
        if (@abs(diff) > 0.001) {
            self.animation_progress += diff * animation_speed * delta_time;
            self.component.markDirty();
        }
    }
    
    /// Render the button
    pub fn render(self: *Self, renderer: *gui.Renderer, bounds: Rect) !void {
        // Calculate colors based on state and animation
        const base_style = self.getEffectiveStyle();
        const bg_color = self.interpolateColor(base_style.background_color);
        const text_color = self.interpolateColor(base_style.text_color);
        const border_color = self.interpolateColor(base_style.border_color);
        
        // Draw background
        try renderer.fillRect(bounds, bg_color);
        
        // Draw border if specified
        if (base_style.border_width > 0) {
            try renderer.drawRectBorder(bounds, border_color, base_style.border_width);
        }
        
        // Calculate content layout
        const content_bounds = bounds.shrink(base_style.padding);
        
        // Render icon and text
        if (self.props.icon) |icon| {
            try self.renderIconAndText(renderer, content_bounds, icon, text_color);
        } else {
            try self.renderText(renderer, content_bounds, text_color);
        }
        
        // Render focus indicator if focused
        if (self.component.has_focus) {
            const focus_color = Color.fromRgb(100, 150, 255);
            const focus_bounds = bounds.grow(2);
            try renderer.drawRectBorder(focus_bounds, focus_color, 2);
        }
    }
    
    fn renderText(self: *Self, renderer: *gui.Renderer, bounds: Rect, color: Color) !void {
        if (self.props.text.len == 0) return;
        
        const style = self.getEffectiveStyle();
        const text_size = try renderer.measureText(self.props.text, style.font_size);
        
        // Center text in bounds
        const text_x = bounds.x + (bounds.width - text_size.width) / 2;
        const text_y = bounds.y + (bounds.height - text_size.height) / 2;
        
        try renderer.drawText(self.props.text, text_x, text_y, color, style.font_size);
    }
    
    fn renderIconAndText(self: *Self, renderer: *gui.Renderer, bounds: Rect, icon: []const u8, color: Color) !void {
        const style = self.getEffectiveStyle();
        const icon_size = 16; // Standard icon size
        const spacing = 8; // Space between icon and text
        
        const text_size = if (self.props.text.len > 0) 
            try renderer.measureText(self.props.text, style.font_size) 
        else 
            gui.Size{ .width = 0, .height = 0 };
        
        // Calculate total content size
        const total_width = switch (self.props.icon_position) {
            .left, .right => icon_size + spacing + text_size.width,
            .top, .bottom => @max(icon_size, text_size.width),
        };
        
        const total_height = switch (self.props.icon_position) {
            .left, .right => @max(icon_size, text_size.height),
            .top, .bottom => icon_size + spacing + text_size.height,
        };
        
        // Center content in bounds
        const content_x = bounds.x + (bounds.width - total_width) / 2;
        const content_y = bounds.y + (bounds.height - total_height) / 2;
        
        // Render icon and text based on position
        switch (self.props.icon_position) {
            .left => {
                try renderer.drawIcon(icon, content_x, content_y + (total_height - icon_size) / 2, icon_size, color);
                if (self.props.text.len > 0) {
                    try renderer.drawText(self.props.text, 
                        content_x + icon_size + spacing, 
                        content_y + (total_height - text_size.height) / 2, 
                        color, style.font_size);
                }
            },
            .right => {
                if (self.props.text.len > 0) {
                    try renderer.drawText(self.props.text, 
                        content_x, 
                        content_y + (total_height - text_size.height) / 2, 
                        color, style.font_size);
                }
                try renderer.drawIcon(icon, 
                    content_x + text_size.width + spacing, 
                    content_y + (total_height - icon_size) / 2, 
                    icon_size, color);
            },
            .top => {
                try renderer.drawIcon(icon, 
                    content_x + (total_width - icon_size) / 2, 
                    content_y, 
                    icon_size, color);
                if (self.props.text.len > 0) {
                    try renderer.drawText(self.props.text, 
                        content_x + (total_width - text_size.width) / 2, 
                        content_y + icon_size + spacing, 
                        color, style.font_size);
                }
            },
            .bottom => {
                if (self.props.text.len > 0) {
                    try renderer.drawText(self.props.text, 
                        content_x + (total_width - text_size.width) / 2, 
                        content_y, 
                        color, style.font_size);
                }
                try renderer.drawIcon(icon, 
                    content_x + (total_width - icon_size) / 2, 
                    content_y + text_size.height + spacing, 
                    icon_size, color);
            },
        }
    }
    
    fn getEffectiveStyle(self: *Self) Style {
        // Start with component's base style
        var style = self.props.style;
        
        // Apply state-specific style modifiers
        switch (self.props.state) {
            .normal => {
                // Base style already applied
            },
            .hover => {
                // Lighten background for hover
                style.background_color = style.background_color.lighten(0.1);
            },
            .active => {
                // Darken background for active state
                style.background_color = style.background_color.darken(0.1);
            },
            .disabled => {
                // Gray out disabled button
                style.background_color = Color.fromRgb(128, 128, 128);
                style.text_color = Color.fromRgb(160, 160, 160);
            },
        }
        
        return style;
    }
    
    fn interpolateColor(self: *Self, base_color: Color) Color {
        if (self.animation_progress == 0.0) return base_color;
        
        // Simple color interpolation for smooth transitions
        const factor = self.animation_progress;
        const accent_color = switch (self.props.state) {
            .normal => base_color,
            .hover => base_color.lighten(0.1),
            .active => base_color.darken(0.1),
            .disabled => Color.fromRgb(128, 128, 128),
        };
        
        return base_color.lerp(accent_color, factor);
    }
    
    /// Get the component interface
    pub fn asComponent(self: *Self) *Component {
        return &self.component;
    }
    
    /// Set button focus state
    pub fn setFocus(self: *Self, focused: bool) void {
        self.component.has_focus = focused;
        self.component.markDirty();
    }
    
    /// Check if button can receive focus
    pub fn canFocus(self: *Self) bool {
        return self.props.enabled;
    }
};

// Tests
test "button creation and basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var button = try Button.init(allocator, ButtonProps{
        .text = "Test Button",
        .enabled = true,
    });
    defer button.deinit(allocator);
    
    try testing.expect(button.props.enabled);
    try testing.expectEqualStrings("Test Button", button.props.text);
    try testing.expectEqual(ButtonState.normal, button.props.state);
}

test "button state transitions" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var button = try Button.init(allocator, ButtonProps{
        .text = "Test",
        .enabled = true,
    });
    defer button.deinit(allocator);
    
    // Test hover
    const hover_event = Event.MouseEvent{
        .type = .move,
        .x = 10,
        .y = 10,
        .button = .left,
    };
    
    // Set bounds for testing
    button.component.setBounds(Rect{ .x = 0, .y = 0, .width = 100, .height = 30 });
    
    _ = button.handleMouseEvent(hover_event);
    try testing.expect(button.is_hovered);
    
    // Test disabled state
    button.setProps(ButtonProps{
        .text = "Test",
        .enabled = false,
    });
    
    try testing.expectEqual(ButtonState.disabled, button.props.state);
}