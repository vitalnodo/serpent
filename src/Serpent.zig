const std = @import("std");
const testing = std.testing;
const rotl = std.math.rotl;
const rotr = std.math.rotr;
const bufPrint = std.fmt.bufPrint;
const hexToBytes = std.fmt.hexToBytes;
const fmtSliceHexUpper = std.fmt.fmtSliceHexUpper;
const writeIntLittle = std.mem.writeIntLittle;
const readIntLittle = std.mem.readIntLittle;
const sBox = @import("sboxes.zig").sBox;
const sBoxInv = @import("sboxes.zig").sBoxInv;

pub const Serpent = struct {
    const PHI: u32 = 0x9E3779B9;
    const Block = [4]u32;
    const RoundKeys = [132]u32;

    pub fn expandKey(key: []const u8) RoundKeys {
        var k = [_]u32{0} ** 32;
        var i: usize = 0;
        while (i <= key.len - 4) : (i += 4) {
            k[i / 4] = @as(u32, key[i]);
            k[i / 4] |= @as(u32, key[i + 1]) << 8;
            k[i / 4] |= @as(u32, key[i + 2]) << 16;
            k[i / 4] |= @as(u32, key[i + 3]) << 24;
        }
        if (i / 4 < 16) {
            k[i / 4] = 1;
        }

        var s = [_]u32{0} ** 132;
        i = 8;
        while (i < 16) : (i += 1) {
            var x: u32 = k[i - 8] ^ k[i - 5] ^ k[i - 3] ^ k[i - 1] ^ PHI ^ @intCast(u32, i - 8);
            k[i] = rotl(u32, x, 11);
            s[i - 8] = k[i];
        }

        i = 8;
        while (i < 132) : (i += 1) {
            var x: u32 = s[i - 8] ^ s[i - 5] ^ s[i - 3] ^ s[i - 1] ^ PHI ^ @intCast(u32, i);
            s[i] = rotl(u32, x, 11);
        }
        return s;
    }

    pub fn keySchedule(expanded_key: RoundKeys) RoundKeys {
        var res = expanded_key;
        var i: usize = 0;
        var j: usize = 3;
        while (i < 132) : (i += 4) {
            var x = sBox[j](expanded_key[i .. i + 4][0..4].*);
            res[i] = x[0];
            res[i + 1] = x[1];
            res[i + 2] = x[2];
            res[i + 3] = x[3];
            j = (j + 7) % 8;
        }
        return res;
    }

    fn linearTransform(block: Block) Block {
        var w0 = block[0];
        var w1 = block[1];
        var w2 = block[2];
        var w3 = block[3];
        w0 = rotl(u32, w0, 13);
        w2 = rotl(u32, w2, 3);
        w1 ^= w0 ^ w2;
        w3 ^= w2 ^ w0 << 3;
        w1 = rotl(u32, w1, 1);
        w3 = rotl(u32, w3, 7);
        w0 ^= w1 ^ w3;
        w2 ^= w3 ^ (w1 << 7);
        w0 = rotl(u32, w0, 5);
        w2 = rotl(u32, w2, 22);
        return [4]u32{ w0, w1, w2, w3 };
    }

    fn inverseLinearTransform(block: Block) Block {
        var w0 = block[0];
        var w1 = block[1];
        var w2 = block[2];
        var w3 = block[3];
        w2 = rotr(u32, w2, 22);
        w0 = rotr(u32, w0, 5);
        w2 ^= w3 ^ (w1 << 7);
        w0 ^= w1 ^ w3;
        w3 = rotr(u32, w3, 7);
        w1 = rotr(u32, w1, 1);
        w3 ^= w2 ^ w0 << 3;
        w1 ^= w0 ^ w2;
        w2 = rotr(u32, w2, 3);
        w0 = rotr(u32, w0, 13);
        return [4]u32{ w0, w1, w2, w3 };
    }

    fn xor(block: Block, key: Block) Block {
        return [4]u32{
            block[0] ^ key[0],
            block[1] ^ key[1],
            block[2] ^ key[2],
            block[3] ^ key[3],
        };
    }

    pub fn encryptBlock(block: Block, round_keys: RoundKeys) Block {
        var b: Block = block;
        var i: usize = 0;
        while (i <= 30 * 4) {
            b = xor(b, round_keys[i .. i + 4][0..4].*);
            b = sBox[(i / 4) % 8](b);
            b = linearTransform(b);
            i += 4;
        }
        b = xor(b, round_keys[4 * 31 .. 4 * 31 + 4][0..4].*);
        b = sBox[7](b);
        b = xor(b, round_keys[4 * 32 .. 4 * 32 + 4][0..4].*);
        return b;
    }

    pub fn decryptBlock(block: Block, round_keys: RoundKeys) Block {
        var b: Block = block;
        b = xor(b, round_keys[4 * 32 .. 4 * 32 + 4][0..4].*);
        b = sBoxInv[7](b);
        b = xor(b, round_keys[4 * 31 .. 4 * 31 + 4][0..4].*);
        var i: usize = 30 * 4;
        while (i >= 4) : (i -= 4) {
            b = inverseLinearTransform(b);
            b = sBoxInv[(i / 4) % 8](b);
            b = xor(b, round_keys[i .. i + 4][0..4].*);
        }
        b = inverseLinearTransform(b);
        b = sBoxInv[0](b);
        b = xor(b, round_keys[0..4][0..4].*);
        return b;
    }

    pub fn blockFromBytes(bytes: [16]u8) Block {
        var block = Block{ 0, 0, 0, 0 };
        block[0] = readIntLittle(u32, bytes[0..4]);
        block[1] = readIntLittle(u32, bytes[4..8]);
        block[2] = readIntLittle(u32, bytes[8..12]);
        block[3] = readIntLittle(u32, bytes[12..16]);
        return block;
    }

    pub fn blockToBytes(block: Block) [16]u8 {
        var bytes: [16]u8 = undefined;
        writeIntLittle(u32, bytes[0..4], block[0]);
        writeIntLittle(u32, bytes[4..8], block[1]);
        writeIntLittle(u32, bytes[8..12], block[2]);
        writeIntLittle(u32, bytes[12..16], block[3]);
        return bytes;
    }
};

// Nessie test vectors are standard,  the vectors on the floppy disks
// that were sent to the AES contest have the bytes in reverse order
// and this is called tnepres sometimes
// https://www.cs.technion.ac.il/~biham/Reports/Serpent/
test "128-bit keys" {
    const TestVector = struct { key: []const u8, plain: []const u8, cipher: []const u8 };

    const test_vectors = [_]TestVector{
        // Set 1, vector#  0:
        TestVector{
            .key = "80000000000000000000000000000000",
            .plain = "00000000000000000000000000000000",
            .cipher = "264E5481EFF42A4606ABDA06C0BFDA3D",
        },
        // Set 2, vector#  8:
        TestVector {
            .key = "00000000000000000000000000000000",
            .plain = "00800000000000000000000000000000",
            .cipher = "0DB0D17349C89E090C845CBEF963F225",
        },
        // Set 2, vector# 28:
        TestVector {
            .key = "00000000000000000000000000000000",
            .plain = "00000008000000000000000000000000",
            .cipher = "41ED367E96E013C651AF3FAEA764FE40",
        },
        // Set 3, vector# 46:
        TestVector {
            .key = "2E2E2E2E2E2E2E2E2E2E2E2E2E2E2E2E",
            .plain = "2E2E2E2E2E2E2E2E2E2E2E2E2E2E2E2E",
            .cipher = "E605C2EF7EFFDAC2316796EB7C15FAC7",
        },
        // Set 5, vector# 34:
        TestVector {
            .key = "00000000200000000000000000000000",
            .plain = "1B2A09A8CB69ECBAD8ACD593D27BCBDB",
            .cipher = "00000000000000000000000000000000",
        },
        // Set 7, vector# 35:
        TestVector {
            .key = "23232323232323232323232323232323",
            .plain = "0F66477951B1C27FBFFFA41E1B4E4764",
            .cipher = "23232323232323232323232323232323",
        },
        TestVector {
            .key = "000102030405060708090A0B0C0D0E0F",
            .plain = "33B3DC87EDDD9B0F6A1F407D14919365",
            .cipher = "00112233445566778899AABBCCDDEEFF",
        }
    };

    for (test_vectors) |vector| {
        var v_key: [16]u8 = undefined;
        _ = try hexToBytes(&v_key, vector.key);
        var v_plain: [16]u8 = undefined;
        _ = try hexToBytes(&v_plain, vector.plain);
        var v_cipher: [16]u8 = undefined;
        _ = try hexToBytes(&v_cipher, vector.cipher);

        const round_keys = Serpent.keySchedule(Serpent.expandKey(&v_key));
        const cipher_res = Serpent.blockToBytes(
            Serpent.encryptBlock(
                Serpent.blockFromBytes(v_plain),
                round_keys,
            ),
        );
        var cipher_res_hex: [32]u8 = undefined;
        _ = try bufPrint(&cipher_res_hex, "{X}", .{fmtSliceHexUpper(&cipher_res)});
        try testing.expectEqualStrings(vector.cipher, &cipher_res_hex);

        var plain_res = Serpent.blockToBytes(
            Serpent.decryptBlock(Serpent.blockFromBytes(v_cipher), round_keys),
        );
        var plain_res_hex: [32]u8 = undefined;
        _ = try bufPrint(&plain_res_hex, "{X}", .{fmtSliceHexUpper(&plain_res)});
        try testing.expectEqualStrings(vector.plain, &plain_res_hex);
    }
}

// TODO: add for 192-bits keys or probably create more generalized function

test "256-bit keys" {
    const TestVector = struct { key: []const u8, plain: []const u8, cipher: []const u8 };

    const test_vectors = [_]TestVector{
        // Set 7, vector#  15:
        TestVector{
            .key = "0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F",
            .plain = "752F945816DDB0E5ED15DA177EF5543F",
            .cipher = "0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F",
        },
        // TODO: add more
    };

    for (test_vectors) |vector| {
        var v_key: [32]u8 = undefined;
        _ = try hexToBytes(&v_key, vector.key);
        var v_plain: [16]u8 = undefined;
        _ = try hexToBytes(&v_plain, vector.plain);
        var v_cipher: [16]u8 = undefined;
        _ = try hexToBytes(&v_cipher, vector.cipher);

        const round_keys = Serpent.keySchedule(Serpent.expandKey(&v_key));
        const cipher_res = Serpent.blockToBytes(
            Serpent.encryptBlock(
                Serpent.blockFromBytes(v_plain),
                round_keys,
            ),
        );
        var cipher_res_hex: [32]u8 = undefined;
        _ = try bufPrint(&cipher_res_hex, "{X}", .{fmtSliceHexUpper(&cipher_res)});
        try testing.expectEqualStrings(vector.cipher, &cipher_res_hex);

        var plain_res = Serpent.blockToBytes(
            Serpent.decryptBlock(Serpent.blockFromBytes(v_cipher), round_keys),
        );
        var plain_res_hex: [32]u8 = undefined;
        _ = try bufPrint(&plain_res_hex, "{X}", .{fmtSliceHexUpper(&plain_res)});
        try testing.expectEqualStrings(vector.plain, &plain_res_hex);
    }
}
