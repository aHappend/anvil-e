module anvil_en1_fp32 (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [2:0] operation,
    input wire [31:0] operand_a, operand_b,
    output wire done_valid,
    input wire done_ready,
    output wire [31:0] done_data,
    output wire [3:0] done_error,
    output wire [63:0] controller_bytes
);
    localparam [4:0] IDLE = 0, CLASSIFY = 1, ADD_ALIGN = 2, ADD_SUM = 3,
        ADD_NORMALIZE = 4, MUL_NORMALIZE = 5, MUL_PARTIAL = 6,
        MUL_REDUCE = 7, MUL_SUM = 8, MUL_ALIGN = 9, ROUND = 10,
        PUBLISH = 11, RESPONSE = 12, HALF_NORMALIZE = 13;
    reg [4:0] state;
    reg [2:0] op;
    reg [31:0] a, b, output_hold;
    reg [3:0] error_hold;
    reg sign_a, sign_b, sign_result;
    reg signed [11:0] exponent_a, exponent_b, exponent_result;
    reg [23:0] mantissa_a, mantissa_b;
    reg [27:0] aligned_a, aligned_b, sum_mantissa;
    reg [23:0] p00, p01, p10, p11;
    reg [47:0] partial_lo, partial_hi, product;
    reg [10:0] half_mantissa;
    reg signed [11:0] half_exponent;
    localparam integer CONTROLLER_BITS = $bits(state) + $bits(op) +
        $bits(a) + $bits(b) + $bits(output_hold) + $bits(error_hold) +
        $bits(sign_a) + $bits(sign_b) + $bits(sign_result) +
        $bits(exponent_a) + $bits(exponent_b) + $bits(exponent_result) +
        $bits(mantissa_a) + $bits(mantissa_b) + $bits(aligned_a) +
        $bits(aligned_b) + $bits(sum_mantissa) + $bits(p00) + $bits(p01) +
        $bits(p10) + $bits(p11) + $bits(partial_lo) + $bits(partial_hi) +
        $bits(product) + $bits(half_mantissa) + $bits(half_exponent);
    assign controller_bytes = rst_n ? 64'((CONTROLLER_BITS+7) >> 3) : 64'd0;

    function automatic [27:0] shift_sticky(
        input [27:0] value, input [11:0] amount
    );
        reg [27:0] shifted, discarded_mask;
        begin
            if (amount == 0)
                shift_sticky = value;
            else if (amount >= 28)
                shift_sticky = {27'd0, |value};
            else begin
                shifted = value >> amount;
                discarded_mask = (28'd1 << amount) - 1'b1;
                shift_sticky = shifted | {27'd0, |(value & discarded_mask)};
            end
        end
    endfunction

    wire a_nan = a[30:23] == 255 && a[22:0] != 0;
    wire b_nan = b[30:23] == 255 && b[22:0] != 0;
    wire a_inf = a[30:23] == 255 && a[22:0] == 0;
    wire b_inf = b[30:23] == 255 && b[22:0] == 0;
    wire a_zero = a[30:0] == 0;
    wire b_zero = b[30:0] == 0;
    wire a_larger = exponent_a > exponent_b ||
        (exponent_a == exponent_b && mantissa_a >= mantissa_b);
    wire signed [11:0] alignment_difference = a_larger ?
        exponent_a - exponent_b : exponent_b - exponent_a;
    wire [27:0] a_extended = {1'b0, mantissa_a, 3'b0};
    wire [27:0] b_extended = {1'b0, mantissa_b, 3'b0};
    wire [27:0] small_aligned = shift_sticky(
        a_larger ? b_extended : a_extended, alignment_difference
    );
    wire [27:0] add_result = sign_a == sign_b ?
        aligned_a + aligned_b : aligned_a - aligned_b;
    wire [27:0] normalized_sum = shift_sticky(sum_mantissa, 12'd1);
    wire [27:0] product_extended = product[47] ?
        {1'b0, product[47:24], product[23:22], |product[21:0]} :
        {1'b0, product[46:23], product[22:21], |product[20:0]};
    wire signed [11:0] product_exponent =
        exponent_a + exponent_b + (product[47] ? 12'sd1 : 12'sd0);
    wire [27:0] subnormal_product = shift_sticky(
        product_extended, -12'sd126 - product_exponent
    );
    wire round_up = sum_mantissa[2] &&
        (sum_mantissa[1] || sum_mantissa[0] || sum_mantissa[3]);
    wire [24:0] rounded = {1'b0, sum_mantissa[26:3]} + {24'd0, round_up};
    wire signed [11:0] rounded_exponent =
        exponent_result + (rounded[24] ? 12'sd1 : 12'sd0);
    wire [23:0] rounded_mantissa = rounded[24] ? rounded[24:1] : rounded[23:0];
    wire [7:0] packed_exponent = 8'(rounded_exponent + 12'sd127);
    wire bf16_up = a[15:0] > 16'h8000 ||
        (a[15:0] == 16'h8000 && a[16]);
    wire [15:0] narrowed_bf16 = a[31:16] + {15'd0, bf16_up};
    wire [7:0] normal_half_exponent = {3'd0, a[14:10]} + 8'd112;
    wire [7:0] subnormal_half_exponent = 8'(half_exponent + 12'sd127);

    assign start_ready = rst_n && state == IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            op <= 0;
            a <= 0;
            b <= 0;
            output_hold <= 0;
            error_hold <= 0;
            sign_a <= 0;
            sign_b <= 0;
            sign_result <= 0;
            exponent_a <= 0;
            exponent_b <= 0;
            exponent_result <= 0;
            mantissa_a <= 0;
            mantissa_b <= 0;
            aligned_a <= 0;
            aligned_b <= 0;
            sum_mantissa <= 0;
            p00 <= 0;
            p01 <= 0;
            p10 <= 0;
            p11 <= 0;
            partial_lo <= 0;
            partial_hi <= 0;
            product <= 0;
            half_mantissa <= 0;
            half_exponent <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    op <= operation;
                    a <= operand_a;
                    b <= operand_b;
                    error_hold <= 0;
                    output_hold <= 0;
                    state <= CLASSIFY;
                end
                CLASSIFY: begin
                    sign_a <= a[31];
                    sign_b <= b[31];
                    mantissa_a <= {a[30:23] != 0, a[22:0]};
                    mantissa_b <= {b[30:23] != 0, b[22:0]};
                    exponent_a <= a[30:23] == 0 ? -12'sd126 :
                        $signed({4'd0, a[30:23]}) - 12'sd127;
                    exponent_b <= b[30:23] == 0 ? -12'sd126 :
                        $signed({4'd0, b[30:23]}) - 12'sd127;
                    case (op)
                        0: begin
                            if (a_nan || b_nan || (a_inf && b_inf && a[31] != b[31])) begin
                                output_hold <= 32'h7fc00000;
                                state <= PUBLISH;
                            end else if (a_inf || b_inf) begin
                                output_hold <= a_inf ? a : b;
                                state <= PUBLISH;
                            end else if (a_zero && b_zero) begin
                                output_hold <= {a[31] && b[31], 31'd0};
                                state <= PUBLISH;
                            end else
                                state <= ADD_ALIGN;
                        end
                        1: begin
                            sign_result <= a[31] ^ b[31];
                            if (a_nan || b_nan || (a_inf && b_zero) || (b_inf && a_zero)) begin
                                output_hold <= 32'h7fc00000;
                                state <= PUBLISH;
                            end else if (a_inf || b_inf) begin
                                output_hold <= {a[31] ^ b[31], 8'hff, 23'd0};
                                state <= PUBLISH;
                            end else if (a_zero || b_zero) begin
                                output_hold <= {a[31] ^ b[31], 31'd0};
                                state <= PUBLISH;
                            end else
                                state <= MUL_NORMALIZE;
                        end
                        2: begin
                            if (a[14:7] == 255 && a[6:0] != 0)
                                output_hold <= 32'h7fc00000;
                            else
                                output_hold <= {a[15:0], 16'd0};
                            state <= PUBLISH;
                        end
                        3: begin
                            if (a_nan)
                                output_hold <= 32'h00007fc0;
                            else
                                output_hold <= {16'd0, narrowed_bf16};
                            state <= PUBLISH;
                        end
                        4: begin
                            sign_result <= a[15];
                            if (a[14:10] == 31) begin
                                if (a[9:0] != 0)
                                    output_hold <= 32'h7fc00000;
                                else
                                    output_hold <= {a[15], 8'hff, 23'd0};
                                state <= PUBLISH;
                            end else if (a[14:0] == 0) begin
                                output_hold <= {a[15], 31'd0};
                                state <= PUBLISH;
                            end else if (a[14:10] != 0) begin
                                output_hold <= {a[15], normal_half_exponent, a[9:0], 13'd0};
                                state <= PUBLISH;
                            end else begin
                                half_mantissa <= {1'b0, a[9:0]};
                                half_exponent <= -12'sd14;
                                state <= HALF_NORMALIZE;
                            end
                        end
                        default: begin
                            output_hold <= 0;
                            error_hold <= 6;
                            state <= PUBLISH;
                        end
                    endcase
                end
                ADD_ALIGN: begin
                    aligned_a <= a_larger ? a_extended : b_extended;
                    aligned_b <= small_aligned;
                    exponent_result <= a_larger ? exponent_a : exponent_b;
                    sign_result <= a_larger ? sign_a : sign_b;
                    state <= ADD_SUM;
                end
                ADD_SUM: begin
                    sum_mantissa <= add_result;
                    state <= ADD_NORMALIZE;
                end
                ADD_NORMALIZE: begin
                    if (sum_mantissa == 0) begin
                        output_hold <= 0;
                        state <= PUBLISH;
                    end else if (sum_mantissa[27]) begin
                        sum_mantissa <= normalized_sum;
                        exponent_result <= exponent_result + 1'b1;
                        state <= ROUND;
                    end else if (!sum_mantissa[26] && exponent_result > -12'sd126) begin
                        sum_mantissa <= sum_mantissa << 1;
                        exponent_result <= exponent_result - 1'b1;
                    end else
                        state <= ROUND;
                end
                MUL_NORMALIZE: begin
                    if (!mantissa_a[23]) begin
                        mantissa_a <= mantissa_a << 1;
                        exponent_a <= exponent_a - 1'b1;
                    end
                    if (!mantissa_b[23]) begin
                        mantissa_b <= mantissa_b << 1;
                        exponent_b <= exponent_b - 1'b1;
                    end
                    if (mantissa_a[23] && mantissa_b[23])
                        state <= MUL_PARTIAL;
                end
                MUL_PARTIAL: begin
                    p00 <= mantissa_a[11:0] * mantissa_b[11:0];
                    p01 <= mantissa_a[11:0] * mantissa_b[23:12];
                    p10 <= mantissa_a[23:12] * mantissa_b[11:0];
                    p11 <= mantissa_a[23:12] * mantissa_b[23:12];
                    state <= MUL_REDUCE;
                end
                MUL_REDUCE: begin
                    partial_lo <= {24'd0, p00} + {12'd0, p01, 12'd0};
                    partial_hi <= {12'd0, p10, 12'd0} + {p11, 24'd0};
                    state <= MUL_SUM;
                end
                MUL_SUM: begin
                    product <= partial_lo + partial_hi;
                    state <= MUL_ALIGN;
                end
                MUL_ALIGN: begin
                    if (product_exponent < -12'sd126) begin
                        exponent_result <= -12'sd126;
                        sum_mantissa <= subnormal_product;
                    end else begin
                        exponent_result <= product_exponent;
                        sum_mantissa <= product_extended;
                    end
                    state <= ROUND;
                end
                ROUND: begin
                    if (rounded_exponent > 12'sd127)
                        output_hold <= {sign_result, 8'hff, 23'd0};
                    else if (rounded_mantissa == 0)
                        output_hold <= {sign_result, 31'd0};
                    else if (rounded_exponent == -12'sd126 && !rounded_mantissa[23])
                        output_hold <= {sign_result, 8'd0, rounded_mantissa[22:0]};
                    else
                        output_hold <= {sign_result, packed_exponent, rounded_mantissa[22:0]};
                    state <= PUBLISH;
                end
                HALF_NORMALIZE: begin
                    if (!half_mantissa[10]) begin
                        half_mantissa <= half_mantissa << 1;
                        half_exponent <= half_exponent - 1'b1;
                    end else begin
                        output_hold <= {
                            sign_result, subnormal_half_exponent, half_mantissa[9:0], 13'd0
                        };
                        state <= PUBLISH;
                    end
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready)
                    state <= IDLE;
                default: begin
                    output_hold <= 0;
                    error_hold <= 7;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
