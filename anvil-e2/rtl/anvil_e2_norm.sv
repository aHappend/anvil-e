module anvil_e2_norm #(
    parameter integer MAX_WIDTH = 2048
) (
    input wire clk,
    input wire rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire [31:0] start_count,
    input wire start_l2,
    input wire in_valid,
    output wire in_ready,
    input wire signed [47:0] in_data,
    input wire signed [31:0] in_weight,
    output wire out_valid,
    input wire out_ready,
    output wire signed [47:0] out_data,
    output wire [31:0] out_index,
    output wire out_last,
    output wire out_error
);
    localparam IDLE=3'd0, LOAD=3'd1, SETUP=3'd2,
               ROOT=3'd3, PREPARE=3'd4, HOLD=3'd5;
    reg [2:0] state;
    reg [31:0] count, index;
    reg l2;
    reg signed [47:0] values [0:MAX_WIDTH-1];
    reg signed [31:0] weights [0:MAX_WIDTH-1];
    reg [127:0] sum_squares;
    wire signed [95:0] square = in_data * in_data;
    reg [191:0] radicand;
    reg [193:0] remainder;
    reg [95:0] root_value;
    reg [6:0] iteration;
    reg signed [47:0] result;
    reg error;
    reg [127:0] denominator_square;
    reg [193:0] shifted_remainder, trial;
    reg signed [127:0] numerator, divisor, magnitude, quotient, residue;
    reg signed [127:0] normalized, unit_weight, product, rounded;

    initial begin
        if (MAX_WIDTH <= 0 || MAX_WIDTH > 65535)
            $fatal(1, "PARAMETER ERROR: norm MAX_WIDTH must be 1..65535");
    end
    assign start_ready = rst_n && state == IDLE;
    assign in_ready = rst_n && state == LOAD;
    assign out_valid = rst_n && state == HOLD;
    assign out_data = rst_n ? result : 48'sd0;
    assign out_index = rst_n ? index : 32'd0;
    assign out_last = rst_n && (error || index == count-1);
    assign out_error = rst_n && error;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            count <= 0;
            index <= 0;
            l2 <= 0;
            sum_squares <= 0;
            radicand <= 0;
            remainder <= 0;
            root_value <= 0;
            iteration <= 0;
            result <= 0;
            error <= 0;
            denominator_square = 0;
            shifted_remainder = 0;
            trial = 0;
            numerator = 0;
            divisor = 0;
            magnitude = 0;
            quotient = 0;
            residue = 0;
            normalized = 0;
            unit_weight = 0;
            product = 0;
            rounded = 0;
        end else begin
            case (state)
                IDLE: if (start_valid) begin
                    count <= start_count;
                    l2 <= start_l2;
                    index <= 0;
                    sum_squares <= 0;
                    error <= 0;
                    result <= 0;
                    if (start_count == 0 || start_count > MAX_WIDTH) begin
                        error <= 1;
                        state <= HOLD;
                    end else begin
                        state <= LOAD;
                    end
                end
                LOAD: if (in_valid) begin
                    values[index] <= in_data;
                    weights[index] <= in_weight;
                    sum_squares <= sum_squares + {32'd0,square};
                    if (index == count-1) begin
                        index <= 0;
                        state <= SETUP;
                    end else begin
                        index <= index + 1'b1;
                    end
                end
                SETUP: begin
                    if (l2) begin
                        denominator_square = sum_squares;
                    end else begin
                        denominator_square = sum_squares / count;
                        residue = sum_squares % count;
                        if (residue > count-residue ||
                            (residue == count-residue && denominator_square[0]))
                            denominator_square = denominator_square + 128'd1;
                        denominator_square = denominator_square + (128'd17 << 56);
                    end
                    radicand <= {denominator_square,64'd0};
                    root_value <= 0;
                    remainder <= 0;
                    iteration <= 0;
                    state <= ROOT;
                end
                ROOT: begin
                    shifted_remainder = (remainder << 2) | {192'd0,radicand[191:190]};
                    trial = ({98'd0,root_value} << 2) | 194'd1;
                    if (shifted_remainder >= trial) begin
                        remainder <= shifted_remainder-trial;
                        root_value <= (root_value << 1) | 96'd1;
                    end else begin
                        remainder <= shifted_remainder;
                        root_value <= root_value << 1;
                    end
                    radicand <= radicand << 2;
                    if (iteration == 95) state <= PREPARE;
                    else iteration <= iteration + 1'b1;
                end
                PREPARE: begin
                    if (root_value == 0) begin
                        result <= 0;
                    end else begin
                        numerator = {{80{values[index][47]}},values[index]} <<< 72;
                        divisor = {32'd0,root_value};
                        magnitude = numerator < 0 ? -numerator : numerator;
                        quotient = magnitude / divisor;
                        residue = magnitude % divisor;
                        if (residue > divisor-residue ||
                            (residue == divisor-residue && quotient[0]))
                            quotient = quotient + 128'sd1;
                        normalized = numerator < 0 ? -quotient : quotient;
                        unit_weight = l2 ? 128'sd16777216 :
                            128'sd16777216 + {{96{weights[index][31]}},weights[index]};
                        product = normalized * unit_weight;
                        rounded = product >>> 24;
                        if (product[23:0] > 24'h800000 ||
                            (product[23:0] == 24'h800000 && rounded[0]))
                            rounded = rounded + 128'sd1;
                        if (rounded > 128'sd140737488289792) result <= 48'sh7fffffff0000;
                        else if (rounded < -128'sd140737488355328) result <= 48'sh800000000000;
                        else result <= rounded[47:0];
                    end
                    state <= HOLD;
                end
                HOLD: if (out_ready) begin
                    if (error || index == count-1) state <= IDLE;
                    else begin
                        index <= index + 1'b1;
                        state <= PREPARE;
                    end
                end
                default: begin
                    error <= 1;
                    result <= 0;
                    state <= HOLD;
                end
            endcase
        end
    end
endmodule
