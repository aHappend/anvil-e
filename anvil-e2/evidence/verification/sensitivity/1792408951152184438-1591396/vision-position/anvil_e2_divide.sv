module anvil_e2_divide (
    input wire clk, rst_n,
    input wire in_valid,
    output wire in_ready,
    input wire signed [127:0] in_numerator,
    input wire [127:0] in_denominator,
    output wire out_valid,
    input wire out_ready,
    output wire signed [127:0] out_data,
    output wire out_error,
    output wire signed [127:0] out_quotient,
    output wire signed [127:0] out_remainder
);
    localparam IDLE=0, RUN=1, ROUND=2, HOLD=3;
    reg [1:0] state;
    reg negative, error;
    reg [7:0] iteration;
    reg [127:0] divisor, quotient, residue;
    reg signed [127:0] result;
    wire [127:0] magnitude=in_numerator[127] ?
        -$unsigned(in_numerator):$unsigned(in_numerator);
    wire [127:0] shifted_divisor=divisor << iteration;
    wire subtract=residue>=shifted_divisor;
    wire [127:0] next_residue=subtract ? residue-shifted_divisor:residue;
    wire [127:0] next_quotient=subtract ?
        quotient | (128'd1 << iteration):quotient;
    wire round_up=residue>divisor-residue ||
        (residue==divisor-residue && quotient[0]);
    wire [128:0] rounded={1'b0,quotient}+{128'd0,round_up};

    function automatic [7:0] bit_length;
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

    assign in_ready=rst_n && state==IDLE;
    assign out_valid=rst_n && state==HOLD;
    assign out_data=rst_n ? result:128'sd0;
    assign out_error=rst_n && error;
    assign out_quotient=!rst_n ? 128'sd0:
        negative ? -$signed(quotient):$signed(quotient);
    assign out_remainder=!rst_n ? 128'sd0:
        negative ? -$signed(residue):$signed(residue);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; negative<=0; error<=0; iteration<=0;
            divisor<=0; quotient<=0; residue<=0; result<=0;
        end else case (state)
            IDLE: if (in_valid) begin
                negative<=in_numerator[127];
                divisor<=in_denominator; quotient<=0; residue<=magnitude;
                iteration<=0; result<=0; error<=0;
                if (in_denominator==0) begin error<=1; state<=HOLD; end
                else if ((in_denominator & (in_denominator-128'd1))==0) begin
                    quotient<=magnitude >> (bit_length(in_denominator)-1'b1);
                    residue<=magnitude & (in_denominator-128'd1);
                    state<=ROUND;
                end else if (magnitude<in_denominator) state<=ROUND;
                else begin
                    iteration<=bit_length(magnitude)-bit_length(in_denominator);
                    state<=RUN;
                end
            end
            RUN: begin
                residue<=next_residue;
                quotient<=next_quotient;
                if (iteration==0) state<=ROUND;
                else iteration<=iteration-1'b1;
            end
            ROUND: begin
                if (rounded[128] || (!negative && rounded[127]) ||
                    (negative && rounded>{2'b01,127'd0})) begin
                    error<=1; result<=0;
                end else result<=negative ? -$signed(rounded[127:0]):
                    $signed(rounded[127:0]);
                state<=HOLD;
            end
            HOLD: if (out_ready) state<=IDLE;
            default: begin error<=1; result<=0; state<=HOLD; end
        endcase
    end
endmodule
