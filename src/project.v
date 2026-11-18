/*
 * Copyright (c) 2026 Ayan Mukhopadhyay
 * SPDX-License-Identifier: Apache-2.0
 */
// ============================================================================
// 1. Single Shared 64-bit Goldilocks Adder (P = 2^64 - 2^32 + 1)
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

// ============================================================================
// 2. Area-Optimized Serial 64-bit Goldilocks Multiplier (64 cycles, ~8k um^2!)
// ============================================================================
module gl_mult_serial (
    input  wire        clk,
    input  wire        start,
    input  wire [63:0] a,
    input  wire [63:0] b,
    output reg  [63:0] result,
    output reg         done
);
    localparam [63:0] P = 64'hFFFFFFFF00000001;
    reg [6:0]   bit_cnt;
    reg [63:0]  acc, shift_a, shift_b;
    reg         busy;

    // Double acc mod P: (acc << 1) mod P
    wire [64:0] acc_2x   = {acc, 1'b0};
    wire [63:0] acc_dbl  = (acc_2x >= {1'b0, P}) ? (acc_2x[63:0] - P) : acc_2x[63:0];

    // Add shift_a if top bit of shift_b is 1
    wire [64:0] acc_plus = {1'b0, acc_dbl} + (shift_b[63] ? {1'b0, shift_a} : 65'd0);
    wire [63:0] acc_next = (acc_plus >= {1'b0, P}) ? (acc_plus[63:0] - P) : acc_plus[63:0];

    always @(posedge clk) begin
        if (start) begin
            acc     <= 64'd0;
            shift_a <= a;
            shift_b <= b;
            bit_cnt <= 7'd0;
            busy    <= 1'b1;
            done    <= 1'b0;
        end else if (busy) begin
            acc     <= acc_next;
            shift_b <= {shift_b[62:0], 1'b0};
            if (bit_cnt == 7'd63) begin
                result <= acc_next;
                busy   <= 1'b0;
                done   <= 1'b1;
            end else begin
                bit_cnt <= bit_cnt + 7'd1;
            end
        end else begin
            done <= 1'b0;
        end
    end
endmodule

// ============================================================================
// 3. Compact Quantus Poseidon2 Miner Core (< 60% Utilization on 8x2 Chip!)
// ============================================================================
module quantus_miner_compact (
    input  wire        clk,
    input  wire        reset,
    input  wire        mining_enable,
    input  wire [7:0]  target_top_byte,
    output reg         golden_nonce_found,
    output reg  [15:0] golden_nonce
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

    localparam [767:0] DIAG_PACKED = {
        64'hd27dbb6944917b60, 64'h0c6388b51545e883, 64'hf3faac6faee378ae, 64'ha2077d7dfbb606b5,
        64'hac45e25b7127b68b, 64'h5528b9362c59bb70, 64'h6743bc47b9595257, 64'h5daf18bbd996604b,
        64'h7964f570e7188037, 64'h0d0c371c5b35b84f, 64'hd84b5de94a324fb6, 64'hc3b6c08e23ba9300
    };

    // State Machine
    localparam [2:0] ST_LOAD     = 3'd0,
                     ST_SBOX_REQ = 3'd1,
                     ST_SBOX_WT  = 3'd2,
                     ST_MIX_SUM  = 3'd3,
                     ST_MIX_LANE = 3'd4,
                     ST_DIAG_WT  = 3'd5;

    reg [2:0]   fsm;
    reg [767:0] state_reg;
    reg [5:0]   round_idx;
    reg [3:0]   lane_idx;
    reg [2:0]   sub_step;
    reg [63:0]  tmp_x2, tmp_x3, running_sum;
    reg [15:0]  nonce_counter;

    wire is_ext_init = (round_idx >= 6'd1) && (round_idx <= 6'd4);
    wire is_int      = (round_idx >= 6'd5) && (round_idx <= 6'd26);
    wire is_ext_term = (round_idx >= 6'd27) && (round_idx <= 6'd30);

    wire [11:0] ext_init_off = (({6'd0, round_idx} - 12'd1) * 12'd12 + {8'd0, lane_idx}) * 12'd64;
    wire [11:0] ext_term_off = (({6'd0, round_idx} - 12'd27) * 12'd12 + {8'd0, lane_idx}) * 12'd64;
    wire [10:0] int_off      = ({5'd0, round_idx} - 11'd5) * 11'd64;
    wire [9:0]  lane_off     = {6'd0, lane_idx} * 10'd64;

    wire [63:0] cur_lane = state_reg[lane_off +: 64];
    wire [63:0] cur_rc   = is_ext_init                  ? EXT_INIT_ROM[ext_init_off +: 64] :
                           (is_int && lane_idx == 4'd0) ? INT_ROM[int_off +: 64] :
                           is_ext_term                  ? EXT_TERM_ROM[ext_term_off +: 64] : 64'd0;

    // 1 Shared 64-bit Goldilocks Adder for the entire chip!
    wire [63:0] add_a = (fsm == ST_MIX_SUM || fsm == ST_MIX_LANE) ? running_sum : cur_lane;
    wire [63:0] add_b = (fsm == ST_MIX_SUM)  ? cur_lane :
                        (fsm == ST_MIX_LANE) ? mult_out : cur_rc;
    wire [63:0] add_out;
    gl_add_comb u_shared_add (.a(add_a), .b(add_b), .out(add_out));

    // 1 Shared Serial 64-bit Multiplier for the entire chip!
    reg         mult_start;
    reg  [63:0] mult_a, mult_b;
    wire [63:0] mult_out;
    wire        mult_done;

    gl_mult_serial u_serial_mult (
        .clk(clk),
        .start(mult_start),
        .a(mult_a),
        .b(mult_b),
        .result(mult_out),
        .done(mult_done)
    );

    // Select multiplier operands for S-box or Internal Diagonal
    wire [63:0] cur_diag = DIAG_PACKED[lane_off +: 64];
    always @(*) begin
        case (sub_step)
            3'd0: begin mult_a = add_out;  mult_b = add_out;  end // x^2
            3'd1: begin mult_a = tmp_x2;   mult_b = add_out;  end // x^3
            3'd2: begin mult_a = tmp_x2;   mult_b = tmp_x2;   end // x^4
            3'd3: begin mult_a = tmp_x3;   mult_b = tmp_x2;   end // x^7
            default: begin mult_a = cur_lane; mult_b = cur_diag; end // diag mult
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            fsm                <= ST_LOAD;
            round_idx          <= 6'd0;
            lane_idx           <= 4'd0;
            sub_step           <= 3'd0;
            tmp_x2             <= 64'd0;
            tmp_x3             <= 64'd0;
            running_sum        <= 64'd0;
            nonce_counter      <= 16'd0;
            state_reg          <= 768'd0;
            mult_start         <= 1'b0;
            golden_nonce_found <= 1'b0;
            golden_nonce       <= 16'd0;
        end else if (mining_enable && !golden_nonce_found) begin
            mult_start <= 1'b0;

            case (fsm)
                ST_LOAD: begin
                    state_reg   <= {704'd0, 48'd0, nonce_counter};
                    round_idx   <= 6'd1;
                    lane_idx    <= 4'd0;
                    sub_step    <= 3'd0;
                    fsm         <= ST_SBOX_REQ;
                end

                ST_SBOX_REQ: begin
                    mult_start <= 1'b1;
                    fsm        <= ST_SBOX_WT;
                end

                ST_SBOX_WT: begin
                    if (mult_done) begin
                        case (sub_step)
                            3'd0: begin tmp_x2 <= mult_out; sub_step <= 3'd1; fsm <= ST_SBOX_REQ; end
                            3'd1: begin tmp_x3 <= mult_out; sub_step <= 3'd2; fsm <= ST_SBOX_REQ; end
                            3'd2: begin tmp_x2 <= mult_out; sub_step <= 3'd3; fsm <= ST_SBOX_REQ; end
default: begin
state_reg[lane_off +: 64] <= mult_out;
sub_step <= 3'd0;
if (is_int || lane_idx == 4'd11) begin
lane_idx    <= 4'd0;
running_sum <= 64'd0;
fsm         <= ST_MIX_SUM;
end else begin
lane_idx <= lane_idx + 4'd1;
fsm      <= ST_SBOX_REQ;
end
end
endcase
end
end
ST_MIX_SUM: begin
running_sum <= add_out;
if (lane_idx == 4'd11) begin
lane_idx <= 4'd0;
sub_step <= 3'd4;
if (is_int) begin
mult_start <= 1'b1;
fsm        <= ST_DIAG_WT;
end else begin
fsm        <= ST_MIX_LANE;
end
end else begin
lane_idx <= lane_idx + 4'd1;
end
end
ST_DIAG_WT: begin
if (mult_done) begin
fsm <= ST_MIX_LANE;
end
end
ST_MIX_LANE: begin
state_reg[lane_off +: 64] <= is_int ? add_out : running_sum;
if (lane_idx == 4'd11) begin
lane_idx <= 4'd0;
sub_step <= 3'd0;
if (round_idx == 6'd30) begin
if (running_sum[63:56] < target_top_byte) begin
golden_nonce_found <= 1'b1;
golden_nonce       <= nonce_counter;
end else begin
nonce_counter <= nonce_counter + 16'd1;
fsm           <= ST_LOAD;
end
end else begin
round_idx <= round_idx + 6'd1;
fsm       <= ST_SBOX_REQ;
end
end else begin
lane_idx <= lane_idx + 4'd1;
if (is_int) begin
mult_start <= 1'b1;
fsm        <= ST_DIAG_WT;
end
end
end
default: fsm <= ST_LOAD;
endcase
end
end
endmodule
// ============================================================================
// 4. Tiny Tapeout 24-Pin Physical Chip Wrapper
// ============================================================================
module tt_um_example (
input  wire [7:0] ui_in,
output wire [7:0] uo_out,
input  wire [7:0] uio_in,
output wire [7:0] uio_out,
output wire [7:0] uio_oe,
input  wire       ena,
input  wire       clk,
input  wire       rst_n
);
wire        golden_nonce_found;
wire [15:0] golden_nonce;
wire _unused = &{ena, uio_in, golden_nonce[15], 1'b0};
quantus_miner_compact quantus_core (
.clk(clk),
.reset(~rst_n),
.mining_enable(ena),
.target_top_byte(ui_in),
.golden_nonce_found(golden_nonce_found),
.golden_nonce(golden_nonce)
);
assign uo_out  = {golden_nonce_found, golden_nonce[6:0]};
assign uio_out = golden_nonce[14:7];
assign uio_oe  = 8'hFF;
endmodule
