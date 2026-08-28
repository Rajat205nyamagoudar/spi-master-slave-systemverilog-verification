// =============================================================================
// Project: 12-bit SPI Master-Slave Controller
// File:    spi_design.sv
// Description: Contains SPI Master, SPI Slave, and Top-level wrapper module
// =============================================================================

// -----------------------------------------------------------------------------
// 1. SPI Master Module
// -----------------------------------------------------------------------------
module spi_master (
    input  wire        clk,
    input  wire        rst,
    input  wire        newd,
    input  wire [11:0] din,
    output reg         sclk,
    output reg         cs,
    output reg         mosi
);

  typedef enum bit [1:0] {
    idle   = 2'b00,
    enable = 2'b01,
    send   = 2'b10,
    comp   = 2'b11
  } state_type;

  state_type state = idle;

  reg [11:0] temp;
  int countc = 0;
  int count  = 0;

  // Clock Divider for SPI Clock Generation (sclk)
  always @(posedge clk) begin
    if (rst == 1'b1) begin
      countc <= 0;
      sclk   <= 1'b0;
    end else begin
      if (countc < 10) begin
        countc <= countc + 1;
      end else begin
        countc <= 0;
        sclk   <= ~sclk;
      end
    end
  end

  // SPI Master FSM
  always @(posedge sclk) begin
    if (rst == 1'b1) begin
      cs    <= 1'b1;
      mosi  <= 1'b0;
      count <= 0;
      state <= idle;
    end else begin
      case (state)
        idle: begin
          if (newd == 1'b1) begin
            state <= send;
            temp  <= din;
            cs    <= 1'b0;
            count <= 0;
          end else begin
            state <= idle;
            temp  <= 12'h000;
          end
        end

        send: begin
          if (count <= 11) begin
            mosi  <= temp[11 - count];
            count <= count + 1;
            state <= send;
          end else begin
            count <= 0;
            mosi  <= 1'b0;
            state <= comp;
          end
        end

        comp: begin
          cs    <= 1'b1;
          state <= idle;
        end

        default: state <= idle;
      endcase
    end
  end

endmodule


// -----------------------------------------------------------------------------
// 2. SPI Slave Module (DAC / Receiver Model)
// -----------------------------------------------------------------------------
module spi_slave (
    input  wire        sclk,
    input  wire        cs,
    input  wire        mosi,
    output wire [11:0] dout,
    output reg         done
);

  typedef enum bit {
    detect_start = 1'b0,
    read_data    = 1'b1
  } state_type;

  state_type state = detect_start;
  reg [11:0] temp = 12'h000;
  int count = 0;

  always @(posedge sclk) begin
    case (state)
      detect_start: begin
        done <= 1'b0;
        if (cs == 1'b0)
          state <= read_data;
        else
          state <= detect_start;
      end

      read_data: begin
        if (count <= 11) begin
          count <= count + 1;
          temp  <= {temp[10:0], mosi};
        end else begin
          count <= 0;
          done  <= 1'b1;
          state <= detect_start;
        end
      end

      default: state <= detect_start;
    endcase
  end

  assign dout = temp;

endmodule


// -----------------------------------------------------------------------------
// 3. Top-Level DUT Module
// -----------------------------------------------------------------------------
module top (
    input  wire        clk,
    input  wire        rst,
    input  wire        newd,
    input  wire [11:0] din,
    output wire [11:0] dout,
    output wire        done
);

  wire sclk;
  wire cs;
  wire mosi;

  // Instantiate SPI Master
  spi_master m1 (
    .clk  (clk),
    .rst  (rst),
    .newd (newd),
    .din  (din),
    .sclk (sclk),
    .cs   (cs),
    .mosi (mosi)
  );

  // Instantiate SPI Slave
  spi_slave s1 (
    .sclk (sclk),
    .cs   (cs),
    .mosi (mosi),
    .dout (dout),
    .done (done)
  );

endmodule
