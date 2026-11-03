module anvil_en1_allocation_ledger (
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
    output wire report_partition_error,
    output wire [63:0] controller_bytes
);
    wire [2047:0] payload_terms, replay_terms, equivalent_terms, scratch_terms;
    wire [2047:0] equivalent_shadow_terms, scratch_shadow_terms;
    wire [2047:0] workspace_terms, workspace_shadow_terms;
    genvar term;
    generate for (term=0; term<32; term=term+1) begin : terms
        if (term==0 || term==1 || term==18) begin
            assign workspace_terms[64*term+:64] = 64'd0;
            assign workspace_shadow_terms[64*term+:64] = 64'd0;
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
            if (term<22 && term!=16 && term!=17)
                assign payload_terms[64*term+:64] = component_live_bytes[64*term+:64];
            else
                assign payload_terms[64*term+:64] = 64'd0;
            if ((term>=5 && term<=16) || term==22)
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
            if (term==27)
                assign replay_terms[64*term+:64] = metadata_bytes[128+:64];
            else
                assign replay_terms[64*term+:64] = 64'd0;
        end
    end endgenerate

    localparam integer VALUE_BITS = 32;
    localparam integer NODE_BITS = VALUE_BITS + 1;
    reg [128*NODE_BITS-1:0] level0;
    reg [64*NODE_BITS-1:0] level1;
    reg [32*NODE_BITS-1:0] level2;
    reg [16*NODE_BITS-1:0] level3;
    reg [8*NODE_BITS-1:0] level4, totals;
    wire [128*NODE_BITS-1:0] next0;
    wire [64*NODE_BITS-1:0] next1;
    wire [32*NODE_BITS-1:0] next2;
    wire [16*NODE_BITS-1:0] next3;
    wire [8*NODE_BITS-1:0] next4;
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

    genvar metric, node;
    generate for (metric=0; metric<8; metric=metric+1) begin : reductions
        for (node=0; node<16; node=node+1) begin : first
            wire [63:0] left = input_terms[64*(metric*32+2*node)+:64];
            wire [63:0] right = input_terms[64*(metric*32+2*node+1)+:64];
            assign next0[NODE_BITS*(metric*16+node)+:NODE_BITS] =
                add_node({|left[63:VALUE_BITS], left[VALUE_BITS-1:0]},
                    {|right[63:VALUE_BITS], right[VALUE_BITS-1:0]});
        end
        for (node=0; node<8; node=node+1) begin : second
            assign next1[NODE_BITS*(metric*8+node)+:NODE_BITS] =
                add_node(level0[NODE_BITS*(metric*16+2*node)+:NODE_BITS],
                    level0[NODE_BITS*(metric*16+2*node+1)+:NODE_BITS]);
        end
        for (node=0; node<4; node=node+1) begin : third
            assign next2[NODE_BITS*(metric*4+node)+:NODE_BITS] =
                add_node(level1[NODE_BITS*(metric*8+2*node)+:NODE_BITS],
                    level1[NODE_BITS*(metric*8+2*node+1)+:NODE_BITS]);
        end
        for (node=0; node<2; node=node+1) begin : fourth
            assign next3[NODE_BITS*(metric*2+node)+:NODE_BITS] =
                add_node(level2[NODE_BITS*(metric*4+2*node)+:NODE_BITS],
                    level2[NODE_BITS*(metric*4+2*node+1)+:NODE_BITS]);
        end
        assign next4[NODE_BITS*metric+:NODE_BITS] =
            add_node(level3[NODE_BITS*(metric*2)+:NODE_BITS],
                level3[NODE_BITS*(metric*2+1)+:NODE_BITS]);
        assign level4_overflow[metric] = level4[NODE_BITS*metric+VALUE_BITS];
        assign expanded_totals[64*metric+:64] =
            totals[NODE_BITS*metric+VALUE_BITS] ? 64'hffffffffffffffff :
                {32'd0, totals[NODE_BITS*metric+:VALUE_BITS]};
    end endgenerate
    wire overlap = observation_fallback &&
        |component_live_bytes[64*5+:64] &&
        (|component_live_bytes[0+:64] || |component_live_bytes[64+:64]);
    wire subset_error = native_workspace_bytes > component_live_bytes[64*5+:64] ||
        native_workspace_shadow_bytes > component_shadow_bytes[64*5+:64] ||
        native_controller_bytes > component_live_bytes[64*22+:64] ||
        native_controller_bytes > component_shadow_bytes[64*22+:64];
    localparam integer CONTROLLER_BITS = $bits(level0) + $bits(level1) +
        $bits(level2) + $bits(level3) + $bits(level4) +
        $bits(totals) + $bits(partition_error) +
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
    assign text_workspace_bytes = rst_n ? expanded_totals[384+:64] : 64'd0;
    assign text_workspace_shadow_bytes = rst_n ? expanded_totals[448+:64] : 64'd0;

    wire workspace_underflow =
        level4[6*NODE_BITS+:VALUE_BITS] < level4[3*NODE_BITS+:VALUE_BITS];
    wire shadow_workspace_underflow =
        level4[7*NODE_BITS+:VALUE_BITS] < level4[5*NODE_BITS+:VALUE_BITS];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            level0 <= 0;
            level1 <= 0;
            level2 <= 0;
            level3 <= 0;
            level4 <= 0;
            totals <= 0;
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
            totals[0+:6*NODE_BITS] <= level4[0+:6*NODE_BITS];
            totals[6*NODE_BITS+:NODE_BITS] <=
                {level4_overflow[6] || level4_overflow[3] || workspace_underflow,
                    level4[6*NODE_BITS+:VALUE_BITS] -
                        level4[3*NODE_BITS+:VALUE_BITS]};
            totals[7*NODE_BITS+:NODE_BITS] <=
                {level4_overflow[7] || level4_overflow[5] || shadow_workspace_underflow,
                    level4[7*NODE_BITS+:VALUE_BITS] -
                        level4[5*NODE_BITS+:VALUE_BITS]};
            partition_error <= partition_pipeline[4] || |level4_overflow ||
                workspace_underflow || shadow_workspace_underflow;
            level0 <= next0;
            level1 <= next1;
            level2 <= next2;
            level3 <= next3;
            level4 <= next4;
        end
    end
endmodule
