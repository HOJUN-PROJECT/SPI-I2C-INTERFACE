`timescale 1ns / 1ps

module spi_master (
    // global signals
    input  logic       clk,
    input  logic       reset,
    // internal signals
    input  logic       start,
    input  logic       cpol,
    input  logic       cpha,
    input  logic [7:0] tx_data,
    output logic [7:0] rx_data,
    output logic       tx_ready,
    output logic       done,
    // external ports
    output logic       sclk,
    output logic       mosi,
    input  logic       miso
);
    typedef enum {
        IDLE,
        CP0,
        CP1,
        CP_DELAY
    } state_t;

    state_t state, state_next;
    logic [7:0] tx_data_reg, tx_data_next;
    logic [7:0] rx_data_reg, rx_data_next;
    logic [5:0] sclk_counter_reg, sclk_counter_next;
    logic [2:0] bit_counter_reg, bit_counter_next;

    logic p_clk;
    logic spi_clk_reg, spi_clk_next;

    assign mosi         = tx_data_reg[7];
    assign rx_data      = rx_data_reg;

    assign p_clk        = ((state_next == CP0) && (cpha == 1)) || ((state_next == CP1) && (cpha == 0));
    assign spi_clk_next = cpol ? ~p_clk : p_clk;
    assign sclk         = spi_clk_reg;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            state            <= IDLE;
            tx_data_reg      <= 0;
            rx_data_reg      <= 0;
            sclk_counter_reg <= 0;
            bit_counter_reg  <= 0;
            spi_clk_reg      <= 0;
        end else begin
            state            <= state_next;
            tx_data_reg      <= tx_data_next;
            rx_data_reg      <= rx_data_next;
            sclk_counter_reg <= sclk_counter_next;
            bit_counter_reg  <= bit_counter_next;
            spi_clk_reg      <= spi_clk_next;
        end
    end

    always_comb begin
        state_next        = state;
        tx_data_next      = tx_data_reg;
        rx_data_next      = rx_data_reg;
        sclk_counter_next = sclk_counter_reg;
        bit_counter_next  = bit_counter_reg;
        tx_ready          = 1'b0;
        done              = 1'b0;
        // sclk              = 1'b0;
        case (state)
            IDLE: begin
                done              = 1'b0;
                tx_ready          = 1'b1;
                sclk_counter_next = 0;
                bit_counter_next  = 0;
                if (start) begin
                    state_next   = cpha ? CP_DELAY : CP0;
                    tx_data_next = tx_data;
                end
            end
            CP0: begin
                // sclk = 1'b0;
                if (sclk_counter_reg == 49) begin
                    rx_data_next      = {rx_data_reg[6:0], miso};
                    sclk_counter_next = 0;
                    state_next        = CP1;
                end else begin
                    sclk_counter_next = sclk_counter_reg + 1;
                end
            end
            CP1: begin
                // sclk = 1'b1;
                if (sclk_counter_reg == 49) begin
                    sclk_counter_next = 0;
                    if (bit_counter_reg == 7) begin
                        bit_counter_next = 0;
                        done             = cpha ? 1'b1 : 1'b0;
                        state_next       = cpha ? IDLE : CP_DELAY;
                    end else begin
                        bit_counter_next = bit_counter_reg + 1;
                        tx_data_next     = {tx_data_reg[6:0], 1'b0};
                        state_next       = CP0;
                    end
                end else begin
                    sclk_counter_next = sclk_counter_reg + 1;
                end
            end
            CP_DELAY: begin
                if (sclk_counter_reg == 49) begin
                    sclk_counter_next = 0;
                    done              = cpha ? 1'b0 : 1'b1;
                    state_next        = cpha ? CP0 : IDLE;
                end else begin
                    sclk_counter_next = sclk_counter_reg + 1;
                end
            end
        endcase
    end
endmodule
