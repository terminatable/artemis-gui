const std = @import("std");
const gui = @import("../gui.zig");
const Component = @import("component.zig").Component;
const Style = @import("../style.zig").Style;
const Event = @import("../events.zig").Event;
const Rect = @import("../geometry.zig").Rect;
const Color = @import("../graphics.zig").Color;
const Size = @import("../geometry.zig").Size;

/// Layout types for arranging child components
pub const LayoutType = enum {
    /// No automatic layout
    none,
    /// Vertical stack layout
    vertical,
    /// Horizontal row layout  
    horizontal,
    /// Grid layout with specified columns
    grid,
    /// Absolute positioning
    absolute,
    /// Flexbox-style layout
    flex,
};

/// Alignment options for layout
pub const Alignment = enum {
    start,
    center,
    end,
    stretch,
    space_between,
    space_around,
    space_evenly,
};

/// Layout properties for flex and grid layouts
pub const LayoutProps = struct {
    /// Primary axis alignment (main axis)
    justify_content: Alignment = .start,
    /// Cross axis alignment
    align_items: Alignment = .start,
    /// Whether to wrap items to new lines
    wrap: bool = false,
    /// Gap between items
    gap: f32 = 0.0,
    /// Grid-specific: number of columns
    grid_columns: u32 = 1,
    /// Flex-specific: direction
    flex_direction: enum { row, column } = .row,
};

/// Panel component properties
pub const PanelProps = struct {
    /// Layout type for child components
    layout: LayoutType = .none,
    /// Layout configuration
    layout_props: LayoutProps = LayoutProps{},
    
    /// Whether panel is scrollable
    scrollable: bool = false,
    /// Scroll position
    scroll_x: f32 = 0.0,
    scroll_y: f32 = 0.0,
    
    /// Whether to clip child content to panel bounds
    clip_contents: bool = true,
    
    /// Minimum size constraints
    min_width: ?f32 = null,
    min_height: ?f32 = null,
    
    /// Maximum size constraints
    max_width: ?f32 = null,
    max_height: ?f32 = null,
    
    /// Custom styling
    style: Style = Style{},
    
    /// Background image (optional)
    background_image: ?[]const u8 = null,
    
    /// Callback for scroll events
    on_scroll: ?*const fn(*Panel, f32, f32) void = null,
    
    /// Callback for resize events
    on_resize: ?*const fn(*Panel, Size) void = null,
};

/// Child component information for layout calculation
pub const ChildInfo = struct {
    component: *Component,
    /// Layout-specific properties
    flex_grow: f32 = 0.0,
    flex_shrink: f32 = 1.0,
    flex_basis: ?f32 = null,
    /// Grid-specific properties
    grid_column: ?u32 = null,
    grid_row: ?u32 = null,
    grid_column_span: u32 = 1,
    grid_row_span: u32 = 1,
    /// Absolute positioning
    position: ?Rect = null,
    /// Margins
    margin_top: f32 = 0.0,
    margin_bottom: f32 = 0.0,
    margin_left: f32 = 0.0,
    margin_right: f32 = 0.0,
};

/// Panel container component with layout management
pub const Panel = struct {
    /// Base component
    component: Component,
    
    /// Panel properties
    props: PanelProps,
    
    /// Child components
    children: std.ArrayList(ChildInfo),
    
    /// Scrolling state
    scroll_position: struct { x: f32, y: f32 } = .{ .x = 0.0, .y = 0.0 },
    content_size: Size = Size{ .width = 0.0, .height = 0.0 },
    
    /// Drag scrolling
    is_scrolling: bool = false,
    last_mouse_pos: struct { x: f32, y: f32 } = .{ .x = 0.0, .y = 0.0 },
    
    /// Layout cache
    layout_cache: ?LayoutCache = null,
    needs_layout: bool = true,
    
    const Self = @This();
    
    const LayoutCache = struct {
        child_bounds: std.ArrayList(Rect),
        content_size: Size,
        
        fn init(allocator: std.mem.Allocator) LayoutCache {
            return LayoutCache{
                .child_bounds = std.ArrayList(Rect).init(allocator),
                .content_size = Size{ .width = 0.0, .height = 0.0 },
            };
        }
        
        fn deinit(self: *LayoutCache) void {
            self.child_bounds.deinit();
        }
    };
    
    pub fn init(allocator: std.mem.Allocator, props: PanelProps) !*Self {
        var panel = try allocator.create(Self);
        panel.* = Self{
            .component = Component.init(.panel),
            .props = props,
            .children = std.ArrayList(ChildInfo).init(allocator),
        };
        
        panel.layout_cache = LayoutCache.init(allocator);
        
        return panel;
    }
    
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        if (self.layout_cache) |*cache| {
            cache.deinit();
        }
        self.children.deinit();
        self.component.deinit(allocator);
        allocator.destroy(self);
    }
    
    /// Add a child component
    pub fn addChild(self: *Self, child: *Component) !void {
        const child_info = ChildInfo{
            .component = child,
        };
        try self.children.append(child_info);
        self.needs_layout = true;
        self.component.markDirty();
    }
    
    /// Add a child with layout properties
    pub fn addChildWithLayout(self: *Self, child_info: ChildInfo) !void {
        try self.children.append(child_info);
        self.needs_layout = true;
        self.component.markDirty();
    }
    
    /// Remove a child component
    pub fn removeChild(self: *Self, child: *Component) void {
        for (self.children.items, 0..) |child_info, i| {
            if (child_info.component == child) {
                _ = self.children.orderedRemove(i);
                self.needs_layout = true;
                self.component.markDirty();
                break;
            }
        }
    }
    
    /// Clear all children
    pub fn clearChildren(self: *Self) void {
        self.children.clearRetainingCapacity();
        self.needs_layout = true;
        self.component.markDirty();
    }
    
    /// Update panel properties
    pub fn setProps(self: *Self, props: PanelProps) void {
        self.props = props;
        self.needs_layout = true;
        self.component.markDirty();
    }
    
    /// Set scroll position
    pub fn setScrollPosition(self: *Self, x: f32, y: f32) void {
        const old_x = self.scroll_position.x;
        const old_y = self.scroll_position.y;
        
        self.scroll_position.x = @max(0.0, @min(x, self.getMaxScrollX()));
        self.scroll_position.y = @max(0.0, @min(y, self.getMaxScrollY()));
        
        if (old_x != self.scroll_position.x or old_y != self.scroll_position.y) {
            self.component.markDirty();
            
            if (self.props.on_scroll) |callback| {
                callback(self, self.scroll_position.x, self.scroll_position.y);
            }
        }
    }
    
    /// Handle mouse events
    pub fn handleMouseEvent(self: *Self, event: Event.MouseEvent) bool {
        const bounds = self.component.getBounds();
        const is_inside = bounds.contains(event.x, event.y);
        
        if (self.props.scrollable) {
            switch (event.type) {
                .press => {
                    if (is_inside and event.button == .left) {
                        self.is_scrolling = true;
                        self.last_mouse_pos.x = event.x;
                        self.last_mouse_pos.y = event.y;
                        return true;
                    }
                },
                .release => {
                    if (self.is_scrolling and event.button == .left) {
                        self.is_scrolling = false;
                        return true;
                    }
                },
                .move => {
                    if (self.is_scrolling) {
                        const delta_x = event.x - self.last_mouse_pos.x;
                        const delta_y = event.y - self.last_mouse_pos.y;
                        
                        self.setScrollPosition(
                            self.scroll_position.x - delta_x,
                            self.scroll_position.y - delta_y
                        );
                        
                        self.last_mouse_pos.x = event.x;
                        self.last_mouse_pos.y = event.y;
                        return true;
                    }
                },
                .scroll => {
                    if (is_inside) {
                        self.setScrollPosition(
                            self.scroll_position.x - event.scroll_x * 20,
                            self.scroll_position.y - event.scroll_y * 20
                        );
                        return true;
                    }
                },
            }
        }
        
        // Forward event to children
        var handled = false;
        for (self.children.items) |child_info| {
            const child_bounds = child_info.component.getBounds();
            const adjusted_event = Event.MouseEvent{
                .type = event.type,
                .x = event.x + self.scroll_position.x,
                .y = event.y + self.scroll_position.y,
                .button = event.button,
                .scroll_x = event.scroll_x,
                .scroll_y = event.scroll_y,
            };
            
            if (child_bounds.contains(adjusted_event.x, adjusted_event.y)) {
                // Forward to child component's mouse handler
                // This would need to be implemented based on the specific component
                // For now, just mark as handled if inside child bounds
                handled = true;
                break;
            }
        }
        
        return handled;
    }
    
    /// Update layout if needed
    pub fn updateLayout(self: *Self, available_size: Size) !void {
        if (!self.needs_layout) return;
        
        const content_bounds = self.getContentBounds(available_size);
        
        switch (self.props.layout) {
            .none => try self.layoutNone(content_bounds),
            .vertical => try self.layoutVertical(content_bounds),
            .horizontal => try self.layoutHorizontal(content_bounds),
            .grid => try self.layoutGrid(content_bounds),
            .absolute => try self.layoutAbsolute(content_bounds),
            .flex => try self.layoutFlex(content_bounds),
        }
        
        self.needs_layout = false;
        
        // Notify resize if size changed
        if (self.props.on_resize) |callback| {
            callback(self, available_size);
        }
    }
    
    fn getContentBounds(self: *const Self, available_size: Size) Rect {
        const style = self.props.style;
        return Rect{
            .x = style.padding.left,
            .y = style.padding.top,
            .width = available_size.width - style.padding.left - style.padding.right,
            .height = available_size.height - style.padding.top - style.padding.bottom,
        };
    }
    
    /// No automatic layout - children positioned manually
    fn layoutNone(self: *Self, content_bounds: Rect) !void {
        _ = content_bounds;
        var cache = &self.layout_cache.?;
        
        cache.child_bounds.clearRetainingCapacity();
        
        for (self.children.items) |child_info| {
            // Use child's existing bounds or default
            const child_bounds = child_info.component.getBounds();
            try cache.child_bounds.append(child_bounds);
        }
        
        // Content size is the bounds that encompasses all children
        self.calculateContentSize();
    }
    
    /// Vertical stack layout
    fn layoutVertical(self: *Self, content_bounds: Rect) !void {
        var cache = &self.layout_cache.?;
        cache.child_bounds.clearRetainingCapacity();
        
        var current_y = content_bounds.y;
        const gap = self.props.layout_props.gap;
        
        for (self.children.items) |child_info| {
            // Calculate child size (simplified - would need proper measurement)
            const child_width = content_bounds.width - child_info.margin_left - child_info.margin_right;
            const child_height = 30.0; // Default height - would need proper measurement
            
            const child_bounds = Rect{
                .x = content_bounds.x + child_info.margin_left,
                .y = current_y + child_info.margin_top,
                .width = child_width,
                .height = child_height,
            };
            
            child_info.component.setBounds(child_bounds);
            try cache.child_bounds.append(child_bounds);
            
            current_y += child_height + child_info.margin_top + child_info.margin_bottom + gap;
        }
        
        self.content_size.width = content_bounds.width;
        self.content_size.height = current_y - content_bounds.y;
    }
    
    /// Horizontal row layout
    fn layoutHorizontal(self: *Self, content_bounds: Rect) !void {
        var cache = &self.layout_cache.?;
        cache.child_bounds.clearRetainingCapacity();
        
        var current_x = content_bounds.x;
        const gap = self.props.layout_props.gap;
        
        for (self.children.items) |child_info| {
            // Calculate child size
            const child_width = 100.0; // Default width - would need proper measurement
            const child_height = content_bounds.height - child_info.margin_top - child_info.margin_bottom;
            
            const child_bounds = Rect{
                .x = current_x + child_info.margin_left,
                .y = content_bounds.y + child_info.margin_top,
                .width = child_width,
                .height = child_height,
            };
            
            child_info.component.setBounds(child_bounds);
            try cache.child_bounds.append(child_bounds);
            
            current_x += child_width + child_info.margin_left + child_info.margin_right + gap;
        }
        
        self.content_size.width = current_x - content_bounds.x;
        self.content_size.height = content_bounds.height;
    }
    
    /// Grid layout
    fn layoutGrid(self: *Self, content_bounds: Rect) !void {
        var cache = &self.layout_cache.?;
        cache.child_bounds.clearRetainingCapacity();
        
        const columns = self.props.layout_props.grid_columns;
        const gap = self.props.layout_props.gap;
        
        const cell_width = (content_bounds.width - gap * @as(f32, @floatFromInt(columns - 1))) / @as(f32, @floatFromInt(columns));
        const cell_height = 100.0; // Default cell height
        
        for (self.children.items, 0..) |child_info, i| {
            const col = @as(u32, @intCast(i)) % columns;
            const row = @as(u32, @intCast(i)) / columns;
            
            const x = content_bounds.x + @as(f32, @floatFromInt(col)) * (cell_width + gap) + child_info.margin_left;
            const y = content_bounds.y + @as(f32, @floatFromInt(row)) * (cell_height + gap) + child_info.margin_top;
            
            const child_bounds = Rect{
                .x = x,
                .y = y,
                .width = cell_width - child_info.margin_left - child_info.margin_right,
                .height = cell_height - child_info.margin_top - child_info.margin_bottom,
            };
            
            child_info.component.setBounds(child_bounds);
            try cache.child_bounds.append(child_bounds);
        }
        
        const rows = (self.children.items.len + columns - 1) / columns; // Ceiling division
        self.content_size.width = content_bounds.width;
        self.content_size.height = @as(f32, @floatFromInt(rows)) * (cell_height + gap) - gap;
    }
    
    /// Absolute positioning layout
    fn layoutAbsolute(self: *Self, content_bounds: Rect) !void {
        var cache = &self.layout_cache.?;
        cache.child_bounds.clearRetainingCapacity();
        
        for (self.children.items) |child_info| {
            const child_bounds = if (child_info.position) |pos| 
                Rect{
                    .x = content_bounds.x + pos.x,
                    .y = content_bounds.y + pos.y,
                    .width = pos.width,
                    .height = pos.height,
                }
            else 
                child_info.component.getBounds();
            
            child_info.component.setBounds(child_bounds);
            try cache.child_bounds.append(child_bounds);
        }
        
        self.calculateContentSize();
    }
    
    /// Flexbox-style layout
    fn layoutFlex(self: *Self, content_bounds: Rect) !void {
        const direction = self.props.layout_props.flex_direction;
        
        if (direction == .row) {
            try self.layoutFlexHorizontal(content_bounds);
        } else {
            try self.layoutFlexVertical(content_bounds);
        }
    }
    
    fn layoutFlexHorizontal(self: *Self, content_bounds: Rect) !void {
        var cache = &self.layout_cache.?;
        cache.child_bounds.clearRetainingCapacity();
        
        // Calculate total flex grow and fixed sizes
        var total_flex_grow: f32 = 0.0;
        var total_fixed_width: f32 = 0.0;
        
        for (self.children.items) |child_info| {
            if (child_info.flex_grow > 0.0) {
                total_flex_grow += child_info.flex_grow;
            } else {
                total_fixed_width += child_info.flex_basis orelse 100.0; // Default width
            }
        }
        
        const available_flex_width = content_bounds.width - total_fixed_width;
        const flex_unit = if (total_flex_grow > 0.0) available_flex_width / total_flex_grow else 0.0;
        
        var current_x = content_bounds.x;
        
        for (self.children.items) |child_info| {
            const child_width = if (child_info.flex_grow > 0.0) 
                child_info.flex_grow * flex_unit 
            else 
                child_info.flex_basis orelse 100.0;
            
            const child_bounds = Rect{
                .x = current_x + child_info.margin_left,
                .y = content_bounds.y + child_info.margin_top,
                .width = child_width - child_info.margin_left - child_info.margin_right,
                .height = content_bounds.height - child_info.margin_top - child_info.margin_bottom,
            };
            
            child_info.component.setBounds(child_bounds);
            try cache.child_bounds.append(child_bounds);
            
            current_x += child_width + child_info.margin_left + child_info.margin_right;
        }
        
        self.content_size.width = current_x - content_bounds.x;
        self.content_size.height = content_bounds.height;
    }
    
    fn layoutFlexVertical(self: *Self, content_bounds: Rect) !void {
        // Similar to layoutFlexHorizontal but for vertical direction
        // Implementation would be similar with height calculations
        try self.layoutVertical(content_bounds);
    }
    
    fn calculateContentSize(self: *Self) void {
        if (self.layout_cache) |*cache| {
            var max_x: f32 = 0.0;
            var max_y: f32 = 0.0;
            
            for (cache.child_bounds.items) |bounds| {
                max_x = @max(max_x, bounds.x + bounds.width);
                max_y = @max(max_y, bounds.y + bounds.height);
            }
            
            self.content_size.width = max_x;
            self.content_size.height = max_y;
        }
    }
    
    fn getMaxScrollX(self: *const Self) f32 {
        const bounds = self.component.getBounds();
        return @max(0.0, self.content_size.width - bounds.width);
    }
    
    fn getMaxScrollY(self: *const Self) f32 {
        const bounds = self.component.getBounds();
        return @max(0.0, self.content_size.height - bounds.height);
    }
    
    /// Render the panel
    pub fn render(self: *Self, renderer: *gui.Renderer, bounds: Rect) !void {
        const style = self.props.style;
        
        // Draw background
        if (self.props.background_image) |image| {
            try renderer.drawImage(image, bounds, style.background_color);
        } else {
            try renderer.fillRect(bounds, style.background_color);
        }
        
        // Draw border
        if (style.border_width > 0) {
            try renderer.drawRectBorder(bounds, style.border_color, style.border_width);
        }
        
        // Set up clipping if enabled
        if (self.props.clip_contents) {
            try renderer.pushClipRect(bounds);
        }
        
        // Render children with scroll offset
        for (self.children.items) |child_info| {
            const child_bounds = child_info.component.getBounds();
            const offset_bounds = Rect{
                .x = child_bounds.x - self.scroll_position.x,
                .y = child_bounds.y - self.scroll_position.y,
                .width = child_bounds.width,
                .height = child_bounds.height,
            };
            
            // Only render if visible
            if (bounds.intersects(offset_bounds)) {
                // This would call the child's render method
                // child_info.component.render(renderer, offset_bounds);
            }
        }
        
        // Restore clipping
        if (self.props.clip_contents) {
            try renderer.popClipRect();
        }
        
        // Draw scrollbars if scrollable
        if (self.props.scrollable) {
            try self.drawScrollbars(renderer, bounds);
        }
    }
    
    fn drawScrollbars(self: *Self, renderer: *gui.Renderer, bounds: Rect) !void {
        const scrollbar_width = 12.0;
        const scrollbar_color = Color.fromRgb(180, 180, 180);
        const thumb_color = Color.fromRgb(100, 100, 100);
        
        // Vertical scrollbar
        if (self.content_size.height > bounds.height) {
            const scrollbar_bounds = Rect{
                .x = bounds.x + bounds.width - scrollbar_width,
                .y = bounds.y,
                .width = scrollbar_width,
                .height = bounds.height,
            };
            
            try renderer.fillRect(scrollbar_bounds, scrollbar_color);
            
            // Thumb
            const thumb_height = (bounds.height / self.content_size.height) * bounds.height;
            const thumb_y = bounds.y + (self.scroll_position.y / self.getMaxScrollY()) * (bounds.height - thumb_height);
            
            const thumb_bounds = Rect{
                .x = scrollbar_bounds.x + 2,
                .y = thumb_y,
                .width = scrollbar_width - 4,
                .height = thumb_height,
            };
            
            try renderer.fillRect(thumb_bounds, thumb_color);
        }
        
        // Horizontal scrollbar (similar implementation)
        if (self.content_size.width > bounds.width) {
            // Implementation similar to vertical scrollbar
        }
    }
    
    /// Get the component interface
    pub fn asComponent(self: *Self) *Component {
        return &self.component;
    }
    
    /// Get child count
    pub fn getChildCount(self: *const Self) usize {
        return self.children.items.len;
    }
    
    /// Get content size
    pub fn getContentSize(self: *const Self) Size {
        return self.content_size;
    }
};

// Tests
test "panel_creation" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var panel = try Panel.init(allocator, PanelProps{
        .layout = .vertical,
    });
    defer panel.deinit(allocator);
    
    try testing.expectEqual(@as(usize, 0), panel.getChildCount());
    try testing.expectEqual(LayoutType.vertical, panel.props.layout);
}

test "panel_child_management" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var panel = try Panel.init(allocator, PanelProps{});
    defer panel.deinit(allocator);
    
    var child_component = Component.init(.button);
    try panel.addChild(&child_component);
    
    try testing.expectEqual(@as(usize, 1), panel.getChildCount());
    
    panel.removeChild(&child_component);
    try testing.expectEqual(@as(usize, 0), panel.getChildCount());
}