`include "uvm_macros.svh"
import uvm_pkg::*;

interface SPI_intf (
    input logic clk,
    input logic reset
);
    logic sclk;
    logic mosi;
    logic miso;
    logic cs_n;
    logic cpol;
    logic cpha;
    logic start;
    logic [7:0] tx_data;
    logic [7:0] rx_data;
    logic tx_ready;
    logic done;
    logic miso_en;
    logic exp_rx_data;
endinterface



class a_seq_item extends uvm_sequence_item;
    rand bit [7:0] tx_data;
    rand bit [7:0] rx_data;
    rand bit       cpha;
    rand bit       cpol;
    bit      [7:0] temp_mosi;
    bit      [7:0] temp_miso;

    function new(string name = "ITEM");
        super.new(name);
    endfunction

    `uvm_object_utils_begin(a_seq_item)
        `uvm_field_int(cpol, UVM_DEFAULT)
        `uvm_field_int(cpha, UVM_DEFAULT)
        `uvm_field_int(tx_data, UVM_DEFAULT)
        `uvm_field_int(rx_data, UVM_DEFAULT)
        `uvm_field_int(temp_mosi, UVM_DEFAULT)
        `uvm_field_int(temp_miso, UVM_DEFAULT)
    `uvm_object_utils_end
endclass


class a_sequence extends uvm_sequence #(a_seq_item);
    `uvm_object_utils(a_sequence)
    a_seq_item a_item;

    function new(string name = "SEQ");
        super.new(name);
    endfunction

    task body();
        #10;
        a_item = a_seq_item::type_id::create("SEQ");
        for (int i = 0; i < 300; i++) begin
            start_item(a_item);
            if (!a_item.randomize()) `uvm_error("SEQ", "Randomize error")

            `uvm_info("SEQ", $sformatf(
                      "Data send to Driver tx:%0h rx:%0h cpha:%0d cpol:%0d",
                      a_item.tx_data,
                      a_item.rx_data,
                      a_item.cpha,
                      a_item.cpol
                      ), UVM_NONE)

            finish_item(a_item);
        end
    endtask
endclass


class a_driver extends uvm_driver #(a_seq_item);
    `uvm_component_utils(a_driver)
    a_seq_item a_item;
    virtual SPI_intf s_if;
    bit [7:0] miso_bits;
    function new(string name = "DRV", uvm_component c);
        super.new(name, c);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        a_item = a_seq_item::type_id::create("ITEM");
        if (!uvm_config_db#(virtual SPI_intf)::get(this, "", "s_if", s_if))
            `uvm_fatal("DRV", "Unable to access uvm_config_db")
    endfunction

    task drive_transfer(a_seq_item a_item);
        s_if.cpha    <= a_item.cpha;
        s_if.cpol    <= a_item.cpol;
        s_if.tx_data <= a_item.tx_data;
        s_if.rx_data <= a_item.rx_data;
        s_if.start   <= 1'b0;

        @(posedge s_if.clk);
        s_if.start <= 1'b1;
        repeat (10) @(negedge s_if.clk);
        s_if.start <= 1'b0;

        wait (s_if.done == 1'b1);
        @(posedge s_if.clk);
        @(posedge s_if.clk);
    endtask

    task drive_miso(a_seq_item a_item);
        miso_bits = a_item.rx_data;
        for (int i = 7; i >= 0; i--) begin
            if (!a_item.cpol && !a_item.cpha) begin
                @(negedge s_if.sclk);
            end else if (!a_item.cpol && a_item.cpha) begin
                @(posedge s_if.sclk);
            end else if (a_item.cpol && !a_item.cpha) begin
                @(posedge s_if.sclk);
            end else begin
                @(negedge s_if.sclk);
            end

            #1;
            s_if.miso <= miso_bits[i];
        end
    endtask

    task run_phase(uvm_phase phase);
        #10;
        forever begin
            seq_item_port.get_next_item(a_item);
            fork
                drive_transfer(a_item);
                drive_miso(a_item);
            join
            `uvm_info("DRV", $sformatf(
                      "DRV tx:%0h rx:%0h cpha:%0d cpol:%0d",
                      a_item.tx_data,
                      a_item.rx_data,
                      a_item.cpha,
                      a_item.cpol
                      ), UVM_NONE)
            @(posedge s_if.clk);
            seq_item_port.item_done();
        end
    endtask
endclass


class a_monitor extends uvm_monitor;
    `uvm_component_utils(a_monitor)
    uvm_analysis_port #(a_seq_item) send;

    bit [7:0] tx_bits;
    bit [7:0] rx_bits;

    a_seq_item a_item;
    a_seq_item cloned_item;
    virtual SPI_intf s_if;

    function new(string name = "MON", uvm_component c);
        super.new(name, c);
        send = new("Write", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        a_item = a_seq_item::type_id::create("ITEM");
        if (!uvm_config_db#(virtual SPI_intf)::get(this, "", "s_if", s_if))
            `uvm_fatal("MON", "Unable to access uvm_config_db")
    endfunction

    task sample_edge(bit cpol, bit cpha);
        if (!cpol && !cpha) @(posedge s_if.sclk);
        else if (!cpol && cpha) @(negedge s_if.sclk);
        else if (cpol && !cpha) @(negedge s_if.sclk);
        else @(posedge s_if.sclk);
    endtask

    task monitor_transfer(a_seq_item a_item);
        wait (s_if.start == 1'b1);
        a_item.cpol = s_if.cpol;
        a_item.cpha = s_if.cpha;

        for (int i = 7; i >= 0; i--) begin
            sample_edge(a_item.cpol, a_item.cpha);

            tx_bits[i] = s_if.mosi;
            rx_bits[i] = s_if.miso;

            `uvm_info("MON_BIT", $sformatf(
                      "[bit %0d] MOSI=%0b  MISO=%0b",
                      i,
                      s_if.mosi,
                      s_if.miso
                      ), UVM_NONE)
        end


        a_item.temp_mosi = tx_bits;
        a_item.temp_miso = rx_bits;
        a_item.tx_data   = s_if.tx_data;
        a_item.rx_data   = s_if.rx_data;

        `uvm_info(
            "MON",
            $sformatf(
                "MONITOR CAPTURE CPOL=%0d CPHA=%0d  temp_mosi=%0h  temp_miso=%0h  tx_data=%0h  rx_data=%0h",
                a_item.cpol, a_item.cpha, a_item.temp_mosi, a_item.temp_miso,
                a_item.tx_data, a_item.rx_data), UVM_NONE)

        wait (s_if.done == 1'b1);
    endtask


    task run_phase(uvm_phase phase);
        #21;
        forever begin
            @(posedge s_if.clk);
            monitor_transfer(a_item);
            cloned_item           = a_seq_item::type_id::create("cloned_item");
            cloned_item.tx_data   = a_item.tx_data;
            cloned_item.rx_data   = a_item.rx_data;
            cloned_item.temp_mosi = a_item.temp_mosi;
            cloned_item.temp_miso = a_item.temp_miso;
            cloned_item.cpol      = a_item.cpol;
            cloned_item.cpha      = a_item.cpha;
            send.write(cloned_item);
        end
    endtask


endclass


class a_agent extends uvm_agent;
    `uvm_component_utils(a_agent)

    a_monitor a_mon;
    a_driver a_drv;
    uvm_sequencer #(a_seq_item) a_sqr;
    virtual SPI_intf s_if;

    function new(string name = "AGENT", uvm_component c);
        super.new(name, c);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual SPI_intf)::get(this, "", "s_if", s_if))
            `uvm_fatal("AGENT", "Unable to get interface s_if")

        a_mon = a_monitor::type_id::create("MON", this);
        a_drv = a_driver::type_id::create("DRV", this);
        a_sqr = uvm_sequencer#(a_seq_item)::type_id::create("SQR", this);

        uvm_config_db#(virtual SPI_intf)::set(this, "DRV", "s_if", s_if);
        uvm_config_db#(virtual SPI_intf)::set(this, "MON", "s_if", s_if);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        a_drv.seq_item_port.connect(a_sqr.seq_item_export);
    endfunction
endclass


class a_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(a_scoreboard)

    uvm_analysis_imp #(a_seq_item, a_scoreboard) recv;

    int tx_pass_counter;
    int rx_pass_counter;
    int FAIL_counter;
    int total_counter;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        recv = new("recv", this);
    endfunction

    function void write(a_seq_item item);
        if (item.temp_mosi !== item.tx_data) begin
            `uvm_error("SCB", $sformatf("MOSI FAIL tx=%0b mosi=%0b",
                                        item.tx_data, item.temp_mosi))
            FAIL_counter++;
        end else begin
            tx_pass_counter++;
        end
        if (item.temp_miso !== item.rx_data) begin
            `uvm_error("SCB", $sformatf("MISO FAIL exp=%0b act=%0b",
                                        item.rx_data, item.temp_miso))
            FAIL_counter++;
        end else begin
            rx_pass_counter++;
        end
        total_counter++;
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCB_REPORT", $sformatf(
                  "\n====== SCOREBOARD SUMMARY ======\nTotal: %0d\nTX_PASS:  %0d\nRX_PASS:  %0d\nFAIL:  %0d\n================================",
                  total_counter,
                  tx_pass_counter,
                  rx_pass_counter,
                  FAIL_counter
                  ), UVM_NONE)
    endfunction

endclass



class a_environment extends uvm_env;
    `uvm_component_utils(a_environment)

    a_agent      a_agt;
    a_scoreboard a_scb;

    function new(string name = "ENV", uvm_component c);
        super.new(name, c);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        a_agt = a_agent::type_id::create("AGT", this);
        a_scb = a_scoreboard::type_id::create("SCB", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        a_agt.a_mon.send.connect(a_scb.recv);
    endfunction
endclass


class test extends uvm_test;
    `uvm_component_utils(test)

    a_sequence    a_seq;
    a_environment a_env;

    function new(string name = "test", uvm_component c);
        super.new(name, c);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        a_seq = a_sequence::type_id::create("SEQ", this);
        a_env = a_environment::type_id::create("ENV", this);
    endfunction

    function void start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);
        uvm_root::get().print_topology();
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        a_seq.start(a_env.a_agt.a_sqr);
        phase.drop_objection(this);
        #21;
    endtask
endclass


module tb_uvm_spi ();

    logic clk;
    logic reset;

    SPI_intf s_if (
        clk,
        reset
    );

    spi_master dut (
        .start   (s_if.start),
        .cpol    (s_if.cpol),
        .cpha    (s_if.cpha),
        .tx_data (s_if.tx_data),
        .rx_data (s_if.rx_data),
        .tx_ready(s_if.tx_ready),
        .done    (s_if.done),
        .sclk    (s_if.sclk),
        .mosi    (s_if.mosi),
        .miso    (s_if.miso),
        .clk     (s_if.clk),
        .reset   (s_if.reset)
    );

    always #5 clk = ~clk;

    initial begin
        clk   = 0;
        reset = 1;
        #10 reset = 0;
    end

    initial begin
        uvm_config_db#(virtual SPI_intf)::set(null, "*", "s_if", s_if);
        run_test("test");
        #10;
        $finish;
    end

endmodule
