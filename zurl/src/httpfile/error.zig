const model = @import("model.zig");

pub const Error = error{
    OutOfMemory,
    WriteFailed,
    InvalidRequestLine,
    InvalidMethod,
    InvalidHeader,
    MissingHeaderSeparator,
    InvalidMetadata,
    InvalidVariableDeclaration,
    DuplicateVariable,
    MissingRequest,
    UnexpectedContent,
    UnclosedInterpolation,
    EmptyInterpolationName,
    InvalidEnvInterpolation,
    UndefinedVariable,
    CircularVariableReference,
    MissingSourcePath,
    FileIncludeNotFound,
    InvalidCliArgs,
    RequestNotFound,
};

pub const ParseError = struct {
    err: Error,
    location: model.SourceLocation,
    message: []const u8,
};
