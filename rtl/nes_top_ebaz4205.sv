// nes_top_ebaz4205.sv
// Modified NES top module for EBAZ4205 board.
//
// Changes from tarunes_top:
//   1. PRG ROM (prombus) connected to external BRAM port instead of internal $readmemh
//   2. CHR ROM (crombus) connected to external BRAM port instead of internal $readmemh
//   3. SFC controller replaced with direct button input (controller1_btns port)
//
// This module is functionally equivalent to tarunes_top but uses:
//   - External dual-port BRAMs for PRG/CHR ROM (loaded by PS at runtime)
//   - Direct 8-bit button input instead of SFC serial protocol

`timescale 1ns / 1ps

module nes_top_ebaz4205 #(
    parameter bit ENABLE_APU    = 1'b1,
    parameter bit I2S_TEST_TONE = 1'b0
) (
    input  var logic          clk,
    input  var logic          rst,          // synchronous active-high reset
    input  var logic          frame_sync,
    // Button input (replaces SFC controller)
    // Bit mapping: {A, B, SELECT, START, UP, DOWN, LEFT, RIGHT}
    input  var logic [7:0]    controller1_btns,
    // PPU outputs
    output var logic [8:0]    scanline,
    output var logic [8:0]    cycle,
    output var logic [5:0]    pixel_index,
    // HDMI video outputs
    output var logic [7:0]    hdmi_r,
    output var logic [7:0]    hdmi_g,
    output var logic [7:0]    hdmi_b,
    output var logic          hdmi_hsync,
    output var logic          hdmi_vsync,
    output var logic          hdmi_de,
    output var logic [9:0]    hdmi_video_x,
    output var logic [9:0]    hdmi_video_y,
    // Audio
    output var logic [7:0]    audio_sample,
    // Buffered, rate-matched (~46.9 kHz) sample for external PWM/1-bit DACs.
    // Unlike audio_sample (raw APU output, bursty in wall-clock time because
    // the core renders ahead and stalls), this follows the I2S playback rate.
    output var logic [7:0]    audio_pcm,
    output var logic          i2s_bclk,
    output var logic          i2s_lrck,
    output var logic          i2s_dout,
    // External PRG ROM BRAM interface (8-bit, read-only from NES core)
    // Address: 15-bit (32KB), connected to dual-port BRAM port B
    output var logic [14:0]   prg_addr,
    input  var logic [7:0]    prg_rdata,
    // External CHR ROM BRAM interface (8-bit, read-only from NES PPU)
    // Address: 13-bit (8KB), connected to dual-port BRAM port B
    output var logic [12:0]   chr_addr,
    input  var logic [7:0]    chr_rdata,
    // Debug outputs
    output var logic [15:0]   debug_cpu_pc,
    output var logic [15:0]   logic_analizer,
    output var logic [7:0]    debug_palette0,
    output var logic [7:0]    debug_palette1,
    output var logic [7:0]    debug_palette2,
    output var logic [7:0]    debug_palette3,
    output var logic [4:0]    debug_bg_palette_addr,
    output var logic [7:0]    debug_bg_palette_data,
    output var logic          debug_palette_write,
    output var logic [4:0]    debug_palette_write_addr,
    output var logic [7:0]    debug_palette_write_data
);
    localparam logic [9:0]  AUDIO_SAMPLES_PER_FRAME = 10'd782;
    localparam logic [16:0] AUDIO_FRAME_CYCLES      = 17'd89342;

    // Internal bus interfaces
    tarunes___bus_if__8__16 cpubus     ();
    tarunes___bus_if__8__3  cpu_ppubus ();
    tarunes___bus_if__8__5  apubus     ();
    tarunes___bus_if__8__1  ctrlbus    ();
    tarunes___bus_if__8__11 wrambus    ();
    tarunes___bus_if__8__15 prombus    ();
    tarunes___bus_if__8__3  dma_ppubus ();
    tarunes___bus_if__8__11 dma_wrambus();
    tarunes___bus_if__8__14 ppubus     ();
    tarunes___bus_if__8__11 vrambus    ();
    tarunes___bus_if__8__13 crombus    ();

    logic          nmi;
    logic          ctrl_sel;
    logic          dma_busy;
    logic          dma_start;
    logic [7:0]    dma_page;
    logic          cpu_halt;
    logic          core_stall;
    logic          apu_stall;
    logic          ppu_frame_wait;
    logic [7:0]    audio_sample_raw;
    logic [7:0]    audio_play_sample;
    logic [7:0]    audio_buffer [1024];
    logic [9:0]    audio_wr_ptr;
    logic [9:0]    audio_rd_ptr;
    logic [10:0]   audio_count;
    logic [16:0]   audio_write_acc;
    logic [9:0]    audio_frame_samples;
    logic          audio_write_pulse;
    logic          i2s_sample_req;
    logic [7:0]    controller2_btns;

    assign core_stall        = ppu_frame_wait;
    assign audio_pcm         = audio_play_sample;
    assign apu_stall         = (audio_frame_samples == AUDIO_SAMPLES_PER_FRAME);
    assign audio_sample      = audio_sample_raw;
    assign controller2_btns = 8'h00;
    assign audio_write_pulse = !frame_sync && !apu_stall &&
                               (audio_write_acc + {7'b0, AUDIO_SAMPLES_PER_FRAME} >= AUDIO_FRAME_CYCLES);
    assign ctrl_sel          = (cpubus.addr == 16'h4016) ||
                               ((cpubus.addr == 16'h4017) && !cpubus.wen);

    // -------------------------------------------------------------------------
    // CPU
    // -------------------------------------------------------------------------
    tarunes_cpu cpu_inst (
        .clk           (clk           ),
        .rst           (rst           ),
        .stall         (core_stall    ),
        .nmi           (nmi           ),
        .halt          (cpu_halt      ),
        .debug_pc      (debug_cpu_pc  ),
        .logic_analizer(logic_analizer),
        .cpubus        (cpubus        )
    );

    // -------------------------------------------------------------------------
    // Work RAM (2KB internal BRAM)
    // -------------------------------------------------------------------------
    tarunes___memory__8__11 wram (
        .clk   (clk       ),
        .rst   (rst       ),
        .stall (core_stall),
        .membus(wrambus   )
    );

    // -------------------------------------------------------------------------
    // PRG ROM: External BRAM (loaded by PS)
    // Replace internal tarunes___memory__8__15 with external BRAM interface
    // -------------------------------------------------------------------------
    // prombus is 15-bit address, 8-bit data
    // We drive prg_addr from prombus.addr and feed prg_rdata back to prombus.rdata
    assign prg_addr      = prombus.addr;
    assign prombus.rdata = prg_rdata;
    // PRG ROM is read-only from NES core (writes are ignored)

    // -------------------------------------------------------------------------
    // CPU Bus arbiter
    // -------------------------------------------------------------------------
    tarunes_bus_cpu ubus_cpu (
        .clk        (clk        ),
        .rst        (rst        ),
        .stall      (core_stall ),
        .dma_busy   (dma_busy   ),
        .dma_start  (dma_start  ),
        .dma_page   (dma_page   ),
        .cpu_halt   (cpu_halt   ),
        .cpubus     (cpubus     ),
        .cpu_ppubus (cpu_ppubus ),
        .dma_ppubus (dma_ppubus ),
        .apubus     (apubus     ),
        .ctrlbus    (ctrlbus    ),
        .dma_wrambus(dma_wrambus),
        .prombus    (prombus    ),
        .wrambus    (wrambus    )
    );

    // -------------------------------------------------------------------------
    // OAM DMA
    // -------------------------------------------------------------------------
    tarunes_oam_dma oam_dma_inst (
        .clk       (clk        ),
        .rst       (rst        ),
        .stall     (core_stall ),
        .start     (dma_start  ),
        .page      (dma_page   ),
        .busy      (dma_busy   ),
        .wrambus   (dma_wrambus),
        .ppu_regbus(dma_ppubus )
    );

    // -------------------------------------------------------------------------
    // APU
    // -------------------------------------------------------------------------
    generate
        if (ENABLE_APU) begin : g_apu
            tarunes_apu apu_inst (
                .clk         (clk             ),
                .rst         (rst             ),
                .stall       (apu_stall       ),
                .bus_stall   (core_stall      ),
                .cpubus      (apubus          ),
                .audio_sample(audio_sample_raw)
            );
        end else begin : g_apu_disabled
            assign apubus.rdata     = 8'h00;
            assign audio_sample_raw = 8'h80;
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Audio buffer and I2S
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst) begin
            audio_play_sample   <= 8'h80;
            audio_wr_ptr        <= 0;
            audio_rd_ptr        <= 0;
            audio_count         <= 0;
            audio_write_acc     <= 0;
            audio_frame_samples <= 0;
        end else begin
            if (frame_sync) begin
                audio_write_acc     <= 0;
                audio_frame_samples <= 0;
            end else if (!apu_stall) begin
                if (audio_write_pulse) begin
                    audio_write_acc     <= audio_write_acc + {7'b0, AUDIO_SAMPLES_PER_FRAME} - AUDIO_FRAME_CYCLES;
                    audio_frame_samples <= audio_frame_samples + 1;
                end else begin
                    audio_write_acc <= audio_write_acc + {7'b0, AUDIO_SAMPLES_PER_FRAME};
                end
            end

            if (audio_write_pulse && audio_count != 11'd1024) begin
                audio_buffer[audio_wr_ptr] <= audio_sample_raw;
                audio_wr_ptr               <= audio_wr_ptr + 1;
                if (!(i2s_sample_req && audio_count != 0)) begin
                    audio_count <= audio_count + 1;
                end
            end

            if (i2s_sample_req) begin
                if (audio_count != 0) begin
                    audio_play_sample <= audio_buffer[audio_rd_ptr];
                    audio_rd_ptr      <= audio_rd_ptr + 1;
                    if (!audio_write_pulse) begin
                        audio_count <= audio_count - 1;
                    end
                end else begin
                    audio_play_sample <= 8'h80;
                end
            end
        end
    end

    tarunes_i2s #(
        .TEST_TONE(I2S_TEST_TONE)
    ) i2s_inst (
        .clk       (clk              ),
        .rst       (rst              ),
        .sample    (audio_play_sample),
        .bclk      (i2s_bclk         ),
        .lrck      (i2s_lrck         ),
        .dout      (i2s_dout         ),
        .sample_req(i2s_sample_req   )
    );

    // -------------------------------------------------------------------------
    // Controller: direct button input (no SFC serial protocol)
    // -------------------------------------------------------------------------
    tarunes_controller controller_inst (
        .clk             (clk             ),
        .rst             (rst             ),
        .stall           (core_stall      ),
        .sel             (ctrl_sel        ),
        .controller1_btns(controller1_btns),
        .controller2_btns(controller2_btns),
        .cpubus          (ctrlbus         )
    );

    // -------------------------------------------------------------------------
    // PPU
    // -------------------------------------------------------------------------
    tarunes_ppu ppu_inst (
        .clk                     (clk                     ),
        .rst                     (rst                     ),
        .frame_sync              (frame_sync              ),
        .cpubus                  (cpu_ppubus              ),
        .ppubus                  (ppubus                  ),
        .scanline                (scanline                ),
        .cycle                   (cycle                   ),
        .pixel_index             (pixel_index             ),
        .nmi                     (nmi                     ),
        .frame_wait              (ppu_frame_wait          ),
        .debug_palette0          (debug_palette0          ),
        .debug_palette1          (debug_palette1          ),
        .debug_palette2          (debug_palette2          ),
        .debug_palette3          (debug_palette3          ),
        .debug_bg_palette_addr   (debug_bg_palette_addr   ),
        .debug_bg_palette_data   (debug_bg_palette_data   ),
        .debug_palette_write     (debug_palette_write     ),
        .debug_palette_write_addr(debug_palette_write_addr),
        .debug_palette_write_data(debug_palette_write_data)
    );

    // -------------------------------------------------------------------------
    // HDMI 480p scaler
    // -------------------------------------------------------------------------
    tarunes_hdmi_480p_scaler hdmi_scaler (
        .clk             (clk         ),
        .rst             (rst         ),
        .core_cycle      (cycle       ),
        .core_scanline   (scanline    ),
        .core_pixel_index(pixel_index ),
        .hdmi_r          (hdmi_r      ),
        .hdmi_g          (hdmi_g      ),
        .hdmi_b          (hdmi_b      ),
        .hdmi_hsync      (hdmi_hsync  ),
        .hdmi_vsync      (hdmi_vsync  ),
        .hdmi_de         (hdmi_de     ),
        .video_x         (hdmi_video_x),
        .video_y         (hdmi_video_y)
    );

    // -------------------------------------------------------------------------
    // PPU Bus arbiter
    // -------------------------------------------------------------------------
    tarunes_bus_ppu ubus_ppu (
        .clk    (clk       ),
        .rst    (rst       ),
        .stall  (core_stall),
        .ppubus (ppubus    ),
        .crombus(crombus   ),
        .vrambus(vrambus   )
    );

    // -------------------------------------------------------------------------
    // Video RAM (2KB internal BRAM)
    // -------------------------------------------------------------------------
    tarunes___memory__8__11 vram (
        .clk   (clk       ),
        .rst   (rst       ),
        .stall (core_stall),
        .membus(vrambus   )
    );

    // -------------------------------------------------------------------------
    // CHR ROM: External BRAM (loaded by PS)
    // Replace internal tarunes___memory__8__13 with external BRAM interface
    // -------------------------------------------------------------------------
    assign chr_addr      = crombus.addr;
    assign crombus.rdata = chr_rdata;
    // CHR ROM is read-only from NES PPU (writes are ignored)

endmodule
