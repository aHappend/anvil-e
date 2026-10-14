module anvil_e1_rope (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire start_full,
    input wire [31:0] start_position, start_pair, start_dim,
    input wire signed [31:0] start_lo, start_hi,
    output wire nonlinear_valid,
    input wire nonlinear_ready,
    output wire [2:0] nonlinear_op,
    output wire signed [31:0] nonlinear_data,
    input wire nonlinear_out_valid,
    output wire nonlinear_out_ready,
    input wire signed [31:0] nonlinear_out_data,
    input wire nonlinear_out_error,
    output wire mac_clear, mac_accumulate,
    output wire signed [31:0] mac_a, mac_b,
    input wire signed [31:0] mac_rounded,
    output wire out_valid,
    input wire out_ready,
    output wire signed [31:0] out_lo, out_hi,
    output wire out_error
);
    localparam IDLE=0, SERIES=1, ANGLE=2, SINREQ=3, SINRSP=4,
        COSREQ=5, COSRSP=6, LO0=7, LO1=8, LOSAVE=9,
        HI0=10, HI1=11, HISAVE=12, HOLD=13;
    localparam signed [95:0] ONE=96'sd1099511627776,
        LN2=96'sd762123384786, PI=96'sd3454217652358,
        TWO_PI=96'sd6908435304715,
        LN_LOCAL=96'sd10126876334763, LN_FULL=96'sd15190314502144;
    reg [3:0] state;
    reg [5:0] iteration;
    reg [31:0] position;
    reg signed [31:0] lo, hi, sine, cosine, angle, result_lo, result_hi;
    reg signed [95:0] reduced, term, total, exponent_shift, temporary, quotient;
    reg error_hold;
    function automatic signed [95:0] multiply_q40;
        input signed [95:0] a,b;
        reg signed [191:0] p,q;
        begin
            p=a*b; q=p>>>40;
            if (p[39:0]>40'h8000000000 || (p[39:0]==40'h8000000000 && q[0]))
                q=q+192'sd1;
            multiply_q40=q[95:0];
        end
    endfunction
    function automatic signed [95:0] divide_round;
        input signed [95:0] n,d;
        reg signed [95:0] m,q,r;
        begin
            m=n<0 ? -n:n; q=m/d; r=m%d;
            if (r>d-r || (r==d-r && q[0])) q=q+96'sd1;
            divide_round=n<0 ? -q:q;
        end
    endfunction
    assign start_ready=rst_n && state==IDLE;
    assign nonlinear_valid=rst_n && (state==SINREQ || state==COSREQ);
    assign nonlinear_op=state==COSREQ ? 3'd2:3'd1;
    assign nonlinear_data=rst_n ? angle:32'sd0;
    assign nonlinear_out_ready=rst_n && (state==SINRSP || state==COSRSP);
    assign mac_clear=rst_n && (state==LO0 || state==HI0);
    assign mac_accumulate=rst_n && (state==LO0 || state==LO1 || state==HI0 || state==HI1);
    assign mac_a=!rst_n ? 32'sd0 : (state==LO0 || state==HI0) ? lo:hi;
    assign mac_b=!rst_n ? 32'sd0 : state==LO0 || state==HI1 ? cosine:
                 state==LO1 ? -sine:sine;
    assign out_valid=rst_n && state==HOLD;
    assign out_lo=rst_n ? result_lo:32'sd0;
    assign out_hi=rst_n ? result_hi:32'sd0;
    assign out_error=rst_n && error_hold;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; iteration<=0; position<=0; lo<=0; hi<=0;
            sine<=0; cosine<=0; angle<=0; result_lo<=0; result_hi<=0;
            reduced<=0; term<=0; total<=0; exponent_shift<=0; error_hold<=0;
            temporary=0; quotient=0;
        end else begin
            case (state)
                IDLE: if (start_valid) begin
                    position<=start_position; lo<=start_lo; hi<=start_hi;
                    error_hold<=0; result_lo<=0; result_hi<=0;
                    if (start_dim==0 || start_dim[0] || start_pair>=start_dim/2) begin
                        error_hold<=1; state<=HOLD;
                    end else begin
                        temporary=-divide_round(
                            (start_full ? LN_FULL:LN_LOCAL)*96'sd2*{64'd0,start_pair},
                            {64'd0,start_dim});
                        quotient=temporary/LN2;
                        if (temporary%LN2<0) quotient=quotient-96'sd1;
                        exponent_shift<=quotient;
                        reduced<=temporary-quotient*LN2;
                        term<=ONE; total<=ONE; iteration<=1; state<=SERIES;
                    end
                end
                SERIES: begin
                    temporary=divide_round(multiply_q40(term,reduced),{90'd0,iteration});
                    term<=temporary; total<=total+temporary;
                    if (iteration==18) state<=ANGLE;
                    else iteration<=iteration+1'b1;
                end
                ANGLE: begin
                    temporary=((total>>>-exponent_shift)*{64'd0,position})%TWO_PI;
                    if (temporary>PI) temporary=temporary-TWO_PI;
                    if (temporary< -PI) temporary=temporary+TWO_PI;
                    quotient=temporary>>>16;
                    if (temporary[15:0]>16'h8000 || (temporary[15:0]==16'h8000 && quotient[0]))
                        quotient=quotient+96'sd1;
                    angle<=quotient[31:0]; state<=SINREQ;
                end
                SINREQ: if (nonlinear_ready) state<=SINRSP;
                SINRSP: if (nonlinear_out_valid) begin
                    if (nonlinear_out_error) begin error_hold<=1; state<=HOLD; end
                    else begin sine<=nonlinear_out_data; state<=COSREQ; end
                end
                COSREQ: if (nonlinear_ready) state<=COSRSP;
                COSRSP: if (nonlinear_out_valid) begin
                    if (nonlinear_out_error) begin error_hold<=1; state<=HOLD; end
                    else begin cosine<=nonlinear_out_data; state<=LO0; end
                end
                LO0: state<=LO1;
                LO1: state<=LOSAVE;
                LOSAVE: begin result_lo<=mac_rounded; state<=HI0; end
                HI0: state<=HI1;
                HI1: state<=HISAVE;
                HISAVE: begin result_hi<=mac_rounded; state<=HOLD; end
                HOLD: if (out_ready) state<=IDLE;
                default: begin error_hold<=1; state<=HOLD; end
            endcase
        end
    end
endmodule
