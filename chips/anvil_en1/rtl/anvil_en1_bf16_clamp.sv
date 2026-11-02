module anvil_en1_bf16_clamp (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [15:0] value, minimum, maximum,
    output wire done_valid,
    input wire done_ready,
    output wire [15:0] done_data,
    output wire [3:0] done_error,
    output wire [63:0] controller_bytes
);
    localparam [2:0] IDLE = 0, COMPARE = 1, SELECT = 2,
        PUBLISH = 3, RESPONSE = 4;
    reg [2:0] state;
    reg [15:0] value_hold, minimum_hold, maximum_hold, output_hold;
    reg [3:0] error_hold;
    reg invalid_bounds, value_nan, below_minimum, above_maximum;

    function automatic less_than(input [15:0] a, input [15:0] b);
        begin
            if (a[14:0] == 0 && b[14:0] == 0)
                less_than = 0;
            else if (a[15] != b[15])
                less_than = a[15];
            else if (a[15])
                less_than = a[14:0] > b[14:0];
            else
                less_than = a[14:0] < b[14:0];
        end
    endfunction

    wire input_nan = value_hold[14:7] == 255 && value_hold[6:0] != 0;
    wire minimum_nan = minimum_hold[14:7] == 255 && minimum_hold[6:0] != 0;
    wire maximum_nan = maximum_hold[14:7] == 255 && maximum_hold[6:0] != 0;
    wire bad_interval = minimum_nan || maximum_nan ||
        less_than(maximum_hold, minimum_hold);
    wire below = less_than(value_hold, minimum_hold);
    wire above = less_than(maximum_hold, value_hold);
    assign start_ready = rst_n && state == IDLE;
    assign done_valid = rst_n && state == RESPONSE;
    assign done_data = rst_n ? output_hold : 16'd0;
    assign done_error = rst_n ? error_hold : 4'd0;
    assign controller_bytes = rst_n ? 64'd10 : 64'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            value_hold <= 0;
            minimum_hold <= 0;
            maximum_hold <= 0;
            output_hold <= 0;
            error_hold <= 0;
            invalid_bounds <= 0;
            value_nan <= 0;
            below_minimum <= 0;
            above_maximum <= 0;
        end else begin
            case (state)
                IDLE: if (start_valid && start_ready) begin
                    value_hold <= value;
                    minimum_hold <= minimum;
                    maximum_hold <= maximum;
                    output_hold <= 0;
                    error_hold <= 0;
                    state <= COMPARE;
                end
                COMPARE: begin
                    invalid_bounds <= bad_interval;
                    value_nan <= input_nan;
                    below_minimum <= below;
                    above_maximum <= above;
                    state <= SELECT;
                end
                SELECT: begin
                    if (invalid_bounds) begin
                        output_hold <= 0;
                        error_hold <= 5;
                    end else if (value_nan)
                        output_hold <= 16'h7fc0;
                    else if (below_minimum)
                        output_hold <= minimum_hold;
                    else if (above_maximum)
                        output_hold <= maximum_hold;
                    else
                        output_hold <= value_hold;
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
