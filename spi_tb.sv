// =============================================================================
// Project: 12-bit SPI Master-Slave Controller Testbench
// File:    spi_tb.sv
// Description: Complete OOP-based layered SystemVerilog verification environment
// =============================================================================

// -----------------------------------------------------------------------------
// 1. Interface
// -----------------------------------------------------------------------------
interface spi_if;
  logic        clk;
  logic        rst;
  logic        newd;
  logic [11:0] din;
  logic        sclk;
  logic        cs;
  logic        mosi;
  logic [11:0] dout;
  logic        done;
endinterface


// -----------------------------------------------------------------------------
// 2. Transaction Class
// -----------------------------------------------------------------------------
class transaction;
  bit              newd;
  rand bit [11:0]  din;
  bit      [11:0]  dout;

  function transaction copy();
    copy      = new();
    copy.newd = this.newd;
    copy.din  = this.din;
    copy.dout = this.dout;
  endfunction

  function void display(string tag);
    $display("[%s] : newd = %0b, din = 0x%03h (%0d), dout = 0x%03h (%0d)", 
             tag, newd, din, din, dout, dout);
  endfunction
endclass


// -----------------------------------------------------------------------------
// 3. Generator Class
// -----------------------------------------------------------------------------
class generator;
  transaction            tr;
  mailbox #(transaction) mbx;
  event                  done;
  int                    count = 0;
  event                  drvnext;
  event                  sconext;

  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    tr       = new();
  endfunction

  task run();
    repeat (count) begin
      assert (tr.randomize()) else $error("[GEN] : Randomization Failed");
      mbx.put(tr.copy());
      $display("[GEN] : Generated din : %0d (0x%03h)", tr.din, tr.din);
      @(sconext);
    end
    -> done;
  endtask
endclass


// -----------------------------------------------------------------------------
// 4. Driver Class
// -----------------------------------------------------------------------------
class driver;
  virtual spi_if         vif;
  transaction            tr;
  mailbox #(transaction) mbx;
  mailbox #(bit [11:0])  mbxds;
  event                  drvnext;

  function new(mailbox #(bit [11:0]) mbxds, mailbox #(transaction) mbx);
    this.mbx   = mbx;
    this.mbxds = mbxds;
  endfunction

  task reset();
    vif.rst  <= 1'b1;
    vif.newd <= 1'b0;
    vif.din  <= 12'h000;
    repeat (10) @(posedge vif.clk);
    vif.rst  <= 1'b0;
    repeat (5) @(posedge vif.clk);

    $display("[DRV] : RESET COMPLETED");
    $display("-----------------------------------------");
  endtask

  task run();
    forever begin
      mbx.get(tr);
      vif.newd <= 1'b1;
      vif.din  <= tr.din;
      mbxds.put(tr.din);

      @(posedge vif.sclk);
      vif.newd <= 1'b0;

      @(posedge vif.done);
      $display("[DRV] : DATA SENT TO DAC : %0d", tr.din);
      @(posedge vif.sclk);
    end
  endtask
endclass


// -----------------------------------------------------------------------------
// 5. Monitor Class
// -----------------------------------------------------------------------------
class monitor;
  transaction           tr;
  mailbox #(bit [11:0]) mbx;
  virtual spi_if        vif;

  function new(mailbox #(bit [11:0]) mbx);
    this.mbx = mbx;
  endfunction

  task run();
    tr = new();
    forever begin
      @(posedge vif.sclk);
      @(posedge vif.done);
      tr.dout = vif.dout;
      @(posedge vif.sclk);
      $display("[MON] : DATA RECEIVED   : %0d", tr.dout);
      mbx.put(tr.dout);
    end
  endtask
endclass


// -----------------------------------------------------------------------------
// 6. Scoreboard Class
// -----------------------------------------------------------------------------
class scoreboard;
  mailbox #(bit [11:0]) mbxds, mbxms;
  bit [11:0]            ds;
  bit [11:0]            ms;
  event                 sconext;

  function new(mailbox #(bit [11:0]) mbxds, mailbox #(bit [11:0]) mbxms);
    this.mbxds = mbxds;
    this.mbxms = mbxms;
  endfunction

  task run();
    forever begin
      mbxds.get(ds);
      mbxms.get(ms);
      $display("[SCO] : DRV (Expected): %0d | MON (Actual): %0d", ds, ms);

      if (ds == ms)
        $display("[SCO] : --> DATA MATCHED");
      else
        $display("[SCO] : --> DATA MISMATCHED");

      $display("-----------------------------------------");
      -> sconext;
    end
  endtask
endclass


// -----------------------------------------------------------------------------
// 7. Environment Class
// -----------------------------------------------------------------------------
class environment;
  generator              gen;
  driver                 drv;
  monitor                mon;
  scoreboard             sco;

  event                  nextgd;
  event                  nextgs;

  mailbox #(transaction) mbxgd;
  mailbox #(bit [11:0])  mbxds;
  mailbox #(bit [11:0])  mbxms;

  virtual spi_if         vif;

  function new(virtual spi_if vif);
    mbxgd = new();
    mbxms = new();
    mbxds = new();

    gen = new(mbxgd);
    drv = new(mbxds, mbxgd);
    mon = new(mbxms);
    sco = new(mbxds, mbxms);

    this.vif = vif;
    drv.vif  = this.vif;
    mon.vif  = this.vif;

    gen.sconext = nextgs;
    sco.sconext = nextgs;

    gen.drvnext = nextgd;
    drv.drvnext = nextgd;
  endfunction

  task pre_test();
    drv.reset();
  endtask

  task test();
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_any
  endtask

  task post_test();
    wait (gen.done.triggered);
    #100;
    $display("[TESTBENCH] : All %0d transactions completed successfully.", gen.count);
    $finish();
  endtask

  task run();
    pre_test();
    test();
    post_test();
  endtask
endclass


// -----------------------------------------------------------------------------
// 8. Testbench Top Module
// -----------------------------------------------------------------------------
module tb;
  // Instantiate Interface
  spi_if vif();

  // Instantiate DUT
  top dut (
    .clk  (vif.clk),
    .rst  (vif.rst),
    .newd (vif.newd),
    .din  (vif.din),
    .dout (vif.dout),
    .done (vif.done)
  );

  // Clock Generation (50 MHz clock -> 20ns period)
  initial begin
    vif.clk <= 0;
  end
  always #10 vif.clk <= ~vif.clk;

  // Environment Instance
  environment env;
  assign vif.sclk = dut.m1.sclk;

  initial begin
    env = new(vif);
    env.gen.count = 10; // Number of test transactions
    env.run();
  end

  // Waveform Dump
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb);
  end
endmodule
