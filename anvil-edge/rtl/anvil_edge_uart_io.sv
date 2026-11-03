module anvil_edge_uart_io #(
  parameter integer RX_FIFO_DEPTH = 16,
  parameter integer TX_FIFO_DEPTH = 16,
  parameter integer FRAME_LOCK = 0
) (
  input wire clk, rst_n,
  input wire uart_rx,
  output wire uart_tx,
  input wire [31:0] divisor,
  input wire axis_bypass,
  input wire [31:0] uart_frame_bytes,
  input wire s_axis_tvalid,
  output wire s_axis_tready,
  input wire [7:0] s_axis_tdata,
  input wire s_axis_tlast,
  output wire m_axis_tvalid,
  input wire m_axis_tready,
  output wire [7:0] m_axis_tdata,
  output wire m_axis_tlast,
  output wire rx_valid,
  input wire rx_ready,
  output wire [7:0] rx_data,
  output wire rx_last,
  input wire tx_valid,
  output wire tx_ready,
  input wire [7:0] tx_data,
  input wire tx_last,
  output wire framing_error, overflow_error,
  output wire rx_idle, tx_idle, rx_line_idle,
  input wire receive_enable,
  input tri0 response_complete
);
  localparam [1:0] RX_IDLE=0, RX_START=1, RX_DATA=2, RX_STOP=3;
  reg rx_meta, rx_sync, rx_previous;
  reg [1:0] rx_state;
  reg [31:0] active_divisor, active_frame_bytes;
  reg active_bypass;
  reg [31:0] rx_counter, frame_count;
  reg [2:0] rx_bit;
  reg [7:0] rx_shift, received_byte;
  reg received_valid;
  reg pending_valid;
  reg [7:0] pending_byte;
  reg framing_fault, overflow_fault, serial_fault, empty_frame_fault;
  reg tx_active;
  reg frame_closed;
  reg [9:0] tx_shift;
  reg [3:0] tx_bit;
  reg [31:0] tx_counter;
  wire rx_fifo_ready, rx_fifo_valid, rx_fifo_out_valid;
  wire [8:0] rx_fifo_in_data, rx_fifo_out_data;
  wire rx_fifo_empty, tx_fifo_empty;
  wire tx_fifo_valid, tx_fifo_pop;
  wire [8:0] tx_fifo_data;
  wire healthy = !framing_fault && !overflow_fault && !serial_fault && !empty_frame_fault;
  wire receive_open=FRAME_LOCK==0 || (receive_enable && !frame_closed);
  wire serial_emit = received_valid &&
                     (active_frame_bytes != 0 || pending_valid);
  wire serial_last = active_frame_bytes != 0 ?
                     frame_count == active_frame_bytes-1 :
                     received_byte == 8'h0a;
  wire [7:0] serial_data = active_frame_bytes != 0 ?
                         received_byte : pending_byte;
  wire paths_idle = rx_state == RX_IDLE && !tx_active &&
                    rx_fifo_empty && tx_fifo_empty && !pending_valid &&
                    frame_count == 0 && !received_valid &&
                    rx_sync && rx_previous && !tx_valid &&
                    !(active_bypass && s_axis_tvalid &&
                      (FRAME_LOCK==0 || receive_enable));

  assign framing_error = rst_n && (framing_fault || serial_fault || empty_frame_fault);
  assign overflow_error = rst_n && overflow_fault;
  assign rx_idle = rst_n && rx_state == RX_IDLE && rx_fifo_empty &&
                   !pending_valid && !received_valid && frame_count == 0 &&
                   rx_sync && rx_previous;
  assign rx_line_idle = rst_n && rx_state == RX_IDLE && !received_valid &&
                        rx_sync && rx_previous;
  assign tx_idle = rst_n && !tx_active && tx_fifo_empty;
  assign uart_tx = !rst_n || !tx_active ? 1'b1 : tx_shift[0];
  assign rx_fifo_valid = rst_n && healthy && receive_open &&
                         (active_bypass ? s_axis_tvalid : serial_emit);
  assign rx_fifo_in_data = active_bypass ?
                           {s_axis_tlast, s_axis_tdata} :
                           {serial_last, serial_data};
  assign s_axis_tready = rst_n && healthy && receive_open && active_bypass && rx_fifo_ready;
  assign rx_valid = rst_n && healthy && rx_fifo_out_valid;
  assign rx_data = rx_valid ? rx_fifo_out_data[7:0] : 0;
  assign rx_last = rx_valid && rx_fifo_out_data[8];
  assign m_axis_tvalid = rst_n && active_bypass && tx_fifo_valid;
  assign m_axis_tdata = m_axis_tvalid ? tx_fifo_data[7:0] : 0;
  assign m_axis_tlast = m_axis_tvalid && tx_fifo_data[8];
  assign tx_fifo_pop = rst_n && (active_bypass ? m_axis_tready : !tx_active);

  anvil_edge_fifo #(.WIDTH(9), .DEPTH(RX_FIFO_DEPTH)) rx_fifo (
    .clk(clk), .rst_n(rst_n),
    .in_valid(rx_fifo_valid), .in_ready(rx_fifo_ready), .in_data(rx_fifo_in_data),
    .out_valid(rx_fifo_out_valid), .out_ready(rx_ready && healthy),
    .out_data(rx_fifo_out_data), .empty(rx_fifo_empty), .full()
  );
  anvil_edge_fifo #(.WIDTH(9), .DEPTH(TX_FIFO_DEPTH)) tx_fifo (
    .clk(clk), .rst_n(rst_n),
    .in_valid(tx_valid), .in_ready(tx_ready), .in_data({tx_last, tx_data}),
    .out_valid(tx_fifo_valid), .out_ready(tx_fifo_pop), .out_data(tx_fifo_data),
    .empty(tx_fifo_empty), .full()
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) frame_closed<=0;
    else if (response_complete) frame_closed<=0;
    else if (FRAME_LOCK!=0 && rx_fifo_valid && rx_fifo_ready && rx_fifo_in_data[8])
      frame_closed<=1;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_meta <= 1;
      rx_sync <= 1;
      rx_previous <= 1;
    end else begin
      rx_meta <= uart_rx;
      rx_sync <= rx_meta;
      rx_previous <= rx_sync;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_divisor <= 868;
      active_frame_bytes <= 0;
      active_bypass <= 0;
      serial_fault <= 0;
    end else if (paths_idle) begin
      if (divisor < 4) serial_fault <= 1;
      else begin
        active_divisor <= divisor;
        active_frame_bytes <= uart_frame_bytes;
        active_bypass <= axis_bypass;
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_state <= RX_IDLE;
      rx_counter <= 0;
      rx_bit <= 0;
      rx_shift <= 0;
      received_byte <= 0;
      received_valid <= 0;
      framing_fault <= 0;
    end else begin
      received_valid <= 0;
      if (!active_bypass) case (rx_state)
        RX_IDLE: if (rx_previous && !rx_sync) begin
          rx_counter <= (active_divisor >> 1)-1;
          rx_state <= RX_START;
        end
        RX_START: if (rx_counter != 0) rx_counter <= rx_counter-1;
          else if (rx_sync) begin
            framing_fault <= 1;
            rx_state <= RX_IDLE;
          end else begin
            rx_counter <= active_divisor-1;
            rx_bit <= 0;
            rx_state <= RX_DATA;
          end
        RX_DATA: if (rx_counter != 0) rx_counter <= rx_counter-1;
          else begin
            rx_shift[rx_bit] <= rx_sync;
            rx_counter <= active_divisor-1;
            if (rx_bit == 7) rx_state <= RX_STOP;
            else rx_bit <= rx_bit+1'b1;
          end
        RX_STOP: if (rx_counter != 0) rx_counter <= rx_counter-1;
          else begin
            if (!rx_sync) framing_fault <= 1;
            else begin
              received_byte <= rx_shift;
              received_valid <= 1;
            end
            rx_state <= RX_IDLE;
          end
        default: begin
          framing_fault <= 1;
          rx_state <= RX_IDLE;
        end
      endcase
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pending_valid <= 0;
      pending_byte <= 0;
      frame_count <= 0;
      overflow_fault <= 0;
      empty_frame_fault <= 0;
    end else if (!active_bypass && received_valid && healthy) begin
      if (!receive_open || (serial_emit && !rx_fifo_ready)) overflow_fault <= 1;
      if (!receive_open) begin
        pending_valid<=0;
        frame_count<=0;
      end else if (active_frame_bytes != 0) begin
        if (frame_count == active_frame_bytes-1) frame_count <= 0;
        else frame_count <= frame_count+1;
      end else if (received_byte == 8'h0a) begin
        pending_valid <= 0;
        if (!pending_valid) empty_frame_fault <= 1;
      end else begin
        pending_byte <= received_byte;
        pending_valid <= 1;
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_active <= 0;
      tx_shift <= 0;
      tx_bit <= 0;
      tx_counter <= 0;
    end else if (!tx_active) begin
      if (!active_bypass && tx_fifo_valid && tx_fifo_pop) begin
        tx_shift <= {1'b1, tx_fifo_data[7:0], 1'b0};
        tx_bit <= 0;
        tx_counter <= active_divisor-1;
        tx_active <= 1;
      end
    end else if (tx_counter != 0) tx_counter <= tx_counter-1;
    else if (tx_bit == 9) begin
      tx_active <= 0;
      tx_counter <= 0;
    end else begin
      tx_shift <= {1'b1, tx_shift[9:1]};
      tx_bit <= tx_bit+1'b1;
      tx_counter <= active_divisor-1;
    end
  end
endmodule
