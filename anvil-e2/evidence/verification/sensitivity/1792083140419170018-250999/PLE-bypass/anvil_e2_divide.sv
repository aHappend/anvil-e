module anvil_e2_divide (
    input wire clk, rst_n,
    input wire in_valid,
    output wire in_ready,
    input wire signed [127:0] in_numerator,
    input wire [127:0] in_denominator,
    output wire out_valid,
    input wire out_ready,
    output wire signed [127:0] out_data,
    output wire out_error
);
    localparam IDLE=0, RUN=1, ROUND=2, HOLD=3;
    reg [1:0] state;
    reg negative, error;
    reg [5:0] iteration, run_iteration;
    reg [127:0] divisor, dividend, quotient, residue;
    reg signed [127:0] result;
    reg [127:0] next_dividend, next_quotient, next_residue;
    reg [128:0] rounded;
    reg [127:0] input_magnitude;
    reg [63:0] estimate_divisor, estimate_numerator, estimate_quotient;
    reg [143:0] trial, estimate_window;
    reg [144:0] estimate_product;
    reg [6:0] estimate_shift;
    integer quotient_bits, run_groups, divisor_shift, divisor_bits, run_step;

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

    assign in_ready=rst_n && state==IDLE;
    assign out_valid=rst_n && state==HOLD;
    assign out_data=rst_n ? result:128'sd0;
    assign out_error=rst_n && error;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; negative<=0; error<=0; iteration<=0;
            divisor<=0; dividend<=0; quotient<=0; residue<=0; result<=0;
            estimate_divisor<=0; estimate_shift<=0;
            input_magnitude=0; quotient_bits=0; run_groups=0; divisor_shift=0;
            divisor_bits=0; run_iteration=0;
            next_dividend=0; next_quotient=0; next_residue=0; rounded=0;
            trial=0; estimate_window=0; estimate_numerator=0;
            estimate_quotient=0; estimate_product=0;
        end else case (state)
            IDLE: if (in_valid) begin
                negative<=in_numerator[127];
                input_magnitude=in_numerator[127] ? -$unsigned(in_numerator):
                    $unsigned(in_numerator);
                divisor<=in_denominator; dividend<=0; quotient<=0; residue<=0;
                iteration<=0; result<=0; error<=0;
                if (in_denominator==0) begin error<=1; state<=HOLD; end
                else if ((in_denominator & (in_denominator-128'd1))==0) begin
                    divisor_shift=bit_length(in_denominator)-1;
                    quotient<=input_magnitude>>divisor_shift;
                    residue<=input_magnitude & (in_denominator-128'd1);
                    state<=ROUND;
                end
                else if (input_magnitude<in_denominator) begin
                    residue<=input_magnitude;
                    state<=ROUND;
                end else begin
                    divisor_bits=bit_length(in_denominator);
                    divisor_shift=divisor_bits>48 ? divisor_bits-48:0;
                    estimate_shift<=7'(divisor_shift);
                    estimate_divisor<=64'(in_denominator>>divisor_shift);
                    quotient_bits=bit_length(input_magnitude)-divisor_bits+1;
                    run_groups=(quotient_bits+15)/16;
                    residue<=input_magnitude>>(16*run_groups);
                    dividend<=input_magnitude<<(128-16*run_groups);
                    iteration<=6'(8-run_groups);
                    state<=RUN;
                end
            end
            RUN: begin
                next_dividend=dividend;
                next_quotient=quotient;
                next_residue=residue;
                run_iteration=iteration;
                for (run_step=0;run_step<4;run_step=run_step+1) begin
                    if (run_iteration<8) begin
                        trial={next_residue,next_dividend[127:112]};
                        estimate_window=trial>>estimate_shift;
                        estimate_numerator=estimate_window[63:0];
                        estimate_quotient=estimate_numerator/estimate_divisor;
                        estimate_product={128'd0,estimate_quotient[16:0]}*
                                         {17'd0,divisor};
                        if (estimate_product>{1'b0,trial}) begin
                            estimate_quotient=estimate_quotient-64'd1;
                            estimate_product=estimate_product-{17'd0,divisor};
                        end
                        next_residue=128'({1'b0,trial}-estimate_product);
                        next_dividend=next_dividend<<16;
                        next_quotient=(next_quotient<<16)|
                            {112'd0,estimate_quotient[15:0]};
                        run_iteration=run_iteration+1'b1;
                    end
                end
                dividend<=next_dividend;
                quotient<=next_quotient;
                residue<=next_residue;
                iteration<=run_iteration;
                if (run_iteration==8) state<=ROUND;
            end
            ROUND: begin
                rounded={1'b0,quotient};
                if (residue>divisor-residue ||
                    (residue==divisor-residue && quotient[0]))
                    rounded=rounded+129'd1;
                if (rounded[128] ||
                    (!negative && rounded[127]) ||
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
