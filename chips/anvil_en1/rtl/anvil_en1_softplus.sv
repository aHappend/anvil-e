module anvil_en1_softplus (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [31:0] operand,
    output wire done_valid,
    input wire done_ready,
    output wire [31:0] done_data,
    output wire [3:0] done_error,
    output wire [63:0] controller_bytes
);
    localparam [5:0] IDLE = 0, CLASSIFY = 1, EXP_START = 2,
        EXP_WAIT = 3, DENOMINATOR = 4, RATIO_START = 5,
        RATIO_WAIT = 6, SQUARE = 7, SQUARE_REGISTER = 8,
        TERM_START = 9, TERM_WAIT = 10, SUM = 11, SUM_REGISTER = 12,
        POWER = 13, POWER_REGISTER = 14, TWICE = 15, LOG_FINISH = 16,
        POSITIVE_ADD = 17, OUTPUT_REGISTER = 18,
        FP_START = 19, FP_WAIT = 20, PUBLISH = 21, RESPONSE = 22;
    reg [5:0] state, fp_return;
    reg [31:0] x, z, denominator, ratio, squared, power, sum;
    reg [31:0] term, fp_a, fp_b, fp_value, output_hold;
    reg [2:0] fp_op;
    reg [3:0] index_hold, error_hold;

    function automatic [31:0] odd_float(input [3:0] index);
        begin
            case (index)
                0: odd_float = 32'h3f800000;
                1: odd_float = 32'h40400000;
                2: odd_float = 32'h40a00000;
                3: odd_float = 32'h40e00000;
                4: odd_float = 32'h41100000;
                5: odd_float = 32'h41300000;
                6: odd_float = 32'h41500000;
                7: odd_float = 32'h41700000;
                8: odd_float = 32'h41880000;
                9: odd_float = 32'h41980000;
                10: odd_float = 32'h41a80000;
                11: odd_float = 32'h41b80000;
                default: odd_float = 0;
            endcase
        end
    endfunction
    wire [31:0] divisor = odd_float(index_hold);
    wire fp_ready, fp_valid, exp_ready, exp_valid, div_ready, div_valid;
    wire [31:0] fp_data, exp_data, div_data;
    wire [3:0] fp_error, exp_error, div_error;
    anvil_en1_fp32 arithmetic (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == FP_START), .start_ready(fp_ready),
        .operation(fp_op), .operand_a(fp_a), .operand_b(fp_b),
        .done_valid(fp_valid), .done_ready(rst_n && state == FP_WAIT),
        .done_data(fp_data), .done_error(fp_error)
    );
    anvil_en1_exp exponent (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && state == EXP_START), .start_ready(exp_ready),
        .operand({1'b1, x[30:0]}),
        .done_valid(exp_valid), .done_ready(rst_n && state == EXP_WAIT),
        .done_data(exp_data), .done_error(exp_error)
    );
    anvil_en1_fp32_divsqrt divider (
        .clk(clk), .rst_n(rst_n),
        .start_valid(rst_n && (state == RATIO_START || state == TERM_START)),
        .start_ready(div_ready), .operation(2'd0),
        .operand_a(state == RATIO_START ? z : power),
        .operand_b(state == RATIO_START ? denominator : divisor),
        .done_valid(div_valid),
        .done_ready(rst_n && (state == RATIO_WAIT || state == TERM_WAIT)),
        .done_data(div_data), .done_error(div_error)
    );
    assign start_ready = rst_n && state == IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;
    localparam integer CONTROLLER_BITS =
        $bits(state) + $bits(fp_return) + $bits(x) + $bits(z) +
        $bits(denominator) + $bits(ratio) + $bits(squared) + $bits(power) +
        $bits(sum) + $bits(term) + $bits(fp_a) + $bits(fp_b) +
        $bits(fp_value) + $bits(output_hold) + $bits(fp_op) +
        $bits(index_hold) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            fp_return <= 0;
            x <= 0;
            z <= 0;
            denominator <= 0;
            ratio <= 0;
            squared <= 0;
            power <= 0;
            sum <= 0;
            term <= 0;
            fp_a <= 0;
            fp_b <= 0;
            fp_value <= 0;
            output_hold <= 0;
            fp_op <= 0;
            index_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    x <= operand;
                    index_hold <= 0;
                    power <= 32'h3f800000;
                    sum <= 0;
                    output_hold <= 0;
                    error_hold <= 0;
                    state <= CLASSIFY;
                end
                CLASSIFY: begin
                    if (x[30:23] == 255 && x[22:0] != 0) begin
                        output_hold <= 32'h7fc00000;
                        state <= PUBLISH;
                    end else if (!x[31] && x[30:0] > 31'h41a00000) begin
                        output_hold <= x;
                        state <= PUBLISH;
                    end else
                        state <= EXP_START;
                end
                EXP_START: if (exp_ready)
                    state <= EXP_WAIT;
                EXP_WAIT: if (exp_valid) begin
                    if (exp_error != 0) begin
                        error_hold <= exp_error;
                        state <= PUBLISH;
                    end else begin
                        z <= exp_data;
                        state <= DENOMINATOR;
                    end
                end
                DENOMINATOR: begin
                    fp_op <= 0;
                    fp_a <= 32'h40000000;
                    fp_b <= z;
                    fp_return <= RATIO_START;
                    state <= FP_START;
                end
                RATIO_START: if (div_ready)
                    state <= RATIO_WAIT;
                RATIO_WAIT: if (div_valid) begin
                    if (div_error != 0) begin
                        error_hold <= div_error;
                        state <= PUBLISH;
                    end else begin
                        ratio <= div_data;
                        state <= SQUARE;
                    end
                end
                SQUARE: begin
                    fp_op <= 1;
                    fp_a <= ratio;
                    fp_b <= ratio;
                    fp_return <= SQUARE_REGISTER;
                    state <= FP_START;
                end
                SQUARE_REGISTER: begin
                    squared <= fp_value;
                    state <= TERM_START;
                end
                TERM_START: if (div_ready)
                    state <= TERM_WAIT;
                TERM_WAIT: if (div_valid) begin
                    if (div_error != 0) begin
                        error_hold <= div_error;
                        state <= PUBLISH;
                    end else begin
                        term <= div_data;
                        state <= SUM;
                    end
                end
                SUM: begin
                    fp_op <= 0;
                    fp_a <= sum;
                    fp_b <= term;
                    fp_return <= SUM_REGISTER;
                    state <= FP_START;
                end
                SUM_REGISTER: begin
                    sum <= fp_value;
                    if (index_hold == 11)
                        state <= TWICE;
                    else
                        state <= POWER;
                end
                POWER: begin
                    fp_op <= 1;
                    fp_a <= power;
                    fp_b <= squared;
                    fp_return <= POWER_REGISTER;
                    state <= FP_START;
                end
                POWER_REGISTER: begin
                    power <= fp_value;
                    index_hold <= index_hold + 1'b1;
                    state <= TERM_START;
                end
                TWICE: begin
                    fp_op <= 1;
                    fp_a <= ratio;
                    fp_b <= 32'h40000000;
                    fp_return <= LOG_FINISH;
                    state <= FP_START;
                end
                LOG_FINISH: begin
                    fp_op <= 1;
                    fp_a <= fp_value;
                    fp_b <= sum;
                    fp_return <= POSITIVE_ADD;
                    state <= FP_START;
                end
                POSITIVE_ADD: begin
                    if (x[31]) begin
                        output_hold <= fp_value;
                        state <= PUBLISH;
                    end else begin
                        fp_op <= 0;
                        fp_a <= x;
                        fp_b <= fp_value;
                        fp_return <= OUTPUT_REGISTER;
                        state <= FP_START;
                    end
                end
                OUTPUT_REGISTER: begin
                    output_hold <= fp_value;
                    state <= PUBLISH;
                end
                FP_START: if (fp_ready)
                    state <= FP_WAIT;
                FP_WAIT: if (fp_valid) begin
                    if (fp_error != 0) begin
                        error_hold <= fp_error;
                        state <= PUBLISH;
                    end else begin
                        fp_value <= fp_data;
                        if (fp_return == RATIO_START)
                            denominator <= fp_data;
                        state <= fp_return;
                    end
                end
                PUBLISH: state <= RESPONSE;
                RESPONSE: if (done_ready)
                    state <= IDLE;
                default: begin
                    error_hold <= 7;
                    state <= PUBLISH;
                end
            endcase
        end
    end
endmodule
