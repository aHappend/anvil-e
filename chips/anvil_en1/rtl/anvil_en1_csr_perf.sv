module anvil_en1_csr_perf (
    input wire clk, rst_n,
    input wire csr_valid, csr_write,
    input wire [11:0] csr_addr,
    input wire [31:0] csr_wdata,
    output wire csr_ready,
    output wire csr_rsp_valid,
    input wire csr_rsp_ready,
    output wire [31:0] csr_rdata,
    output wire csr_error,
    input wire [1:0] status_model,
    input wire status_busy,
    input wire [3:0] status_error,
    input wire event_valid,
    input wire [1:0] event_model,
    input wire [24:0] event_mask,
    input wire [1599:0] event_values,
    input wire allocation_valid,
    input wire [1:0] allocation_model,
    input wire [63:0] allocation_payload_bytes, allocation_replay_bytes,
    input wire [63:0] allocation_equivalent_bytes,
    input wire traffic_valid,
    input wire [1:0] traffic_model,
    input wire traffic_write, traffic_input, traffic_cache,
    output wire [63:0] controller_bytes
);
    localparam integer METRICS = 29;
    localparam [1:0] IDLE = 0, EXECUTE = 1, RESPONSE = 2;
    reg [1:0] state;
    reg write_hold;
    reg [11:0] addr_hold;
    reg [31:0] wdata_hold, response_hold;
    reg error_hold, bank_select, request_bank, snapshot_active;
    reg [1:0] status_model_hold;
    reg status_busy_hold;
    reg [3:0] status_error_hold;
    reg atomic_valid, atomic_bank;
    reg [4:0] atomic_metric;
    reg [31:0] atomic_high;
    reg [63:0] counters [0:2*METRICS-1];
    reg [63:0] snapshots [0:2*METRICS-1];
    localparam integer CONTROLLER_BITS = 4*METRICS*64 + $bits({
        state, write_hold, addr_hold, wdata_hold, response_hold, error_hold,
        bank_select, request_bank, snapshot_active, status_model_hold,
        status_busy_hold, status_error_hold, atomic_valid, atomic_bank,
        atomic_metric, atomic_high
    });
    assign controller_bytes = rst_n ? 64'((CONTROLLER_BITS+7) >> 3) : 64'd0;

    wire control_legal = wdata_hold[31:3] == 0 &&
        !(wdata_hold[1] && wdata_hold[2]);
    wire clear_counters = state == EXECUTE && write_hold &&
        addr_hold == 12'h008 && control_legal && wdata_hold[0];
    wire capture_snapshot = state == EXECUTE && write_hold &&
        addr_hold == 12'h008 && control_legal && wdata_hold[1];
    wire release_snapshot = state == EXECUTE && write_hold &&
        addr_hold == 12'h008 && control_legal && wdata_hold[2];
    wire [11:0] metric_offset = addr_hold - 12'h020;
    wire [8:0] metric_wide = metric_offset[11:3];
    wire metric_legal = addr_hold >= 12'h020 && addr_hold <= 12'h104 &&
        addr_hold[1:0] == 0 && metric_wide < METRICS;
    wire [4:0] metric_index = metric_wide[4:0];
    wire [5:0] selected_index = request_bank ?
        {1'b0, metric_index} + 6'(METRICS) : {1'b0, metric_index};
    wire [63:0] selected_value = metric_legal ?
        (snapshot_active ? snapshots[selected_index] : counters[selected_index]) : 64'd0;
    wire event_native = event_model == 1 || event_model == 2;
    wire traffic_native = traffic_model == 1 || traffic_model == 2;

    genvar bank, metric;
    generate for (bank = 0; bank < 2; bank = bank + 1) begin : metric_banks
        for (metric = 0; metric < METRICS; metric = metric + 1) begin : metric_words
            localparam integer INDEX = bank*METRICS+metric;
            wire legacy_event;
            wire [63:0] legacy_value;
            if (metric < 25) begin : legacy
                assign legacy_event = event_valid && event_mask[metric] &&
                    (bank == 0 ? event_model == 0 : event_native);
                assign legacy_value = event_values[64*metric+:64];
            end else begin : appended
                assign legacy_event = 1'b0;
                assign legacy_value = 64'd0;
            end
            wire traffic_bank = bank == 0 ? traffic_model == 0 : traffic_native;
            wire traffic_class =
                (metric == 4 && traffic_native && traffic_cache && !traffic_write) ||
                (metric == 5 && traffic_native && traffic_cache && traffic_write) ||
                (metric == 25 && traffic_native && !traffic_write &&
                    !traffic_cache && traffic_input) ||
                (metric == 26 && traffic_native && !traffic_write &&
                    !traffic_cache && !traffic_input) ||
                (metric == 27 && traffic_native && traffic_write && !traffic_cache) ||
                metric == 28;
            wire traffic_event = traffic_valid && traffic_bank && traffic_class;
            wire allocation_event = allocation_valid &&
                (metric == 15 || metric == 20 || metric == 24) &&
                (bank == 0 ? allocation_model == 0 :
                    (allocation_model == 1 || allocation_model == 2));
            wire selected_event = allocation_event || traffic_event || legacy_event;
            wire [63:0] value = allocation_event ?
                (metric == 15 ? allocation_payload_bytes :
                    (metric == 20 ? allocation_replay_bytes : allocation_equivalent_bytes)) :
                (traffic_event ? 64'd4 : legacy_value);
            wire [64:0] updated = {1'b0, counters[INDEX]} + {1'b0, value};
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    counters[INDEX] <= 0;
                    snapshots[INDEX] <= 0;
                end else begin
                    if (clear_counters)
                        counters[INDEX] <= 0;
                    else if (selected_event) begin
                        if (metric == 15 || metric == 16)
                            counters[INDEX] <= value;
                        else if (metric == 20 || metric == 24) begin
                            if (value > counters[INDEX])
                                counters[INDEX] <= value;
                        end else
                            counters[INDEX] <= updated[64] ?
                                64'hffffffffffffffff : updated[63:0];
                    end
                    if (clear_counters)
                        snapshots[INDEX] <= 0;
                    else if (capture_snapshot)
                        snapshots[INDEX] <= counters[INDEX];
                end
            end
        end
    end endgenerate

    assign csr_ready = rst_n && state == IDLE;
    assign csr_rsp_valid = rst_n && state == RESPONSE;
    assign csr_rdata = rst_n ? response_hold : 32'd0;
    assign csr_error = rst_n && error_hold;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            write_hold <= 0;
            addr_hold <= 0;
            wdata_hold <= 0;
            response_hold <= 0;
            error_hold <= 0;
            bank_select <= 0;
            request_bank <= 0;
            snapshot_active <= 0;
            status_model_hold <= 0;
            status_busy_hold <= 0;
            status_error_hold <= 0;
            atomic_valid <= 0;
            atomic_bank <= 0;
            atomic_metric <= 0;
            atomic_high <= 0;
        end else begin
            case (state)
                IDLE: if (csr_valid && csr_ready) begin
                    write_hold <= csr_write;
                    addr_hold <= csr_addr;
                    wdata_hold <= csr_wdata;
                    request_bank <= bank_select;
                    status_model_hold <= status_model;
                    status_busy_hold <= status_busy;
                    status_error_hold <= status_error;
                    state <= EXECUTE;
                end
                EXECUTE: begin
                    response_hold <= 0;
                    error_hold <= 0;
                    state <= RESPONSE;
                    if (addr_hold[1:0] != 0)
                        error_hold <= 1;
                    else if (write_hold) begin
                        case (addr_hold)
                            12'h008: begin
                                if (!control_legal)
                                    error_hold <= 1;
                                else begin
                                    atomic_valid <= 0;
                                    if (capture_snapshot)
                                        snapshot_active <= 1;
                                    else if (release_snapshot)
                                        snapshot_active <= 0;
                                end
                            end
                            12'h00c: begin
                                if ((wdata_hold & 32'hfffeffff) != 0)
                                    error_hold <= 1;
                                else begin
                                    bank_select <= wdata_hold[16];
                                    atomic_valid <= 0;
                                end
                            end
                            default: error_hold <= 1;
                        endcase
                    end else begin
                        case (addr_hold)
                            12'h000: response_hold <= 32'h01000000;
                            12'h004: response_hold <= 32'h000000ff;
                            12'h008: response_hold <= {30'd0, snapshot_active, 1'b0};
                            12'h00c: response_hold <= {
                                15'd0, request_bank, status_error_hold, 2'd0,
                                status_model_hold, 7'd0, status_busy_hold
                            };
                            default: begin
                                if (!metric_legal)
                                    error_hold <= 1;
                                else if (!addr_hold[2]) begin
                                    response_hold <= selected_value[31:0];
                                    atomic_high <= selected_value[63:32];
                                    atomic_metric <= metric_index;
                                    atomic_bank <= request_bank;
                                    atomic_valid <= 1;
                                end else if (!atomic_valid ||
                                    atomic_bank != request_bank || atomic_metric != metric_index)
                                    error_hold <= 1;
                                else begin
                                    response_hold <= atomic_high;
                                    atomic_valid <= 0;
                                end
                            end
                        endcase
                    end
                end
                RESPONSE: if (csr_rsp_ready)
                    state <= IDLE;
                default: begin
                    response_hold <= 0;
                    error_hold <= 1;
                    state <= RESPONSE;
                end
            endcase
        end
    end
endmodule
