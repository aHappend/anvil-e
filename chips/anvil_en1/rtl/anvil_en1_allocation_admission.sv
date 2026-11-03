module anvil_en1_allocation_admission (
    input wire clk, rst_n,
    input wire req_valid,
    output wire req_ready,
    input wire [1:0] model,
    input wire fallback,
    input wire [1599:0] component_live_bytes, component_shadow_bytes,
    input wire [255:0] metadata_bytes, shadow_metadata_bytes,
    input wire [63:0] integration_bytes, matched_payload_bytes,
    input wire [63:0] native_controller_bytes,
    input wire [4:0] candidate_component,
    input wire [63:0] candidate_bytes, candidate_shadow_bytes,
    input wire [63:0] candidate_native_bytes, candidate_native_shadow_bytes,
    output wire rsp_valid,
    input wire rsp_ready,
    output wire rsp_allowed,
    output wire [63:0] controller_bytes
);
    localparam [1:0] IDLE = 0, WAIT_REPORT = 1, COMPARE = 2, RESPONSE = 3;
    reg [1:0] state;
    reg [63:0] baseline_hold;
    reg [68:0] scaled_payload, scaled_shadow, scaled_baseline;
    reg limit_failure, allowed_hold, candidate_legal_hold;
    wire [1599:0] prospective_live, prospective_shadow;
    genvar component;
    generate for (component=0; component<25; component=component+1) begin : candidates
        assign prospective_live[64*component+:64] = candidate_component == component ?
            candidate_bytes : component_live_bytes[64*component+:64];
        assign prospective_shadow[64*component+:64] = candidate_component == component ?
            candidate_shadow_bytes : component_shadow_bytes[64*component+:64];
    end endgenerate
    wire report_valid, report_fallback, report_overlap;
    wire report_partition_error;
    wire [1:0] report_model;
    wire [63:0] equivalent, equivalent_shadow, scratch, scratch_shadow;
    wire [63:0] text_workspace, text_workspace_shadow;
    wire [63:0] fallback_working, fallback_working_shadow;
    wire [63:0] text_limit = report_model == 1 ? 64'd32768 : 64'd65536;
    wire [63:0] ledger_controller_bytes;
    wire [63:0] scratch_limit = baseline_hold[63:3] > 61'd1048576 ?
        64'd1048576 : {3'd0, baseline_hold[63:3]};
    wire [68:0] payload_wide = {5'd0, equivalent};
    wire [68:0] shadow_wide = {5'd0, equivalent_shadow};
    wire [68:0] baseline_wide = {5'd0, baseline_hold};
    localparam integer CONTROLLER_BITS = $bits(state) + $bits(baseline_hold) +
        $bits(scaled_payload) + $bits(scaled_shadow) + $bits(scaled_baseline) +
        $bits(limit_failure) + $bits(allowed_hold) + $bits(candidate_legal_hold);

    assign req_ready = rst_n && state == IDLE;
    assign rsp_valid = rst_n && state == RESPONSE;
    assign rsp_allowed = rst_n && state == RESPONSE && allowed_hold;
    assign controller_bytes = rst_n ?
        64'((CONTROLLER_BITS+7) >> 3) + ledger_controller_bytes : 64'd0;

    anvil_en1_allocation_ledger #(.REPORT_BREAKDOWN(0)) prospective (
        .clk(clk), .rst_n(rst_n),
        .observation_valid(req_valid && req_ready), .observation_model(model),
        .component_live_bytes(prospective_live),
        .component_shadow_bytes(prospective_shadow),
        .metadata_bytes(metadata_bytes), .shadow_metadata_bytes(shadow_metadata_bytes),
        .integration_bytes(integration_bytes),
        .native_workspace_bytes(candidate_native_bytes),
        .native_workspace_shadow_bytes(candidate_native_shadow_bytes),
        .native_controller_bytes(native_controller_bytes),
        .observation_check_valid(1'b1), .observation_fallback(fallback),
        .report_valid(report_valid), .report_check_valid(),
        .report_fallback(report_fallback), .report_overlap(report_overlap),
        .report_model(report_model), .payload_bytes(), .replay_bytes(),
        .equivalent_bytes(equivalent), .equivalent_shadow_bytes(equivalent_shadow),
        .native_scratch_bytes(scratch), .native_scratch_shadow_bytes(scratch_shadow),
        .text_workspace_bytes(text_workspace),
        .text_workspace_shadow_bytes(text_workspace_shadow),
        .fallback_working_bytes(fallback_working),
        .fallback_working_shadow_bytes(fallback_working_shadow),
        .report_partition_error(report_partition_error),
        .controller_bytes(ledger_controller_bytes)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            baseline_hold <= 0;
            scaled_payload <= 0;
            scaled_shadow <= 0;
            scaled_baseline <= 0;
            limit_failure <= 0;
            allowed_hold <= 0;
            candidate_legal_hold <= 0;
        end else begin
            case (state)
                IDLE: if (req_valid && req_ready) begin
                    baseline_hold <= matched_payload_bytes;
                    candidate_legal_hold <= candidate_component == 0 ||
                        candidate_component == 1 || candidate_component == 2 ||
                        candidate_component == 3 || candidate_component == 4 ||
                        candidate_component == 5 ||
                        candidate_component == 6 || candidate_component == 7 ||
                        candidate_component == 8 || candidate_component == 9 || candidate_component == 10 ||
                        candidate_component == 11 || candidate_component == 12 ||
                        candidate_component == 13 || candidate_component == 14 ||
                        candidate_component == 15 || candidate_component == 19 ||
                        candidate_component == 20;
                    allowed_hold <= 0;
                    state <= WAIT_REPORT;
                end
                WAIT_REPORT: if (report_valid) begin
                    scaled_payload <= (payload_wide << 4) + (payload_wide << 2);
                    scaled_shadow <= (shadow_wide << 4) + (shadow_wide << 2);
                    scaled_baseline <= (baseline_wide << 3) + baseline_wide;
                    limit_failure <= !candidate_legal_hold || baseline_hold == 0 ||
                        (report_model != 1 && report_model != 2) ||
                        report_overlap || report_partition_error ||
                        equivalent_shadow < equivalent ||
                        scratch_shadow < scratch || text_workspace_shadow < text_workspace ||
                        fallback_working_shadow < fallback_working ||
                        (report_fallback ?
                            (equivalent > 64'd1048576 ||
                             equivalent_shadow > 64'd1048576 ||
                             fallback_working > 64'd65536 ||
                             fallback_working_shadow > 64'd65536) :
                            (scratch > scratch_limit || scratch_shadow > scratch_limit ||
                             text_workspace > text_limit ||
                             text_workspace_shadow > text_limit));
                    state <= COMPARE;
                end
                COMPARE: begin
                    allowed_hold <= !limit_failure &&
                        scaled_payload < scaled_baseline &&
                        scaled_shadow < scaled_baseline;
                    state <= RESPONSE;
                end
                RESPONSE: if (rsp_ready)
                    state <= IDLE;
                default: begin
                    allowed_hold <= 0;
                    state <= RESPONSE;
                end
            endcase
        end
    end
endmodule
