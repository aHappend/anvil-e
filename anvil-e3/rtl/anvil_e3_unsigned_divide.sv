module anvil_e3_unsigned_divide #(
    parameter integer WIDTH=128
) (
    input wire clk, rst_n,
    input wire in_valid,
    output wire in_ready,
    input wire [WIDTH-1:0] in_numerator, in_denominator,
    output wire out_valid,
    input wire out_ready,
    output wire [WIDTH-1:0] out_quotient, out_remainder,
    output wire out_error
);
    localparam IDLE=0, RUN=1, HOLD=2;
    localparam integer COUNT_WIDTH=WIDTH<2 ? 1:$clog2(WIDTH+1);
    reg [1:0] state;
    reg [COUNT_WIDTH-1:0] remaining;
    reg [WIDTH-1:0] divisor, quotient, residue;
    reg error_hold;
    wire [WIDTH:0] trial={residue,quotient[WIDTH-1]};
    wire subtract_divisor=trial>={1'b0,divisor};
    wire [WIDTH:0] next_residue=subtract_divisor ?
        trial-{1'b0,divisor}:trial;

    initial begin
        if (WIDTH<1)
            $fatal(1,"PARAMETER ERROR: unsigned divider WIDTH must be positive");
    end
    assign in_ready=rst_n && state==IDLE;
    assign out_valid=rst_n && state==HOLD;
    assign out_quotient=rst_n ? quotient:{WIDTH{1'b0}};
    assign out_remainder=rst_n ? residue:{WIDTH{1'b0}};
    assign out_error=rst_n && error_hold;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; remaining<=0; divisor<=0;
            quotient<=0; residue<=0; error_hold<=0;
        end else case (state)
            IDLE: if (in_valid) begin
                divisor<=in_denominator; residue<=0; error_hold<=0;
                if (in_denominator==0) begin
                    quotient<=0; error_hold<=1; state<=HOLD;
                end else begin
                    quotient<=in_numerator;
                    remaining<=COUNT_WIDTH'(WIDTH);
                    state<=RUN;
                end
            end
            RUN: begin
                residue<=next_residue[WIDTH-1:0];
                quotient<=(quotient<<1) | {{(WIDTH-1){1'b0}},subtract_divisor};
                remaining<=remaining-1'b1;
                if (remaining==1) state<=HOLD;
            end
            HOLD: if (out_ready) state<=IDLE;
            default: begin
                quotient<=0; residue<=0; error_hold<=1; state<=HOLD;
            end
        endcase
    end
endmodule
