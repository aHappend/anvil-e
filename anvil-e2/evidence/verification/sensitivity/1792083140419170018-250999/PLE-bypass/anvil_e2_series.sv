module anvil_e2_series #(
    parameter integer TRIG = 1
) (
    input wire enable,
    input wire [2:0] operation,
    input wire signed [63:0] reduced, term, total,
    input wire [6:0] iteration,
    output reg signed [63:0] next_term, next_total,
    output reg [6:0] next_iteration,
    output wire finished
);
    reg signed [63:0] numerator;
    reg [11:0] divisor;
    integer step;

    function automatic signed [63:0] multiply_q40;
        input signed [63:0] a, b;
        reg signed [127:0] product, rounded;
        begin
            product = a * b;
            rounded = product >>> 40;
            if (product[39:0] > 40'h8000000000 ||
                (product[39:0] == 40'h8000000000 && rounded[0]))
                rounded = rounded + 128'sd1;
            multiply_q40 = rounded[63:0];
        end
    endfunction

    function automatic signed [63:0] divide_round;
        input signed [63:0] n;
        input [11:0] d;
        reg [63:0] magnitude, denominator, quotient, remainder;
        begin
            magnitude = n < 0 ? -n : n;
            denominator = {52'd0,d};
            quotient = magnitude / denominator;
            remainder = magnitude - quotient * denominator;
            if (remainder > denominator-remainder ||
                (remainder == denominator-remainder && quotient[0]))
                quotient = quotient + 64'd1;
            divide_round = n < 0 ? -$signed(quotient) : $signed(quotient);
        end
    endfunction

    assign finished = next_iteration > 18 || next_term == 0;
    always @* begin
        next_term = term;
        next_total = total;
        next_iteration = iteration;
        numerator = 0;
        divisor = 1;
        for (step=0; step<4; step=step+1) begin
            if (enable && next_iteration <= 18 && next_term != 0) begin
                if (TRIG && (operation == 1 || operation == 2)) begin
                    numerator = -multiply_q40(
                        multiply_q40(next_term,reduced),reduced);
                    if (operation == 1)
                        divisor = (12'd2*next_iteration) *
                            (12'd2*next_iteration+12'd1);
                    else
                        divisor = (12'd2*next_iteration-12'd1) *
                            (12'd2*next_iteration);
                end else begin
                    numerator = multiply_q40(next_term,reduced);
                    divisor = {5'd0,next_iteration};
                end
                next_term = divide_round(numerator,divisor);
                next_total = next_total + next_term;
                next_iteration = next_iteration + 1'b1;
            end
        end
    end
endmodule
