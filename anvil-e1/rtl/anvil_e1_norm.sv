module anvil_e1_norm #(
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
    input wire signed [31:0] in_data,
    input wire signed [31:0] in_weight,
    output wire out_valid,
    input wire out_ready,
    output wire signed [31:0] out_data,
    output wire [31:0] out_index,
    output wire out_last,
    output wire out_error
);
    localparam IDLE=0, LOAD=1, SETUP=2, ROOT=3, PREPARE=4, HOLD=5,
               DIVIDE=6, SETUP_SAVE=7, NORMALIZE=8, DIV_DONE=9, NORMALIZE_SAVE=10;
    localparam [95:0] EPSILON_Q48 = 96'd281474977;
    reg [3:0] state;
    reg [31:0] count, index;
    reg l2;
    reg signed [31:0] values [0:MAX_WIDTH-1];
    reg signed [31:0] weights [0:MAX_WIDTH-1];
    reg [95:0] sum_squares;
    wire signed [63:0] square = in_data * in_data;
    reg [159:0] radicand;
    reg [161:0] remainder;
    reg [79:0] root_value;
    reg [6:0] iteration;
    reg signed [31:0] result;
    reg error;
    wire [161:0] shifted_remainder=(remainder<<2)|{160'd0,radicand[159:158]};
    wire [161:0] trial=({82'd0,root_value}<<2)|162'd1;
    reg [95:0] div_quotient, div_divisor;
    reg [96:0] div_remainder;
    reg div_negative;
    reg [5:0] div_iteration;
    reg [3:0] div_return;
    reg [95:0] div_rounded_reg;
    reg signed [95:0] div_result_reg, norm_prod_reg;
    reg [95:0] div_next_quotient;
    reg [96:0] div_next_remainder;
    integer div_bit;
    always @* begin
        div_next_quotient=div_quotient;
        div_next_remainder=div_remainder;
        if (state==DIVIDE) begin
            for (div_bit=0; div_bit<2; div_bit=div_bit+1) begin
                div_next_remainder={div_next_remainder[95:0],div_next_quotient[95]};
                div_next_quotient=div_next_quotient<<1;
                if (div_next_remainder>={1'b0,div_divisor}) begin
                    div_next_remainder=div_next_remainder-{1'b0,div_divisor};
                    div_next_quotient[0]=1'b1;
                end
            end
        end
    end
    wire [95:0] div_rounded_magnitude=div_quotient+
        ((div_remainder>{1'b0,div_divisor}-div_remainder ||
          (div_remainder=={1'b0,div_divisor}-div_remainder && div_quotient[0]))
         ? 96'd1:96'd0);
    wire signed [95:0] div_result=div_negative ?
        -$signed(div_rounded_magnitude):$signed(div_rounded_magnitude);
    task automatic begin_divide;
        input signed [95:0] numerator, denominator;
        input [3:0] next_state;
        begin
            div_quotient<=numerator<0 ? -numerator:numerator;
            div_divisor<=denominator<0 ? -denominator:denominator;
            div_remainder<=0; div_iteration<=0;
            div_negative<=(numerator<0)!=(denominator<0);
            div_return<=next_state; state<=DIVIDE;
        end
    endtask
    function automatic signed [31:0] round_saturate_q24;
        input signed [95:0] product;
        reg signed [95:0] rounded;
        begin
            rounded=product>>>24;
            if (product[23:0]>24'h800000 ||
                (product[23:0]==24'h800000 && rounded[0]))
                rounded=rounded+96'sd1;
            if (rounded>96'sd2147483647) round_saturate_q24=32'sh7fffffff;
            else if (rounded< -96'sd2147483648) round_saturate_q24=32'sh80000000;
            else round_saturate_q24=rounded[31:0];
        end
    endfunction

    initial begin
        if (MAX_WIDTH <= 0 || MAX_WIDTH > 65535)
            $fatal(1, "PARAMETER ERROR: norm MAX_WIDTH must be 1..65535");
    end
    assign start_ready = rst_n && state == IDLE;
    assign in_ready = rst_n && state == LOAD;
    assign out_valid = rst_n && state == HOLD;
    assign out_data = rst_n ? result : 32'sd0;
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
            div_quotient<=0; div_divisor<=0; div_remainder<=0;
            div_negative<=0; div_iteration<=0; div_return<=IDLE;
            div_rounded_reg<=0; div_result_reg<=0; norm_prod_reg<=0;
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
                        radicand<={sum_squares,64'd0};
                        root_value<=0; remainder<=0; iteration<=0; state<=ROOT;
                    end else begin_divide($signed(sum_squares),{64'd0,count},SETUP_SAVE);
                end
                DIVIDE: begin
                    div_quotient<=div_next_quotient; div_remainder<=div_next_remainder;
                    if (div_iteration==47) state<=DIV_DONE;
                    else div_iteration<=div_iteration+1'b1;
                end
                DIV_DONE: begin
                    div_rounded_reg<=div_rounded_magnitude;
                    div_result_reg<=div_result;
                    state<=div_return;
                end
                SETUP_SAVE: begin
                    radicand <= {div_rounded_reg+EPSILON_Q48,64'd0};
                    root_value<=0; remainder<=0; iteration<=0; state<=ROOT;
                end
                ROOT: begin
                    if (shifted_remainder >= trial) begin
                        remainder <= shifted_remainder-trial;
                        root_value <= (root_value << 1) | 80'd1;
                    end else begin
                        remainder <= shifted_remainder;
                        root_value <= root_value << 1;
                    end
                    radicand <= radicand << 2;
                    if (iteration == 79) state <= PREPARE;
                    else iteration <= iteration + 1'b1;
                end
                PREPARE: begin
                    if (root_value == 0) begin
                        result <= 0;
                        state <= HOLD;
                    end else begin_divide(
                        $signed({{64{values[index][31]}},values[index]})<<<56,
                        {16'd0,root_value},NORMALIZE);
                end
                NORMALIZE: begin
                    norm_prod_reg<=div_result_reg*(l2 ? 96'sd16777216:
                        96'sd16777216+{{64{weights[index][31]}},weights[index]});
                    state<=NORMALIZE_SAVE;
                end
                NORMALIZE_SAVE: begin
                    result<=round_saturate_q24(norm_prod_reg);
                    state<=HOLD;
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
