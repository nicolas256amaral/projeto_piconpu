-------------------------------------------------------------------------------------------------------------
--
-- File: npu_controller.vhd
-- 
--  ██████╗ ██████╗ ███╗   ██╗████████╗██████╗  ██████╗ ██╗     ██╗     ███████╗██████╗ 
-- ██╔════╝██╔═══██╗████╗  ██║╚══██╔══╝██╔══██╗██╔═══██╗██║     ██║     ██╔════╝██╔══██╗
-- ██║     ██║   ██║██╔██╗ ██║   ██║   ██████╔╝██║   ██║██║     ██║     █████╗  ██████╔╝
-- ██║     ██║   ██║██║╚██╗██║   ██║   ██╔══██╗██║   ██║██║     ██║     ██╔══╝  ██╔══██╗
-- ╚██████╗╚██████╔╝██║ ╚████║   ██║   ██║  ██║╚██████╔╝███████╗███████╗███████╗██║  ██║
--  ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝                                                                                  
--
-- Descrição: NPU - Micro-Sequencer Controller (FSM)
--
-- Autor    : [André Maiolini]
-- Data     : [21/01/2026]
--
-------------------------------------------------------------------------------------------------------------

library ieee;                                                    -- Biblioteca padrão IEEE
use ieee.std_logic_1164.all;                                     -- Tipos de lógica digital
use ieee.numeric_std.all;                                        -- Tipos numéricos (signed, unsigned)
use work.npu_pkg.all;                                            -- Pacote de definições do NPU

-------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface do controlador (FSM)
-------------------------------------------------------------------------------------------------------------

entity npu_controller is

    generic (
    
        ROWS          : integer := 4;                            -- Quantidade de Linhas do Array Sistólico
        COLS          : integer := 4                             -- Quantidade de Colunas do Array Sistólico
    
    );

    port (

        -----------------------------------------------------------------------------------------------------
        -- Sinais de Controle e Sincronização
        -----------------------------------------------------------------------------------------------------

        clk           : in  std_logic;
        rst_n         : in  std_logic;
        soc_en_i      : in  std_logic;

        -----------------------------------------------------------------------------------------------------
        -- Interface Register File
        -----------------------------------------------------------------------------------------------------

        cmd_start     : in  std_logic;
        cmd_no_drain  : in  std_logic;
        cmd_rst_w     : in  std_logic;                           -- Reset Wgt Ptr
        cmd_rst_i     : in  std_logic;                           -- Reset Inp Ptr
        cfg_run_size  : in  unsigned(31 downto 0);

        -----------------------------------------------------------------------------------------------------
        -- Sinais de Saída (Status e Controle)
        -----------------------------------------------------------------------------------------------------

        sts_busy      : out std_logic;
        sts_done      : out std_logic;
        
        -----------------------------------------------------------------------------------------------------
        -- Controle do Pipeline
        -----------------------------------------------------------------------------------------------------

        wgt_rd_ptr    : out unsigned(31 downto 0);
        inp_rd_ptr    : out unsigned(31 downto 0);

        ctl_ram_re    : out std_logic;                           -- Read Enable
        ctl_core_vld  : out std_logic;                           -- Valid In (Delayed)
        ctl_acc_dump  : out std_logic;

        -----------------------------------------------------------------------------------------------------
        -- Backpressure
        -----------------------------------------------------------------------------------------------------

        fifo_ready_i  : in  std_logic;                           -- (1 = Pode enviar, 0 = Pare)
        ofifo_write_i : in  std_logic                            -- Pulso: palavra gravada na FIFO

        -----------------------------------------------------------------------------------------------------

    );

end entity npu_controller;

-------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação comportamental do controlador (FSM)
-------------------------------------------------------------------------------------------------------------

architecture rtl of npu_controller is

    function clog2(value : positive) return positive is
        variable result : positive := 1;
        variable limit  : natural  := 2;
    begin
        while limit < value loop
            result := result + 1;
            limit  := limit * 2;
        end loop;
        return result;
    end function;

    -- Constantes de Latência -------------------------------------------------------------------------------

    constant C_PIPE_LATENCY : integer  := 1 + 1 + (ROWS + COLS);
    constant C_ROW_CNT_W    : positive := clog2(ROWS + 1);

    -- Estados da FSM ---------------------------------------------------------------------------------------

    type state_t is (IDLE, COMPUTE, DRAIN, WAIT_OUTPUT);
    signal state : state_t := IDLE;

    signal r_cycle_cnt   : unsigned(31 downto 0) := (others => '0');
    signal r_dump_cnt    : unsigned(C_ROW_CNT_W-1 downto 0) := (others => '0');
    signal r_output_cnt  : unsigned(C_ROW_CNT_W-1 downto 0) := (others => '0');
    signal s_ram_read_en : std_logic := '0';
    
    -- Ponteiros internos -----------------------------------------------------------------------------------

    signal r_wgt_rd_ptr : unsigned(31 downto 0) := (others => '0');
    signal r_inp_rd_ptr : unsigned(31 downto 0) := (others => '0');

    -- Shadow Registers -------------------------------------------------------------------------------------

    signal r_no_drain   : std_logic := '0';

    ---------------------------------------------------------------------------------------------------------

begin

    wgt_rd_ptr <= r_wgt_rd_ptr;
    inp_rd_ptr <= r_inp_rd_ptr;
    ctl_ram_re <= s_ram_read_en;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                state <= IDLE;
                r_wgt_rd_ptr <= (others => '0');
                r_inp_rd_ptr <= (others => '0');
                r_cycle_cnt <= (others => '0');
                r_dump_cnt <= (others => '0');
                r_output_cnt <= (others => '0');
                s_ram_read_en <= '0';
                ctl_core_vld  <= '0';
                ctl_acc_dump  <= '0';
                sts_busy <= '0';
                sts_done <= '0';
                r_no_drain <= '0';
            
            elsif soc_en_i = '1' then

                -- Pipeline do Valid (Acompanha latência de 1 ciclo da BRAM)
                ctl_core_vld <= s_ram_read_en;

                case state is
                    when IDLE =>
                        sts_busy <= '0';
                        s_ram_read_en <= '0';
                        ctl_acc_dump <= '0';
                        
                        -- Start Check
                        if cmd_start = '1' then
                            state <= COMPUTE;
                            sts_busy <= '1';
                            sts_done <= '0';
                            r_cycle_cnt <= (others => '0');
                            r_dump_cnt <= (others => '0');
                            r_output_cnt <= (others => '0');
                            
                            -- Capture configs
                            r_no_drain <= cmd_no_drain;

                            -- Reset Pointers caso requisitado
                            if cmd_rst_w = '1' then r_wgt_rd_ptr <= (others => '0'); end if;
                            if cmd_rst_i = '1' then r_inp_rd_ptr <= (others => '0'); end if;
                        end if;

                    when COMPUTE =>
                        sts_busy <= '1';
                        
                        -- Lógica 1: Controle de Leitura da RAM 
                        if r_cycle_cnt < cfg_run_size then
                            s_ram_read_en <= '1';
                            r_wgt_rd_ptr <= r_wgt_rd_ptr + 1;
                            r_inp_rd_ptr <= r_inp_rd_ptr + 1;
                        else
                            s_ram_read_en <= '0';
                        end if;

                        -- Lógica 2: Controle de Estado (Run + Latência de Propagação)
                        if r_cycle_cnt < (cfg_run_size + C_PIPE_LATENCY) then
                            r_cycle_cnt <= r_cycle_cnt + 1;
                        else
                            -- Pipeline esvaziou. Verificar se é Tiling ou Drain.
                            if r_no_drain = '1' then
                                -- MODO TILING: Acumula resultado, não limpa FIFO, volta IDLE
                                state <= IDLE;
                                sts_done <= '1'; 
                            else
                                -- MODO FINAL: Hora de drenar resultados
                                state <= DRAIN;
                                r_cycle_cnt <= (others => '0');
                            end if;
                        end if;

                    when DRAIN =>
                        sts_busy <= '1';
                        s_ram_read_en <= '0';

                        -- Gera exatamente ROWS pulsos de drenagem.
                        if fifo_ready_i = '1' then
                            if r_dump_cnt < to_unsigned(ROWS, r_dump_cnt'length) then
                                ctl_acc_dump <= '1';
                                r_dump_cnt <= r_dump_cnt + 1;
                            else
                                ctl_acc_dump <= '0';
                                r_output_cnt <= (others => '0');
                                state <= WAIT_OUTPUT;
                            end if;
                        else
                            ctl_acc_dump <= '0';
                        end if;

                    when WAIT_OUTPUT =>
                        sts_busy <= '1';
                        s_ram_read_en <= '0';
                        ctl_acc_dump <= '0';

                        -- Finaliza apenas após ROWS gravações reais na FIFO.
                        if ofifo_write_i = '1' then
                            if r_output_cnt = to_unsigned(ROWS - 1, r_output_cnt'length) then
                                r_output_cnt <= (others => '0');
                                r_dump_cnt <= (others => '0');
                                state <= IDLE;
                                sts_busy <= '0';
                                sts_done <= '1';
                            else
                                r_output_cnt <= r_output_cnt + 1;
                            end if;
                        end if;

                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------------------------------------

end architecture; -- rtl

-------------------------------------------------------------------------------------------------------------