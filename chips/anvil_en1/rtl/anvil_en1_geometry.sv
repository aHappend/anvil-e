`ifndef ANVIL_EN1_GEOMETRY_SV
`define ANVIL_EN1_GEOMETRY_SV
package anvil_en1_geometry;
    function automatic native_model(input [1:0] model);
        native_model = model == 1 || model == 2;
    endfunction

    function automatic [7:0] layer_count(input [1:0] model);
        case (model)
            1: layer_count = 35;
            2: layer_count = 42;
            default: layer_count = 0;
        endcase
    endfunction

    function automatic [7:0] owner_count(input [1:0] model);
        case (model)
            1: owner_count = 15;
            2: owner_count = 24;
            default: owner_count = 0;
        endcase
    endfunction

    function automatic global_layer(input [1:0] model, input [7:0] layer);
        begin
            global_layer = 0;
            case (model)
                1: case (layer)
                    4, 9, 14, 19, 24, 29, 34: global_layer = 1;
                    default: global_layer = 0;
                endcase
                2: case (layer)
                    5, 11, 17, 23, 29, 35, 41: global_layer = 1;
                    default: global_layer = 0;
                endcase
                default: global_layer = 0;
            endcase
        end
    endfunction

    function automatic [7:0] anchor_owner(
        input [1:0] model, input is_global
    );
        case (model)
            1: anchor_owner = is_global ? 8'd14 : 8'd13;
            2: anchor_owner = is_global ? 8'd23 : 8'd22;
            default: anchor_owner = 0;
        endcase
    endfunction

    function automatic [7:0] logical_owner(
        input [1:0] model, input [7:0] layer
    );
        begin
            if (!native_model(model) || layer >= layer_count(model))
                logical_owner = 0;
            else if (layer < owner_count(model))
                logical_owner = layer;
            else
                logical_owner = anchor_owner(model, global_layer(model, layer));
        end
    endfunction

    function automatic [11:0] hidden_size(input [1:0] model);
        case (model)
            1: hidden_size = 1536;
            2: hidden_size = 2560;
            default: hidden_size = 0;
        endcase
    endfunction

    function automatic [13:0] intermediate_size(
        input [1:0] model, input [7:0] layer
    );
        case (model)
            1: intermediate_size = layer >= 15 ? 14'd12288 : 14'd6144;
            2: intermediate_size = 10240;
            default: intermediate_size = 0;
        endcase
    endfunction
endpackage
`endif
