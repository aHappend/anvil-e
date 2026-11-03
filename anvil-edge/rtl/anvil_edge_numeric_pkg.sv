package anvil_edge_numeric_pkg;
  function automatic signed [31:0] sat32(input signed [127:0] x);
    begin
      if (x>128'sd2147483647) sat32=32'sh7fffffff;
      else if (x< -128'sd2147483648) sat32=32'sh80000000;
      else sat32=x[31:0];
    end
  endfunction

  function automatic signed [127:0] round_shift(
    input signed [127:0] x, input integer bits);
    reg [128:0] magnitude;
    begin
      magnitude=x<0 ? -$signed({x[127],x}) : {1'b0,x};
      if (bits>0) magnitude=(magnitude+(129'd1 << (bits-1))) >> bits;
      round_shift=x<0 ? -$signed(magnitude) : $signed(magnitude);
    end
  endfunction

  function automatic f16_invalid(input [15:0] h);
    begin f16_invalid=h[14:10]==5'd31; end
  endfunction

  function automatic [31:0] f16_scale(input [15:0] h);
    reg [31:0] magnitude;
    integer shift;
    begin
      magnitude=h[14:10]==0 ? {22'd0,h[9:0]} : {21'd0,1'b1,h[9:0]};
      shift=h[14:10]==0 ? -8 : $signed({27'd0,h[14:10]})-9;
      if (shift>=0) magnitude=magnitude << shift;
      else magnitude=(magnitude+(32'd1 << (-shift-1))) >> (-shift);
      f16_scale=magnitude;
    end
  endfunction

  function automatic signed [31:0] f16_q16(input [15:0] h);
    reg [31:0] magnitude;
    reg signed [32:0] signed_value;
    begin
      magnitude=f16_scale(h);
      signed_value=h[15] ? -$signed({1'b0,magnitude}) : $signed({1'b0,magnitude});
      f16_q16=sat32({{95{signed_value[32]}},signed_value});
    end
  endfunction
endpackage
