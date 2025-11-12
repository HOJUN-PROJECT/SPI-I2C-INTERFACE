`timescale 1ns / 1ps

module I2C_Master (
    input  logic       clk,
    input  logic       reset,
    input  logic       I2C_START,
    input  logic       I2C_STOP,
    input  logic       I2C_ACK,
    input  logic       I2C_EN,
    input  logic       read_write,
    input  logic [7:0] tx_data,
    output logic       tx_done,
    output logic       tx_ready,
    output logic [7:0] rx_data,
    output logic       rx_done,
    output logic       SCL,
    inout  logic       SDA
);

    typedef enum {
        IDLE,
        START,
        ADDR,
        ACK,
        HOLD,
        WRITE,
        READ,
        STOP
    } state_s;

    state_s state, state_next;
    logic [11:0] clk_cnt_reg, clk_cnt_next;
    logic [2:0] bit_cnt_reg, bit_cnt_next;
    logic [7:0] tx_data_reg, tx_data_next;
    logic [7:0] rx_data_reg, rx_data_next;
    logic SCL_reg, SCL_next;
    logic SDA_out, SDA_out_next;
    logic SDA_en, SDA_en_next;
    logic tx_done_reg, tx_done_next;
    logic rx_done_reg, rx_done_next;
    logic tx_ready_reg, tx_ready_next;

    assign SCL = SCL_reg;
    assign SDA = SDA_en ? SDA_out : 1'bz;
    assign tx_done = tx_done_reg;
    assign rx_done = rx_done_reg;
    assign tx_ready = tx_ready_reg;
    assign rx_data = rx_data_reg;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            clk_cnt_reg  <= 0;
            bit_cnt_reg  <= 0;
            SCL_reg      <= 1;
            SDA_out      <= 1;
            SDA_en       <= 1;
            tx_data_reg  <= 0;
            rx_data_reg  <= 0;
            state        <= IDLE;
            tx_done_reg  <= 0;
            rx_done_reg  <= 0;
            tx_ready_reg <= 1;
        end else begin
            clk_cnt_reg  <= clk_cnt_next;
            bit_cnt_reg  <= bit_cnt_next;
            SCL_reg      <= SCL_next;
            SDA_out      <= SDA_out_next;
            SDA_en       <= SDA_en_next;
            tx_data_reg  <= tx_data_next;
            rx_data_reg  <= rx_data_next;
            state        <= state_next;
            tx_done_reg  <= tx_done_next;
            rx_done_reg  <= rx_done_next;
            tx_ready_reg <= tx_ready_next;
        end
    end

    always_comb begin
        clk_cnt_next  = clk_cnt_reg;
        bit_cnt_next  = bit_cnt_reg;
        SCL_next      = SCL_reg;
        SDA_out_next  = SDA_out;
        SDA_en_next   = SDA_en;
        tx_data_next  = tx_data_reg;
        rx_data_next  = rx_data_reg;
        tx_done_next  = 0;
        rx_done_next  = 0;
        tx_ready_next = tx_ready_reg;
        state_next    = state;

        case (state)
            IDLE: begin
                SDA_en_next   = 1;
                SDA_out_next  = 1;
                SCL_next      = 1;
                tx_ready_next = 1;
                if (I2C_EN) begin
                    tx_data_next  = tx_data;
                    tx_ready_next = 0;
                    SDA_out_next  = 0;
                    SCL_next      = 1;
                    state_next    = START;
                end else begin
                    state_next = IDLE;
                end
            end

            START: begin
                if (clk_cnt_reg == 999) begin
                    clk_cnt_next = 0;
                    SDA_out_next = tx_data_reg[7];
                    SDA_en_next  = 1;
                    SCL_next     = 0;
                    state_next   = ADDR;
                end else begin
                    clk_cnt_next = clk_cnt_reg + 1;
                    state_next   = START;
                end
            end

            ADDR: begin
                SDA_en_next  = 1;
                SDA_out_next = tx_data_reg[7];
                if (clk_cnt_reg == 249) begin
                    clk_cnt_next = 0;
                    if (bit_cnt_reg == 7) begin
                        bit_cnt_next = 0;
                        SDA_en_next  = 0;
                        tx_done_next = 1;
                        state_next   = ACK;
                    end else begin
                        bit_cnt_next = bit_cnt_reg + 1;
                        state_next   = ADDR;
                    end
                end else clk_cnt_next = clk_cnt_reg + 1;
            end

            ACK: begin
                SDA_en_next = 0;
                if (clk_cnt_reg == 249) begin
                    SCL_next = 1;
                end
                if (clk_cnt_reg == 499) begin
                    clk_cnt_next = 0;
                    SCL_next     = 0;
                    state_next   = HOLD;
                end else clk_cnt_next = clk_cnt_reg + 1;
            end


            HOLD: begin
                case ({
                    I2C_START, I2C_STOP
                })
                    2'b00: state_next = WRITE;
                    2'b01: state_next = STOP;
                    2'b10: state_next = START;
                    2'b11:  state_next = READ;
                endcase
            end

            READ: begin
                SDA_en_next = 0;
                SCL_next = 0;
                if (clk_cnt_reg == 499) begin
                    clk_cnt_next = 0;
                    if (bit_cnt_reg == 7) begin
                        bit_cnt_next = 0;
                        SDA_en_next  = 1;
                        SDA_out_next = 0;
                        rx_done_next = 1;
                        state_next   = ACK;
                    end else begin
                        rx_data_next = {rx_data_reg[6:0], SDA};
                        bit_cnt_next = bit_cnt_reg + 1;
                        state_next   = READ;
                    end
                end else clk_cnt_next = clk_cnt_reg + 1;
            end

            WRITE: begin
                SDA_en_next  = 1;
                SDA_out_next = tx_data_reg[7];
                if (clk_cnt_reg == 999) begin
                    clk_cnt_next = 0;
                    if (bit_cnt_reg == 7) begin
                        bit_cnt_next = 0;
                        SDA_en_next  = 0;
                        tx_done_next = 1;
                        state_next   = ACK;
                    end else begin
                        bit_cnt_next = bit_cnt_reg + 1;
                        tx_data_next = {tx_data_reg[6:0], 1'b0};
                        state_next   = WRITE;
                    end
                end else clk_cnt_next = clk_cnt_reg + 1;
            end


            STOP: begin
                if (clk_cnt_reg == 499) begin
                    clk_cnt_next = 0;
                    SDA_en_next = 1;
                    SCL_next = 1;
                    SDA_out_next = 1;
                    tx_ready_next = 1;
                    state_next = IDLE;
                end else clk_cnt_next = clk_cnt_reg + 1;
            end

        endcase
    end
endmodule
