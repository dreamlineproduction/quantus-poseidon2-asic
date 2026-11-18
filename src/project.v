/*
 * Copyright (c) 2026 Ayan Mukhopadhyay
 * SPDX-License-Identifier: Apache-2.0
 */

// ============================================================================
// 1. Goldilocks Field Arithmetic (P = 2^64 - 2^32 + 1)
// ============================================================================
module gl_add_comb (
    input  wire [63:0] a,
    input  wire [63:0] b,
    output wire [63:0] out
);
    localparam [63:0] P = 64'hFFFFFFFF00000001;
    wire [64:0] sum = a + b;
    assign out = (sum >= P) ? (sum - P) : sum[63:0];
endmodule

module gl_mult_comb (
    input  wire [63:0] a,
    input  wire [63:0] b,
    output wire [63:0] out
);
    localparam [63:0] P = 64'hFFFFFFFF00000001;
    wire [127:0] prod  = a * b;
    wire [63:0]  x_lo  = prod[63:0];
    wire [31:0]  x_mid = prod[95:64];
    wire [31:0]  x_hi  = prod[127:96];

    wire [64:0] term1 = {1'b0, x_lo} + ({33'd0, x_mid} << 32) - {33'd0, x_mid};
    wire signed [65:0] reduced = $signed({1'b0, term1}) - $signed({34'd0, x_hi});

    assign out = (reduced < 0)  ? (reduced + P) :
                 (reduced >= P) ? (reduced - P) : reduced[63:0];
endmodule

// Single-cycle S-Box (x^7 mod P)
module sbox_comb (
    input  wire [63:0] x,
    output wire [63:0] out
);
    wire [63:0] x2, x3, x4;
    gl_mult_comb m1(x,  x,  x2);
    gl_mult_comb m2(x2, x,  x3);
    gl_mult_comb m3(x2, x2, x4);
    gl_mult_comb m4(x3, x4, out);
endmodule

// ============================================================================
// 2. External Linear Layer (Exact Quantus apply_mat4 + Outer Sum)
// ============================================================================
module poseidon2_mds_ext (
    input  wire [767:0] state_in,
    output wire [767:0] state_out
);
    wire [63:0] x [0:11];
    genvar i;
    generate
        for (i = 0; i < 12; i = i + 1) begin : unpack
            assign x[i] = state_in[i*64 +: 64];
        end
    endgenerate

    wire [63:0] t [0:11];
    generate
        for (i = 0; i < 3; i = i + 1) begin : mds4
            wire [63:0] x0 = x[i*4 + 0];
            wire [63:0] x1 = x[i*4 + 1];
            wire [63:0] x2 = x[i*4 + 2];
            wire [63:0] x3 = x[i*4 + 3];

            wire [63:0] t01, t23, t0123, t01123, t01233, x0_2, x2_2;
            gl_add_comb u1(x0,    x1,    t01);
            gl_add_comb u2(x2,    x3,    t23);
            gl_add_comb u3(t01,   t23,   t0123);
            gl_add_comb u4(t0123, x1,    t01123);
            gl_add_comb u5(t0123, x3,    t01233);
            gl_add_comb u6(x0,    x0,    x0_2);
            gl_add_comb u7(x2,    x2,    x2_2);

            gl_add_comb o0(t01123, t01,  t[i*4 + 0]);
            gl_add_comb o1(t01123, x2_2, t[i*4 + 1]);
            gl_add_comb o2(t01233, t23,  t[i*4 + 2]);
            gl_add_comb o3(t01233, x0_2, t[i*4 + 3]);
        end
    endgenerate

    wire [63:0] y [0:11];
    generate
        for (i = 0; i < 4; i = i + 1) begin : cross_mix
            wire [63:0] s01, col_sum;
            gl_add_comb c1(t[i], t[i+4], s01);
            gl_add_comb c2(s01, t[i+8], col_sum);

            gl_add_comb f0(t[i],   col_sum, y[i]);
            gl_add_comb f1(t[i+4], col_sum, y[i+4]);
            gl_add_comb f2(t[i+8], col_sum, y[i+8]);
        end
    endgenerate

    generate
        for (i = 0; i < 12; i = i + 1) begin : pack
            assign state_out[i*64 +: 64] = y[i];
        end
    endgenerate
endmodule

// ============================================================================
// 3. Internal Linear Layer (Exact Quantus MATRIX_DIAG)
// ============================================================================
module poseidon2_mds_int (
    input  wire [767:0] state_in,
    output wire [767:0] state_out
);
    localparam [767:0] DIAG_PACKED = {
        64'hd27dbb6944917b60, 64'h0c6388b51545e883, 64'hf3faac6faee378ae, 64'ha2077d7dfbb606b5,
        64'hac45e25b7127b68b, 64'h5528b9362c59bb70, 64'h6743bc47b9595257, 64'h5daf18bbd996604b,
        64'h7964f570e7188037, 64'h0d0c371c5b35b84f, 64'hd84b5de94a324fb6, 64'hc3b6c08e23ba9300
    };

    wire [63:0] s0, s1, s2, s3, s4, s5, s6, s7, s8, s9, total_sum;
    gl_add_comb a0(state_in[63:0],    state_in[127:64],  s0);
    gl_add_comb a1(s0,                state_in[191:128], s1);
    gl_add_comb a2(s1,                state_in[255:192], s2);
    gl_add_comb a3(s2,                state_in[319:256], s3);
    gl_add_comb a4(s3,                state_in[383:320], s4);
    gl_add_comb a5(s4,                state_in[447:384], s5);
    gl_add_comb a6(s5,                state_in[511:448], s6);
    gl_add_comb a7(s6,                state_in[575:512], s7);
    gl_add_comb a8(s7,                state_in[639:576], s8);
    gl_add_comb a9(s8,                state_in[703:640], s9);
    gl_add_comb a10(s9,               state_in[767:704], total_sum);

    genvar i;
    generate
        for (i = 0; i < 12; i = i + 1) begin : diag_lanes
            wire [63:0] prod;
            gl_mult_comb m_d (.a(state_in[i*64 +: 64]), .b(DIAG_PACKED[i*64 +: 64]), .out(prod));
            gl_add_comb  a_d (.a(total_sum), .b(prod), .out(state_out[i*64 +: 64]));
        end
    endgenerate
endmodule

// ============================================================================
// 4. Complete Autonomous Quantus ASIC Miner (Iterative 30-Clock Engine!)
// ============================================================================
module quantus_miner_asic (
    input  wire         clk,
    input  wire         reset,
    input  wire         mining_enable,
    input  wire [767:0] midstate_in,
    input  wire [255:0] target_difficulty,
    output reg          golden_nonce_found,
    output reg  [63:0]  golden_nonce,
    output reg  [255:0] golden_hash
);
    // Official Quantus Round Constants ROMs
    localparam [3071:0] EXT_INIT_ROM = {
        {64'hde795c20a2357af7, 64'h5b4e40ffc759532f, 64'h902cbd0956f655e3, 64'hcdb13f4cd93e024c, 64'he9da8d699b94184a, 64'haad3bea4baac9a5a, 64'h23eda6f3c99150dd, 64'h3ba588cacb43b5e0, 64'h63c8e72f542bf3fc, 64'haa284b3ecdb222ae, 64'h622462a1f9aaaeed, 64'h1e5e2b5760e32477},
        {64'hf51593e2beb5e3bd, 64'h5762bfe181f25047, 64'h4fd53e50ca04a7ee, 64'hee0b22d0dfae8bb8, 64'h64b0a186698e01d3, 64'h999a649b69b9d32f, 64'h265293b0e47ce88a, 64'h78f04462d48b1c98, 64'hdb14234eafaf5173, 64'hb35a8e976d2af617, 64'h89ae889caaf0802c, 64'h7d5c08eef608e382},
        {64'hd29bb7edbeb9c405, 64'hee3e2b889abe977d, 64'h41df7ef9d730ae3e, 64'hcd895e8c68b57a9e, 64'hfcd59aa12c6090ad, 64'he5076df75b72c3d0, 64'h3600427d397a7f68, 64'h1f7a9d55923bf51e, 64'h56eb3d6b5256d67a, 64'h4ae6acd0c9c92897, 64'h2711aa8b5509d516, 64'hada1f8dc7676ed25},
        {64'h2a3dd4505b478fdc, 64'he59b3f57aabba1ae, 64'hd9a64f068dca7c29, 64'he3f30d509a1436bb, 64'h6c1cb2a358cc24f1, 64'h486dcb55419d475a, 64'hec33b868f3cc46c1, 64'hd5e0ba2f541b6449, 64'he4f2fe29e03234ac, 64'h72938dfbe774f7f9, 64'hbca51a8dfe14593a, 64'hc002e770975b1607}
    };

    localparam [1407:0] INT_ROM = {
        64'h5538cdf4f23445d3, 64'h3ec372e7a0fa3786, 64'hf6d49ff997ae0260, 64'h192c42d86803d7a6,
        64'h1b061b76a1c0ded3, 64'h0f3a74bf215eaac6, 64'h1e0e18496da2444a, 64'hee72f470262574d6,
        64'h8492362ad2392556, 64'h8e79b4a5d0096d6d, 64'h3fcc9ee82cc4577e, 64'h964a209f85dc9ecc,
        64'h3e52ef8bca48314a, 64'h3998cfe6871cc137, 64'h3defd7645cde6425, 64'h8a084bbba8ed86cc,
        64'h5874e441117bd746, 64'h295275001eede5b5, 64'ha9d06906a3858e24, 64'h69a377a79f9ad206,
        64'hd1d2bf082f60d4f0, 64'h97f7798a784ad863
    };

    localparam [3071:0] EXT_TERM_ROM = {
        {64'he0a3389266fb6dc9, 64'hbce34a649cfccaf9, 64'h504c4c51f3faee94, 64'h52a345d5c7adb0b8, 64'h85ae1528caea3811, 64'h7d2ffb1bb0e17271, 64'h2cd8c96d9a3ce855, 64'hf83a42660c08c0bc, 64'h5711fd5cf4784511, 64'he6ae134bb82f2e78, 64'h7257e5b147fd3803, 64'hfe04051f909e042b},
        {64'h5f1e28615a11e486, 64'h624370be5670b327, 64'h0b24c1b7a030fca4, 64'h1ef581a93eaf6acf, 64'he3d95f30309819c0, 64'h98f607485d48cdea, 64'h93c393dbfc2fe76f, 64'h0e43551233ae13b2, 64'h7691eb2d194b24f4, 64'h0908bf65eb0a1f0d, 64'h763b45d2a3821b28, 64'he498691679d9330f},
        {64'hd8e3cf2bbd355417, 64'hb0f2b8905a0976f6, 64'h213de241fcf33835, 64'h16e7c2074d654a2d, 64'h57df2d8c2a32107a, 64'hf8806b6588f49a8b, 64'h6d808a08f7b71df6, 64'hf39942b6a8585089, 64'hf7d0ce75de23f74e, 64'he81025b5a24c69cd, 64'h3fd5eb927e95fe4f, 64'h605f902830872e01},
        {64'h6673e505cfd0b6ba, 64'h1cbb36f11127338b, 64'h0ed0d75c27975d97, 64'h64ddb9d5de7e00a6, 64'hb0464d9d77b97fca, 64'h34f7909ae5258d64, 64'hf6e7e38b1ea6ba2f, 64'ha205d0ffa9b9def3, 64'h6d36c5022c4fe7c2, 64'h802028b68f35fc88, 64'h144573dae2ce9976, 64'h7b72c539e0ea4c6e}
    };

    reg [767:0] state_reg;
    reg [5:0]   round_idx; // 0 = Init MDS, 1..30 = Poseidon2 Rounds
    reg [63:0]  nonce_counter;

    // Select active round constant based on round_idx (1..30)
    wire is_ext_init = (round_idx >= 6'd1) && (round_idx <= 6'd4);
    wire is_int      = (round_idx >= 6'd5) && (round_idx <= 6'd26);
    wire is_ext_term = (round_idx >= 6'd27) && (round_idx <= 6'd30);

    wire [767:0] active_rc = is_ext_init ? EXT_INIT_ROM[(round_idx - 6'd1)*768 +: 768] :
                             is_int      ? {704'd0, INT_ROM[(round_idx - 6'd5)*64 +: 64]} :
                             is_ext_term ? EXT_TERM_ROM[(round_idx - 6'd27)*768 +: 768] : 768'd0;

    // Add Round Constants & Apply S-Box (12 S-boxes for external, 1 S-box for internal)
    wire [767:0] after_rc, after_sbox;
    genvar i;
    generate
        for (i = 0; i < 12; i = i + 1) begin : round_lanes
            gl_add_comb rc_add (.a(state_reg[i*64 +: 64]), .b(active_rc[i*64 +: 64]), .out(after_rc[i*64 +: 64]));
            wire [63:0] sbox_val;
            sbox_comb sb (.x(after_rc[i*64 +: 64]), .out(sbox_val));
            // For internal rounds, only Lane 0 uses S-box; Lanes 1..11 bypass!
            assign after_sbox[i*64 +: 64] = (i == 0 || !is_int) ? sbox_val : state_reg[i*64 +: 64];
        end
    endgenerate

    wire [767:0] mds_ext_out, mds_int_out, init_mds_out;
poseidon2_mds_ext m_init (.state_in({midstate_in[767:64], midstate_in[63:0] ^ nonce_counter}), .state_out(init_mds_out));
poseidon2_mds_ext m_ext  (.state_in(after_sbox), .state_out(mds_ext_out));
poseidon2_mds_int m_int  (.state_in(after_sbox), .state_out(mds_int_out));
wire [767:0] next_state = (round_idx == 6'd0) ? init_mds_out :
is_int              ? mds_int_out  : mds_ext_out;
always @(posedge clk) begin
if (reset) begin
round_idx          <= 6'd0;
nonce_counter      <= 64'd0;
state_reg          <= 768'd0;
golden_nonce_found <= 1'b0;
golden_nonce       <= 64'd0;
golden_hash        <= 256'd0;
end else if (mining_enable && !golden_nonce_found) begin
state_reg <= next_state;
if (round_idx == 6'd30) begin
// Hash finished! Check difficulty target!
if (next_state[255:0] < target_difficulty) begin
golden_nonce_found <= 1'b1;
golden_nonce       <= nonce_counter;
golden_hash        <= next_state[255:0];
end else begin
nonce_counter <= nonce_counter + 64'd1;
round_idx     <= 6'd0;
end
end else begin
round_idx <= round_idx + 6'd1;
end
end
end
endmodule
// ============================================================================
// Tiny Tapeout 24-Pin Physical Chip Wrapper
// ============================================================================
module tt_um_example (
    input  wire [7:0] ui_in,    // 8 Dedicated Inputs (Target difficulty byte)
    output wire [7:0] uo_out,   // 8 Dedicated Outputs (Winning nonce byte + alarm)
    input  wire [7:0] uio_in,   // 8 Bidirectional Inputs
    output wire [7:0] uio_out,  // 8 Bidirectional Outputs
    output wire [7:0] uio_oe,   // Bidirectional Enable (0 = input, 1 = output)
    input  wire       ena,      // Chip Enable (1 when active)
    input  wire       clk,      // System Clock
    input  wire       rst_n     // Active-Low Reset (0 = reset, 1 = run)
);
    wire         golden_nonce_found;
    wire [63:0]  golden_nonce;
    wire [255:0] golden_hash;

    // Prevent unused input warnings during ASIC synthesis
    wire _unused = &{ena, uio_in, golden_nonce[63:15], golden_hash, 1'b0};

    // Connect your Quantus ASIC to the physical chip pins!
    quantus_miner_asic quantus_core (
        .clk(clk),
        .reset(~rst_n),
        .mining_enable(ena),
        .midstate_in(768'd0),
        .target_difficulty({ui_in, 248'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF}),
        .golden_nonce_found(golden_nonce_found),
        .golden_nonce(golden_nonce),
        .golden_hash(golden_hash)
    );

    // Send status & winning nonce bytes out to the physical chip pins!
    assign uo_out  = {golden_nonce_found, golden_nonce[6:0]};
    assign uio_out = golden_nonce[14:7];
    assign uio_oe  = 8'hFF;
endmodule
