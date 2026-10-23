module anvil_e3_audio_norm #(
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
    localparam IDLE=0, LOAD=1, SETUP=2, ROOT=3, PREPARE=4, HOLD=5,
               MEAN_WAIT=6, ROOT_SETUP=7, RATIO_WAIT=8, APPLY=9, APPLY_ROUND=10;
    reg [3:0] state;
    reg [31:0] count, index;
    reg l2;
    reg signed [47:0] values [0:MAX_WIDTH-1];
    reg signed [31:0] weights [0:MAX_WIDTH-1];
    reg signed [31:0] weight_reg;
    reg [127:0] sum_squares;
    wire signed [95:0] square=in_data*in_data;
    reg [191:0] radicand;
    reg [97:0] remainder;
    reg [95:0] root_value;
    reg [6:0] iteration;
    reg signed [47:0] result;
    reg error;
    reg [127:0] denominator_square;
    integer root_groups;
    reg signed [127:0] normalized, unit_weight, product, product_reg, rounded;
    wire [97:0] step_shift=(remainder<<2)|{96'd0,radicand[191:190]};
    wire [97:0] step_trial=({2'd0,root_value}<<2)|98'd1;
    wire step_ge=step_shift>=step_trial;
    wire divide_in_ready, divide_out_valid, divide_error;
    wire signed [127:0] divide_result;
    wire signed [127:0] ratio_numerator=
        $signed({{80{values[index][47]}},values[index]}) <<< 72;

    function automatic integer bit_length;
        input [127:0] value;
        reg [127:0] remaining;
        begin
            remaining=value;
            bit_length=0;
            if (|remaining[127:64]) begin remaining=remaining>>64; bit_length=64; end
            if (|remaining[63:32]) begin remaining=remaining>>32; bit_length=bit_length+32; end
            if (|remaining[31:16]) begin remaining=remaining>>16; bit_length=bit_length+16; end
            if (|remaining[15:8]) begin remaining=remaining>>8; bit_length=bit_length+8; end
            if (|remaining[7:4]) begin remaining=remaining>>4; bit_length=bit_length+4; end
            if (|remaining[3:2]) begin remaining=remaining>>2; bit_length=bit_length+2; end
            if (remaining[1]) begin remaining=remaining>>1; bit_length=bit_length+1; end
            if (remaining[0]) bit_length=bit_length+1;
        end
    endfunction

    anvil_e2_divide divider (
        .clk(clk), .rst_n(rst_n),
        .in_valid(rst_n && ((state==SETUP && !l2) ||
                           (state==PREPARE && root_value!=0))),
        .in_ready(divide_in_ready),
        .in_numerator(state==SETUP ? $signed(sum_squares):ratio_numerator),
        .in_denominator(state==SETUP ? {96'd0,count}:{32'd0,root_value}),
        .out_valid(divide_out_valid),
        .out_ready(state==MEAN_WAIT || state==RATIO_WAIT),
        .out_data(divide_result), .out_error(divide_error)
    );

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

    always @* begin
        root_groups=(bit_length(denominator_square)+79)>>4;
        unit_weight=l2 ? 128'sd16777216:
            {{96{weight_reg[31]}},weight_reg};
        product=normalized*unit_weight;
        rounded=product_reg>>>24;
        if (product_reg[23:0]>24'h800000 ||
            (product_reg[23:0]==24'h800000 && rounded[0]))
            rounded=rounded+128'sd1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            count <= 0;
            index <= 0;
            l2 <= 0;
            weight_reg <= 0;
            sum_squares <= 0;
            radicand <= 0;
            remainder <= 0;
            root_value <= 0;
            iteration <= 0;
            result <= 0;
            error <= 0;
            denominator_square <= 0;
            normalized <= 0;
            product_reg <= 0;
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
                        denominator_square <= sum_squares;
                        state <= ROOT_SETUP;
                    end else if (divide_in_ready) state <= MEAN_WAIT;
                end
                MEAN_WAIT: if (divide_out_valid) begin
                    if (divide_error) begin error<=1; result<=0; state<=HOLD; end
                    else begin
                        denominator_square <= $unsigned(divide_result) + (128'd17 << 56);
                        state <= ROOT_SETUP;
                    end
                end
                ROOT_SETUP: begin
                    root_value <= 0;
                    remainder <= 0;
                    if (denominator_square==0) begin
                        radicand <= 0;
                        iteration <= 0;
                        state <= PREPARE;
                    end else begin
                        radicand <= {denominator_square,64'd0} <<
                            (192-16*root_groups);
                        iteration <= 7'(96-8*root_groups);
                        state <= ROOT;
                    end
                end
                ROOT: begin
                    radicand <= radicand << 2;
                    remainder <= step_ge ? (step_shift - step_trial) : step_shift;
                    root_value <= (root_value << 1) | {95'd0, step_ge};
                    if (iteration == 7'd95) state <= PREPARE;
                    else iteration <= iteration + 1'b1;
                end
                PREPARE: begin
                    weight_reg <= weights[index];
                    if (root_value == 0) begin
                        result <= 0;
                        state <= HOLD;
                    end else if (divide_in_ready) state <= RATIO_WAIT;
                end
                RATIO_WAIT: if (divide_out_valid) begin
                    if (divide_error) begin error<=1; result<=0; state<=HOLD; end
                    else begin normalized<=divide_result; state<=APPLY; end
                end
                APPLY: begin
                    product_reg <= product;
                    state <= APPLY_ROUND;
                end
                APPLY_ROUND: begin
                    if (rounded > 128'sd140737488289792) result <= 48'sh7fffffff0000;
                    else if (rounded < -128'sd140737488355328) result <= 48'sh800000000000;
                    else result <= rounded[47:0];
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
