module anvil_en1_allocation_ledger #(
    parameter integer REPORT_BREAKDOWN = 1
) (
    input wire clk, rst_n,
    input wire observation_valid,
    input wire [1:0] observation_model,
    input wire [1599:0] component_live_bytes,
    input wire [1599:0] component_shadow_bytes,
    input wire [255:0] metadata_bytes,
    input wire [255:0] shadow_metadata_bytes,
    input wire [63:0] integration_bytes,
    input wire [63:0] native_workspace_bytes, native_controller_bytes,
    input wire [63:0] native_workspace_shadow_bytes,
    input wire observation_check_valid, observation_fallback,
    output wire report_valid,
    output wire report_check_valid, report_fallback, report_overlap,
    output wire [1:0] report_model,
    output wire [63:0] payload_bytes, replay_bytes, equivalent_bytes,
    output wire [63:0] native_scratch_bytes,
    output wire [63:0] equivalent_shadow_bytes, native_scratch_shadow_bytes,
    output wire [63:0] text_workspace_bytes, text_workspace_shadow_bytes,
    output wire [63:0] fallback_working_bytes, fallback_working_shadow_bytes,
    output wire report_partition_error,
    output wire [63:0] controller_bytes
);
    wire [2047:0] payload_terms, replay_terms, equivalent_terms, scratch_terms;
    wire [2047:0] equivalent_shadow_terms, scratch_shadow_terms;
    wire [2047:0] workspace_terms, workspace_shadow_terms;
    genvar term;
    generate for (term=0; term<32; term=term+1) begin : terms
        if (term==5) begin
            assign workspace_terms[64*term+:64] = observation_fallback ?
                64'd0 : equivalent_terms[64*term+:64];
            assign workspace_shadow_terms[64*term+:64] = observation_fallback ?
                64'd0 : equivalent_shadow_terms[64*term+:64];
        end else if (term==0 || term==1 || term==18) begin
            assign workspace_terms[64*term+:64] = observation_fallback ?
                equivalent_terms[64*term+:64] : 64'd0;
            assign workspace_shadow_terms[64*term+:64] = observation_fallback ?
                equivalent_shadow_terms[64*term+:64] : 64'd0;
        end else begin
            assign workspace_terms[64*term+:64] = equivalent_terms[64*term+:64];
            assign workspace_shadow_terms[64*term+:64] =
                equivalent_shadow_terms[64*term+:64];
        end
        if (term==3 || term==9 || term==10 ||
            (term>=12 && term<=15) || term==19)
        begin
            assign scratch_terms[64*term+:64] = component_live_bytes[64*term+:64];
            assign scratch_shadow_terms[64*term+:64] = component_shadow_bytes[64*term+:64];
        end else if (term==25) begin
            assign scratch_terms[64*term+:64] = native_workspace_bytes;
            assign scratch_shadow_terms[64*term+:64] = native_workspace_shadow_bytes;
        end else if (term==26) begin
            assign scratch_terms[64*term+:64] = native_controller_bytes;
            assign scratch_shadow_terms[64*term+:64] = native_controller_bytes;
        end else begin
            assign scratch_terms[64*term+:64] = 64'd0;
            assign scratch_shadow_terms[64*term+:64] = 64'd0;
        end
        if (term<25) begin
            assign equivalent_terms[64*term+:64] = component_live_bytes[64*term+:64];
            assign equivalent_shadow_terms[64*term+:64] = component_shadow_bytes[64*term+:64];
            if (REPORT_BREAKDOWN && term<22 && term!=16 && term!=17)
                assign payload_terms[64*term+:64] = component_live_bytes[64*term+:64];
            else
                assign payload_terms[64*term+:64] = 64'd0;
            if (REPORT_BREAKDOWN && ((term>=5 && term<=16) || term==22))
                assign replay_terms[64*term+:64] = component_live_bytes[64*term+:64];
            else
                assign replay_terms[64*term+:64] = 64'd0;
        end else begin
            assign payload_terms[64*term+:64] = 64'd0;
            if (term<29) begin
                assign equivalent_terms[64*term+:64] = metadata_bytes[64*(term-25)+:64];
                assign equivalent_shadow_terms[64*term+:64] =
                    shadow_metadata_bytes[64*(term-25)+:64];
            end else if (term==29) begin
                assign equivalent_terms[64*term+:64] = integration_bytes;
                assign equivalent_shadow_terms[64*term+:64] = integration_bytes;
            end else begin
                assign equivalent_terms[64*term+:64] = 64'd0;
                assign equivalent_shadow_terms[64*term+:64] = 64'd0;
            end
            if (REPORT_BREAKDOWN && term==27)
                assign replay_terms[64*term+:64] = metadata_bytes[128+:64];
            else
                assign replay_terms[64*term+:64] = 64'd0;
        end
    end endgenerate

    localparam integer VALUE_BITS = 23;
    localparam integer NODE_BITS = VALUE_BITS + 1;
    wire [128*NODE_BITS-1:0] stage_values [0:4];
    wire [8*NODE_BITS-1:0] level4 = stage_values[4][0+:8*NODE_BITS];
    wire [8*NODE_BITS-1:0] totals;
    wire [511:0] expanded_totals;
    wire [7:0] level4_overflow;
    reg partition_error;
    reg [5:0] valid_pipeline;
    reg [5:0] check_pipeline, fallback_pipeline, overlap_pipeline;
    reg [4:0] partition_pipeline;
    reg [11:0] model_pipeline;
    wire [16383:0] input_terms =
        {workspace_shadow_terms, workspace_terms,
            scratch_shadow_terms, equivalent_shadow_terms,
            scratch_terms, equivalent_terms, replay_terms, payload_terms};
    initial begin
        if (REPORT_BREAKDOWN != 0 && REPORT_BREAKDOWN != 1)
            $fatal(1, "PARAMETER ERROR: REPORT_BREAKDOWN must be 0 or 1");
    end
    function automatic integer leaf_identity(input integer metric, term_index);
        begin
            leaf_identity = 0;
            if (metric == 0) begin
                if (REPORT_BREAKDOWN && term_index < 22 &&
                    term_index != 16 && term_index != 17)
                    leaf_identity = 1 + term_index;
            end else if (metric == 1) begin
                if (REPORT_BREAKDOWN && ((term_index >= 5 && term_index <= 16) ||
                    term_index == 22))
                    leaf_identity = 1 + term_index;
                else if (REPORT_BREAKDOWN && term_index == 27)
                    leaf_identity = 67;
            end else if (metric == 3 || metric == 5) begin
                if (term_index == 3 || term_index == 9 || term_index == 10 ||
                    (term_index >= 12 && term_index <= 15) || term_index == 19)
                    leaf_identity = (metric == 3 ? 1 : 33) + term_index;
                else if (term_index == 25)
                    leaf_identity = metric == 3 ? 74 : 75;
                else if (term_index == 26)
                    leaf_identity = 76;
            end else if (metric >= 6 &&
                (term_index == 0 || term_index == 1 ||
                    term_index == 5 || term_index == 18)) begin
                leaf_identity = 77 + (metric-6)*4 +
                    (term_index == 0 ? 0 : (term_index == 1 ? 1 :
                        (term_index == 5 ? 2 : 3)));
            end else begin
                if (term_index < 25)
                    leaf_identity = (metric == 2 || metric == 6 ? 1 : 33) + term_index;
                else if (term_index < 29)
                    leaf_identity = (metric == 2 || metric == 6 ? 65 : 69) +
                        term_index - 25;
                else if (term_index == 29)
                    leaf_identity = 73;
            end
        end
    endfunction
    function automatic integer node_present(
        input integer metric, first_term, term_count
    );
        integer offset;
        begin
            node_present = 0;
            for (offset=0; offset<term_count; offset=offset+1)
                if (leaf_identity(metric, first_term+offset) != 0)
                    node_present = 1;
        end
    endfunction
    function automatic integer node_source(
        input integer metric, first_term, term_count
    );
        integer previous, offset, identical;
        begin
            node_source = metric;
            for (previous=0; previous<metric; previous=previous+1) begin
                identical = 1;
                for (offset=0; offset<term_count; offset=offset+1)
                    if (leaf_identity(metric, first_term+offset) !=
                        leaf_identity(previous, first_term+offset))
                        identical = 0;
                if (identical && node_source == metric)
                    node_source = previous;
            end
        end
    endfunction
    function automatic integer registered_nodes;
        integer stage, metric, node, count, span;
        begin
            registered_nodes = 0;
            for (stage=0; stage<5; stage=stage+1) begin
                count = 16 >> stage;
                span = 2 << stage;
                for (metric=0; metric<8; metric=metric+1)
                    for (node=0; node<count; node=node+1)
                        if (node_present(metric, node*span, span) &&
                            node_source(metric, node*span, span) == metric)
                            registered_nodes = registered_nodes + 1;
            end
            registered_nodes = registered_nodes + (REPORT_BREAKDOWN ? 8 : 6);
        end
    endfunction
    function automatic [NODE_BITS-1:0] add_node(
        input [NODE_BITS-1:0] left, right
    );
        reg [VALUE_BITS:0] sum;
        begin
            sum = {1'b0, left[VALUE_BITS-1:0]} +
                {1'b0, right[VALUE_BITS-1:0]};
            add_node = {left[VALUE_BITS] || right[VALUE_BITS] ||
                sum[VALUE_BITS], sum[VALUE_BITS-1:0]};
        end
    endfunction

    genvar stage, metric, node;
    generate for (stage=0; stage<5; stage=stage+1) begin : stages
        localparam integer NODES = 16 >> stage;
        localparam integer SPAN = 2 << stage;
        if (stage > 0)
            assign stage_values[stage][8*NODES*NODE_BITS+:(128-8*NODES)*NODE_BITS] = 0;
        for (metric=0; metric<8; metric=metric+1) begin : metrics
            for (node=0; node<NODES; node=node+1) begin : nodes
                localparam integer SOURCE = node_source(metric, node*SPAN, SPAN);
                localparam integer INDEX = NODE_BITS*(metric*NODES+node);
                if (!node_present(metric, node*SPAN, SPAN)) begin : zero_node
                    assign stage_values[stage][INDEX+:NODE_BITS] = 0;
                end else if (SOURCE != metric) begin : shared_node
                    assign stage_values[stage][INDEX+:NODE_BITS] =
                        stage_values[stage][NODE_BITS*(SOURCE*NODES+node)+:NODE_BITS];
                end else begin : registered_node
                    wire [NODE_BITS-1:0] left_node, right_node;
                    wire [NODE_BITS-1:0] next_value = add_node(left_node, right_node);
                    reg [NODE_BITS-1:0] value;
                    if (stage == 0) begin : input_pair
                        wire [63:0] left = input_terms[64*(metric*32+2*node)+:64];
                        wire [63:0] right = input_terms[64*(metric*32+2*node+1)+:64];
                        assign left_node = {|left[63:VALUE_BITS], left[VALUE_BITS-1:0]};
                        assign right_node = {|right[63:VALUE_BITS], right[VALUE_BITS-1:0]};
                    end else begin : preceding_pair
                        assign left_node = stage_values[stage-1][
                            NODE_BITS*(metric*2*NODES+2*node)+:NODE_BITS];
                        assign right_node = stage_values[stage-1][
                            NODE_BITS*(metric*2*NODES+2*node+1)+:NODE_BITS];
                    end
                    assign stage_values[stage][INDEX+:NODE_BITS] = value;
                    always @(posedge clk or negedge rst_n) begin
                        if (!rst_n)
                            value <= 0;
                        else
                            value <= next_value;
                    end
                end
            end
        end
    end
    for (metric=0; metric<8; metric=metric+1) begin : reductions
        assign level4_overflow[metric] = level4[NODE_BITS*metric+VALUE_BITS];
        if (!REPORT_BREAKDOWN && metric < 2) begin : omitted_breakdown
            assign totals[NODE_BITS*metric+:NODE_BITS] = 0;
        end else begin : output_register
            reg [NODE_BITS-1:0] value;
            wire [NODE_BITS-1:0] next_value;
            if (metric == 6 || metric == 7) begin : workspace_partition
                localparam integer SCRATCH = metric == 6 ? 3 : 5;
                wire underflow = level4[metric*NODE_BITS+:VALUE_BITS] <
                    level4[SCRATCH*NODE_BITS+:VALUE_BITS];
                assign next_value = fallback_pipeline[4] ?
                    level4[metric*NODE_BITS+:NODE_BITS] :
                    {level4_overflow[metric] || level4_overflow[SCRATCH] || underflow,
                        level4[metric*NODE_BITS+:VALUE_BITS] -
                            level4[SCRATCH*NODE_BITS+:VALUE_BITS]};
            end else begin : total
                assign next_value = level4[metric*NODE_BITS+:NODE_BITS];
            end
            assign totals[NODE_BITS*metric+:NODE_BITS] = value;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    value <= 0;
                else
                    value <= next_value;
            end
        end
        assign expanded_totals[64*metric+:64] =
            totals[NODE_BITS*metric+VALUE_BITS] ? 64'hffffffffffffffff :
                {{(64-VALUE_BITS){1'b0}}, totals[NODE_BITS*metric+:VALUE_BITS]};
    end endgenerate
    wire overlap = observation_fallback &&
        |component_live_bytes[64*5+:64] &&
        (|component_live_bytes[0+:64] || |component_live_bytes[64+:64]);
    wire subset_error = native_workspace_bytes > component_live_bytes[64*5+:64] ||
        native_workspace_shadow_bytes > component_shadow_bytes[64*5+:64] ||
        native_controller_bytes > component_live_bytes[64*22+:64] ||
        native_controller_bytes > component_shadow_bytes[64*22+:64];
    localparam [31:0] CONTROLLER_BITS = registered_nodes()*NODE_BITS +
        $bits(partition_error) +
        $bits(valid_pipeline) + $bits(model_pipeline) + $bits(check_pipeline) +
        $bits(fallback_pipeline) + $bits(overlap_pipeline) + $bits(partition_pipeline);
    assign controller_bytes = rst_n ? 64'((CONTROLLER_BITS+7) >> 3) : 64'd0;
    assign report_valid = rst_n && valid_pipeline[5];
    assign report_check_valid = rst_n && valid_pipeline[5] && check_pipeline[5];
    assign report_fallback = rst_n && fallback_pipeline[5];
    assign report_overlap = rst_n && overlap_pipeline[5];
    assign report_model = rst_n ? model_pipeline[11:10] : 2'd0;
    assign report_partition_error = rst_n && partition_error;
    assign payload_bytes = rst_n ? expanded_totals[0+:64] : 64'd0;
    assign replay_bytes = rst_n ? expanded_totals[64+:64] : 64'd0;
    assign equivalent_bytes = rst_n ? expanded_totals[128+:64] : 64'd0;
    assign native_scratch_bytes = rst_n ? expanded_totals[192+:64] : 64'd0;
    assign equivalent_shadow_bytes = rst_n ? expanded_totals[256+:64] : 64'd0;
    assign native_scratch_shadow_bytes = rst_n ? expanded_totals[320+:64] : 64'd0;
    assign text_workspace_bytes = rst_n && !fallback_pipeline[5] ?
        expanded_totals[384+:64] : 64'd0;
    assign text_workspace_shadow_bytes = rst_n && !fallback_pipeline[5] ?
        expanded_totals[448+:64] : 64'd0;
    assign fallback_working_bytes = rst_n && fallback_pipeline[5] ?
        expanded_totals[384+:64] : 64'd0;
    assign fallback_working_shadow_bytes = rst_n && fallback_pipeline[5] ?
        expanded_totals[448+:64] : 64'd0;

    wire workspace_underflow = !fallback_pipeline[4] &&
        level4[6*NODE_BITS+:VALUE_BITS] < level4[3*NODE_BITS+:VALUE_BITS];
    wire shadow_workspace_underflow = !fallback_pipeline[4] &&
        level4[7*NODE_BITS+:VALUE_BITS] < level4[5*NODE_BITS+:VALUE_BITS];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            partition_error <= 0;
            valid_pipeline <= 0;
            check_pipeline <= 0;
            fallback_pipeline <= 0;
            overlap_pipeline <= 0;
            partition_pipeline <= 0;
            model_pipeline <= 0;
        end else begin
            valid_pipeline <= {valid_pipeline[4:0], observation_valid};
            check_pipeline <= {check_pipeline[4:0], observation_check_valid};
            fallback_pipeline <= {fallback_pipeline[4:0], observation_fallback};
            overlap_pipeline <= {overlap_pipeline[4:0], overlap};
            partition_pipeline <= {partition_pipeline[3:0], subset_error};
            model_pipeline <= {model_pipeline[9:0], observation_model};
            partition_error <= partition_pipeline[4] || |level4_overflow ||
                workspace_underflow || shadow_workspace_underflow;
        end
    end
endmodule
