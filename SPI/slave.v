`timescale 1ns / 1ps

module spi_slave (
    // global signals
    input  logic       clk,
    input  logic       reset,
    // SPI External port
    input  logic       sclk,
    input  logic       mosi,
    output logic       miso,
    input  logic       cs,
    // Internal signals
    output logic [7:0] si_data,   // rx_data
    output logic       si_done,   // rx_done
    input  logic [7:0] so_data,   // tx_data
    input  logic       so_start,  // tx_start
    output logic       so_ready   // tx_ready
);

    /////////// Synchronizer Edge Detecotor ////////////
    logic sclk_sync0, sclk_sync1;
    logic sclk_rising, sclk_falling;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            sclk_sync0 <= 0;
            sclk_sync1 <= 0;
        end else begin
            sclk_sync0 <= sclk;
            sclk_sync1 <= sclk_sync0;
        end
    end

    assign sclk_rising  = sclk_sync0 && ~sclk_sync1;
    assign sclk_falling = ~sclk_sync0 && sclk_sync1;



    /////////// Slave In Sequence ////////////

    logic [2:0] si_bit_cnt_reg, si_bit_cnt_next;
    logic [7:0] si_data_reg, si_data_next;
    logic si_done_reg, si_done_next;

    assign si_data = si_data_reg;
    assign si_done = si_done_reg;

    typedef enum {
        SI_IDLE,
        SI_PHASE
    } si_state_e;
    si_state_e si_state, si_state_next;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            si_state       <= SI_IDLE;
            si_data_reg    <= 0;
            si_bit_cnt_reg <= 0;
            si_done_reg    <= 0;
        end else begin
            si_state       <= si_state_next;
            si_data_reg    <= si_data_next;
            si_bit_cnt_reg <= si_bit_cnt_next;
            si_done_reg    <= si_done_next;
        end
    end

    always_comb begin
        si_state_next   = si_state;
        si_bit_cnt_next = si_bit_cnt_reg;
        si_data_next    = si_data_reg;
        si_done_next    = si_done_reg;
        case (si_state)
            SI_IDLE: begin
                si_done_next = 1'b0;
                if (!cs) begin
                    si_state_next = SI_PHASE;
                end
            end
            SI_PHASE: begin
                if (!cs) begin
                    if (sclk_rising) begin
                        si_data_next = {si_data_reg[6:0], mosi};
                        if (si_bit_cnt_reg == 7) begin
                            si_bit_cnt_next = 0;
                            si_state_next   = SI_IDLE;
                            si_done_next    = 1'b1;
                        end else begin
                            si_bit_cnt_next = si_bit_cnt_reg + 1;

                        end
                    end
                end else begin
                    si_state_next = SI_IDLE;
                end
            end
        endcase
    end

    /////////// Slave Out Sequence ////////////

    logic [2:0] so_bit_cnt_reg, so_bit_cnt_next;
    logic [7:0] so_data_reg, so_data_next;

    assign miso = cs ? 1'bz : so_data_reg[7];

    typedef enum {
        SO_IDLE,
        SO_PHASE
    } so_state_e;

    so_state_e so_state, so_state_next;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            so_state       <= SO_IDLE;
            so_data_reg    <= 0;
            so_bit_cnt_reg <= 0;
        end else begin
            so_state       <= so_state_next;
            so_data_reg    <= so_data_next;
            so_bit_cnt_reg <= so_bit_cnt_next;
        end
    end

    always_comb begin
        so_state_next   = so_state;
        so_bit_cnt_next = so_bit_cnt_reg;
        so_data_next    = so_data_reg;
        so_ready        = 1'b0;
        case (so_state)
            SO_IDLE: begin
                if (!cs) begin
                    so_ready = 1'b1;
                    if (so_start) begin
                        so_state_next   = SO_PHASE;
                        so_data_next    = so_data;
                        so_bit_cnt_next = 0;
                    end
                end
            end
            SO_PHASE: begin
                if (!cs) begin
                    if (sclk_falling) begin
                        so_data_next = {so_data_reg[6:0], 1'b0};
                        if (so_bit_cnt_reg == 7) begin
                            so_bit_cnt_next = 0;
                            so_state_next   = SO_IDLE;
                        end else begin
                            so_bit_cnt_next = so_bit_cnt_reg + 1;
                        end
                    end
                end else begin
                    so_state_next = SO_IDLE;
                end
            end
        endcase
    end

endmodule
