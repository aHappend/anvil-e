module anvil_en1_uint_to_fp32 (
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
    localparam [2:0] IDLE = 0, NORMALIZE = 1, ROUND = 2,
        PUBLISH = 3, RESPONSE = 4;
    reg [2:0] state;
    reg [31:0] integer_hold, output_hold;
    reg [7:0] exponent_hold;
    reg [3:0] error_hold;
    localparam integer CONTROLLER_BITS = $bits(state) + $bits(integer_hold) +
        $bits(output_hold) + $bits(exponent_hold) + $bits(error_hold);
    assign controller_bytes = rst_n ? 64'((CONTROLLER_BITS+7) >> 3) : 64'd0;
    wire round_up = integer_hold[7] &&
        (|integer_hold[6:0] || integer_hold[8]);
    wire [24:0] rounded = {1'b0, integer_hold[31:8]} + {24'd0, round_up};
    wire [7:0] final_exponent = exponent_hold + {7'd0, rounded[24]};

    assign start_ready = rst_n && state == IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 32'd0;
    assign done_error = rst_n ? error_hold : 4'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            integer_hold <= 0;
            output_hold <= 0;
            exponent_hold <= 0;
            error_hold <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    integer_hold <= operand;
                    exponent_hold <= 158;
                    error_hold <= 0;
                    state <= NORMALIZE;
                end
                NORMALIZE: begin
                    if (integer_hold == 0) begin
                        output_hold <= 0;
                        state <= PUBLISH;
                    end else if (!integer_hold[31]) begin
                        integer_hold <= integer_hold << 1;
                        exponent_hold <= exponent_hold - 1'b1;
                    end else
                        state <= ROUND;
                end
                ROUND: begin
                    output_hold <= {
                        1'b0, final_exponent,
                        rounded[24] ? rounded[23:1] : rounded[22:0]
                    };
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
