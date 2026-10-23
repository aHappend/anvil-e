module anvil_e1_address #(
    parameter integer VOCAB_SIZE=262144, HIDDEN_SIZE=512,
    PER_LAYER_INPUT_SIZE=512, INTERMEDIATE_SIZE=2048, EMBEDDING_DIM=768,
    NUM_LAYERS=24, NUM_Q_HEADS=4, LOCAL_KV_HEADS=2, FULL_KV_HEADS=1,
    LOCAL_HEAD_DIM=256, FULL_HEAD_DIM=512
) (
    input wire [63:0] weights_base, scratch_base,
    input wire [31:0] job_tokens,
    input wire [4:0] tensor_id,
    input wire [31:0] layer_index,
    input wire [63:0] element_index,
    input wire [2:0] scratch_region,
    input wire [63:0] scratch_word,
    output reg [63:0] tensor_addr, scratch_addr,
    output reg [31:0] tensor_rows, tensor_cols,
    output wire [127:0] weights_bytes,
    output reg [127:0] scratch_bytes,
    output reg tensor_error, scratch_error
);
    localparam integer DM=LOCAL_HEAD_DIM>FULL_HEAD_DIM ? LOCAL_HEAD_DIM:FULL_HEAD_DIM;
    localparam integer KM=LOCAL_KV_HEADS>FULL_KV_HEADS ? LOCAL_KV_HEADS:FULL_KV_HEADS;
    reg [127:0] offset, count, tensor_address_value;
    reg [127:0] scratch_address_value, region_offset, region_count;
    reg [127:0] h_words, ple_words, q_words, kv_words;

    function automatic full_layer;
        input [31:0] layer;
        integer l, phase;
        begin
            full_layer=1'b0;
            phase=0;
            for (l=0; l<NUM_LAYERS; l=l+1) begin
                if (layer==l[31:0])
                    full_layer=(phase==5);
                if (phase==5) phase=0;
                else phase=phase+1;
            end
        end
    endfunction

    function automatic [127:0] rows;
        input integer id, layer;
        integer d, kv;
        begin
            d=full_layer(layer) ? FULL_HEAD_DIM:LOCAL_HEAD_DIM;
            kv=full_layer(layer) ? FULL_KV_HEADS:LOCAL_KV_HEADS;
            case (id)
                0: rows=VOCAB_SIZE;
                1: rows=EMBEDDING_DIM;
                2: rows=HIDDEN_SIZE;
                3: rows=128'(NUM_LAYERS)*PER_LAYER_INPUT_SIZE;
                4: rows=PER_LAYER_INPUT_SIZE;
                5,7,11,12,13,14,15,18: rows=HIDDEN_SIZE;
                6: rows=1;
                8,9: rows=INTERMEDIATE_SIZE;
                10: rows=PER_LAYER_INPUT_SIZE;
                16,19: rows=d;
                17,21: rows=128'(kv)*d;
                20: rows=128'(NUM_Q_HEADS)*d;
                default: rows=0;
            endcase
        end
    endfunction

    function automatic [127:0] cols;
        input integer id, layer;
        integer d;
        begin
            d=full_layer(layer) ? FULL_HEAD_DIM:LOCAL_HEAD_DIM;
            case (id)
                0,1,3,8,9,10,17,20,21: cols=HIDDEN_SIZE;
                7: cols=INTERMEDIATE_SIZE;
                11: cols=PER_LAYER_INPUT_SIZE;
                18: cols=128'(NUM_Q_HEADS)*d;
                default: cols=1;
            endcase
        end
    endfunction

    // Called only for elaboration-time constants; entry 17 is the layer extent.
    function automatic [2303:0] layer_prefixes;
        input integer layer;
        reg [127:0] prefix;
        integer suffix;
        begin
            layer_prefixes=0;
            prefix=0;
            for (suffix=5; suffix<22; suffix=suffix+1) begin
                layer_prefixes[(suffix-5)*128 +: 128]=prefix;
                prefix=prefix+rows(suffix,layer)*cols(suffix,layer)*128'd4;
            end
            layer_prefixes[17*128 +: 128]=prefix;
        end
    endfunction

    function automatic [2175:0] layer_counts;
        input integer layer;
        integer suffix;
        begin
            layer_counts=0;
            for (suffix=5; suffix<22; suffix=suffix+1)
                layer_counts[(suffix-5)*128 +: 128]=rows(suffix,layer)*cols(suffix,layer);
        end
    endfunction

    localparam [127:0] COUNT_0=rows(0,0)*cols(0,0);
    localparam [127:0] COUNT_1=rows(1,0)*cols(1,0);
    localparam [127:0] COUNT_2=rows(2,0)*cols(2,0);
    localparam [127:0] COUNT_3=rows(3,0)*cols(3,0);
    localparam [127:0] COUNT_4=rows(4,0)*cols(4,0);
    localparam [127:0] GLOBAL_0=0;
    localparam [127:0] GLOBAL_1=GLOBAL_0+COUNT_0*128'd4;
    localparam [127:0] GLOBAL_2=GLOBAL_1+COUNT_1*128'd4;
    localparam [127:0] GLOBAL_3=GLOBAL_2+COUNT_2*128'd4;
    localparam [127:0] GLOBAL_4=GLOBAL_3+COUNT_3*128'd4;
    localparam [127:0] GLOBAL_BYTES=GLOBAL_4+COUNT_4*128'd4;
    localparam [2303:0] LOCAL_PREFIXES=layer_prefixes(0);
    localparam [2303:0] FULL_PREFIXES=layer_prefixes(5);
    localparam [2175:0] LOCAL_COUNTS=layer_counts(0);
    localparam [2175:0] FULL_COUNTS=layer_counts(5);
    localparam [127:0] LOCAL_LAYER_BYTES=LOCAL_PREFIXES[17*128 +: 128];
    localparam [127:0] FULL_LAYER_BYTES=FULL_PREFIXES[17*128 +: 128];
    localparam [127:0] FULL_LAYER_COUNT=128'(NUM_LAYERS)/128'd6;
    localparam [127:0] TOTAL_WEIGHTS_BYTES=GLOBAL_BYTES+
        (128'(NUM_LAYERS)-FULL_LAYER_COUNT)*LOCAL_LAYER_BYTES+
        FULL_LAYER_COUNT*FULL_LAYER_BYTES;

    function automatic [127:0] layer_offset;
        input [31:0] layer;
        reg [127:0] acc;
        integer l, phase;
        begin
            layer_offset=128'd0;
            acc=GLOBAL_BYTES;
            phase=0;
            for (l=0; l<NUM_LAYERS; l=l+1) begin
                if (layer==l[31:0])
                    layer_offset=acc;
                acc=acc+((phase==5) ? FULL_LAYER_BYTES:LOCAL_LAYER_BYTES);
                if (phase==5) phase=0;
                else phase=phase+1;
            end
        end
    endfunction

    function automatic [127:0] suffix_prefix;
        input [4:0] id;
        input full_layer;
        begin
            case (id)
                5: suffix_prefix=full_layer ? FULL_PREFIXES[0*128 +: 128]:LOCAL_PREFIXES[0*128 +: 128];
                6: suffix_prefix=full_layer ? FULL_PREFIXES[1*128 +: 128]:LOCAL_PREFIXES[1*128 +: 128];
                7: suffix_prefix=full_layer ? FULL_PREFIXES[2*128 +: 128]:LOCAL_PREFIXES[2*128 +: 128];
                8: suffix_prefix=full_layer ? FULL_PREFIXES[3*128 +: 128]:LOCAL_PREFIXES[3*128 +: 128];
                9: suffix_prefix=full_layer ? FULL_PREFIXES[4*128 +: 128]:LOCAL_PREFIXES[4*128 +: 128];
                10: suffix_prefix=full_layer ? FULL_PREFIXES[5*128 +: 128]:LOCAL_PREFIXES[5*128 +: 128];
                11: suffix_prefix=full_layer ? FULL_PREFIXES[6*128 +: 128]:LOCAL_PREFIXES[6*128 +: 128];
                12: suffix_prefix=full_layer ? FULL_PREFIXES[7*128 +: 128]:LOCAL_PREFIXES[7*128 +: 128];
                13: suffix_prefix=full_layer ? FULL_PREFIXES[8*128 +: 128]:LOCAL_PREFIXES[8*128 +: 128];
                14: suffix_prefix=full_layer ? FULL_PREFIXES[9*128 +: 128]:LOCAL_PREFIXES[9*128 +: 128];
                15: suffix_prefix=full_layer ? FULL_PREFIXES[10*128 +: 128]:LOCAL_PREFIXES[10*128 +: 128];
                16: suffix_prefix=full_layer ? FULL_PREFIXES[11*128 +: 128]:LOCAL_PREFIXES[11*128 +: 128];
                17: suffix_prefix=full_layer ? FULL_PREFIXES[12*128 +: 128]:LOCAL_PREFIXES[12*128 +: 128];
                18: suffix_prefix=full_layer ? FULL_PREFIXES[13*128 +: 128]:LOCAL_PREFIXES[13*128 +: 128];
                19: suffix_prefix=full_layer ? FULL_PREFIXES[14*128 +: 128]:LOCAL_PREFIXES[14*128 +: 128];
                20: suffix_prefix=full_layer ? FULL_PREFIXES[15*128 +: 128]:LOCAL_PREFIXES[15*128 +: 128];
                21: suffix_prefix=full_layer ? FULL_PREFIXES[16*128 +: 128]:LOCAL_PREFIXES[16*128 +: 128];
                default: suffix_prefix=0;
            endcase
        end
    endfunction

    function automatic [127:0] tensor_count;
        input [4:0] id;
        input is_full;
        begin
            case (id)
                0: tensor_count=COUNT_0;
                1: tensor_count=COUNT_1;
                2: tensor_count=COUNT_2;
                3: tensor_count=COUNT_3;
                4: tensor_count=COUNT_4;
                5: tensor_count=is_full ? FULL_COUNTS[0*128 +: 128]:LOCAL_COUNTS[0*128 +: 128];
                6: tensor_count=is_full ? FULL_COUNTS[1*128 +: 128]:LOCAL_COUNTS[1*128 +: 128];
                7: tensor_count=is_full ? FULL_COUNTS[2*128 +: 128]:LOCAL_COUNTS[2*128 +: 128];
                8: tensor_count=is_full ? FULL_COUNTS[3*128 +: 128]:LOCAL_COUNTS[3*128 +: 128];
                9: tensor_count=is_full ? FULL_COUNTS[4*128 +: 128]:LOCAL_COUNTS[4*128 +: 128];
                10: tensor_count=is_full ? FULL_COUNTS[5*128 +: 128]:LOCAL_COUNTS[5*128 +: 128];
                11: tensor_count=is_full ? FULL_COUNTS[6*128 +: 128]:LOCAL_COUNTS[6*128 +: 128];
                12: tensor_count=is_full ? FULL_COUNTS[7*128 +: 128]:LOCAL_COUNTS[7*128 +: 128];
                13: tensor_count=is_full ? FULL_COUNTS[8*128 +: 128]:LOCAL_COUNTS[8*128 +: 128];
                14: tensor_count=is_full ? FULL_COUNTS[9*128 +: 128]:LOCAL_COUNTS[9*128 +: 128];
                15: tensor_count=is_full ? FULL_COUNTS[10*128 +: 128]:LOCAL_COUNTS[10*128 +: 128];
                16: tensor_count=is_full ? FULL_COUNTS[11*128 +: 128]:LOCAL_COUNTS[11*128 +: 128];
                17: tensor_count=is_full ? FULL_COUNTS[12*128 +: 128]:LOCAL_COUNTS[12*128 +: 128];
                18: tensor_count=is_full ? FULL_COUNTS[13*128 +: 128]:LOCAL_COUNTS[13*128 +: 128];
                19: tensor_count=is_full ? FULL_COUNTS[14*128 +: 128]:LOCAL_COUNTS[14*128 +: 128];
                20: tensor_count=is_full ? FULL_COUNTS[15*128 +: 128]:LOCAL_COUNTS[15*128 +: 128];
                21: tensor_count=is_full ? FULL_COUNTS[16*128 +: 128]:LOCAL_COUNTS[16*128 +: 128];
                default: tensor_count=0;
            endcase
        end
    endfunction

    assign weights_bytes=TOTAL_WEIGHTS_BYTES;

    always @* begin
        offset=0;
        case (tensor_id)
            0: offset=GLOBAL_0;
            1: offset=GLOBAL_1;
            2: offset=GLOBAL_2;
            3: offset=GLOBAL_3;
            4: offset=GLOBAL_4;
            default: begin
                if (tensor_id<=21 && layer_index<NUM_LAYERS)
                    offset=layer_offset(layer_index)+
                        suffix_prefix(tensor_id,full_layer(layer_index));
            end
        endcase
        tensor_rows=rows(tensor_id,layer_index);
        tensor_cols=cols(tensor_id,layer_index);
        count=tensor_count(tensor_id,full_layer(layer_index));
        tensor_address_value={64'd0,weights_base}+offset+{62'd0,element_index,2'b00};
        tensor_error=tensor_id>21 || (tensor_id>=5 && layer_index>=NUM_LAYERS) ||
                     {64'd0,element_index}>=count || |tensor_address_value[127:64];
        tensor_addr=tensor_address_value[63:0];
    end

    always @* begin
        h_words={96'd0,job_tokens}*HIDDEN_SIZE;
        ple_words={96'd0,job_tokens}*NUM_LAYERS*PER_LAYER_INPUT_SIZE;
        q_words={96'd0,job_tokens}*NUM_Q_HEADS*DM;
        kv_words={96'd0,job_tokens}*KM*DM;
        scratch_bytes=(h_words*2+ple_words+q_words+kv_words*2)*128'd4;
        region_offset=0;
        region_count=0;
        case (scratch_region)
            0: begin region_offset=0; region_count=h_words; end
            1: begin region_offset=h_words; region_count=ple_words; end
            2: begin region_offset=h_words+ple_words; region_count=q_words; end
            3: begin region_offset=h_words+ple_words+q_words; region_count=kv_words; end
            4: begin region_offset=h_words+ple_words+q_words+kv_words; region_count=kv_words; end
            5: begin region_offset=h_words+ple_words+q_words+kv_words*2; region_count=h_words; end
            default: begin region_offset=0; region_count=0; end
        endcase
        scratch_address_value={64'd0,scratch_base}+(region_offset+{64'd0,scratch_word})*128'd4;
        scratch_error=scratch_region>5 || {64'd0,scratch_word}>=region_count ||
                      |scratch_address_value[127:64];
        scratch_addr=scratch_address_value[63:0];
    end
endmodule
