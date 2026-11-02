module anvil_en1_fp32_divsqrt (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [1:0] operation,
    input wire [31:0] operand_a, operand_b,
    output wire done_valid,
    input wire done_ready,
    output wire [31:0] done_data,
    output wire [3:0] done_error
);
    localparam [3:0] IDLE = 0, CLASSIFY = 1, NORMALIZE = 2,
        DIV_SETUP = 3, DIV_DIGIT = 4, SQRT_SETUP = 5, SQRT_DIGIT = 6,
        ALIGN = 7, ROUND = 8, PUBLISH = 9, RESPONSE = 10,
        RSQRT_SETUP = 11, RSQRT_DIV_DIGIT = 12;
    reg [3:0] state;
    reg [1:0] op;
    reg sign_hold;
    reg [31:0] a, b, output_hold;
    reg [3:0] error_hold;
    reg [23:0] mantissa_a, mantissa_b;
    reg signed [11:0] exponent_a, exponent_b, exponent_hold;
    reg [24:0] div_remainder;
    reg [26:0] quotient, root;
    reg [5:0] digits_left;
    reg [53:0] radicand;
    reg [29:0] root_remainder;
    reg [27:0] round_input;
    reg [53:0] reciprocal_radicand;
    reg [25:0] reciprocal_remainder;
    reg [24:0] reciprocal_denominator;
    reg [6:0] reciprocal_digits_left;

    function automatic [27:0] shift_sticky(
        input [27:0] value, input [11:0] amount
    );
        reg [27:0] shifted, mask;
        begin
            if (amount == 0)
                shift_sticky = value;
            else if (amount >= 28)
                shift_sticky = {27'd0, |value};
            else begin
                shifted = value >> amount;
                mask = (28'd1 << amount) - 1'b1;
                shift_sticky = shifted | {27'd0, |(value & mask)};
            end
        end
    endfunction

    wire a_nan = a[30:23] == 255 && a[22:0] != 0;
    wire b_nan = b[30:23] == 255 && b[22:0] != 0;
    wire a_inf = a[30:23] == 255 && a[22:0] == 0;
    wire b_inf = b[30:23] == 255 && b[22:0] == 0;
    wire a_zero = a[30:0] == 0;
    wire b_zero = b[30:0] == 0;
    wire [24:0] division_numerator = mantissa_a < mantissa_b ?
        {mantissa_a, 1'b0} : {1'b0, mantissa_a};
    wire [25:0] division_trial = {div_remainder, 1'b0};
    wire division_bit = division_trial >= {2'd0, mantissa_b};
    wire [25:0] division_next = division_bit ?
        division_trial - {2'd0, mantissa_b} : division_trial;
    wire [24:0] sqrt_mantissa = exponent_a[0] ?
        {mantissa_a, 1'b0} : {1'b0, mantissa_a};
    wire signed [11:0] sqrt_even_exponent = exponent_a[0] ?
        exponent_a - 12'sd1 : exponent_a;
    wire [29:0] sqrt_trial_remainder =
        {root_remainder[27:0], radicand[53:52]};
    wire [29:0] sqrt_trial_divisor = {1'b0, root, 2'b01};
    wire sqrt_bit = sqrt_trial_remainder >= sqrt_trial_divisor;
    wire [29:0] sqrt_next_remainder = sqrt_bit ?
        sqrt_trial_remainder - sqrt_trial_divisor : sqrt_trial_remainder;
    wire [26:0] reciprocal_trial = {
        reciprocal_remainder, reciprocal_digits_left == 78
    };
    wire reciprocal_bit = reciprocal_trial >= {2'd0, reciprocal_denominator};
    wire [26:0] reciprocal_next = reciprocal_bit ?
        reciprocal_trial - {2'd0, reciprocal_denominator} : reciprocal_trial;
    wire [27:0] result_extended = op != 0 ?
        {1'b0, root[26:1], root[0] | (|root_remainder) |
            (op == 2 && (|reciprocal_remainder))} :
        {1'b0, quotient[26:1], quotient[0] | (|div_remainder)};
    wire [27:0] result_subnormal = shift_sticky(
        result_extended, -12'sd126 - exponent_hold
    );
    wire round_up = round_input[2] &&
        (round_input[1] || round_input[0] || round_input[3]);
    wire [24:0] rounded = {1'b0, round_input[26:3]} + {24'd0, round_up};
    wire [23:0] final_mantissa = rounded[24] ? rounded[24:1] : rounded[23:0];
    wire signed [11:0] final_exponent =
        exponent_hold + (rounded[24] ? 12'sd1 : 12'sd0);
    wire [7:0] packed_exponent = 8'(final_exponent + 12'sd127);

    assign start_ready = rst_n && state == IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            op <= 0;
            sign_hold <= 0;
            a <= 0;
            b <= 0;
            output_hold <= 0;
            error_hold <= 0;
            mantissa_a <= 0;
            mantissa_b <= 0;
            exponent_a <= 0;
            exponent_b <= 0;
            exponent_hold <= 0;
            div_remainder <= 0;
            quotient <= 0;
            root <= 0;
            digits_left <= 0;
            radicand <= 0;
            root_remainder <= 0;
            round_input <= 0;
            reciprocal_radicand <= 0;
            reciprocal_remainder <= 0;
            reciprocal_denominator <= 0;
            reciprocal_digits_left <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    op <= operation;
                    a <= operand_a;
                    b <= operand_b;
                    error_hold <= 0;
                    state <= CLASSIFY;
                end
                CLASSIFY: begin
                    sign_hold <= op != 0 ? 1'b0 : a[31] ^ b[31];
                    mantissa_a <= {a[30:23] != 0, a[22:0]};
                    mantissa_b <= {b[30:23] != 0, b[22:0]};
                    exponent_a <= a[30:23] == 0 ? -12'sd126 :
                        $signed({4'd0, a[30:23]}) - 12'sd127;
                    exponent_b <= b[30:23] == 0 ? -12'sd126 :
                        $signed({4'd0, b[30:23]}) - 12'sd127;
                    if (op == 3) begin
                        output_hold <= 0;
                        error_hold <= 6;
                        state <= PUBLISH;
                    end else if (op != 0) begin
                        if (a_nan || (a[31] && !a_zero)) begin
                            output_hold <= 32'h7fc00000;
                            state <= PUBLISH;
                        end else if (a_inf || a_zero) begin
                            if (op == 2)
                                output_hold <= a_zero ?
                                    {a[31], 8'hff, 23'd0} : 32'd0;
                            else
                                output_hold <= a;
                            state <= PUBLISH;
                        end else
                            state <= NORMALIZE;
                    end else if (a_nan || b_nan || (a_inf && b_inf) ||
                        (a_zero && b_zero)) begin
                        output_hold <= 32'h7fc00000;
                        state <= PUBLISH;
                    end else if (a_inf || b_zero) begin
                        output_hold <= {a[31] ^ b[31], 8'hff, 23'd0};
                        state <= PUBLISH;
                    end else if (a_zero || b_inf) begin
                        output_hold <= {a[31] ^ b[31], 31'd0};
                        state <= PUBLISH;
                    end else
                        state <= NORMALIZE;
                end
                NORMALIZE: begin
                    if (!mantissa_a[23]) begin
                        mantissa_a <= mantissa_a << 1;
                        exponent_a <= exponent_a - 1'b1;
                    end
                    if (op == 0 && !mantissa_b[23]) begin
                        mantissa_b <= mantissa_b << 1;
                        exponent_b <= exponent_b - 1'b1;
                    end
                    if (mantissa_a[23] && (op != 0 || mantissa_b[23])) begin
                        if (op == 2 && mantissa_a == 24'h800000 &&
                            !exponent_a[0]) begin
                            exponent_hold <= -(exponent_a >>> 1);
                            root <= 27'h4000000;
                            root_remainder <= 0;
                            reciprocal_remainder <= 0;
                            state <= ALIGN;
                        end else if (op == 2)
                            state <= RSQRT_SETUP;
                        else if (op == 1)
                            state <= SQRT_SETUP;
                        else
                            state <= DIV_SETUP;
                    end
                end
                DIV_SETUP: begin
                    exponent_hold <= exponent_a - exponent_b -
                        (mantissa_a < mantissa_b ? 12'sd1 : 12'sd0);
                    div_remainder <= division_numerator - {1'b0, mantissa_b};
                    quotient <= 27'd1;
                    digits_left <= 26;
                    state <= DIV_DIGIT;
                end
                DIV_DIGIT: begin
                    div_remainder <= division_next[24:0];
                    quotient <= {quotient[25:0], division_bit};
                    digits_left <= digits_left - 1'b1;
                    if (digits_left == 1)
                        state <= ALIGN;
                end
                SQRT_SETUP: begin
                    if (op == 2) begin
                        exponent_hold <= -(sqrt_even_exponent >>> 1) - 12'sd1;
                        radicand <= reciprocal_radicand;
                    end else begin
                        exponent_hold <= sqrt_even_exponent >>> 1;
                        radicand <= {sqrt_mantissa, 29'd0};
                    end
                    root <= 0;
                    root_remainder <= 0;
                    digits_left <= 27;
                    state <= SQRT_DIGIT;
                end
                SQRT_DIGIT: begin
                    root_remainder <= sqrt_next_remainder;
                    radicand <= {radicand[51:0], 2'd0};
                    root <= {root[25:0], sqrt_bit};
                    digits_left <= digits_left - 1'b1;
                    if (digits_left == 1)
                        state <= ALIGN;
                end
                RSQRT_SETUP: begin
                    reciprocal_denominator <= sqrt_mantissa;
                    reciprocal_remainder <= 0;
                    reciprocal_radicand <= 0;
                    reciprocal_digits_left <= 78;
                    state <= RSQRT_DIV_DIGIT;
                end
                RSQRT_DIV_DIGIT: begin
                    reciprocal_remainder <= reciprocal_next[25:0];
                    reciprocal_radicand <= {reciprocal_radicand[52:0], reciprocal_bit};
                    reciprocal_digits_left <= reciprocal_digits_left - 1'b1;
                    if (reciprocal_digits_left == 1)
                        state <= SQRT_SETUP;
                end
                ALIGN: begin
                    if (exponent_hold < -12'sd126) begin
                        round_input <= result_subnormal;
                        exponent_hold <= -12'sd126;
                    end else
                        round_input <= result_extended;
                    state <= ROUND;
                end
                ROUND: begin
                    if (final_exponent > 12'sd127)
                        output_hold <= {sign_hold, 8'hff, 23'd0};
                    else if (final_mantissa == 0)
                        output_hold <= {sign_hold, 31'd0};
                    else if (final_exponent == -12'sd126 && !final_mantissa[23])
                        output_hold <= {sign_hold, 8'd0, final_mantissa[22:0]};
                    else
                        output_hold <= {sign_hold, packed_exponent, final_mantissa[22:0]};
                    state <= PUBLISH;
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
