module anvil_e2_rope #(parameter integer VISION=0) (
    input wire clk, rst_n,
    input wire start_valid,
    output wire start_ready,
    input wire start_full,
    input wire [31:0] start_position, start_pair, start_dim,
    input wire signed [47:0] start_lo, start_hi,
    output wire nonlinear_valid,
    input wire nonlinear_ready,
    output wire [2:0] nonlinear_op,
    output wire signed [47:0] nonlinear_data,
    input wire nonlinear_out_valid,
    output wire nonlinear_out_ready,
    input wire signed [47:0] nonlinear_out_data,
    input wire nonlinear_out_error,
    output wire mac_clear, mac_accumulate,
    output wire signed [47:0] mac_a, mac_b,
    input wire signed [47:0] mac_rounded,
    output wire out_valid,
    input wire out_ready,
    output wire signed [47:0] out_lo, out_hi,
    output wire out_error
);
    localparam IDLE=0, SERIES=1, ANGLE=2, SINREQ=3, SINRSP=4,
        COSREQ=5, COSRSP=6, LO0=7, LO1=8, LOSAVE=9,
        HI0=10, HI1=11, HISAVE=12, HOLD=13,
        FREQ_START=14, FREQ_WAIT=15, REDUCE_START=16, REDUCE_WAIT=17;
    localparam signed [95:0] ONE=96'sd1099511627776,
        LN2=96'sd762123384786, PI=96'sd3454217652358,
        TWO_PI=96'sd6908435304715,
        LN_LOCAL=96'sd10126876334763, LN_FULL=96'sd15190314502144,
        LN_VISION=96'sd5063438167381;
    reg [4:0] state;
    reg [5:0] iteration;
    reg [31:0] position;
    reg signed [47:0] lo, hi, sine, cosine, angle, result_lo, result_hi;
    reg signed [95:0] reduced, term, total, exponent_shift;
    reg signed [127:0] divide_numerator;
    reg [127:0] divide_denominator;
    reg angle_reduction;
    wire divide_ready, divide_valid, divide_error;
    wire signed [127:0] divide_data, divide_quotient, divide_remainder;
    reg error_hold;
    reg trig_cached;
    reg signed [47:0] cached_angle, cached_sine, cached_cosine;
    reg previous_trig_cached;
    reg signed [47:0] previous_angle, previous_sine, previous_cosine;
    wire signed [63:0] series_term, series_total;
    wire [6:0] series_iteration;
    wire series_finished, series_valid, series_error;
    anvil_e2_series #(.TRIG(0)) series (
        .clk(clk), .rst_n(rst_n),
        .enable(state==SERIES), .operation(3'd0),
        .reduced(reduced[63:0]), .term(term[63:0]), .total(total[63:0]),
        .iteration({1'b0,iteration}),
        .next_term(series_term), .next_total(series_total),
        .next_iteration(series_iteration), .finished(series_finished),
        .step_valid(series_valid), .step_error(series_error)
    );
    anvil_e2_divide divider (
        .clk(clk), .rst_n(rst_n),
        .in_valid(state==FREQ_START || state==REDUCE_START),
        .in_ready(divide_ready), .in_numerator(divide_numerator),
        .in_denominator(divide_denominator), .out_valid(divide_valid),
        .out_ready(state==FREQ_WAIT || state==REDUCE_WAIT),
        .out_data(divide_data), .out_error(divide_error),
        .out_quotient(divide_quotient), .out_remainder(divide_remainder)
    );
    wire signed [95:0] remainder_value=divide_remainder[95:0];
    wire signed [95:0] reduced_angle=remainder_value>PI ? remainder_value-TWO_PI:
        remainder_value< -PI ? remainder_value+TWO_PI:remainder_value;
    wire signed [95:0] floor_quotient=divide_remainder<0 ?
        divide_quotient[95:0]-96'sd1:divide_quotient[95:0];
    wire signed [95:0] angle_product=(total>>>-exponent_shift)*{64'd0,position};
    assign start_ready=rst_n && state==IDLE;
    assign nonlinear_valid=rst_n && (state==SINREQ || state==COSREQ);
    assign nonlinear_op=state==COSREQ ? 3'd2:3'd1;
    assign nonlinear_data=rst_n ? angle:48'sd0;
    assign nonlinear_out_ready=rst_n && (state==SINRSP || state==COSRSP);
    assign mac_clear=rst_n && (state==LO0 || state==HI0);
    assign mac_accumulate=rst_n && (state==LO0 || state==LO1 || state==HI0 || state==HI1);
    assign mac_a=!rst_n ? 48'sd0 : (state==LO0 || state==HI0) ? lo:hi;
    assign mac_b=!rst_n ? 48'sd0 : state==LO0 || state==HI1 ? cosine:
                 state==LO1 ? -sine:sine;
    assign out_valid=rst_n && state==HOLD;
    assign out_lo=rst_n ? result_lo:48'sd0;
    assign out_hi=rst_n ? result_hi:48'sd0;
    assign out_error=rst_n && error_hold;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; iteration<=0; position<=0; lo<=0; hi<=0;
            sine<=0; cosine<=0; angle<=0; result_lo<=0; result_hi<=0;
            reduced<=0; term<=0; total<=0; exponent_shift<=0; error_hold<=0;
            divide_numerator<=0; divide_denominator<=0; angle_reduction<=0;
            trig_cached<=0; cached_angle<=0; cached_sine<=0; cached_cosine<=0;
            previous_trig_cached<=0; previous_angle<=0;
            previous_sine<=0; previous_cosine<=0;
        end else begin
            case (state)
                IDLE: if (start_valid) begin
                    position<=start_position; lo<=start_lo; hi<=start_hi;
                    error_hold<=0; result_lo<=0; result_hi<=0;
                    if (start_dim==0 || start_dim[0] || start_pair>=(start_dim>>1)) begin
                        error_hold<=1; state<=HOLD;
                    end else if (start_pair==0) begin
                        total<=ONE; exponent_shift<=0; state<=ANGLE;
                    end else begin
                        divide_numerator<=
                            (VISION ? LN_VISION:(start_full ? LN_FULL:LN_LOCAL))*
                            128'sd2*{96'd0,start_pair};
                        divide_denominator<={96'd0,start_dim};
                        state<=FREQ_START;
                    end
                end
                FREQ_START: if (divide_ready) state<=FREQ_WAIT;
                FREQ_WAIT: if (divide_valid) begin
                    if (divide_error) begin error_hold<=1; state<=HOLD; end
                    else begin
                        divide_numerator<=-divide_data;
                        divide_denominator<=128'd762123384786;
                        angle_reduction<=0; state<=REDUCE_START;
                    end
                end
                REDUCE_START: if (divide_ready) state<=REDUCE_WAIT;
                REDUCE_WAIT: if (divide_valid) begin
                    if (divide_error) begin error_hold<=1; state<=HOLD; end
                    else if (angle_reduction) begin
                        angle<=reduced_angle[47:0];
                        if (trig_cached && cached_angle==reduced_angle[47:0]) begin
                            sine<=cached_sine; cosine<=cached_cosine; state<=LO0;
                        end else if (previous_trig_cached &&
                                     previous_angle==reduced_angle[47:0]) begin
                            sine<=previous_sine; cosine<=previous_cosine; state<=LO0;
                        end else state<=SINREQ;
                    end else begin
                        exponent_shift<=floor_quotient;
                        reduced<=divide_remainder<0 ? remainder_value+LN2:remainder_value;
                        term<=ONE; total<=ONE; iteration<=1; state<=SERIES;
                    end
                end
                SERIES: if (series_valid) begin
                    term<=series_term; total<=series_total; iteration<=series_iteration[5:0];
                    if (series_error) begin error_hold<=1; state<=HOLD; end
                    else if (series_finished) state<=ANGLE;
                end
                ANGLE: begin
                    divide_numerator<={{32{angle_product[95]}},angle_product};
                    divide_denominator<=128'd6908435304715;
                    angle_reduction<=1; state<=REDUCE_START;
                end
                SINREQ: if (nonlinear_ready) state<=SINRSP;
                SINRSP: if (nonlinear_out_valid) begin
                    if (nonlinear_out_error) begin error_hold<=1; state<=HOLD; end
                    else begin sine<=nonlinear_out_data; state<=COSREQ; end
                end
                COSREQ: if (nonlinear_ready) state<=COSRSP;
                COSRSP: if (nonlinear_out_valid) begin
                    if (nonlinear_out_error) begin error_hold<=1; state<=HOLD; end
                    else begin
                        cosine<=nonlinear_out_data;
                        previous_angle<=cached_angle; previous_sine<=cached_sine;
                        previous_cosine<=cached_cosine; previous_trig_cached<=trig_cached;
                        cached_angle<=angle; cached_sine<=sine;
                        cached_cosine<=nonlinear_out_data; trig_cached<=1;
                        state<=LO0;
                    end
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
