module anvil_e2_series #(
    parameter integer TRIG = 1
) (
    input wire clk, rst_n,
    input wire enable,
    output wire in_ready,
    input wire [2:0] operation,
    input wire signed [63:0] reduced, term, total,
    input wire [6:0] iteration,
    output wire out_valid,
    input wire out_ready,
    output wire signed [63:0] next_term, next_total,
    output wire [6:0] next_iteration,
    output wire finished,
    output wire out_error
);
    localparam IDLE=0, MULTIPLY1=1, ROUND1=2, MULTIPLY2=3, ROUND2=4,
        DIV_START=5, DIV_WAIT=6, ROUND_DIV=7, SIGN_DIV=8, ACCUMULATE=9,
        HOLD=10;
    reg [3:0] state;
    reg [2:0] operation_hold;
    reg signed [63:0] reduced_hold, term_hold, total_hold, factor, numerator;
    reg signed [127:0] product;
    reg [6:0] iteration_hold;
    reg [1:0] batch_step;
    reg [63:0] denom_hold, quotient_hold, remainder_hold, rounded_quotient;
    reg error_hold;
    wire trig_term=TRIG && (operation_hold==1 || operation_hold==2);
    wire [11:0] twice_iteration={4'd0,iteration_hold,1'b0};
    wire [11:0] trig_divisor=operation_hold==1 ?
        twice_iteration*(twice_iteration+12'd1):
        (twice_iteration-12'd1)*twice_iteration;
    wire [63:0] denominator=trig_term ?
        {52'd0,trig_divisor}:{57'd0,iteration_hold};
    wire [63:0] magnitude=numerator[63] ?
        -$unsigned(numerator):$unsigned(numerator);
    wire divide_ready, divide_valid, divide_error;
    wire [63:0] quotient, residue;

    anvil_e3_unsigned_divide #(.WIDTH(64)) divider (
        .clk(clk), .rst_n(rst_n), .in_valid(state==DIV_START),
        .in_ready(divide_ready), .in_numerator(magnitude),
        .in_denominator(denom_hold), .out_valid(divide_valid),
        .out_ready(state==DIV_WAIT), .out_quotient(quotient),
        .out_remainder(residue), .out_error(divide_error)
    );

    function automatic signed [63:0] round_product;
        input signed [127:0] value;
        reg signed [127:0] rounded;
        begin
            rounded=value>>>40;
            if (value[39:0]>40'h8000000000 ||
                (value[39:0]==40'h8000000000 && rounded[0]))
                rounded=rounded+128'sd1;
            round_product=rounded[63:0];
        end
    endfunction

    assign in_ready=rst_n && state==IDLE;
    assign out_valid=rst_n && state==HOLD;
    assign next_term=rst_n ? term_hold:64'sd0;
    assign next_total=rst_n ? total_hold:64'sd0;
    assign next_iteration=rst_n ? iteration_hold:7'd0;
    assign finished=rst_n && (iteration_hold>18 || term_hold==0);
    assign out_error=rst_n && error_hold;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; operation_hold<=0; reduced_hold<=0;
            term_hold<=0; total_hold<=0; factor<=0; numerator<=0;
            product<=0; iteration_hold<=0; batch_step<=0;
            denom_hold<=0; quotient_hold<=0; remainder_hold<=0; rounded_quotient<=0;
            error_hold<=0;
        end else case (state)
            IDLE: if (enable) begin
                operation_hold<=operation; reduced_hold<=reduced;
                term_hold<=term; total_hold<=total; iteration_hold<=iteration;
                batch_step<=0; error_hold<=0;
                if (iteration==0) begin
                    error_hold<=1; state<=HOLD;
                end else if (iteration>18 || term==0) state<=HOLD;
                else state<=MULTIPLY1;
            end
            MULTIPLY1: begin
                product<=term_hold*reduced_hold;
                state<=ROUND1;
            end
            ROUND1: begin
                denom_hold<=denominator;
                if (trig_term) begin
                    factor<=round_product(product); state<=MULTIPLY2;
                end else begin
                    numerator<=round_product(product); state<=DIV_START;
                end
            end
            MULTIPLY2: begin
                product<=factor*reduced_hold; state<=ROUND2;
            end
            ROUND2: begin
                numerator<=-round_product(product); state<=DIV_START;
            end
            DIV_START: if (divide_ready) state<=DIV_WAIT;
            DIV_WAIT: if (divide_valid) begin
                if (divide_error) begin
                    error_hold<=1; state<=HOLD;
                end else begin
                    quotient_hold<=quotient; remainder_hold<=residue;
                    state<=ROUND_DIV;
                end
            end
            ROUND_DIV: begin
                rounded_quotient<=quotient_hold+
                    64'(({remainder_hold,1'b0}>{1'b0,denom_hold}) ||
                        (({remainder_hold,1'b0}=={1'b0,denom_hold}) &&
                         quotient_hold[0]));
                state<=SIGN_DIV;
            end
            SIGN_DIV: begin
                term_hold<=numerator[63] ? -$signed(rounded_quotient):
                    $signed(rounded_quotient);
                state<=ACCUMULATE;
            end
            ACCUMULATE: begin
                total_hold<=total_hold+term_hold;
                iteration_hold<=iteration_hold+1'b1;
                if (batch_step==3 || iteration_hold==18 || term_hold==0)
                    state<=HOLD;
                else begin
                    batch_step<=batch_step+1'b1; state<=MULTIPLY1;
                end
            end
            HOLD: if (out_ready) state<=IDLE;
            default: begin error_hold<=1; state<=HOLD; end
        endcase
    end
endmodule
