module anvil_en1_exp (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [31:0] operand,
    output wire done_valid,
    input wire done_ready,
    output wire [31:0] done_data,
    output wire [3:0] done_error
);
    localparam [3:0] IDLE = 0, CLASSIFY = 1, REDUCE = 2,
        MUL_START = 3, MUL_WAIT = 4, ADD_START = 5, ADD_WAIT = 6,
        SCALE_FIRST = 7, SCALE_SECOND = 8, PUBLISH = 9, RESPONSE = 10;
    localparam [2:0] RETURN_REDUCE = 0, RETURN_PRODUCT = 1,
        RETURN_HORNER = 2, RETURN_SCALE_FIRST = 3, RETURN_SCALE_SECOND = 4;
    reg [3:0] state;
    reg [2:0] return_state;
    reg [31:0] x, remainder_hold, polynomial, output_hold;
    reg [31:0] fp_a, fp_b;
    reg [2:0] fp_op;
    reg [3:0] error_hold;
    reg signed [9:0] power;
    reg [3:0] coefficient_index;
    wire fp_start_ready, fp_done_valid;
    wire [31:0] fp_done_data;
    wire [3:0] fp_done_error;

    function automatic [31:0] coefficient(input [3:0] index);
        begin
            case (index)
                0, 1: coefficient = 32'h3f800000;
                2: coefficient = 32'h3f000000;
                3: coefficient = 32'h3e2aaaab;
                4: coefficient = 32'h3d2aaaab;
                5: coefficient = 32'h3c088889;
                6: coefficient = 32'h3ab60b61;
                7: coefficient = 32'h39500d01;
                8: coefficient = 32'h37d00d01;
                default: coefficient = 0;
            endcase
        end
    endfunction

    wire [31:0] next_coefficient = coefficient(coefficient_index);
    wire negative_reduce = remainder_hold[31] &&
        remainder_hold[30:0] >= 31'h3f317218;
    wire positive_reduce = !remainder_hold[31] &&
        remainder_hold[30:0] >= 31'h3f317218;
    wire signed [9:0] first_power = power < -10'sd126 ? -10'sd126 :
        (power > 10'sd127 ? 10'sd127 : power);
    wire signed [9:0] second_power = power - first_power;
    wire [7:0] first_exponent = 8'(first_power + 10'sd127);
    wire [7:0] second_exponent = 8'(second_power + 10'sd127);
    wire fp_start_valid = rst_n && (state == MUL_START || state == ADD_START);
    wire fp_done_ready = rst_n && (state == MUL_WAIT || state == ADD_WAIT);

    anvil_en1_fp32 fp_unit (
        .clk(clk), .rst_n(rst_n),
        .start_valid(fp_start_valid), .start_ready(fp_start_ready),
        .operation(fp_op), .operand_a(fp_a), .operand_b(fp_b),
        .done_valid(fp_done_valid), .done_ready(fp_done_ready),
        .done_data(fp_done_data), .done_error(fp_done_error)
    );

    assign start_ready = rst_n && state == IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            return_state <= 0;
            x <= 0;
            remainder_hold <= 0;
            polynomial <= 0;
            output_hold <= 0;
            fp_a <= 0;
            fp_b <= 0;
            fp_op <= 0;
            error_hold <= 0;
            power <= 0;
            coefficient_index <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    x <= operand;
                    remainder_hold <= operand;
                    power <= 0;
                    error_hold <= 0;
                    state <= CLASSIFY;
                end
                CLASSIFY: begin
                    if (x[30:23] == 255 && x[22:0] != 0) begin
                        output_hold <= 32'h7fc00000;
                        state <= PUBLISH;
                    end else if (!x[31] && x[30:0] >= 31'h42b20000) begin
                        output_hold <= 32'h7f800000;
                        state <= PUBLISH;
                    end else if (x[31] && x[30:0] >= 31'h42d00000) begin
                        output_hold <= 0;
                        state <= PUBLISH;
                    end else
                        state <= REDUCE;
                end
                REDUCE: begin
                    if (negative_reduce || positive_reduce) begin
                        fp_op <= 0;
                        fp_a <= remainder_hold;
                        fp_b <= negative_reduce ? 32'h3f317218 : 32'hbf317218;
                        power <= power + (negative_reduce ? -10'sd1 : 10'sd1);
                        return_state <= RETURN_REDUCE;
                        state <= ADD_START;
                    end else begin
                        polynomial <= 32'h37d00d01;
                        coefficient_index <= 7;
                        fp_op <= 1;
                        fp_a <= 32'h37d00d01;
                        fp_b <= remainder_hold;
                        return_state <= RETURN_PRODUCT;
                        state <= MUL_START;
                    end
                end
                MUL_START: if (fp_start_ready)
                    state <= MUL_WAIT;
                ADD_START: if (fp_start_ready)
                    state <= ADD_WAIT;
                MUL_WAIT, ADD_WAIT: if (fp_done_valid && fp_done_ready) begin
                    if (fp_done_error != 0) begin
                        error_hold <= fp_done_error;
                        output_hold <= 0;
                        state <= PUBLISH;
                    end else begin
                        case (return_state)
                            RETURN_REDUCE: begin
                                remainder_hold <= fp_done_data;
                                state <= REDUCE;
                            end
                            RETURN_PRODUCT: begin
                                fp_op <= 0;
                                fp_a <= fp_done_data;
                                fp_b <= next_coefficient;
                                return_state <= RETURN_HORNER;
                                state <= ADD_START;
                            end
                            RETURN_HORNER: begin
                                polynomial <= fp_done_data;
                                if (coefficient_index == 0)
                                    state <= SCALE_FIRST;
                                else begin
                                    coefficient_index <= coefficient_index - 1'b1;
                                    fp_op <= 1;
                                    fp_a <= fp_done_data;
                                    fp_b <= remainder_hold;
                                    return_state <= RETURN_PRODUCT;
                                    state <= MUL_START;
                                end
                            end
                            RETURN_SCALE_FIRST: begin
                                polynomial <= fp_done_data;
                                state <= SCALE_SECOND;
                            end
                            RETURN_SCALE_SECOND: begin
                                output_hold <= fp_done_data;
                                state <= PUBLISH;
                            end
                            default: begin
                                error_hold <= 7;
                                output_hold <= 0;
                                state <= PUBLISH;
                            end
                        endcase
                    end
                end
                SCALE_FIRST: begin
                    fp_op <= 1;
                    fp_a <= polynomial;
                    fp_b <= {1'b0, first_exponent, 23'd0};
                    return_state <= RETURN_SCALE_FIRST;
                    state <= MUL_START;
                end
                SCALE_SECOND: begin
                    fp_op <= 1;
                    fp_a <= polynomial;
                    fp_b <= {1'b0, second_exponent, 23'd0};
                    return_state <= RETURN_SCALE_SECOND;
                    state <= MUL_START;
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
