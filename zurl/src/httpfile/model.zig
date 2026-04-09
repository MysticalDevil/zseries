const std = @import("std");

pub const SourceLocation = struct {
    line: usize,
    column: usize,
};

pub const Segment = union(enum) {
    text: []const u8,
    variable: []const u8,
    env: []const u8,

    pub fn deinit(self: Segment, allocator: std.mem.Allocator) void {
        switch (self) {
            .text => |value| allocator.free(value),
            .variable => |value| allocator.free(value),
            .env => |value| allocator.free(value),
        }
    }
};

pub const TemplateString = struct {
    segments: []Segment,

    pub fn deinit(self: TemplateString, allocator: std.mem.Allocator) void {
        for (self.segments) |segment| {
            segment.deinit(allocator);
        }
        allocator.free(self.segments);
    }
};

pub const VariableDecl = struct {
    name: []const u8,
    value: TemplateString,
    location: SourceLocation,

    pub fn deinit(self: VariableDecl, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.value.deinit(allocator);
    }
};

pub const Header = struct {
    name: []const u8,
    value: TemplateString,
    location: SourceLocation,

    pub fn deinit(self: Header, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.value.deinit(allocator);
    }
};

pub const Body = union(enum) {
    @"inline": TemplateString,
    file_include: []const u8,

    pub fn deinit(self: Body, allocator: std.mem.Allocator) void {
        switch (self) {
            .@"inline" => |value| value.deinit(allocator),
            .file_include => |value| allocator.free(value),
        }
    }
};

pub const Request = struct {
    name: ?[]const u8,
    description: ?[]const u8,
    tags: []const []const u8,
    method: std.http.Method,
    target: TemplateString,
    headers: []Header,
    body: ?Body,
    location: SourceLocation,

    pub fn deinit(self: Request, allocator: std.mem.Allocator) void {
        if (self.name) |value| allocator.free(value);
        if (self.description) |value| allocator.free(value);
        for (self.tags) |tag| allocator.free(tag);
        allocator.free(self.tags);
        self.target.deinit(allocator);
        for (self.headers) |header| header.deinit(allocator);
        allocator.free(self.headers);
        if (self.body) |body| body.deinit(allocator);
    }
};

pub const Document = struct {
    variables: []VariableDecl,
    requests: []Request,
    source_path: ?[]const u8,

    pub fn deinit(self: Document, allocator: std.mem.Allocator) void {
        for (self.variables) |variable| variable.deinit(allocator);
        allocator.free(self.variables);
        for (self.requests) |request| request.deinit(allocator);
        allocator.free(self.requests);
        if (self.source_path) |value| allocator.free(value);
    }
};

pub const ResolvedHeader = struct {
    name: []const u8,
    value: []const u8,

    pub fn deinit(self: ResolvedHeader, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
    }
};

pub const ResolvedRequest = struct {
    name: ?[]const u8,
    description: ?[]const u8,
    tags: []const []const u8,
    method: std.http.Method,
    target: []const u8,
    headers: []ResolvedHeader,
    body: ?[]const u8,

    pub fn deinit(self: ResolvedRequest, allocator: std.mem.Allocator) void {
        if (self.name) |value| allocator.free(value);
        if (self.description) |value| allocator.free(value);
        for (self.tags) |tag| allocator.free(tag);
        allocator.free(self.tags);
        allocator.free(self.target);
        for (self.headers) |header| header.deinit(allocator);
        allocator.free(self.headers);
        if (self.body) |value| allocator.free(value);
    }
};
