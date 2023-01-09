const std = @import("std");
const util = @import("util.zig");

const add = util.add;
const sub = util.sub;
const mul = util.mul;
const div = util.div;

const bitReader = @import("bit_reader.zig").bitReader;

const MAX_NB_COMMENTS = 1 << 10;
const MAX_COMMENT_LEN = 8 << 20; // rejecting any comments larger than 8 megs seems reasonable

pub const PixelFormat = enum(u2) {
    yuv420 = 0,
    yuv422 = 2,
    yuv444 = 3,
};

inline fn getNsbs(pf: u2, _fmbw: u16, _fmbh: u16) !u32 {
    const fmbw: u32 = _fmbw;
    const fmbh: u32 = _fmbh;

    try util.assert(.SanityCheck, pf != 1, error.InvalidPixelFormat);

    const luma_nsbs = try mul(try div(try add(fmbw, 1), 2), try div(try add(fmbh, 1), 2));
    var chroma_nsbs: u32 = undefined;

    switch(@intToEnum(PixelFormat, pf)) {
        .yuv420 => chroma_nsbs = try add(try div(try add(fmbw,3),4),try div(try add(fmbh,3),4)),
        .yuv422 => chroma_nsbs = try add(try div(try add(fmbw,3),4),try div(try add(fmbh,1),2)),
        .yuv444 => chroma_nsbs = luma_nsbs,
    }
    return try add(luma_nsbs, try mul(2, chroma_nsbs));
}

inline fn getNbs(pf: u2, _fmbw: u16, _fmbh: u16) !u32 {
    const fmbw: u32 = _fmbw;
    const fmbh: u32 = _fmbh;

    try util.assert(.SanityCheck, pf != 1, error.InvalidPixelFormat);

    const nb_luma_mbs: u32 = try mul(fmbw, fmbh);

    return switch(@intToEnum(PixelFormat, pf)) {
        .yuv420 => try mul(6, nb_luma_mbs),
        .yuv422 => try mul(8, nb_luma_mbs),
        .yuv444 => try mul(12, nb_luma_mbs),
    };
}

/// The identification header. See section 6.2.
pub const IdentificationHeader = struct {
    /// Major version
    vmaj: u8,
    /// Minor version
    vmin: u8,
    /// Revision version
    vrev: u8,
    /// Width of the frame in macroblocks
    fmbw: u16,
    /// Height of the frame in macroblocks
    fmbh: u16,
    /// Total number of superblocks per frame
    nsbs: u32,
    /// Total number of blocks per frame
    nbs: u36,
    /// Total number of macroblocks per frame
    nmbs: u32,
    /// Picture width, in pixels
    picw: u20,
    /// Picture height, in pixels
    pich: u20,
    /// X offset of the picture, in pixels
    picx: u8,
    /// Y offset of the picture, in pixels
    picy: u8,
    /// Numerator of the frame rate
    frn: u32,
    /// Denominator of the frame rate
    frd: u32,
    /// Numerator of the pixel aspect ratio
    parn: u24,
    /// Denominator of the pixel aspect ratio
    pard: u24,
    /// Color space
    cs: u8,
    /// Pixel format
    pf: u2,
    /// Nominal bitrate, bits/s
    nombr: u24,
    /// Quality hint
    qual: u6,
    /// By how much to shift the key frame number in the granule position
    kfgshift: u5,

    pub fn read(br: anytype) !IdentificationHeader {
        var ih: IdentificationHeader = undefined;
        try br.read(&ih.vmaj);
        if (ih.vmaj != 3) return error.UnsupportedMajor;

        try br.read(&ih.vmin);
        if (ih.vmin != 2) return error.UnsupportedMinor;

        try br.read(&ih.vrev);

        try br.read(&ih.fmbw);
        if (ih.fmbw == 0) return error.InvalidMacroblockWidth;

        try br.read(&ih.fmbh);
        if (ih.fmbh == 0) return error.InvalidMacroblockHeight;

        try br.readO(u24, &ih.picw);
        if (ih.picw > @as(u20, ih.fmbw) *| 16) return error.InvalidPictureWidth;

        try br.readO(u24, &ih.pich);
        if (ih.pich > @as(u20, ih.fmbh) *| 16) return error.InvalidPictureHeight;

        try br.read(&ih.picx);
        if (ih.picx > ih.fmbw *% 16 -% ih.picx) return error.InvalidPictureXOffset;

        try br.read(&ih.picy);
        if (ih.picy > ih.fmbh *% 16 -% ih.picy) return error.InvalidPictureYOffset;

        try br.read(&ih.frn);
        if (ih.frn == 0) return error.InvalidFramerateNumerator;

        try br.read(&ih.frd);
        if (ih.frd == 0) return error.InvalidFramerateDenominator;

        try br.read(&ih.parn);
        if (ih.parn == 0) return error.InvalidPixelAspectRatioNumerator;

        try br.read(&ih.pard);
        if (ih.parn == 0) return error.InvalidPixelAspectRatioDenominator;

        try br.read(&ih.cs);
        if (ih.cs > 3) return error.ReservedColorspace;

        try br.read(&ih.nombr);

        try br.read(&ih.qual);

        try br.read(&ih.kfgshift);

        try br.read(&ih.pf);
        if (ih.pf == 1) return error.ReservedPixelFormat;

        // reserved
        if(try br.readInt(u3) != 0) return error.InvalidReserved;

        ih.nmbs = try mul(@as(u32, ih.fmbw), @as(u32, ih.fmbh));

        ih.nsbs = try getNsbs(ih.pf, ih.fmbw, ih.fmbh);

        ih.nbs = try getNbs(ih.pf, ih.fmbw, ih.fmbh);

        return ih;
    }
    test {
        const buf = [_]u8{
            0x03, 0x02, 0x01, 0x00, 0x1b, 0x00, 0x0f, 0x00, 0x01, 0xaa, 0x00,
            0x00, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
            0xb0, 0xc0,
        };
        const expected_result = IdentificationHeader{
            .vmaj     = 3,
            .vmin     = 2,
            .vrev     = 1,
            .fmbw     = 27,
            .fmbh     = 15,
            .nsbs     = 134,
            .nbs      = 2430,
            .nmbs     = 405,
            .picw     = 426,
            .pich     = 240,
            .picx     = 0,
            .picy     = 0,
            .frn      = 24,
            .frd      = 1,
            .parn     = 1,
            .pard     = 1,
            .cs       = 0,
            .pf       = 0,
            .nombr    = 0,
            .qual     = 44,
            .kfgshift = 6,
        };
        var fbs = std.io.fixedBufferStream(&buf);
        var br = bitReader(fbs.reader());
        try std.testing.expectEqual(expected_result, try read(&br));
    }
};

/// The comment header. See section 6.3
pub const CommentHeader = struct {
    /// The name of the program that produced this bitstream.
    vendor: []const u8,
    /// Comments, formatted in NAME=value.
    comments: [][]const u8,

    pub fn read(br: anytype, a: std.mem.Allocator) !CommentHeader {
        var ch: CommentHeader = undefined;
        ch.vendor = try br.readStringAlloc(a, MAX_COMMENT_LEN);
        errdefer a.free(ch.vendor);

        const nb_comments = try br.readStringLength();
        std.debug.print("\n{d}\n", .{nb_comments});
        if(nb_comments > MAX_NB_COMMENTS) return error.TooManyComments;

        ch.comments = try a.alloc([]const u8, nb_comments);
        errdefer a.free(ch.comments);

        {
            var i: u32 = 0;

            // cleanup
            errdefer {
                var j: u32 = 0;
                while(j < i) : (j += 1)
                    a.free(ch.comments[j]);
            }

            while(i < nb_comments) : (i += 1) {
                ch.comments[i] = try br.readStringAlloc(a, MAX_COMMENT_LEN);
            }
        }
        return ch;
    }

    pub fn deinit(self: CommentHeader, a: std.mem.Allocator) void {
        a.free(self.vendor);
        for(self.comments) |c|
            a.free(c);
        a.free(self.comments);
    }

    test {
        return error.SkipZigTest; // TODO
        // var fbs = std.io.fixedBufferStream(&buf);
        // var br = bitReader(fbs.reader());
        // const x = try read(&br, std.testing.allocator);
        // defer x.deinit();
        // std.debug.print("{any}", .{x});
    }
};

/// The setup header. See section 6.3
pub const SetupHeader = struct {
    /// Loop filter limit values.
    lflims: [64]u7,

    /// Scale values for AC coefficients.
    acscale: [64]u16,

    /// Scale values for DC coefficients.
    dcscale: [64]u16,

    /// Base matrices.
    bms: [][64]u8,

    /// Number of quant ranges.
    nqrs: [2][3]u6,

    /// Sizes of each quant range
    qrsizes: [2][3][63]u6,

    /// XXX: the bmis used for each quant range?
    qrbmis: [2][3][64]u9,

    /// XXX: Huffman tables
    hts: void,

    pub fn read(br: anytype, a: std.mem.Allocator) !SetupHeader {
        var sh: SetupHeader = undefined;

        { // Loop filter limits
            const nbits = try br.readInt(u3);
            comptime var i = 0;
            inline while(i < 64) : (i += 1)
                sh.lflims[i] = try br.readBits(u7, nbits);
        }
        { // Quantization parameters
            var nbits = try add(try br.readInt(u4), 1);

            for(sh.acscale) |*e| e.* = try br.readBits(u16, nbits);

            nbits = try add(try br.readInt(u4), 1);
            var i: usize = 0;
            while(i < 64) : (i += 1)
                sh.dcscale[i] = try br.readBits(u16, nbits);

            const nbms = try add(try br.readInt(u9), 1);
            if(nbms > 384) return error.InvalidNbms;

            sh.bms = a.alloc(@TypeOf(sh.bms.*), nbms);
            errdefer a.free(sh.bms);
            for(sh.bms) |e| { for(e) |*f| f.* = try br.readInt(u8); }

            for(sh.nqrs) |e, qti| {
                for(e) |_, pli| {
                    const newqr = if(qti > 0 or pli > 0) try br.readBool() else true;
                    if(!newqr) {
                        // copy an earlier set of quant ranges
                        const rpqr = if(qti > 0 or pli > 0) try br.readBool() else false;
                        const qtj: usize =
                            if(rpqr)
                            try sub(qti, 1)
                            else
                            try div(try add(try mul(3, qti), pli), 3);
                        const plj: usize =
                            if(rpqr) pli else (try add(pli, 3)) % 3;

                        sh.nqrs[qti][pli] = sh.nqrs[qtj][plj];
                        sh.qrsizes[qti][pli] = sh.qrsizes[qtj][plj];
                        sh.qrbmis[qti][pli] = sh.qrbmis[qtj][plj];

                    } else {
                        // new quant ranges
                        var qri = 0;
                        var qi = 0;
                        const sz = try util.ilog(nbms - 1);
                        sh.qrbmis[qti][pli][qri] = try br.readBits(u9, sz);
                        if(sh.qrbmis[qti][pli][qri] >= nbms) return error.InvalidQRBMI;
                        while(true) {
                            sh.qrsizes[qti][pli][qri] = try add(try br.readBits(u6, try util.ilog(62 - qi)), 1);
                            qi = try add(qi, sh.qrsizes[qti][pli][qri]);
                            qri = try add(qri, 1);
                            if(qi < 63) continue;
                            if(qi > 63) return error.InvalidQI;
                            sh.nqrs[qti][pli] = qri;
                            break;
                        }
                    }
                }
            }
        }
    }

    pub fn deinit(sh: SetupHeader, a: std.mem.Allocator) void {
        a.free(sh.bms);
    }

    pub fn computeQuantMat(sh: SetupHeader, dst: *[64]u16, qti: u1, pli: u2, qi: u6) !void {
        var qri     : u6  = 0;

        while(true) : (qri += 1) {
            const qi_lower = try util.summation(u6, 0, qri -| 1, 1, sh.qrsizes[qti][pli]);
            const qi_upper = try util.summation(u6, 0, qri, 1, sh.qrsizes[qti][pli]);
            if(qi >= qi_lower and qi <= qi_upper) break;
        }
        const qistart = try util.summation(u6, 0, qri -| 1, 1, sh.qrsizes[qti][pli]);
        const qiend = try util.summation(u6, 0, qri, 1, sh.qrsizes[qti][pli]);
        const bmi = sh.qrbmis[qti][pli][qri];
        const bmj = sh.qrbmis[qti][pli][try add(qri, 1)];

        var bm: [64]u8 = undefined;
        for(bm) |*e, ci| {
            @setRuntimeSafety(true); // XXX: use functions
            e.* =
                (2 * (qiend - qi) * sh.bms[bmi][ci]
                     + 2 * (qi - qistart) * sh.bms[bmj][ci]
                     + sh.qrsizes[qti][pli][qri]) / (2 * sh.qrsizes[qti][pli][qri]);

            const qmin: u16 = if(ci == 0) if(qti == 0) 16 else 32 else if(qti == 0) 8 else 16;
            const qscale = if(ci == 0) sh.dcscale[qi] else sh.acscale[qi];
            dst[ci] = util.max(qmin, util.min((qscale * bm[ci] / 100) * 4, 4096));
        }
    }

    test {
        return error.SkipZigTest;// TODO
    }
};

comptime {
    std.testing.refAllDeclsRecursive(@This());
}
