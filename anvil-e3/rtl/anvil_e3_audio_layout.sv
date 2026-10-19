module anvil_e3_audio_layout #(
    parameter integer AUDIO_LAYERS=12, AUDIO_HIDDEN=1024, AUDIO_FFN=4096,
    AUDIO_HEAD_DIM=128, AUDIO_OUT_DIM=1536, AUDIO_CONV_KERNEL=5,
    AUDIO_SUBSAMPLE_C0=128, AUDIO_SUBSAMPLE_C1=32, AUDIO_FREQ_BINS=128,
    TEXT_HIDDEN=512
) (
    input wire [63:0] weights_base,
    input wire [31:0] layer_index,
    input wire [5:0] tensor_group,
    output reg [63:0] tensor_addr,
    output wire [127:0] weights_bytes,
    output reg address_error
);
    localparam [127:0] H=AUDIO_HIDDEN, F=AUDIO_FFN, O=AUDIO_OUT_DIM;
    localparam [127:0] C0=AUDIO_SUBSAMPLE_C0, C1=AUDIO_SUBSAMPLE_C1;
    localparam [127:0] F2=(128'(AUDIO_FREQ_BINS)+3)/4;
    localparam [127:0] SUB_WORDS=10*C0+9*C1*C0+C1+H*C1*F2;
    localparam [127:0] LAYER_WORDS=4*F*H+8*H*H+9*H+
        H*AUDIO_CONV_KERNEL+AUDIO_HEAD_DIM+40;
    localparam [127:0] OUTPUT_WORD=SUB_WORDS+128'(AUDIO_LAYERS)*LAYER_WORDS;
    function automatic [127:0] group_words(input integer g);
        begin
            case (g)
                0: group_words=9*C0;
                1: group_words=C0;
                2: group_words=9*C1*C0;
                3: group_words=C1;
                4: group_words=H*C1*F2;
                5,6,9,10: group_words=H*F+4;
                7,8,11,12,13,17,18,19,20: group_words=H;
                14: group_words=H*AUDIO_CONV_KERNEL;
                15,21,23,24,26: group_words=H*H+4;
                16: group_words=2*H*H+4;
                22: group_words=AUDIO_HEAD_DIM;
                25: group_words=H*H;
                27: group_words=O*H;
                28: group_words=O;
                29: group_words=128'(TEXT_HIDDEN)*O;
                default: group_words=0;
            endcase
        end
    endfunction
    function automatic [3839:0] prefixes;
        reg [127:0] offset;
        integer g;
        begin
            prefixes=0; offset=0;
            for (g=0;g<30;g=g+1) begin
                if (g==5) offset=0;
                if (g==27) offset=0;
                prefixes[g*128 +: 128]=offset;
                offset=offset+group_words(g);
            end
        end
    endfunction
    localparam [3839:0] PREFIX=prefixes();
    reg [127:0] word_offset, address_value;
    assign weights_bytes=(OUTPUT_WORD+O*H+O+128'(TEXT_HIDDEN)*O)*4;
    always @* begin
        word_offset=0;
        address_error=1;
        if (tensor_group<30) begin
            word_offset=PREFIX[tensor_group*128 +: 128];
            if (tensor_group>=5 && tensor_group<=26)
                word_offset=word_offset+SUB_WORDS+128'(layer_index)*LAYER_WORDS;
            else if (tensor_group>=27) word_offset=word_offset+OUTPUT_WORD;
            address_error=(tensor_group>=5 && tensor_group<=26 &&
                           layer_index>=AUDIO_LAYERS);
        end
        address_value={64'd0,weights_base}+word_offset*4;
        tensor_addr=address_value[63:0];
        address_error=address_error || |address_value[127:64];
    end
endmodule
