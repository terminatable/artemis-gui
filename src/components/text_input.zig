const std = @import("std");
const gui = @import("../gui.zig");
const Component = @import("component.zig").Component;
const Style = @import("../style.zig").Style;
const Event = @import("../events.zig").Event;
const Rect = @import("../geometry.zig").Rect;
const Color = @import("../graphics.zig").Color;

/// Input validation types
pub const ValidationType = enum {
    none,
    text,
    email,
    number,
    password,
    url,
    custom,
};

/// Input formatting options
pub const FormatType = enum {
    none,
    uppercase,
    lowercase,
    capitalize,
    phone,
    currency,
    custom,
};

/// Text input validation result
pub const ValidationResult = struct {
    is_valid: bool,
    error_message: ?[]const u8 = null,
};

/// Custom validation function type
pub const ValidationFn = *const fn([]const u8) ValidationResult;
pub const FormatFn = *const fn([]const u8, std.mem.Allocator) ?[]const u8;

/// Text input component properties
pub const TextInputProps = struct {
    /// Current text value
    value: []const u8 = "",
    
    /// Placeholder text when empty
    placeholder: []const u8 = "",
    
    /// Maximum text length
    max_length: ?u32 = null,
    
    /// Whether input is enabled
    enabled: bool = true,
    
    /// Whether input is read-only
    readonly: bool = false,
    
    /// Input validation type
    validation_type: ValidationType = .none,
    
    /// Custom validation function
    custom_validator: ?ValidationFn = null,
    
    /// Input formatting type
    format_type: FormatType = .none,
    
    /// Custom formatting function
    custom_formatter: ?FormatFn = null,
    
    /// Whether to show validation errors
    show_validation: bool = true,
    
    /// Whether input is multiline
    multiline: bool = false,
    
    /// Number of visible lines for multiline
    lines: u32 = 1,
    
    /// Callback for text changes
    on_change: ?*const fn(*TextInput, []const u8) void = null,
    
    /// Callback for validation
    on_validate: ?*const fn(*TextInput, ValidationResult) void = null,
    
    /// Callback for focus events
    on_focus: ?*const fn(*TextInput, bool) void = null,
    
    /// Callback for submit (Enter key)
    on_submit: ?*const fn(*TextInput) void = null,
    
    /// Custom styling
    style: Style = Style{},
    
    /// Accessibility label
    aria_label: ?[]const u8 = null,
};

/// Text input component with validation and formatting
pub const TextInput = struct {
    /// Base component
    component: Component,
    
    /// Input properties
    props: TextInputProps,
    
    /// Internal text buffer
    text_buffer: std.ArrayList(u8),
    
    /// Cursor position in text
    cursor_position: u32 = 0,
    
    /// Selection start/end positions
    selection_start: u32 = 0,
    selection_end: u32 = 0,
    
    /// Visual state
    is_focused: bool = false,
    is_hovered: bool = false,
    
    /// Validation state
    validation_result: ValidationResult = ValidationResult{ .is_valid = true },
    last_validated_text: []const u8 = "",
    
    /// Cursor animation
    cursor_blink_timer: f32 = 0.0,
    cursor_visible: bool = true,
    
    /// Scroll offset for long text
    scroll_offset: f32 = 0.0,
    
    const Self = @This();
    const CURSOR_BLINK_RATE = 0.5; // Blink every 500ms
    
    pub fn init(allocator: std.mem.Allocator, props: TextInputProps) !*Self {
        var input = try allocator.create(Self);
        input.* = Self{
            .component = Component.init(.text_input),
            .props = props,
            .text_buffer = std.ArrayList(u8).init(allocator),
        };
        
        // Initialize with provided value
        try input.setText(props.value);
        
        return input;
    }
    
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.text_buffer.deinit();
        self.component.deinit(allocator);
        allocator.destroy(self);
    }
    
    /// Set the text content
    pub fn setText(self: *Self, text: []const u8) !void {
        self.text_buffer.clearRetainingCapacity();
        try self.text_buffer.appendSlice(text);
        
        // Adjust cursor position if necessary
        self.cursor_position = @min(self.cursor_position, @as(u32, @intCast(self.text_buffer.items.len)));
        
        // Clear selection
        self.selection_start = self.cursor_position;
        self.selection_end = self.cursor_position;
        
        // Validate new text
        try self.validateText();
        
        self.component.markDirty();
    }
    
    /// Get the current text content
    pub fn getText(self: *const Self) []const u8 {
        return self.text_buffer.items;
    }
    
    /// Update input properties
    pub fn setProps(self: *Self, props: TextInputProps) !void {
        const old_value = self.props.value;
        self.props = props;
        
        // Update text if value changed
        if (!std.mem.eql(u8, old_value, props.value)) {
            try self.setText(props.value);
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
                    self.component.markDirty();
                }
            },
            .press => {
                if (is_inside and event.button == .left) {
                    self.setFocus(true);
                    
                    // Calculate cursor position from mouse position
                    const text_bounds = self.getTextBounds(bounds);
                    const relative_x = event.x - text_bounds.x + self.scroll_offset;
                    self.cursor_position = self.getPositionFromX(relative_x);
                    
                    // Clear selection
                    self.selection_start = self.cursor_position;
                    self.selection_end = self.cursor_position;
                    
                    self.resetCursorBlink();
                    return true;
                } else if (!is_inside) {
                    self.setFocus(false);
                }
            },
            .release => {},
        }
        
        return false;
    }
    
    /// Handle keyboard events
    pub fn handleKeyEvent(self: *Self, event: Event.KeyEvent) bool {
        if (!self.props.enabled or !self.is_focused or event.type != .press) return false;
        
        switch (event.key) {
            .left => {
                if (self.cursor_position > 0) {
                    self.cursor_position -= 1;
                    if (!event.shift) {
                        self.selection_start = self.cursor_position;
                        self.selection_end = self.cursor_position;
                    }
                    self.resetCursorBlink();
                    self.component.markDirty();
                }
                return true;
            },
            .right => {
                if (self.cursor_position < self.text_buffer.items.len) {
                    self.cursor_position += 1;
                    if (!event.shift) {
                        self.selection_start = self.cursor_position;
                        self.selection_end = self.cursor_position;
                    }
                    self.resetCursorBlink();
                    self.component.markDirty();
                }
                return true;
            },
            .home => {
                self.cursor_position = 0;
                if (!event.shift) {
                    self.selection_start = self.cursor_position;
                    self.selection_end = self.cursor_position;
                }
                self.resetCursorBlink();
                self.component.markDirty();
                return true;
            },
            .end => {
                self.cursor_position = @intCast(self.text_buffer.items.len);
                if (!event.shift) {
                    self.selection_start = self.cursor_position;
                    self.selection_end = self.cursor_position;
                }
                self.resetCursorBlink();
                self.component.markDirty();
                return true;
            },
            .backspace => {
                if (self.hasSelection()) {
                    try self.deleteSelection();
                } else if (self.cursor_position > 0) {
                    _ = self.text_buffer.orderedRemove(self.cursor_position - 1);
                    self.cursor_position -= 1;
                    self.selection_start = self.cursor_position;
                    self.selection_end = self.cursor_position;
                }
                try self.onTextChanged();
                return true;
            },
            .delete => {
                if (self.hasSelection()) {
                    try self.deleteSelection();
                } else if (self.cursor_position < self.text_buffer.items.len) {
                    _ = self.text_buffer.orderedRemove(self.cursor_position);
                }
                try self.onTextChanged();
                return true;
            },
            .enter => {
                if (self.props.multiline) {
                    try self.insertText("\n");
                } else {
                    if (self.props.on_submit) |callback| {
                        callback(self);
                    }
                }
                return true;
            },
            .tab => {
                // Tab handling could insert tab or focus next element
                return false; // Let focus system handle it
            },
            else => {
                // Handle character input
                if (event.char) |char| {
                    if (char >= 32 and char <= 126) { // Printable ASCII
                        const char_byte = @as(u8, @intCast(char));
                        try self.insertText(&[_]u8{char_byte});
                        return true;
                    }
                }
            },
        }
        
        return false;
    }
    
    /// Insert text at cursor position
    fn insertText(self: *Self, text: []const u8) !void {
        if (self.props.readonly) return;
        
        // Check length limit
        if (self.props.max_length) |max| {
            if (self.text_buffer.items.len + text.len > max) return;
        }
        
        // Delete selection if present
        if (self.hasSelection()) {
            try self.deleteSelection();
        }
        
        // Insert text
        try self.text_buffer.insertSlice(self.cursor_position, text);
        self.cursor_position += @intCast(text.len);
        self.selection_start = self.cursor_position;
        self.selection_end = self.cursor_position;
        
        try self.onTextChanged();
    }
    
    /// Delete selected text
    fn deleteSelection(self: *Self) !void {
        if (!self.hasSelection()) return;
        
        const start = @min(self.selection_start, self.selection_end);
        const end = @max(self.selection_start, self.selection_end);
        
        // Remove selected text
        for (0..(end - start)) |_| {
            _ = self.text_buffer.orderedRemove(start);
        }
        
        self.cursor_position = start;
        self.selection_start = start;
        self.selection_end = start;
    }
    
    /// Check if there's a text selection
    fn hasSelection(self: *const Self) bool {
        return self.selection_start != self.selection_end;
    }
    
    /// Handle text change events
    fn onTextChanged(self: *Self) !void {
        // Apply formatting
        try self.applyFormatting();
        
        // Validate text
        try self.validateText();
        
        // Call callback
        if (self.props.on_change) |callback| {
            callback(self, self.text_buffer.items);
        }
        
        self.resetCursorBlink();
        self.component.markDirty();
    }
    
    /// Apply text formatting
    fn applyFormatting(self: *Self) !void {
        switch (self.props.format_type) {
            .none => {},
            .uppercase => {
                for (self.text_buffer.items) |*char| {
                    char.* = std.ascii.toUpper(char.*);
                }
            },
            .lowercase => {
                for (self.text_buffer.items) |*char| {
                    char.* = std.ascii.toLower(char.*);
                }
            },
            .capitalize => {
                var capitalize_next = true;
                for (self.text_buffer.items) |*char| {
                    if (capitalize_next and std.ascii.isAlphabetic(char.*)) {
                        char.* = std.ascii.toUpper(char.*);
                        capitalize_next = false;
                    } else if (!std.ascii.isAlphanumeric(char.*)) {
                        capitalize_next = true;
                    }
                }
            },
            .phone => {
                // Format as (XXX) XXX-XXXX
                // Implementation would be more complex
            },
            .currency => {
                // Format with currency symbols and decimal places
                // Implementation would be more complex
            },
            .custom => {
                if (self.props.custom_formatter) |formatter| {
                    if (formatter(self.text_buffer.items, self.text_buffer.allocator)) |formatted| {
                        self.text_buffer.clearRetainingCapacity();
                        try self.text_buffer.appendSlice(formatted);
                        // Would need to free formatted text in real implementation
                    }
                }
            },
        }
    }
    
    /// Validate current text
    fn validateText(self: *Self) !void {
        const text = self.text_buffer.items;
        
        // Skip validation if text hasn't changed
        if (std.mem.eql(u8, text, self.last_validated_text)) return;
        
        self.validation_result = switch (self.props.validation_type) {
            .none => ValidationResult{ .is_valid = true },
            .text => self.validateText_text(text),
            .email => self.validateEmail(text),
            .number => self.validateNumber(text),
            .password => self.validatePassword(text),
            .url => self.validateUrl(text),
            .custom => if (self.props.custom_validator) |validator| 
                validator(text) 
            else 
                ValidationResult{ .is_valid = true },
        };
        
        // Update last validated text
        // In real implementation, would need to manage memory properly
        self.last_validated_text = text;
        
        if (self.props.on_validate) |callback| {
            callback(self, self.validation_result);
        }
    }
    
    fn validateText_text(self: *const Self, text: []const u8) ValidationResult {
        _ = self;
        if (text.len == 0) {
            return ValidationResult{ .is_valid = false, .error_message = "Text is required" };
        }
        return ValidationResult{ .is_valid = true };
    }
    
    fn validateEmail(self: *const Self, text: []const u8) ValidationResult {
        _ = self;
        const has_at = std.mem.indexOf(u8, text, "@") != null;
        const has_dot = std.mem.indexOf(u8, text, ".") != null;
        
        if (!has_at or !has_dot) {
            return ValidationResult{ .is_valid = false, .error_message = "Invalid email format" };
        }
        return ValidationResult{ .is_valid = true };
    }
    
    fn validateNumber(self: *const Self, text: []const u8) ValidationResult {
        _ = self;
        if (text.len == 0) {
            return ValidationResult{ .is_valid = false, .error_message = "Number is required" };
        }
        
        _ = std.fmt.parseFloat(f64, text) catch {
            return ValidationResult{ .is_valid = false, .error_message = "Invalid number format" };
        };
        
        return ValidationResult{ .is_valid = true };
    }
    
    fn validatePassword(self: *const Self, text: []const u8) ValidationResult {
        _ = self;
        if (text.len < 8) {
            return ValidationResult{ .is_valid = false, .error_message = "Password must be at least 8 characters" };
        }
        return ValidationResult{ .is_valid = true };
    }
    
    fn validateUrl(self: *const Self, text: []const u8) ValidationResult {
        _ = self;
        if (!std.mem.startsWith(u8, text, "http://") and !std.mem.startsWith(u8, text, "https://")) {
            return ValidationResult{ .is_valid = false, .error_message = "URL must start with http:// or https://" };
        }
        return ValidationResult{ .is_valid = true };
    }
    
    /// Update animations
    pub fn update(self: *Self, delta_time: f32) void {
        if (self.is_focused) {
            self.cursor_blink_timer += delta_time;
            if (self.cursor_blink_timer >= CURSOR_BLINK_RATE) {
                self.cursor_visible = !self.cursor_visible;
                self.cursor_blink_timer = 0.0;
                self.component.markDirty();
            }
        }
    }
    
    /// Render the text input
    pub fn render(self: *Self, renderer: *gui.Renderer, bounds: Rect) !void {
        const style = self.getEffectiveStyle();
        
        // Draw background
        try renderer.fillRect(bounds, style.background_color);
        
        // Draw border
        const border_color = if (self.is_focused) 
            Color.fromRgb(100, 150, 255) 
        else if (!self.validation_result.is_valid) 
            Color.fromRgb(255, 100, 100)
        else 
            style.border_color;
            
        if (style.border_width > 0) {
            try renderer.drawRectBorder(bounds, border_color, style.border_width);
        }
        
        // Calculate text area
        const text_bounds = self.getTextBounds(bounds);
        
        // Draw text or placeholder
        const display_text = if (self.text_buffer.items.len > 0) 
            self.text_buffer.items 
        else 
            self.props.placeholder;
            
        const text_color = if (self.text_buffer.items.len > 0) 
            style.text_color 
        else 
            style.text_color.withAlpha(0.5);
        
        if (display_text.len > 0) {
            try renderer.drawText(display_text, text_bounds.x - self.scroll_offset, text_bounds.y, text_color, style.font_size);
        }
        
        // Draw selection
        if (self.hasSelection() and self.is_focused) {
            try self.drawSelection(renderer, text_bounds);
        }
        
        // Draw cursor
        if (self.is_focused and self.cursor_visible and !self.hasSelection()) {
            try self.drawCursor(renderer, text_bounds);
        }
        
        // Draw validation error
        if (!self.validation_result.is_valid and self.props.show_validation) {
            if (self.validation_result.error_message) |error_msg| {
                const error_y = bounds.y + bounds.height + 4;
                try renderer.drawText(error_msg, bounds.x, error_y, Color.fromRgb(255, 100, 100), style.font_size * 0.8);
            }
        }
    }
    
    fn getTextBounds(self: *const Self, bounds: Rect) Rect {
        const style = self.getEffectiveStyle();
        return bounds.shrink(style.padding);
    }
    
    fn drawSelection(self: *Self, renderer: *gui.Renderer, text_bounds: Rect) !void {
        const start = @min(self.selection_start, self.selection_end);
        const end = @max(self.selection_start, self.selection_end);
        
        const start_x = self.getXFromPosition(start);
        const end_x = self.getXFromPosition(end);
        
        const selection_bounds = Rect{
            .x = text_bounds.x + start_x - self.scroll_offset,
            .y = text_bounds.y,
            .width = end_x - start_x,
            .height = text_bounds.height,
        };
        
        try renderer.fillRect(selection_bounds, Color.fromRgb(100, 150, 255).withAlpha(0.3));
    }
    
    fn drawCursor(self: *Self, renderer: *gui.Renderer, text_bounds: Rect) !void {
        const cursor_x = self.getXFromPosition(self.cursor_position);
        const cursor_bounds = Rect{
            .x = text_bounds.x + cursor_x - self.scroll_offset,
            .y = text_bounds.y,
            .width = 1,
            .height = text_bounds.height,
        };
        
        try renderer.fillRect(cursor_bounds, Color.fromRgb(0, 0, 0));
    }
    
    fn getXFromPosition(self: *const Self, position: u32) f32 {
        if (position == 0) return 0.0;
        
        const text = self.text_buffer.items[0..@min(position, self.text_buffer.items.len)];
        // This would need proper text measurement implementation
        return @as(f32, @floatFromInt(text.len)) * 8.0; // Approximate character width
    }
    
    fn getPositionFromX(self: *const Self, x: f32) u32 {
        // This would need proper text measurement implementation
        const char_width = 8.0; // Approximate
        const position = @as(u32, @intFromFloat(x / char_width));
        return @min(position, @as(u32, @intCast(self.text_buffer.items.len)));
    }
    
    fn resetCursorBlink(self: *Self) void {
        self.cursor_blink_timer = 0.0;
        self.cursor_visible = true;
    }
    
    fn setFocus(self: *Self, focused: bool) void {
        if (self.is_focused != focused) {
            self.is_focused = focused;
            self.resetCursorBlink();
            
            if (self.props.on_focus) |callback| {
                callback(self, focused);
            }
            
            self.component.markDirty();
        }
    }
    
    fn getEffectiveStyle(self: *const Self) Style {
        var style = self.props.style;
        
        // Apply state-specific styling
        if (self.is_focused) {
            style.border_color = Color.fromRgb(100, 150, 255);
        } else if (!self.validation_result.is_valid) {
            style.border_color = Color.fromRgb(255, 100, 100);
        }
        
        if (!self.props.enabled) {
            style.background_color = Color.fromRgb(240, 240, 240);
            style.text_color = Color.fromRgb(160, 160, 160);
        }
        
        return style;
    }
    
    /// Get the component interface
    pub fn asComponent(self: *Self) *Component {
        return &self.component;
    }
    
    /// Check if input can receive focus
    pub fn canFocus(self: *const Self) bool {
        return self.props.enabled and !self.props.readonly;
    }
    
    /// Get validation status
    pub fn isValid(self: *const Self) bool {
        return self.validation_result.is_valid;
    }
};

// Tests
test "text_input_creation" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var input = try TextInput.init(allocator, TextInputProps{
        .placeholder = "Enter text...",
        .validation_type = .text,
    });
    defer input.deinit(allocator);
    
    try testing.expect(input.props.enabled);
    try testing.expectEqualStrings("", input.getText());
    try testing.expectEqualStrings("Enter text...", input.props.placeholder);
}

test "text_input_validation" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var input = try TextInput.init(allocator, TextInputProps{
        .validation_type = .email,
    });
    defer input.deinit(allocator);
    
    // Invalid email
    try input.setText("invalid");
    try testing.expect(!input.isValid());
    
    // Valid email
    try input.setText("test@example.com");
    try testing.expect(input.isValid());
}

test "text_input_cursor_movement" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var input = try TextInput.init(allocator, TextInputProps{});
    defer input.deinit(allocator);
    
    try input.setText("Hello World");
    input.cursor_position = 5;
    
    // Move cursor left
    const left_event = Event.KeyEvent{
        .type = .press,
        .key = .left,
        .shift = false,
        .ctrl = false,
        .alt = false,
        .char = null,
    };
    
    _ = input.handleKeyEvent(left_event);
    try testing.expectEqual(@as(u32, 4), input.cursor_position);
}