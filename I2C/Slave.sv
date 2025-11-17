`timescale 1ns / 1ps

module I2C_SLAVE (
    // global signals
    input  logic       clk,
    input  logic       reset,
    // Internal signals
    input  logic [7:0] tx_data,
    output logic       tx_done,
    output logic       tx_ready,
    output logic [7:0] rx_data,
    output logic       rx_done,
    // External signals
    input  logic       scl,
    inout  logic       sda
);

    logic sda_en;
    logic o_sda;
    logic [7:0] addr_reg, addr_next;
    logic [7:0] rx_data_reg, rx_data_next;
    logic [7:0] tx_data_reg, tx_data_next;
    logic burst_read_reg, burst_read_next;
    
    ///////////////////////synchronizer && edge detector////////////////////////////////
    logic sda_falling, sda_rising;
    logic scl_falling, scl_rising;
    logic sda_sync0, sda_sync1;
    logic scl_sync0, scl_sync1;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            sda_sync0 <= 0;
            sda_sync1 <= 0;
            scl_sync0 <= 0;
            scl_sync1 <= 0;
        end else begin
            sda_sync0 <= sda;
            sda_sync1 <= sda_sync0;
            scl_sync0 <= scl;
            scl_sync1 <= scl_sync0;
        end
    end

    assign sda_rising  = sda_sync0 && (~sda_sync1);
    assign sda_falling = (~sda_sync0) && sda_sync1;
    assign scl_rising  = scl_sync0 && (~scl_sync1);
    assign scl_falling = (~scl_sync0) && scl_sync1;
    ////////////////////////////////////////////////////////////////////////////////////

    assign sda         = (sda_en) ? o_sda : 1'bz;

    typedef enum {
        IDLE,
        ADDR,
        SEND_ACK,
        WAIT,
        SEND_DATA,
        RCV_DATA,
        RCV_ACK,
        RCV_ACK_HOLD,
        WAIT_2,
        SEND_ACK_2,
        STOP
    } state_e;

    state_e state, state_next;

    logic [2:0] bit_cnt_reg, bit_cnt_next;
    logic rx_done_reg, rx_done_next;
    wire [6:0] slave_addr = 7'b1111110;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            state          <= IDLE;
            bit_cnt_reg    <= 0;
            addr_reg       <= 0;
            rx_data_reg    <= 0;
            rx_done_reg    <= 0;
            tx_data_reg    <= 0;
            burst_read_reg <= 0;
        end else begin
            state          <= state_next;
            bit_cnt_reg    <= bit_cnt_next;
            addr_reg       <= addr_next;
            rx_data_reg    <= rx_data_next;
            rx_done_reg    <= rx_done_next;
            tx_data_reg    <= tx_data_next;
            burst_read_reg <= burst_read_next;

        end
    end

    always_comb begin
        state_next      = state;
        bit_cnt_next    = bit_cnt_reg;
        addr_next       = addr_reg;
        rx_data_next    = rx_data_reg;
        rx_done_next    = 0;
        o_sda           = 1'b1;  // 기본 값 1??
        tx_data_next    = tx_data_reg;
        burst_read_next = burst_read_reg;
        tx_done         = 0;

        if (state != IDLE) begin
            if (scl_sync1 && sda_rising) begin
                state_next = STOP;
            end else if (scl_sync1 && sda_falling) begin
                state_next   = ADDR;
                bit_cnt_next = 0;
            end
        end
        case (state)
            IDLE: begin
                rx_data_next = 0;
                if (scl && sda_falling) begin
                    bit_cnt_next = 0;
                    state_next   = ADDR;
                end
            end
            ADDR: begin
                if (scl_rising) begin
                    addr_next = {addr_reg[6:0], sda};
                    if (bit_cnt_reg == 7) begin
                        state_next   = WAIT;
                        rx_done_next = 1;
                        bit_cnt_next = 0;
                    end else begin
                        bit_cnt_next = bit_cnt_reg + 1;
                    end
                end
            end
            WAIT: begin  // rising_edge에서 바로 SEDN_ACK로 가버리면 충돌남
                if (scl_falling) begin
                    state_next = SEND_ACK;
                end
            end
            SEND_ACK: begin
                if (addr_reg[7:1] == slave_addr) begin
                    o_sda = 0;
                end
                if (scl_falling) begin
                    if (addr_reg[7:1] == slave_addr) begin
                        addr_next = 0;
                        if (addr_reg[0]) begin
                            state_next   = SEND_DATA;  // READ 동작
                            tx_data_next = tx_data;
                        end else begin
                            state_next = RCV_DATA;  // Write 동작
                        end
                    end else begin
                        state_next = STOP;  // 주소 불일치
                    end
                end
            end
            RCV_DATA: begin
                if (scl_rising) begin
                    rx_data_next = {rx_data_reg[6:0], sda};
                    if (bit_cnt_reg == 7) begin
                        state_next   = WAIT_2;
                        bit_cnt_next = 0;
                    end else begin
                        bit_cnt_next = bit_cnt_reg + 1;
                    end
                end
            end
            WAIT_2: begin  // rising_edge에서 바로 SEDN_ACK로 가버리면 충돌남
                if (scl_falling) begin
                    state_next = SEND_ACK_2;
                end
            end
            SEND_ACK_2: begin
                o_sda = 0;
                if (scl_falling) begin
                    rx_done_next = 1'b1;  // rx_done 1 tick
                    rx_data_next = 0;
                    state_next   = RCV_DATA;
                end
            end
            SEND_DATA: begin
                o_sda = tx_data_reg[7];
                if (scl_falling) begin
                    if (bit_cnt_reg == 7) begin
                        state_next = RCV_ACK;
                        tx_done    = 1;
                    end else begin
                        tx_data_next = {tx_data_reg[6:0], 1'b0};
                        bit_cnt_next = bit_cnt_reg + 1;
                    end
                end
            end
            RCV_ACK: begin
                if (scl_rising) begin
                    state_next = RCV_ACK_HOLD;
                    if (!sda_sync1) begin
                        burst_read_next = 1;
                        bit_cnt_next = 0;
                    end else begin
                        burst_read_next = 0;
                        bit_cnt_next = 0;
                    end
                end
            end
            RCV_ACK_HOLD: begin
                if (scl_falling) begin
                    if (burst_read_reg) begin
                        state_next   = SEND_DATA;
                        tx_data_next = tx_data;
                    end 
                    // else begin
                    //     state_next = STOP;
                    // end
                end
            end
            STOP: begin
                rx_data_next = 0;
                state_next   = IDLE;
            end
        endcase
    end

    assign sda_en  = (state == SEND_ACK) || (state == SEND_ACK_2) || (state == SEND_DATA);
    assign rx_done = rx_done_reg;
    assign rx_data = rx_data_reg;


endmodule
