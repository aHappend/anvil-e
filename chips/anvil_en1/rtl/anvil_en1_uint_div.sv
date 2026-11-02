module anvil_en1_uint_div (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [31:0] numerator, denominator,
    output wire done_valid,
    input wire done_ready,
    output wire [31:0] quotient, remainder,
    output wire [3:0] done_error,
    output wire [63:0] controller_bytes
);
    localparam [2:0] IDLE = 0, CLASSIFY = 1, DIGIT_COMPARE = 2,
        DIGIT_SUBTRACT = 3, REGISTER = 4, PUBLISH = 5, RESPONSE = 6;
    reg [2:0] state;
    reg [31:0] divisor_hold, quotient_hold;
    reg [32:0] remainder_hold, shifted_hold;
    reg subtract_hold;
    reg [5:0] digits;
    reg [3:0] error_hold;
    wire [32:0] next_remainder = {remainder_hold[31:0], quotient_hold[31]};
    assign start_ready = rst_n && state == IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign quotient = rst_n ? quotient_hold : 32'd0;
    assign remainder = rst_n ? remainder_hold[31:0] : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;
    localparam integer CONTROLLER_BITS = $bits(state) + $bits(divisor_hold) +
        $bits(quotient_hold) + $bits(remainder_hold) + $bits(shifted_hold) +
        $bits(subtract_hold) + $bits(digits) + $bits(error_hold);
    assign controller_bytes = rst_n ? (CONTROLLER_BITS + 7) >> 3 : 64'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            divisor_hold <= 0;
            quotient_hold <= 0;
            remainder_hold <= 0;
            shifted_hold <= 0;
            subtract_hold <= 0;
            digits <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    divisor_hold <= denominator;
                    quotient_hold <= numerator;
                    remainder_hold <= 0;
                    shifted_hold <= 0;
                    subtract_hold <= 0;
                    digits <= 32;
                    error_hold <= 0;
                    state <= CLASSIFY;
                end
                CLASSIFY: begin
                    if (divisor_hold == 0) begin
                        quotient_hold <= 0;
                        remainder_hold <= 0;
                        error_hold <= 5;
                        state <= PUBLISH;
                    end else
                        state <= DIGIT_COMPARE;
                end
                DIGIT_COMPARE: begin
                    shifted_hold <= next_remainder;
                    subtract_hold <= next_remainder >= {1'b0, divisor_hold};
                    state <= DIGIT_SUBTRACT;
                end
                DIGIT_SUBTRACT: begin
                    remainder_hold <= subtract_hold ?
                        shifted_hold - {1'b0, divisor_hold} : shifted_hold;
                    quotient_hold <= {quotient_hold[30:0], subtract_hold};
                    digits <= digits - 1'b1;
                    if (digits == 1)
                        state <= REGISTER;
                    else
                        state <= DIGIT_COMPARE;
                end
                REGISTER: state <= PUBLISH;
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
