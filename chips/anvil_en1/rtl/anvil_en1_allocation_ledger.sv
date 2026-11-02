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
    output wire [63:0] controller_bytes
);
    wire [2047:0] payload_terms, replay_terms, equivalent_terms, scratch_terms;
    wire [2047:0] equivalent_shadow_terms, scratch_shadow_terms;
    genvar term;
    generate for (term=0; term<32; term=term+1) begin : terms
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

    reg [6143:0] level0;
    reg [3071:0] level1;
    reg [1535:0] level2;
    reg [767:0] level3;
    reg [383:0] level4;
    reg [4:0] valid_pipeline;
    reg [4:0] check_pipeline, fallback_pipeline, overlap_pipeline;
    reg [9:0] model_pipeline;
    wire [12287:0] input_terms =
        {scratch_shadow_terms, equivalent_shadow_terms,
            scratch_terms, equivalent_terms, replay_terms, payload_terms};
    wire overlap = observation_fallback &&
        |component_live_bytes[64*5+:64] &&
        (|component_live_bytes[0+:64] || |component_live_bytes[64+:64]);
    localparam integer CONTROLLER_BITS = $bits(level0) + $bits(level1) +
        $bits(level2) + $bits(level3) + $bits(level4) +
        $bits(valid_pipeline) + $bits(model_pipeline) + $bits(check_pipeline) +
        $bits(fallback_pipeline) + $bits(overlap_pipeline);
    assign controller_bytes = rst_n ? 64'((CONTROLLER_BITS+7) >> 3) : 64'd0;
    assign report_valid = rst_n && valid_pipeline[4];
    assign report_check_valid = rst_n && valid_pipeline[4] && check_pipeline[4];
    assign report_fallback = rst_n && fallback_pipeline[4];
    assign report_overlap = rst_n && overlap_pipeline[4];
    assign report_model = rst_n ? model_pipeline[9:8] : 2'd0;
    assign payload_bytes = rst_n ? level4[0+:64] : 64'd0;
    assign replay_bytes = rst_n ? level4[64+:64] : 64'd0;
    assign equivalent_bytes = rst_n ? level4[128+:64] : 64'd0;
    assign native_scratch_bytes = rst_n ? level4[192+:64] : 64'd0;
    assign equivalent_shadow_bytes = rst_n ? level4[256+:64] : 64'd0;
    assign native_scratch_shadow_bytes = rst_n ? level4[320+:64] : 64'd0;

    integer metric, node;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            level0 <= 0;
            level1 <= 0;
            level2 <= 0;
            level3 <= 0;
            level4 <= 0;
            valid_pipeline <= 0;
            check_pipeline <= 0;
            fallback_pipeline <= 0;
            overlap_pipeline <= 0;
            model_pipeline <= 0;
        end else begin
            valid_pipeline <= {valid_pipeline[3:0], observation_valid};
            check_pipeline <= {check_pipeline[3:0], observation_check_valid};
            fallback_pipeline <= {fallback_pipeline[3:0], observation_fallback};
            overlap_pipeline <= {overlap_pipeline[3:0], overlap};
            model_pipeline <= {model_pipeline[7:0], observation_model};
            for (metric=0; metric<6; metric=metric+1) begin
                for (node=0; node<16; node=node+1)
                    level0[64*(metric*16+node)+:64] <=
                        input_terms[64*(metric*32+2*node)+:64] +
                        input_terms[64*(metric*32+2*node+1)+:64];
                for (node=0; node<8; node=node+1)
                    level1[64*(metric*8+node)+:64] <=
                        level0[64*(metric*16+2*node)+:64] +
                        level0[64*(metric*16+2*node+1)+:64];
                for (node=0; node<4; node=node+1)
                    level2[64*(metric*4+node)+:64] <=
                        level1[64*(metric*8+2*node)+:64] +
                        level1[64*(metric*8+2*node+1)+:64];
                for (node=0; node<2; node=node+1)
                    level3[64*(metric*2+node)+:64] <=
                        level2[64*(metric*4+2*node)+:64] +
                        level2[64*(metric*4+2*node+1)+:64];
                level4[64*metric+:64] <=
                    level3[64*(metric*2)+:64] + level3[64*(metric*2+1)+:64];
            end
        end
    end
endmodule
