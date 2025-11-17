`timescale 1ns / 1ps

module I2C_MASTER #(
    parameter D_LENGTH = 2
) (
    // global ports
    input  logic                      clk,
    input  logic                      reset,
    // internal ports
    input  logic                      I2C_En,
    input  logic [               6:0] addr,
    input  logic                      CR_RW,
    input  logic [               7:0] tx_data,
    output logic                      tx_done,
    output logic                      tx_ready,
    output logic [               7:0] rx_data,
    output logic                      rx_done,
    input  logic                      I2C_start,
    input  logic                      I2C_stop,
    input  logic [$clog2(D_LENGTH):0] length,
    // external ports
    output logic                      SCL,
    inout  logic                      SDA
);

    logic [7:0] tx_data_reg, tx_data_next;
    logic [7:0] rx_data_reg, rx_data_next;
    logic tx_done_next, tx_done_reg;
    logic rx_done_next, rx_done_reg;

    logic [$clog2(D_LENGTH):0] length_next, length_reg;

    logic SDA_EN;
    logic O_SDA;
    logic SCL_REG, SCL_NEXT;
    logic addr_sig_reg, addr_sig_next;
    logic ACK_LOW_REG, ACK_LOW_NEXT;

    logic [$clog2(500)-1:0] clk_counter_reg, clk_counter_next;
    logic [$clog2(4)-1:0] data_cnt_reg, data_cnt_next;
    logic [$clog2(7)-1:0] bit_counter_reg, bit_counter_next;

    assign tx_done = tx_done_reg;
    assign rx_done = rx_done_reg;
    assign rx_data = rx_data_reg;

    assign SCL = SCL_REG;


    typedef enum logic [3:0] {
        ST_IDLE,
        ST_START1,
        ST_START2,
        ST_WRITE,
        ST_READ,  // slave -> master (read DATA)
        ST_ACK,
        ST_WRITE_ACK,
        ST_READ_ACK,  // master -> slave (ACK/NACK)
        ST_HOLD,
        ST_HOLD2,
        ST_STOP1,
        ST_STOP2
    } i2c_state_t;

    i2c_state_t state, next_state;

    assign SDA = (SDA_EN) ? O_SDA : 1'bz;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            state           <= ST_IDLE;
            tx_data_reg     <= 8'h00;
            rx_data_reg     <= 8'h00;
            clk_counter_reg <= 0;
            bit_counter_reg <= 0;
            data_cnt_reg    <= 0;
            tx_done_reg     <= 0;
            rx_done_reg     <= 0;
            SCL_REG         <= 1;
            addr_sig_reg    <= 1;
            ACK_LOW_REG     <= 0;
            length_reg      <= 0;
        end else begin
            state           <= next_state;
            tx_data_reg     <= tx_data_next;
            rx_data_reg     <= rx_data_next;
            clk_counter_reg <= clk_counter_next;
            bit_counter_reg <= bit_counter_next;
            data_cnt_reg    <= data_cnt_next;
            tx_done_reg     <= tx_done_next;
            rx_done_reg     <= rx_done_next;
            SCL_REG         <= SCL_NEXT;
            addr_sig_reg    <= addr_sig_next;
            ACK_LOW_REG     <= ACK_LOW_NEXT;
            length_reg      <= length_next;
        end

    end

    always_comb begin
        next_state       = state;
        O_SDA            = 1'b1;
        SCL_NEXT         = SCL_REG;
        tx_data_next     = tx_data_reg;
        rx_data_next     = rx_data_reg;
        clk_counter_next = clk_counter_reg;
        bit_counter_next = bit_counter_reg;
        data_cnt_next    = data_cnt_reg;
        tx_done_next     = 1'b0;
        SDA_EN           = 1'b1;
        tx_ready         = 1'b0;
        rx_done_next     = 1'b0;
        addr_sig_next    = addr_sig_reg;
        ACK_LOW_NEXT     = ACK_LOW_REG;
        length_next      = length_reg;
        case (state)
            ST_IDLE: begin
                O_SDA    = 1'b1;
                SCL_NEXT = 1'b1;
                tx_ready = 1'b1;
                if (I2C_En) begin
                    next_state    = ST_START1;
                    addr_sig_next = 1'b1;
                    length_next   = length;
                    tx_data_next  = {addr, CR_RW};
                end
            end
            ST_HOLD2: begin
                next_state   = ST_WRITE;
                tx_data_next = tx_data;
            end
            ST_HOLD: begin
                if (!I2C_start && I2C_stop) begin
                    SCL_NEXT   = 1;
                    next_state = ST_STOP1;
                end
                if (I2C_start && !I2C_stop) begin
                    SCL_NEXT      = 1;
                    addr_sig_next = 1'b1;
                    length_next   = length;
                    tx_data_next  = {addr, CR_RW};
                    next_state    = ST_START1;
                end
            end
            ST_START1: begin
                O_SDA = 0;
                if (clk_counter_reg == 499) begin
                    clk_counter_next = 0;
                    SCL_NEXT = 0;
                    next_state = ST_START2;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            ST_START2: begin
                O_SDA = 0;
                if (clk_counter_reg == 499) begin
                    clk_counter_next = 0;
                    SCL_NEXT         = 0;
                    next_state       = ST_WRITE;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            ST_WRITE: begin
                O_SDA = tx_data_reg[7];
                if ((bit_counter_reg == 7) && (data_cnt_reg == 3)) begin
                    SDA_EN = 1'b0;
                end
                if (clk_counter_reg == 249) begin
                    SCL_NEXT = (data_cnt_reg == 0 || data_cnt_reg == 2) ? ~SCL_NEXT : SCL_NEXT;
                    clk_counter_next = 0;
                    if (data_cnt_reg == 3) begin
                        data_cnt_next = 0;
                        tx_data_next  = {tx_data_reg[6:0], 1'b0};
                        if (bit_counter_reg == 7) begin
                            bit_counter_next = 0;
                            SCL_NEXT = 0;
                            next_state = (addr_sig_reg) ? ST_ACK : ST_WRITE_ACK;
                        end else begin
                            bit_counter_next = bit_counter_reg + 1;
                        end
                    end else begin
                        data_cnt_next = data_cnt_reg + 1;
                    end
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            ST_READ: begin
                if ((bit_counter_reg == 7) && (data_cnt_reg == 3)) begin
                    SDA_EN = 1'b1;
                end else begin
                    SDA_EN = 1'b0;
                end
                if (clk_counter_reg == 249) begin
                    SCL_NEXT = (data_cnt_reg == 0 || data_cnt_reg == 2) ? ~SCL_NEXT : SCL_NEXT;
                    clk_counter_next = 0;
                    if (data_cnt_reg == 1) begin
                        rx_data_next = {rx_data_reg[6:0], SDA};
                    end
                    if (data_cnt_reg == 3) begin
                        data_cnt_next = 0;
                        if (bit_counter_reg == 7) begin
                            bit_counter_next = 0;
                            SCL_NEXT         = 0;
                            next_state       = ST_READ_ACK;
                        end else begin
                            bit_counter_next = bit_counter_reg + 1;
                        end
                    end else begin
                        data_cnt_next = data_cnt_reg + 1;
                    end
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            ST_ACK: begin
                SDA_EN = 1'b0;
                if (clk_counter_reg == 249) begin
                    SCL_NEXT = (data_cnt_reg == 0 || data_cnt_reg == 2) ? ~SCL_NEXT : SCL_NEXT;
                    clk_counter_next = 0;
                    if (data_cnt_reg == 3) begin
                        data_cnt_next = 0;
                        tx_done_next  = 1;
                        ///edit
                        if (!ACK_LOW_REG) begin
                            next_state    = (length_reg == 0) ? ST_STOP1 : (CR_RW == 1) ? ST_READ : ST_HOLD2;
                            SCL_NEXT      = (length_reg == 0) ? 1 : 0;  // STOP : DATA
                            addr_sig_next = 1'b0;
                            length_next   = length_reg - 1;
                        end else begin
                            SCL_NEXT   = 1;
                            next_state = ST_STOP1;
                        end
                        ///
                    end else begin
                        data_cnt_next = data_cnt_reg + 1;
                    end
                    if (data_cnt_reg == 1) ACK_LOW_NEXT = SDA;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            /////EDIT
            ST_WRITE_ACK: begin
                SDA_EN = 1'b0;
                O_SDA  = 1'b1;
                if (clk_counter_reg == 249) begin
                    SCL_NEXT = (data_cnt_reg == 0 || data_cnt_reg == 2) ? ~SCL_NEXT : SCL_NEXT;
                    clk_counter_next = 0;
                    if (data_cnt_reg == 3) begin
                        data_cnt_next = 0;
                        tx_done_next  = 1;
                        if (!ACK_LOW_REG) begin
                            if (length_reg == 0) begin
                                SCL_NEXT   = 1;
                                next_state = ST_HOLD;
                            end else begin
                                tx_data_next = tx_data;
                                SCL_NEXT     = 0;
                                next_state   = ST_HOLD2;
                                length_next  = length_reg - 1;
                            end
                        end else begin
                            SCL_NEXT   = 1;
                            next_state = ST_STOP1;
                        end
                    end else begin
                        data_cnt_next = data_cnt_reg + 1;
                    end
                    if (data_cnt_reg == 1) ACK_LOW_NEXT = SDA;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            ST_READ_ACK: begin
                SDA_EN = 1'b1;
                O_SDA  = (length_reg == 0) ? 1'b1 : 1'b0;  // nack : ack
                if (clk_counter_reg == 249) begin
                    SCL_NEXT = (data_cnt_reg == 0 || data_cnt_reg == 2) ? ~SCL_NEXT : SCL_NEXT;
                    clk_counter_next = 0;
                    if (data_cnt_reg == 3) begin
                        data_cnt_next = 0;
                        rx_done_next  = 1;
                        if (length_reg == 0) begin
                            next_state = ST_HOLD;
                        end else begin
                            SCL_NEXT    = 0;
                            next_state  = ST_READ;
                            length_next = length_reg - 1;
                        end
                    end else begin
                        data_cnt_next = data_cnt_reg + 1;
                    end
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            ST_STOP1: begin
                O_SDA = 0;
                if (clk_counter_reg == 499) begin
                    clk_counter_next = 0;
                    next_state = ST_STOP2;
                    SCL_NEXT = 1;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            ST_STOP2: begin
                O_SDA = 1;
                if (clk_counter_reg == 499) begin
                    clk_counter_next = 0;
                    next_state = ST_IDLE;
                    SCL_NEXT = 1'b1;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
        endcase
    end
endmodule
