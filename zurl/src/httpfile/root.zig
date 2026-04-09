const std = @import("std");
const model = @import("model.zig");
const errors = @import("error.zig");

pub const Body = model.Body;
pub const Document = model.Document;
pub const Header = model.Header;
pub const Request = model.Request;
pub const ResolvedHeader = model.ResolvedHeader;
pub const ResolvedRequest = model.ResolvedRequest;
pub const Segment = model.Segment;
pub const SourceLocation = model.SourceLocation;
pub const TemplateString = model.TemplateString;
pub const VariableDecl = model.VariableDecl;
pub const Error = errors.Error;
pub const ParseError = errors.ParseError;

pub const parse = @import("parser.zig").parse;
pub const parseFile = @import("parser.zig").parseFile;
pub const renderDocument = @import("render.zig").renderDocument;
pub const renderRequest = @import("render.zig").renderRequest;
pub const runner = @import("runner.zig");

pub fn findRequestByName(document: *const Document, name: []const u8) ?*const Request {
    for (document.requests) |*request| {
        if (request.name) |value| {
            if (std.mem.eql(u8, value, name)) return request;
        }
    }
    return null;
}
