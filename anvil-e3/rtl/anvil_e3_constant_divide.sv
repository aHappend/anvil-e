module anvil_e3_constant_divide #(
    parameter integer WIDTH=64,
    parameter [WIDTH-1:0] DIVISOR=1
) (
    input wire [WIDTH-1:0] numerator,
    output wire [WIDTH-1:0] quotient, remainder
);
    // The reciprocal is elaboration-only. For n < 2**WIDTH the estimate
    // underestimates floor(n/d) by at most one; one correction is exact.
    localparam [WIDTH:0] RECIPROCAL=
        {1'b1,{WIDTH{1'b0}}}/(DIVISOR==0 ? {{(WIDTH-1){1'b0}},1'b1}:DIVISOR);
    wire [2*WIDTH:0] product=numerator*RECIPROCAL;
    wire [WIDTH-1:0] estimate=product[2*WIDTH-1:WIDTH];
    wire [WIDTH-1:0] residue=numerator-estimate*DIVISOR;
    assign quotient=DIVISOR==1 ? numerator:
        estimate+{{(WIDTH-1){1'b0}},(residue>=DIVISOR)};
    assign remainder=DIVISOR==1 ? {WIDTH{1'b0}}:
        residue>=DIVISOR ? residue-DIVISOR:residue;
    initial begin
        if (WIDTH<1 || DIVISOR==0)
            $fatal(1,"PARAMETER ERROR: constant divider geometry");
    end
endmodule
