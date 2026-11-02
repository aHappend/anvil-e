module anvil_en1_allocation_guard (
    input wire clk, rst_n,
    input wire clear,
    input wire report_valid, report_fallback, report_overlap,
    input wire [63:0] equivalent_bytes, native_scratch_bytes,
    input wire [63:0] matched_payload_bytes,
    output wire failed,
    output wire [63:0] controller_bytes
);
    reg comparison_valid, limit_failure, failure_hold;
    reg [68:0] scaled_payload, scaled_baseline;
    wire [63:0] scratch_limit = matched_payload_bytes[63:3] > 61'd1048576 ?
        64'd1048576 : {3'd0, matched_payload_bytes[63:3]};
    wire [68:0] payload_wide = {5'd0, equivalent_bytes};
    wire [68:0] baseline_wide = {5'd0, matched_payload_bytes};
    localparam integer CONTROLLER_BITS = $bits(comparison_valid) +
        $bits(limit_failure) + $bits(failure_hold) +
        $bits(scaled_payload) + $bits(scaled_baseline);
    assign failed = rst_n && failure_hold;
    assign controller_bytes = rst_n ? 64'((CONTROLLER_BITS+7) >> 3) : 64'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            comparison_valid <= 0;
            limit_failure <= 0;
            failure_hold <= 0;
            scaled_payload <= 0;
            scaled_baseline <= 0;
        end else if (clear) begin
            comparison_valid <= 0;
            limit_failure <= 0;
            failure_hold <= 0;
            scaled_payload <= 0;
            scaled_baseline <= 0;
        end else begin
            comparison_valid <= report_valid;
            if (report_valid) begin
                scaled_payload <= (payload_wide << 4) + (payload_wide << 2);
                scaled_baseline <= (baseline_wide << 3) + baseline_wide;
                limit_failure <= matched_payload_bytes == 0 || report_overlap ||
                    (report_fallback ? equivalent_bytes > 64'd1048576 :
                        native_scratch_bytes > scratch_limit);
            end
            if (comparison_valid &&
                (limit_failure || scaled_payload >= scaled_baseline))
                failure_hold <= 1;
        end
    end
endmodule
