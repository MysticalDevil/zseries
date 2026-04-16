const std = @import("std");
const model = @import("model.zig");
const errors = @import("error.zig");
const parser = @import("parser.zig");
const render = @import("render.zig");

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

pub const parse = parser.parse;
pub const parseFile = parser.parseFile;
pub const renderDocument = render.renderDocument;
pub const renderRequest = render.renderRequest;
pub const runner = @import("runner.zig");

pub fn findRequestByName(document: *const Document, name: []const u8) ?*const Request {
    for (document.requests) |*request| {
        if (request.name) |value| {
            if (std.mem.eql(u8, value, name)) return request;
        }
    }
    return null;
}
