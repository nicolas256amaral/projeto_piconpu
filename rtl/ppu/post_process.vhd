-------------------------------------------------------------------------------------------------------------
--
-- File: post_process.vhd
--
-- Descrição:
--   Unidade de pós-processamento da NPU.
--
-- Correção de timing:
--   A multiplicação signed ACC_W x QUANT_W deixou de ser executada como um
--   único multiplicador combinacional. O multiplicador de quantização é
--   decomposto em duas partes:
--
--       quant_mult = high * 2^LOW_W + low
--
--   Os dois produtos parciais são registrados e combinados no ciclo seguinte.
--   Isso adiciona um estágio ao pipeline, mas reduz o caminho combinacional
--   crítico que anteriormente causava violação de setup.
--
-------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.npu_pkg.all;

entity post_process is
    generic (
        ACC_W   : integer := 32;
        DATA_W  : integer := 8;
        QUANT_W : integer := 32
    );
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;
        soc_en_i    : in  std_logic;

        valid_in    : in  std_logic;
        acc_in      : in  std_logic_vector(ACC_W-1 downto 0);
        bias_in     : in  std_logic_vector(ACC_W-1 downto 0);
        quant_mult  : in  std_logic_vector(QUANT_W-1 downto 0);
        quant_shift : in  std_logic_vector(4 downto 0);
        zero_point  : in  std_logic_vector(DATA_W-1 downto 0);
        en_relu     : in  std_logic;

        valid_out   : out std_logic;
        data_out    : out std_logic_vector(DATA_W-1 downto 0)
    );
end entity post_process;

architecture rtl of post_process is

    constant MAX_OUT_VAL : integer := (2**(DATA_W-1)) - 1;
    constant MIN_OUT_VAL : integer := -(2**(DATA_W-1));

    constant PROD_W : integer := ACC_W + QUANT_W;

    -- A implementação pressupõe QUANT_W >= 2.
    constant QUANT_LOW_W  : integer := QUANT_W / 2;
    constant QUANT_HIGH_W : integer := QUANT_W - QUANT_LOW_W;

    -- A parte baixa recebe um bit adicional para ser representada como
    -- signed positivo.
    constant LOW_OPERAND_W : integer := QUANT_LOW_W + 1;
    constant LOW_PROD_W    : integer := ACC_W + LOW_OPERAND_W;
    constant HIGH_PROD_W   : integer := ACC_W + QUANT_HIGH_W;

    -- Estágio 1: soma do bias e captura dos parâmetros.
    signal s1_sum         : signed(ACC_W-1 downto 0) := (others => '0');
    signal s1_quant_low   : signed(LOW_OPERAND_W-1 downto 0) := (others => '0');
    signal s1_quant_high  : signed(QUANT_HIGH_W-1 downto 0) := (others => '0');
    signal s1_quant_shift : unsigned(4 downto 0) := (others => '0');
    signal s1_zero_point  : signed(DATA_W downto 0) := (others => '0');
    signal s1_relu        : std_logic := '0';
    signal s1_valid       : std_logic := '0';

    -- Estágio 2: produtos parciais.
    signal s2_prod_low    : signed(LOW_PROD_W-1 downto 0) := (others => '0');
    signal s2_prod_high   : signed(HIGH_PROD_W-1 downto 0) := (others => '0');
    signal s2_quant_shift : unsigned(4 downto 0) := (others => '0');
    signal s2_zero_point  : signed(DATA_W downto 0) := (others => '0');
    signal s2_relu        : std_logic := '0';
    signal s2_valid       : std_logic := '0';

    -- Estágio 3: combinação dos produtos parciais.
    signal s3_prod        : signed(PROD_W-1 downto 0) := (others => '0');
    signal s3_quant_shift : unsigned(4 downto 0) := (others => '0');
    signal s3_zero_point  : signed(DATA_W downto 0) := (others => '0');
    signal s3_relu        : std_logic := '0';
    signal s3_valid       : std_logic := '0';

    -- Estágio 4: shift e arredondamento.
    signal s4_shifted     : signed(ACC_W-1 downto 0) := (others => '0');
    signal s4_zero_point  : signed(DATA_W downto 0) := (others => '0');
    signal s4_relu        : std_logic := '0';
    signal s4_valid       : std_logic := '0';

begin

    assert QUANT_W >= 2
        report "post_process: QUANT_W deve ser maior ou igual a 2"
        severity failure;

    process(clk)
        variable v_round_bit : signed(PROD_W-1 downto 0);
        variable v_shifted   : signed(PROD_W-1 downto 0);
        variable v_combined  : signed(PROD_W-1 downto 0);
        variable v_final_int : signed(ACC_W-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                s1_sum         <= (others => '0');
                s1_quant_low   <= (others => '0');
                s1_quant_high  <= (others => '0');
                s1_quant_shift <= (others => '0');
                s1_zero_point  <= (others => '0');
                s1_relu        <= '0';
                s1_valid       <= '0';

                s2_prod_low    <= (others => '0');
                s2_prod_high   <= (others => '0');
                s2_quant_shift <= (others => '0');
                s2_zero_point  <= (others => '0');
                s2_relu        <= '0';
                s2_valid       <= '0';

                s3_prod        <= (others => '0');
                s3_quant_shift <= (others => '0');
                s3_zero_point  <= (others => '0');
                s3_relu        <= '0';
                s3_valid       <= '0';

                s4_shifted     <= (others => '0');
                s4_zero_point  <= (others => '0');
                s4_relu        <= '0';
                s4_valid       <= '0';

                valid_out      <= '0';
                data_out       <= (others => '0');

            elsif soc_en_i = '1' then

                ----------------------------------------------------------------
                -- ESTÁGIO 1: BIAS E DECOMPOSIÇÃO DO MULTIPLICADOR
                ----------------------------------------------------------------
                s1_sum <= signed(acc_in) + signed(bias_in);

                -- Parte baixa interpretada como magnitude positiva.
                s1_quant_low <= signed(
                    '0' & quant_mult(QUANT_LOW_W-1 downto 0)
                );

                -- Parte alta mantém o sinal do multiplicador original.
                s1_quant_high <= signed(
                    quant_mult(QUANT_W-1 downto QUANT_LOW_W)
                );

                s1_quant_shift <= unsigned(quant_shift);

                -- Mantém a conversão usada no código original.
                s1_zero_point <= resize(signed(zero_point), DATA_W + 1);
                s1_relu       <= en_relu;
                s1_valid      <= valid_in;

                ----------------------------------------------------------------
                -- ESTÁGIO 2: PRODUTOS PARCIAIS
                ----------------------------------------------------------------
                s2_prod_low  <= s1_sum * s1_quant_low;
                s2_prod_high <= s1_sum * s1_quant_high;

                s2_quant_shift <= s1_quant_shift;
                s2_zero_point  <= s1_zero_point;
                s2_relu        <= s1_relu;
                s2_valid       <= s1_valid;

                ----------------------------------------------------------------
                -- ESTÁGIO 3: RECOMBINAÇÃO EXATA
                --
                -- A * B = A * low + (A * high) * 2^QUANT_LOW_W
                ----------------------------------------------------------------
                v_combined :=
                    resize(s2_prod_low, PROD_W) +
                    shift_left(resize(s2_prod_high, PROD_W), QUANT_LOW_W);

                s3_prod        <= v_combined;
                s3_quant_shift <= s2_quant_shift;
                s3_zero_point  <= s2_zero_point;
                s3_relu        <= s2_relu;
                s3_valid       <= s2_valid;

                ----------------------------------------------------------------
                -- ESTÁGIO 4: SHIFT E ARREDONDAMENTO
                ----------------------------------------------------------------
                if to_integer(s3_quant_shift) > 0 then
                    v_round_bit :=
                        shift_left(
                            to_signed(1, PROD_W),
                            to_integer(s3_quant_shift) - 1
                        );
                else
                    v_round_bit := (others => '0');
                end if;

                v_shifted :=
                    shift_right(
                        s3_prod + v_round_bit,
                        to_integer(s3_quant_shift)
                    );

                s4_shifted    <= v_shifted(ACC_W-1 downto 0);
                s4_zero_point <= s3_zero_point;
                s4_relu       <= s3_relu;
                s4_valid      <= s3_valid;

                ----------------------------------------------------------------
                -- ESTÁGIO 5: ZERO POINT, RELU E SATURAÇÃO
                ----------------------------------------------------------------
                v_final_int :=
                    s4_shifted + resize(s4_zero_point, ACC_W);

                if s4_relu = '1' and v_final_int < 0 then
                    v_final_int := (others => '0');
                end if;

                if v_final_int > to_signed(MAX_OUT_VAL, ACC_W) then
                    data_out <= std_logic_vector(
                        to_signed(MAX_OUT_VAL, DATA_W)
                    );
                elsif v_final_int < to_signed(MIN_OUT_VAL, ACC_W) then
                    data_out <= std_logic_vector(
                        to_signed(MIN_OUT_VAL, DATA_W)
                    );
                else
                    data_out <= std_logic_vector(
                        v_final_int(DATA_W-1 downto 0)
                    );
                end if;

                valid_out <= s4_valid;

            else
                -- O pipeline fica congelado quando soc_en_i = '0'.
                valid_out <= '0';
            end if;
        end if;
    end process;

end architecture rtl;
