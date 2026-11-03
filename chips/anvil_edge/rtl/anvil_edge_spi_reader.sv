module anvil_edge_spi_reader #(
  parameter integer FLASH_ADDRESS_BYTES = 3,
  parameter [63:0] FLASH_CAPACITY_BYTES = 64'd16777216,
  parameter integer CLOCK_HALF_PERIOD = 2
) (
  input wire clk, rst_n,
  input wire req_valid,
  output wire req_ready,
  input wire [63:0] req_address, req_bytes,
  output wire data_valid,
  input wire data_ready,
  output wire [7:0] data,
  output wire data_last,
  output wire busy, done, error,
  output wire [7:0] error_code,
  input wire spi_miso,
  output wire spi_mosi, spi_sck, spi_cs_n
);
  generate
    if ((FLASH_ADDRESS_BYTES != 3 && FLASH_ADDRESS_BYTES != 4) ||
        CLOCK_HALF_PERIOD < 1 || FLASH_CAPACITY_BYTES == 0 ||
        (FLASH_ADDRESS_BYTES == 3 && FLASH_CAPACITY_BYTES > 64'd16777216) ||
        FLASH_CAPACITY_BYTES > 64'd4294967296) begin : invalid_parameters
      initial $fatal(1, "ANVIL_EDGE_SPI PARAMETER ERROR: address width, capacity or clock period");
      assign req_ready = 0;
      assign data_valid = 0;
      assign data = 0;
      assign data_last = 0;
      assign busy = 0;
      assign done = 0;
      assign error = 0;
      assign error_code = 0;
      assign spi_mosi = 0;
      assign spi_sck = 0;
      assign spi_cs_n = 1;
    end else begin : reader
      localparam [2:0] IDLE=0, COMMAND=1, RECEIVE=2, LAST_FALL=3,
                       BYTE_HOLD=4, FAILED=5;
      localparam integer COUNTER_W =
        CLOCK_HALF_PERIOD > 1 ? $clog2(CLOCK_HALF_PERIOD) : 1;
      reg [2:0] state;
      reg [COUNTER_W-1:0] counter;
      reg clock_level;
      reg [39:0] command_shift;
      reg [5:0] command_bits;
      reg [2:0] receive_bit;
      reg [7:0] receive_shift, byte_result;
      reg [63:0] bytes_left;
      reg done_r;
      wire [64:0] request_end = {1'b0, req_address}+{1'b0, req_bytes};
      assign req_ready = rst_n && state == IDLE;
      assign data_valid = rst_n && state == BYTE_HOLD;
      assign data = data_valid ? byte_result : 0;
      assign data_last = data_valid && bytes_left == 1;
      assign busy = rst_n && state != IDLE && state != FAILED;
      assign done = rst_n && done_r;
      assign error = rst_n && state == FAILED;
      assign error_code = error ? 8'h02 : 0;
      assign spi_sck = rst_n && clock_level;
      assign spi_cs_n = !rst_n || state == IDLE || state == FAILED;
      assign spi_mosi = rst_n && state == COMMAND && command_shift[39];

      always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          state <= IDLE;
          counter <= 0;
          clock_level <= 0;
          command_shift <= 0;
          command_bits <= 0;
          receive_bit <= 0;
          receive_shift <= 0;
          byte_result <= 0;
          bytes_left <= 0;
          done_r <= 0;
        end else begin
          done_r <= 0;
          case (state)
            IDLE: if (req_valid && req_ready) begin
              if (req_bytes == 0 || request_end[64] ||
                  request_end > {1'b0, FLASH_CAPACITY_BYTES} ||
                  (FLASH_ADDRESS_BYTES == 3 && req_address[63:24] != 0) ||
                  (FLASH_ADDRESS_BYTES == 4 && req_address[63:32] != 0)) begin
                state <= FAILED;
              end else begin
                if (FLASH_ADDRESS_BYTES == 4) begin
                  command_shift <= {8'h13, req_address[31:0]};
                  command_bits <= 40;
                end else begin
                  command_shift <= {8'h03, req_address[23:0], 8'd0};
                  command_bits <= 32;
                end
                bytes_left <= req_bytes;
                counter <= CLOCK_HALF_PERIOD-1;
                clock_level <= 0;
                state <= COMMAND;
              end
            end
            COMMAND: if (counter != 0) counter <= counter-1'b1;
              else begin
                counter <= CLOCK_HALF_PERIOD-1;
                clock_level <= !clock_level;
                if (clock_level) begin
                  command_shift <= command_shift << 1;
                  command_bits <= command_bits-1'b1;
                  if (command_bits == 1) begin
                    receive_bit <= 0;
                    receive_shift <= 0;
                    state <= RECEIVE;
                  end
                end
              end
            RECEIVE: if (counter != 0) counter <= counter-1'b1;
              else begin
                counter <= CLOCK_HALF_PERIOD-1;
                clock_level <= !clock_level;
                if (!clock_level) begin
                  receive_shift <= {receive_shift[6:0], spi_miso};
                  if (receive_bit == 7) begin
                    byte_result <= {receive_shift[6:0], spi_miso};
                    state <= LAST_FALL;
                  end else receive_bit <= receive_bit+1'b1;
                end
              end
            LAST_FALL: if (counter != 0) counter <= counter-1'b1;
              else begin
                clock_level <= 0;
                counter <= CLOCK_HALF_PERIOD-1;
                state <= BYTE_HOLD;
              end
            BYTE_HOLD: if (data_valid && data_ready) begin
              if (bytes_left == 1) begin
                done_r <= 1;
                state <= IDLE;
              end else begin
                bytes_left <= bytes_left-1;
                receive_bit <= 0;
                receive_shift <= 0;
                counter <= CLOCK_HALF_PERIOD-1;
                state <= RECEIVE;
              end
            end
            FAILED: state <= FAILED;
            default: begin
              clock_level <= 0;
              state <= FAILED;
            end
          endcase
        end
      end
    end
  endgenerate
endmodule
