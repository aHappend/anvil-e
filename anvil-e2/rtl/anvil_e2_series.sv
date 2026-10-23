module anvil_e2_series #(
    parameter integer TRIG = 1
) (
    input wire clk, rst_n, enable,
    input wire [2:0] operation,
    input wire signed [63:0] reduced, term, total,
    input wire [6:0] iteration,
    output wire signed [63:0] next_term, next_total,
    output wire [6:0] next_iteration,
    output wire step_valid, step_error, finished
);
    function automatic signed [63:0] multiply_q40;
        input signed [63:0] a, b;
        reg signed [127:0] product, rounded;
        begin
            product=a*b;
            rounded=product>>>40;
            if (product[39:0]>40'h8000000000 ||
                (product[39:0]==40'h8000000000 && rounded[0]))
                rounded=rounded+128'sd1;
            multiply_q40=rounded[63:0];
        end
    endfunction
    wire trig=TRIG && (operation==1 || operation==2);
    wire [11:0] denominator=!trig ? {5'd0,iteration}:
        operation==1 ? (12'd2*iteration)*(12'd2*iteration+12'd1):
        (12'd2*iteration-12'd1)*(12'd2*iteration);
    wire bypass=iteration>18 || term==0;
    localparam S_IDLE=2'd0, S_TRIG_MUL=2'd1, S_DIV=2'd2;
    reg [1:0] s_state;
    reg signed [63:0] prod1_reg, num_reg;
    reg [11:0] denom_reg;
    wire divide_ready, divide_valid, divide_error;
    wire signed [127:0] divide_result;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_state<=S_IDLE; prod1_reg<=0; num_reg<=0; denom_reg<=0;
        end else if (!enable || bypass) begin
            s_state<=S_IDLE;
        end else begin
            case (s_state)
                S_IDLE: begin
                    prod1_reg<=multiply_q40(term,reduced);
                    num_reg<=multiply_q40(term,reduced);
                    denom_reg<=denominator;
                    if (trig) s_state<=S_TRIG_MUL;
                    else s_state<=S_DIV;
                end
                S_TRIG_MUL: begin
                    num_reg<=-multiply_q40(prod1_reg,reduced);
                    s_state<=S_DIV;
                end
                S_DIV: if (divide_valid) begin
                    s_state<=S_IDLE;
                end
                default: s_state<=S_IDLE;
            endcase
        end
    end
    anvil_e2_divide divider (
        .clk(clk), .rst_n(rst_n), .in_valid(enable && !bypass && s_state==S_DIV),
        .in_ready(divide_ready), .in_numerator({{64{num_reg[63]}},num_reg}),
        .in_denominator({116'd0,denom_reg}),
        .out_valid(divide_valid), .out_ready(enable && s_state==S_DIV),
        .out_data(divide_result), .out_error(divide_error)
    );
    assign next_term=bypass ? term:divide_result[63:0];
    assign next_total=bypass ? total:total+next_term;
    assign next_iteration=bypass ? iteration:iteration+1'b1;
    assign step_valid=rst_n && enable && (bypass || (s_state==S_DIV && divide_valid));
    assign step_error=!bypass && divide_error;
    assign finished=next_iteration>18 || next_term==0;
endmodule
