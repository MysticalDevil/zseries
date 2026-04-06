const std = @import("std");
const zjwt = @import("zjwt");

const testing = std.testing;

test "algorithm from string" {
    try testing.expectEqual(zjwt.Algorithm.HS256, zjwt.Algorithm.fromString("HS256").?);
    try testing.expectEqual(zjwt.Algorithm.RS256, zjwt.Algorithm.fromString("RS256").?);
    try testing.expectEqual(zjwt.Algorithm.ES256, zjwt.Algorithm.fromString("ES256").?);
    try testing.expectEqual(null, zjwt.Algorithm.fromString("INVALID"));
}

test "encode and verify HS256 token" {
    const allocator = testing.allocator;
    const secret = "my-super-secret-key";

    var claims = zjwt.Claims.init(allocator);
    defer claims.deinit();

    claims.sub = "user123";
    claims.iss = "test-issuer";
    claims.exp = std.time.timestamp() + 3600;
    claims.iat = std.time.timestamp();
    try claims.setString("role", "admin");

    var encoder = zjwt.Encoder.init(allocator, .HS256, zjwt.Key.fromHmacSecret(secret));
    const token = try encoder.encode(claims);
    defer allocator.free(token);

    try testing.expect(std.mem.indexOf(u8, token, ".") != null);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, token, "."));

    var verifier = zjwt.Verifier.init(allocator, .HS256, zjwt.Key.fromHmacSecret(secret), .{
        .issuer = "test-issuer",
    });

    var verified = try verifier.verify(token);
    defer verified.deinit();

    try testing.expectEqualStrings("user123", verified.claims.sub.?);
    try testing.expectEqualStrings("test-issuer", verified.claims.iss.?);
    try testing.expectEqualStrings("admin", verified.claims.getString("role").?);
}

test "verify fails with wrong secret" {
    const allocator = testing.allocator;

    var claims = zjwt.Claims.init(allocator);
    defer claims.deinit();

    claims.sub = "user123";
    claims.exp = std.time.timestamp() + 3600;

    var encoder = zjwt.Encoder.init(allocator, .HS256, zjwt.Key.fromHmacSecret("correct-secret"));
    const token = try encoder.encode(claims);
    defer allocator.free(token);

    var verifier = zjwt.Verifier.init(allocator, .HS256, zjwt.Key.fromHmacSecret("wrong-secret"), .{});
    const result = verifier.verify(token);
    try testing.expectError(error.InvalidSignature, result);
}

test "verify fails with expired token" {
    const allocator = testing.allocator;

    var claims = zjwt.Claims.init(allocator);
    defer claims.deinit();

    claims.sub = "user123";
    claims.exp = std.time.timestamp() - 10; // 10 seconds ago

    var encoder = zjwt.Encoder.init(allocator, .HS256, zjwt.Key.fromHmacSecret("secret"));
    const token = try encoder.encode(claims);
    defer allocator.free(token);

    var verifier = zjwt.Verifier.init(allocator, .HS256, zjwt.Key.fromHmacSecret("secret"), .{});
    const result = verifier.verify(token);
    try testing.expectError(error.TokenExpired, result);
}

test "sliding expiration" {
    const allocator = testing.allocator;

    var claims = zjwt.Claims.init(allocator);
    defer claims.deinit();

    claims.sub = "user123";
    claims.exp = std.time.timestamp() + 100; // 100 seconds from now
    claims.iat = std.time.timestamp() - 3500; // Issued 1 hour ago

    var encoder = zjwt.Encoder.init(allocator, .HS256, zjwt.Key.fromHmacSecret("secret"));
    const token = try encoder.encode(claims);
    defer allocator.free(token);

    var verifier = zjwt.Verifier.init(allocator, .HS256, zjwt.Key.fromHmacSecret("secret"), .{
        .sliding_expiration = true,
        .sliding_window = 300, // 5 minutes
    });

    var verified = try verifier.verify(token);
    defer verified.deinit();

    // Should have a new token because less than 5 minutes remaining
    try testing.expect(verified.new_token != null);
}

test "base64url encoding" {
    const allocator = testing.allocator;

    const data = "hello world+/=";
    const encoded = try zjwt.base64UrlEncode(allocator, data);
    defer allocator.free(encoded);

    const decoded = try zjwt.base64UrlDecode(allocator, encoded);
    defer allocator.free(decoded);

    try testing.expectEqualStrings(data, decoded);
}
