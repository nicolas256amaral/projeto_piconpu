------------------------------------------------------------------------------------------------------------------
-- 
-- File: ram_dual.vhd
--
-- ██████╗  █████╗ ███╗   ███╗
-- ██╔══██╗██╔══██╗████╗ ████║
-- ██████╔╝███████║██╔████╔██║
-- ██╔══██╗██╔══██║██║╚██╔╝██║
-- ██║  ██║██║  ██║██║ ╚═╝ ██║
-- ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝
--  
-- Descrição : RAM de Porta Dupla Simples (Inferência de BRAM)
--             Porta A: Escrita (Usada pelo DMA/CPU)
--             Porta B: Leitura (Usada pela NPU Core)
-- 
-- Autor     : [André Maiolini]
-- Data      : [21/01/2026]    
--
------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
-- Bibliotecas adicionadas para leitura de arquivos na simulação
use std.textio.all;
use ieee.std_logic_textio.all; 

-------------------------------------------------------------------------------------------------------------------
-- ENTIDADE: Definição da interface da Dual Port RAM
-------------------------------------------------------------------------------------------------------------------

entity ram_dual is

    generic (

        DATA_W : integer := 32;
        DEPTH  : integer := 4096 -- 16KB

    );

    port (

        -- Sincronização (clock)
        clk      : in  std_logic;
        
        -- Porta de Escrita (DMA)
        wr_en    : in  std_logic;
        wr_addr  : in  std_logic_vector(31 downto 0);
        wr_data  : in  std_logic_vector(DATA_W-1 downto 0);
        
        -- Porta de Leitura (NPU)
        rd_addr  : in  std_logic_vector(31 downto 0);
        rd_data  : out std_logic_vector(DATA_W-1 downto 0)

    );

end entity;

-------------------------------------------------------------------------------------------------------------------
-- ARQUITETURA: Implementação da Dual Port RAM
-------------------------------------------------------------------------------------------------------------------

architecture rtl of ram_dual is

    -- Função para calcular log2 para dimensionar o array
    function log2_ceil(val : integer) return integer is
        variable res : integer := 0;
        variable tmp : integer := 1;
    begin
        if val <= 1 then return 1; end if;
        while tmp < val loop
            tmp := tmp * 2;
            res := res + 1;
        end loop;
        return res;
    end function;

    constant ADDR_BITS : integer := log2_ceil(DEPTH);
    type mem_t is array (0 to DEPTH-1) of std_logic_vector(DATA_W-1 downto 0);

    -- ========================================================================
    -- BACKDOOR VHDL: Função impura para inicializar a RAM com arquivo .hex
    -- ========================================================================
    impure function init_ram_hex return mem_t is

        file text_file : text open read_mode is "C:/Users/Nicolas/Desktop/UVM_NPU/uvm_test/uvm_test.sim/sim_1/behav/xsim/conv2d_1_weights_axi.hex";
        variable text_line : line;
        variable ram_content : mem_t := (others => (others => '0'));
        variable i : integer := 0;
        variable hex_val : std_logic_vector(DATA_W-1 downto 0);
    begin
        -- Lê linha por linha até o fim do arquivo ou até o limite da memória
        while not endfile(text_file) and i < DEPTH loop
            readline(text_file, text_line);
            hread(text_line, hex_val);
            ram_content(i) := hex_val;
            i := i + 1;
        end loop;
        return ram_content;
    end function;

    -- A RAM agora é inicializada utilizando a função criada acima
    signal ram : mem_t := init_ram_hex;

begin

    process(clk)
    begin

        if rising_edge(clk) then
        
            -- Escrita Síncrona
            if wr_en = '1' then
                ram(to_integer(unsigned(wr_addr(ADDR_BITS-1 downto 0)))) <= wr_data;
            end if;
            
            -- Leitura Síncrona
            rd_data <= ram(to_integer(unsigned(rd_addr(ADDR_BITS-1 downto 0))));
        
        end if;

    end process;

end architecture;

-------------------------------------------------------------------------------------------------------------------