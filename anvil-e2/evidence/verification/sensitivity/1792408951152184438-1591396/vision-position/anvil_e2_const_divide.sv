module anvil_e2_const_divide #(
    parameter logic [63:0] DIVISOR=64'd1
) (
    input wire [63:0] numerator,
    output wire [63:0] quotient, remainder
);
    generate
        if (DIVISOR==0) begin : invalid_divisor
            initial $fatal(1,"PARAMETER ERROR: constant divisor must be positive");
            assign quotient=0;
            assign remainder=0;
        end else if (DIVISOR==1) begin : identity
            assign quotient=numerator;
            assign remainder=0;
        end else begin : reciprocal
            // The only division is an elaboration-time constant expression.
            localparam [63:0] RECIPROCAL=(128'd1 << 64)/DIVISOR;
            wire [127:0] product=numerator*RECIPROCAL;
            wire [63:0] estimate=product[127:64];
            wire [63:0] residual=numerator-estimate*DIVISOR;
            wire correction=residual>=DIVISOR;
            assign quotient=estimate+{63'd0,correction};
            assign remainder=correction ? residual-DIVISOR:residual;
        end
    endgenerate
endmodule
