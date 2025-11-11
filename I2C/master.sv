`timescale 1ns / 1ps

module I2C_Master (
    input  logic       clk,
    input  logic       reset,
    input  logic       I2C_START,
    input  logic       I2C_STOP,
    input  logic       I2C_ACK,
    input  logic       I2C_EN,
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
        START1,
        START2,
        DATA1,
        DATA2,
        DATA3,
        DATA4,
        READ_DATA1,
        READ_DATA2,
        READ_DATA3,
        READ_DATA4,
        ACK1,
        ACK2,
        ACK3,
        ACK4,
        HOLD,
        STOP1,
        STOP2
    } state_s;

    state_s state, state_next;
    logic [8:0] clk_cnt_reg, clk_cnt_next;
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
                    state_next    = START1;
                end
            end

            START1: begin
                if (clk_cnt_reg == 499) begin
                    clk_cnt_next = 0;
                    SCL_next     = 0;
                    state_next   = START2;
                end else clk_cnt_next = clk_cnt_reg + 1;
            end

            START2: begin
                if (clk_cnt_reg == 499) begin
                    clk_cnt_next = 0;
                    SDA_out_next = tx_data_reg[7];
                    SDA_en_next  = 1;
                    SCL_next     = 0;
                    state_next   = DATA1;
                end else clk_cnt_next = clk_cnt_reg + 1;
            end

            DATA1: begin
                SDA_en_next  = 1;
                SDA_out_next = tx_data_reg[7];
                if (clk_cnt_reg == 249) begin
                    clk_cnt_next = 0;
                    SCL_next = 1;
                    state_next = DATA2;
                end else clk_cnt_next = clk_cnt_reg + 1;
            end

            DATA2: begin
                SDA_en_next  = 1;
                SDA_out_next = tx_data_reg[7];
                if (clk_cnt_reg == 249) begin
                    clk_cnt_next = 0;
                    SCL_next = 1;
                    state_next = DATA3;
                end else clk_cnt_next = clk_cnt_reg + 1;
            end

            DATA3: begin
                SDA_en_next  = 1;
                SDA_out_next = tx_data_reg[7];
                if (clk_cnt_reg == 249) begin
                    clk_cnt_next = 0;
                    SCL_next = 0;
                    tx_data_next = {tx_data_reg[6:0], 1'b0};
                    state_next = DATA4;
                end else clk_cnt_next = clk_cnt_reg + 1;
            end

            DATA4: begin
                SDA_en_next  = 1;
                SDA_out_next = tx_data_reg[7];
                if (clk_cnt_reg == 249) begin
                    clk_cnt_next = 0;
                    if (bit_cnt_reg == 7) begin
                        bit_cnt_next = 0;
                        SDA_en_next  = 0;
                        tx_done_next = 1;
                        state_next   = ACK1;
                    end else begin
                        bit_cnt_next = bit_cnt_reg + 1;
                        state_next   = DATA1;
                    end
                end else clk_cnt_next = clk_cnt_reg + 1;
            end

            READ_DATA1: begin
                SDA_en_next = 0;
                SCL_next = 0;
                if (clk_cnt_reg == 249) begin
                    clk_cnt_next = 0;
                    state_next   = READ_DATA2;
                end else clk_cnt_next = clk_cnt_reg + 1;
            end

            READ_DATA2: begin
                SDA_en_next = 0;
                SCL_next = 0;
                if (clk_cnt_reg == 249) begin
                    clk_cnt_next = 0;
                    state_next   = READ_DATA3;
                end else clk_cnt_next = clk_cnt_reg + 1;
            end

            READ_DATA3: begin
                SDA_en_next = 0;
                SCL_next = 1;
                if (clk_cnt_reg == 249) begin
                    clk_cnt_next = 0;
                    rx_data_next = {rx_data_reg[6:0], SDA};
                    state_next   = READ_DATA4;
                end else clk_cnt_next = clk_cnt_reg + 1;
            end

            READ_DATA4: begin
                SDA_en_next = 0;
                SCL_next = 0;
                if (clk_cnt_reg == 249) begin
                    clk_cnt_next = 0;
                    if (bit_cnt_reg == 7) begin
                        bit_cnt_next = 0;
                        SDA_en_next  = 1;
                        SDA_out_next = 0;  // ACK
                        rx_done_next = 1;
                        state_next   = ACK1;
                    end else begin
                        bit_cnt_next = bit_cnt_reg + 1;
                        state_next   = READ_DATA1;
                    end
                end else clk_cnt_next = clk_cnt_reg + 1;
            end

            ACK1: begin
                SDA_en_next = 0;
                if (clk_cnt_reg == 249) begin
                    clk_cnt_next = 0;
                    SCL_next = 1;
                    state_next = ACK2;
                end else clk_cnt_next = clk_cnt_reg + 1;
            end

            ACK2: begin
                SDA_en_next = 0;
                if (clk_cnt_reg == 249) begin
                    clk_cnt_next = 0;
                    SCL_next = 1;
                    state_next = ACK3;
                end else clk_cnt_next = clk_cnt_reg + 1;
            end

            ACK3: begin
                SDA_en_next = 0;
                if (clk_cnt_reg == 249) begin
                    clk_cnt_next = 0;
                    SCL_next = 0;
                    state_next = HOLD;
                end else clk_cnt_next = clk_cnt_reg + 1;
            end

            HOLD: begin
                if ((I2C_START == 0) && (I2C_STOP == 0)) state_next = DATA1;
                else if ((I2C_START == 0) && (I2C_STOP == 1)) begin
                    SDA_en_next = 1;
                    SDA_out_next = 0;
                    SCL_next = 1;
                    state_next = STOP1;
                end else if ((I2C_START == 1) && (I2C_STOP == 0)) begin
                    state_next = START1;
                end else if ((I2C_START == 1) && (I2C_STOP == 1)) begin
                    SDA_en_next = 0;
                    state_next  = READ_DATA1;
                end
            end

            STOP1: begin
                SDA_en_next  = 1;
                SCL_next     = 1;
                SDA_out_next = 1;
                state_next   = STOP2;
            end

            STOP2: begin
                SDA_en_next   = 1;
                SCL_next      = 1;
                SDA_out_next  = 1;
                tx_ready_next = 1;
                state_next    = IDLE;
            end

            default: state_next = IDLE;
        endcase
    end
endmodule
