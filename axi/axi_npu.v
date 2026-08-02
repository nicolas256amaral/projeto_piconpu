module axi_npu #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  resetn,

    // ---------------------------------------------------------
    // AXI-Lite Slave
    // ---------------------------------------------------------
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                  s_axi_awvalid,
    output reg                   s_axi_awready,

    input  wire [DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [3:0]            s_axi_wstrb,
    input  wire                  s_axi_wvalid,
    output reg                   s_axi_wready,

    output wire [1:0]            s_axi_bresp,
    output reg                   s_axi_bvalid,
    input  wire                  s_axi_bready,

    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                  s_axi_arvalid,
    output reg                   s_axi_arready,

    output reg  [DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0]            s_axi_rresp,
    output reg                   s_axi_rvalid,
    input  wire                  s_axi_rready,

    // ---------------------------------------------------------
    // IRQ
    // ---------------------------------------------------------
    output wire                  irq_done_o
);

    assign s_axi_bresp = 2'b00;
    assign s_axi_rresp = 2'b00;

    // ---------------------------------------------------------
    // Latches AXI
    // ---------------------------------------------------------
    reg [ADDR_WIDTH-1:0] awaddr_lat;
    reg                  awaddr_valid;

    reg [DATA_WIDTH-1:0] wdata_lat;
    reg [3:0]            wstrb_lat;
    reg                  wdata_valid;

    reg [ADDR_WIDTH-1:0] araddr_lat;
    reg                  araddr_valid;

    // ---------------------------------------------------------
    // Interface MMIO da NPU
    // ---------------------------------------------------------
    reg                  npu_vld_i;
    reg                  npu_we_i;
    reg  [31:0]          npu_addr_i;
    reg  [31:0]          npu_data_i;
    wire [31:0]          npu_data_o;
    wire                 npu_rdy_o;

    // ---------------------------------------------------------
    // Estados simples
    // ---------------------------------------------------------
    reg write_inflight;
    reg read_inflight;

    wire aw_hs = s_axi_awvalid && s_axi_awready;
    wire w_hs  = s_axi_wvalid  && s_axi_wready;
    wire ar_hs = s_axi_arvalid && s_axi_arready;

    // ---------------------------------------------------------
    // AXI Write / Read control
    // ---------------------------------------------------------
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            s_axi_awready  <= 1'b0;
            s_axi_wready   <= 1'b0;
            s_axi_bvalid   <= 1'b0;
            s_axi_arready  <= 1'b0;
            s_axi_rvalid   <= 1'b0;
            s_axi_rdata    <= 32'h0;

            awaddr_lat     <= {ADDR_WIDTH{1'b0}};
            awaddr_valid   <= 1'b0;
            wdata_lat      <= {DATA_WIDTH{1'b0}};
            wstrb_lat      <= 4'h0;
            wdata_valid    <= 1'b0;
            araddr_lat     <= {ADDR_WIDTH{1'b0}};
            araddr_valid   <= 1'b0;

            npu_vld_i      <= 1'b0;
            npu_we_i       <= 1'b0;
            npu_addr_i     <= 32'h0;
            npu_data_i     <= 32'h0;

            write_inflight <= 1'b0;
            read_inflight  <= 1'b0;
        end else begin
            // defaults
            npu_vld_i <= 1'b0;

            // -------------------------------------------------
            // READY generation
            // -------------------------------------------------
            s_axi_awready <= (!awaddr_valid) && (!write_inflight) && (!s_axi_bvalid);
            s_axi_wready  <= (!wdata_valid)  && (!write_inflight) && (!s_axi_bvalid);
            s_axi_arready <= (!araddr_valid) && (!read_inflight)  && (!s_axi_rvalid);

            // -------------------------------------------------
            // Capture write address
            // -------------------------------------------------
            if (aw_hs) begin
                awaddr_lat   <= s_axi_awaddr;
                awaddr_valid <= 1'b1;
            end

            // -------------------------------------------------
            // Capture write data
            // -------------------------------------------------
            if (w_hs) begin
                wdata_lat   <= s_axi_wdata;
                wstrb_lat   <= s_axi_wstrb;
                wdata_valid <= 1'b1;
            end

            // -------------------------------------------------
            // Start MMIO write request to NPU
            // -------------------------------------------------
            if (!write_inflight && awaddr_valid && wdata_valid && !s_axi_bvalid) begin
                // NPU é word-aligned; repassa endereço local
                npu_addr_i     <= {20'd0, awaddr_lat};
                npu_data_i     <= wdata_lat;
                npu_we_i       <= 1'b1;
                npu_vld_i      <= 1'b1;
                write_inflight <= 1'b1;
            end

            // -------------------------------------------------
            // Complete MMIO write when NPU is ready
            // -------------------------------------------------
            if (write_inflight && npu_rdy_o) begin
                write_inflight <= 1'b0;
                awaddr_valid   <= 1'b0;
                wdata_valid    <= 1'b0;
                s_axi_bvalid   <= 1'b1;
            end

            // Write response accepted
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            // -------------------------------------------------
            // Capture read address
            // -------------------------------------------------
            if (ar_hs) begin
                araddr_lat   <= s_axi_araddr;
                araddr_valid <= 1'b1;
            end

            // -------------------------------------------------
            // Start MMIO read request to NPU
            // -------------------------------------------------
            if (!read_inflight && araddr_valid && !s_axi_rvalid) begin
                npu_addr_i    <= {20'd0, araddr_lat};
                npu_data_i    <= 32'h0;
                npu_we_i      <= 1'b0;
                npu_vld_i     <= 1'b1;
                read_inflight <= 1'b1;
            end

            // -------------------------------------------------
            // Complete MMIO read when NPU is ready
            // -------------------------------------------------
            if (read_inflight && npu_rdy_o) begin
                read_inflight <= 1'b0;
                araddr_valid  <= 1'b0;
                s_axi_rdata   <= npu_data_o;
                s_axi_rvalid  <= 1'b1;
            end

            // Read data accepted
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    // ---------------------------------------------------------
    // Instância da NPU (VHDL)
    // ---------------------------------------------------------
    // Observação:
    // Para simulação/síntese mista, o nome da entidade VHDL
    // precisa estar visível no projeto como "npu_top".
    npu_top u_npu_top (
        .clk        (clk),
        .rst_n      (resetn),
        .soc_en_i   (1'b1),

        .vld_i      (npu_vld_i),
        .rdy_o      (npu_rdy_o),
        .we_i       (npu_we_i),
        .addr_i     (npu_addr_i),
        .data_i     (npu_data_i),
        .data_o     (npu_data_o),

        .irq_done_o (irq_done_o)
    );

endmodule