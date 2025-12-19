`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

interface SPI_intf (
    input logic clk,
    input logic reset
);
    logic sclk;
    logic mosi;
    logic miso;
    logic cs;
    logic [7:0] si_data;
    logic       si_done;
    logic [7:0] so_data;
    logic       so_start;
    logic       so_ready;
endinterface

class a_seq_item extends uvm_sequence_item;

    rand bit [7:0] si_data;
    rand bit [7:0] so_data;

    bit [7:0] temp_mosi;
    bit [7:0] temp_miso;

    function new(string name = "ITEM");
        super.new(name);
    endfunction

    `uvm_object_utils_begin(a_seq_item)
        `uvm_field_int(si_data   , UVM_DEFAULT)
        `uvm_field_int(so_data   , UVM_DEFAULT)
        `uvm_field_int(temp_mosi , UVM_DEFAULT)
        `uvm_field_int(temp_miso , UVM_DEFAULT)
    `uvm_object_utils_end
endclass


class a_sequence extends uvm_sequence #(a_seq_item);
    `uvm_object_utils(a_sequence)

    a_seq_item item;

    function new(string name = "SEQ");
        super.new(name);
    endfunction

    task body();
        item = a_seq_item::type_id::create("ITEM");
        for (int i = 0; i < 300; i++) begin
            start_item(item);
            if (!item.randomize())
                `uvm_error("SEQ", "Randomize failed")

            `uvm_info("SEQ", $sformatf("Send so_data=%0h si_data=%0h",
                        item.so_data, item.si_data), UVM_NONE)
            finish_item(item);
        end
    endtask
endclass


class a_driver extends uvm_driver #(a_seq_item);
    `uvm_component_utils(a_driver)

    virtual SPI_intf s_if;
    a_seq_item item;

    function new(string name = "DRV", uvm_component c);
        super.new(name, c);
    endfunction

    function void build_phase(uvm_phase phase);
        if(!uvm_config_db#(virtual SPI_intf)::get(this,"","s_if",s_if))
            `uvm_fatal("DRV","NO IF")
    endfunction

    task gen_sclk();
        @(negedge s_if.reset);
        repeat(2) @(posedge s_if.clk);
        forever begin
            #50 s_if.sclk = 1;
            #50 s_if.sclk = 0;
        end
    endtask

    task send_mosi(bit m);
        @(negedge s_if.sclk);
        s_if.mosi <= m;
    endtask

    task master_transfer(a_seq_item it);
        s_if.cs <= 1;
        repeat(2) @(posedge s_if.clk);
        s_if.cs <= 0;

        @(posedge s_if.clk);
        s_if.so_data <= it.so_data;
        s_if.so_start <= 1;
        @(posedge s_if.clk);

        s_if.so_start <= 0;

        for (int i = 7; i >= 0; i--) begin
            send_mosi(it.si_data[i]);
        end
        wait(s_if.si_done);
        @(negedge s_if.sclk);
        s_if.cs <= 1;
        repeat(2) @(posedge s_if.clk);
    endtask

    task run_phase(uvm_phase phase);
        fork
            gen_sclk();
        join_none

        s_if.mosi     <= 0;
        s_if.cs       <= 1;
        s_if.so_start <= 0;
        s_if.so_ready <= 0;

        `uvm_info("DRV","START_DRV",UVM_LOW)

        forever begin
            seq_item_port.get_next_item(item);
            master_transfer(item);
            seq_item_port.item_done();
        end
    endtask
endclass


class a_monitor extends uvm_monitor;
    `uvm_component_utils(a_monitor)

    virtual SPI_intf s_if;
    uvm_analysis_port #(a_seq_item) send;

    a_seq_item item;

    function new(string name = "MON", uvm_component c);
        super.new(name, c);
        send = new("SEND", this);
    endfunction

    function void build_phase(uvm_phase phase);
        if(!uvm_config_db#(virtual SPI_intf)::get(this,"","s_if",s_if))
            `uvm_fatal("MON","NO IF")
        item = a_seq_item::type_id::create("ITEM");
    endfunction

    task monitor_transfer(output bit [7:0] tx_bits,
                          output bit [7:0] rx_bits);

        @(negedge s_if.cs);
        @(negedge s_if.sclk);

        for (int i = 7; i >= 0; i--) begin
            tx_bits[i] = s_if.mosi;
            rx_bits[i] = s_if.miso;
            `uvm_info("MON_BIT", $sformatf(
                      "[bit %0d] MOSI=%0b  MISO=%0b",
                      i,
                      s_if.mosi,
                      s_if.miso
                      ), UVM_NONE)
            @(posedge s_if.sclk);

        end
    endtask

    task run_phase(uvm_phase phase);
        forever begin
            a_seq_item item_local;
            item_local = a_seq_item::type_id::create("ITEM_LOCAL", this);

            monitor_transfer(item_local.temp_mosi,
                             item_local.temp_miso);

            item_local.si_data = s_if.si_data;
            item_local.so_data = s_if.so_data;

            send.write(item_local);

            `uvm_info("MON","MONITOR EVENT",UVM_LOW)
        end
    endtask
endclass


class a_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(a_scoreboard)

    uvm_analysis_imp #(a_seq_item, a_scoreboard) recv;

    int tx_pass, rx_pass, tx_fail, rx_fail, total;

    function new(string name, uvm_component c);
        super.new(name, c);
        recv = new("RECV", this);
    endfunction

    function void write(a_seq_item it);

        if (it.temp_mosi !== it.si_data) begin
            `uvm_error("SCB",
                $sformatf("MOSI FAIL SI_DATA = %0b MOSI_DATA = %0b",
                it.si_data, it.temp_mosi))
            tx_fail++;
        end else begin
            `uvm_info("SCB",
                $sformatf("MOSI PASS SI_DATA = %0b MOSI_DATA = %0b",
                it.si_data, it.temp_mosi), UVM_LOW)
            tx_pass++;
        end

        if (it.temp_miso !== it.so_data) begin
            `uvm_error("SCB",
                $sformatf("MISO FAIL SO_DATA=%0b MISO_DATA=%0b",
                it.so_data, it.temp_miso))
            rx_fail++;
        end else begin
            `uvm_info("SCB",
                $sformatf("MISO PASS SO_DATA = %0b MISO_DATA = %0b",
                it.so_data, it.temp_miso), UVM_LOW)
            rx_pass++;
        end

        total++;
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCB_REPORT",
            $sformatf(
            "\n=== SCB REPORT ===\nTOTAL=%0d\nTX_PASS=%0d\nRX_PASS=%0d\nTX_FAIL=%0d\nRX_FAIL=%0d\n",
            total, tx_pass, rx_pass, tx_fail, rx_fail),
        UVM_NONE)
    endfunction
endclass


class a_agent extends uvm_agent;
    `uvm_component_utils(a_agent)

    virtual SPI_intf s_if;
    a_driver drv;
    a_monitor mon;
    uvm_sequencer #(a_seq_item) sqr;

    function new(string name="AGT", uvm_component c);
        super.new(name,c);
    endfunction

    function void build_phase(uvm_phase phase);
        uvm_config_db#(virtual SPI_intf)::get(this,"","s_if",s_if);

        drv = a_driver::type_id::create("DRV",this);
        mon = a_monitor::type_id::create("MON",this);
        sqr = uvm_sequencer#(a_seq_item)::type_id::create("SQR",this);

        uvm_config_db#(virtual SPI_intf)::set(this,"DRV","s_if",s_if);
        uvm_config_db#(virtual SPI_intf)::set(this,"MON","s_if",s_if);
    endfunction

    function void connect_phase(uvm_phase phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass


class a_environment extends uvm_env;
    `uvm_component_utils(a_environment)

    a_agent agt;
    a_scoreboard scb;

    function new(string name="ENV", uvm_component c);
        super.new(name,c);
    endfunction

    function void build_phase(uvm_phase phase);
        agt = a_agent::type_id::create("AGT",this);
        scb = a_scoreboard::type_id::create("SCB",this);
    endfunction

    function void connect_phase(uvm_phase phase);
        agt.mon.send.connect(scb.recv);
    endfunction
endclass


class test extends uvm_test;
    `uvm_component_utils(test)

    a_sequence    seq;
    a_environment env;

    function new(string name="test", uvm_component c);
        super.new(name,c);
    endfunction

    function void build_phase(uvm_phase phase);
        seq = a_sequence::type_id::create("SEQ", this);
        env = a_environment::type_id::create("ENV", this);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        seq.start(env.agt.sqr);
        phase.drop_objection(this);
    endtask
endclass


module tb_uvm_spi;
    logic clk, reset;

    SPI_intf s_if(clk, reset);

    spi_slave dut (
        .clk     (s_if.clk),
        .reset   (s_if.reset),
        .sclk    (s_if.sclk),
        .mosi    (s_if.mosi),
        .miso    (s_if.miso),
        .cs      (s_if.cs),
        .si_data (s_if.si_data),
        .si_done (s_if.si_done),
        .so_data (s_if.so_data),
        .so_start(s_if.so_start),
        .so_ready(s_if.so_ready)
    );

    always #5 clk = ~clk;

    initial begin
        $fsdbDumpvars(0);
        $fsdbDumpfile("wave.fsdb");
        clk = 0;
        reset = 1;
        #20 reset = 0;
    end

    initial begin
        uvm_config_db#(virtual SPI_intf)::set(null,"*","s_if",s_if);
        run_test("test");
    end
endmodule
