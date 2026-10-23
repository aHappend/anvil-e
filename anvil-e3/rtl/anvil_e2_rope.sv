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
        FREQUENCY_START=14, FREQUENCY_WAIT=15, FREQUENCY_REDUCE=16,
        SERIES_WAIT=17, FREQ_RED_START=18, FREQ_RED_WAIT=19,
        FREQ_MUL=20, ANGLE_PREP=21, ANGLE_MUL=22, ANGLE_ABS=23,
        ANGLE_RED_START=24, ANGLE_RED_WAIT=25, ANGLE_SUB=26;
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
    reg [95:0] frequency_numerator, frequency_denominator;
    reg signed [95:0] frequency_exponent;
    reg [63:0] exp_q_reg, exp_r_reg;
    reg signed [95:0] exp_quotient_reg, exp_prod_reg;
    reg signed [95:0] angle_shifted_reg, angle_product_reg, temporary_reg;
    reg [95:0] angle_mag_reg, angle_r_reg;
    reg error_hold;
    reg trig_cached;
    reg signed [47:0] cached_angle, cached_sine, cached_cosine;
    reg previous_trig_cached;
    reg signed [47:0] previous_angle, previous_sine, previous_cosine;
    wire signed [63:0] series_term, series_total;
    wire [6:0] series_iteration;
    wire series_ready, series_valid, series_finished, series_error;
    wire frequency_ready, frequency_valid, frequency_error;
    wire [95:0] frequency_quotient, frequency_remainder;
    wire frequency_round_up=
        ({frequency_remainder,1'b0}>{1'b0,frequency_denominator}) ||
        (({frequency_remainder,1'b0}=={1'b0,frequency_denominator}) &&
         frequency_quotient[0]);
    wire [95:0] frequency_rounded=frequency_quotient+96'(frequency_round_up);
    wire [63:0] exponent_magnitude=frequency_exponent[63] ?
        -$unsigned(frequency_exponent[63:0]):$unsigned(frequency_exponent[63:0]);
    wire signed [95:0] quotient=frequency_exponent[63] ?
        -$signed({32'd0,exp_q_reg})-96'(exp_r_reg!=0):$signed({32'd0,exp_q_reg});
    wire signed [95:0] angle_base=angle_product_reg[95] ?
        -$signed(angle_r_reg):$signed(angle_r_reg);
    wire signed [95:0] temporary=angle_base>PI ? angle_base-TWO_PI:
        angle_base< -PI ? angle_base+TWO_PI:angle_base;
    wire div_in_valid=(state==FREQUENCY_START || state==FREQ_RED_START || state==ANGLE_RED_START);
    wire [95:0] div_in_num=(state==FREQUENCY_START) ? frequency_numerator :
        (state==FREQ_RED_START) ? {32'd0,exponent_magnitude} : angle_mag_reg;
    wire [95:0] div_in_den=(state==FREQUENCY_START) ? frequency_denominator :
        (state==FREQ_RED_START) ? 96'd762123384786 : 96'd6908435304715;
    anvil_e3_unsigned_divide #(.WIDTH(96)) frequency_divider (
        .clk(clk), .rst_n(rst_n),
        .in_valid(div_in_valid), .in_ready(frequency_ready),
        .in_numerator(div_in_num), .in_denominator(div_in_den),
        .out_valid(frequency_valid),
        .out_ready(state==FREQUENCY_WAIT || state==FREQ_RED_WAIT || state==ANGLE_RED_WAIT),
        .out_quotient(frequency_quotient), .out_remainder(frequency_remainder),
        .out_error(frequency_error)
    );
    anvil_e2_series #(.TRIG(0)) series (
        .clk(clk), .rst_n(rst_n),
        .enable(state==SERIES), .operation(3'd0),
        .in_ready(series_ready), .out_valid(series_valid),
        .out_ready(state==SERIES_WAIT), .out_error(series_error),
        .reduced(reduced[63:0]), .term(term[63:0]), .total(total[63:0]),
        .iteration({1'b0,iteration}),
        .next_term(series_term), .next_total(series_total),
        .next_iteration(series_iteration), .finished(series_finished)
    );
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
            frequency_numerator<=0; frequency_denominator<=0; frequency_exponent<=0;
            trig_cached<=0; cached_angle<=0; cached_sine<=0; cached_cosine<=0;
            previous_trig_cached<=0; previous_angle<=0;
            previous_sine<=0; previous_cosine<=0;
            exp_q_reg<=0; exp_r_reg<=0; exp_quotient_reg<=0; exp_prod_reg<=0;
            angle_shifted_reg<=0; angle_product_reg<=0; temporary_reg<=0;
            angle_mag_reg<=0; angle_r_reg<=0;
        end else begin
            case (state)
                IDLE: if (start_valid) begin
                    position<=start_position; lo<=start_lo; hi<=start_hi;
                    error_hold<=0; result_lo<=0; result_hi<=0;
                    if (start_dim==0 || start_dim[0] || start_pair>=(start_dim>>1)) begin
                        error_hold<=1; state<=HOLD;
                    end else if (start_pair==0) begin
                        total<=ONE; exponent_shift<=0; state<=ANGLE_PREP;
                    end else begin
                        frequency_numerator<=
                            (VISION ? LN_VISION:(start_full ? LN_FULL:LN_LOCAL))*
                            96'sd2*{64'd0,start_pair};
                        frequency_denominator<={64'd0,start_dim};
                        state<=FREQUENCY_START;
                    end
                end
                FREQUENCY_START: if (frequency_ready) state<=FREQUENCY_WAIT;
                FREQUENCY_WAIT: if (frequency_valid) begin
                    if (frequency_error) begin error_hold<=1; state<=HOLD; end
                    else begin
                        frequency_exponent<=-$signed(frequency_rounded);
                        state<=FREQ_RED_START;
                    end
                end
                FREQ_RED_START: if (frequency_ready) state<=FREQ_RED_WAIT;
                FREQ_RED_WAIT: if (frequency_valid) begin
                    if (frequency_error) begin error_hold<=1; state<=HOLD; end
                    else begin
                        exp_q_reg<=frequency_quotient[63:0];
                        exp_r_reg<=frequency_remainder[63:0];
                        state<=FREQ_MUL;
                    end
                end
                FREQ_MUL: begin
                    exp_quotient_reg<=quotient;
                    exp_prod_reg<=quotient*LN2;
                    state<=FREQUENCY_REDUCE;
                end
                FREQUENCY_REDUCE: begin
                    exponent_shift<=exp_quotient_reg;
                    reduced<=frequency_exponent-exp_prod_reg;
                    term<=ONE; total<=ONE; iteration<=1; state<=SERIES;
                end
                SERIES: if (series_ready) state<=SERIES_WAIT;
                SERIES_WAIT: if (series_valid) begin
                    if (series_error) begin error_hold<=1; state<=HOLD; end
                    else begin
                        term<=series_term; total<=series_total;
                        iteration<=series_iteration[5:0];
                        if (series_finished) state<=ANGLE_PREP;
                        else state<=SERIES;
                    end
                end
                ANGLE_PREP: begin
                    angle_shifted_reg<=(total>>>-exponent_shift);
                    state<=ANGLE_MUL;
                end
                ANGLE_MUL: begin
                    angle_product_reg<=angle_shifted_reg*{64'd0,position};
                    state<=ANGLE_ABS;
                end
                ANGLE_ABS: begin
                    angle_mag_reg<=angle_product_reg[95] ?
                        -$unsigned(angle_product_reg):$unsigned(angle_product_reg);
                    state<=ANGLE_RED_START;
                end
                ANGLE_RED_START: if (frequency_ready) state<=ANGLE_RED_WAIT;
                ANGLE_RED_WAIT: if (frequency_valid) begin
                    if (frequency_error) begin error_hold<=1; state<=HOLD; end
                    else begin
                        angle_r_reg<=frequency_remainder;
                        state<=ANGLE_SUB;
                    end
                end
                ANGLE_SUB: begin
                    temporary_reg<=temporary;
                    state<=ANGLE;
                end
                ANGLE: begin
                    angle<=temporary_reg[47:0];
                    if (trig_cached && cached_angle==temporary_reg[47:0]) begin
                        sine<=cached_sine; cosine<=cached_cosine; state<=LO0;
                    end else if (previous_trig_cached && previous_angle==temporary_reg[47:0]) begin
                        sine<=previous_sine; cosine<=previous_cosine; state<=LO0;
                    end else state<=SINREQ;
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
