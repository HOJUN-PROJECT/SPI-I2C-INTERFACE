`timescale 1ns / 1ps

module tb_I2C_MASTER ();

    localparam LENGTH = 4;
    // global ports
    logic                    clk;
    logic                    reset;
    // internal ports
    logic                    I2C_En;
    logic [             6:0] addr;
    logic [$clog2(LENGTH):0] length;
    logic                    CR_RW;
    logic [             7:0] m_tx_data;
    logic                    m_tx_done;
    logic                    m_tx_ready;
    logic [             7:0] m_rx_data;
    logic                    m_rx_done;
    logic [             7:0] s_tx_data;
    logic                    s_tx_done;
    logic                    s_tx_ready;
    logic [             7:0] s_rx_data;
    logic                    s_rx_done;
    logic                    I2C_start;
    logic                    I2C_stop;
    // external ports
    logic                    SCL;
    tri                      SDA;

    logic                    I2C_ACK;

    I2C_MASTER #(
        .D_LENGTH(LENGTH)
    ) dut_master (
        .clk      (clk),
        .reset    (reset),
        .I2C_En   (I2C_En),
        .addr     (addr),
        .CR_RW    (CR_RW),
        .tx_data  (m_tx_data),
        .tx_done  (m_tx_done),
        .tx_ready (m_tx_ready),
        .rx_done  (m_rx_done),
        .rx_data  (m_rx_data),
        .I2C_start(I2C_start),
        .I2C_stop (I2C_stop),
        .length   (length),
        .SCL      (SCL),
        .SDA      (SDA)
    );

    I2C_SLAVE dut_slave (
        .clk     (clk),
        .reset   (reset),
        .tx_data (s_tx_data),
        .tx_done (s_tx_done),
        .tx_ready(s_tx_ready),
        .rx_data (s_rx_data),
        .rx_done (s_rx_done),
        .scl     (SCL),
        .sda     (SDA)
    );

    initial clk = 0;

    always #5 clk = ~clk;

    task start_write_ADDR(input logic [6:0] Addr, input logic RW, input logic [$clog2(LENGTH):0] Length);
        @(posedge clk);
        I2C_En = 1;
        addr   = Addr;
        length = Length;
        CR_RW  = RW;  // WRITE or READ
        #20;
        I2C_En = 0;
        @(posedge clk);
        wait (m_tx_done);
    endtask

    task start_read_ADDR(input logic [6:0] Addr, input logic RW, input logic [$clog2(LENGTH):0] Length);
        @(posedge clk);
        I2C_En = 1;
        addr   = Addr;
        length = Length;
        CR_RW  = RW;  // WRITE or READ
        #20;
        I2C_En = 0;
        @(posedge clk);
        wait (s_rx_done);
    endtask

    task RESTART(input logic [6:0] Addr, input logic RW, input logic [$clog2(LENGTH):0] Length);
        @(posedge clk);
        I2C_start = 1;
        I2C_stop = 0;
        addr = Addr;
        length = Length;
        CR_RW = RW;  // WRITE or READ
        #20;
        I2C_start = 0;
        I2C_stop  = 0;
        wait (m_tx_done);
    endtask

    task STOP();
        @(posedge clk);
        I2C_start = 0;
        I2C_stop  = 1;
        wait (m_tx_ready);
        #100;
    endtask

    task Write_txdata(input logic [7:0] data_in);
        
        I2C_start = 1;
        I2C_stop = 0;
        m_tx_data = data_in;
        repeat (2) @(posedge clk);
        I2C_start = 0;
        wait (m_tx_done);
    endtask

    task Read_rx_data(input logic [7:0] data_in);
        s_tx_data = data_in;
        // read tb
        repeat (2) @(posedge clk);
        wait (s_tx_done);
    endtask

    initial begin
        reset = 1;
        #50;
        reset = 0;
        #50;
        // write tb
        // start_write_ADDR(7'b1111110, 0, LENGTH);
        // Write_txdata(8'h11);
        // Write_txdata(8'h22);
        // Write_txdata(8'h33);
        // Write_txdata(8'h44);

        // RESTART(7'b1111110, 0, LENGTH);
        // Write_txdata(8'h55);
        // Write_txdata(8'h66);
        // Write_txdata(8'h77);
        // Write_txdata(8'h88);
        // #1000;
        // STOP();
        // #1000;
        // $finish;

        // read tb
        start_read_ADDR(7'b1111110, 1, LENGTH);
        Read_rx_data(8'h11);
        Read_rx_data(8'h22);
        Read_rx_data(8'h33);
        Read_rx_data(8'h44);

        #1000;
        STOP();
        #1000;
        $finish;
    end
endmodule
