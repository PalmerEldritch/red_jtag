library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ft245_sync_if is
    port (
        clk         : in    std_logic;
        rst_n       : in    std_logic;

        ft_data     : inout std_logic_vector(7 downto 0);
        ft_rxf_n    : in    std_logic;
        ft_txe_n    : in    std_logic;
        ft_rd_n     : out   std_logic;
        ft_wr_n     : out   std_logic;
        ft_siwu_n   : out   std_logic;

        rx_valid    : out   std_logic;
        rx_data     : out   std_logic_vector(7 downto 0);

        tx_valid    : in    std_logic;
        tx_data     : in    std_logic_vector(7 downto 0);
        tx_ready    : out   std_logic
    );
end entity;

architecture rtl of ft245_sync_if is

    type ft_state_t is (
        ST_IDLE,
        ST_READ_PULSE,
        ST_READ_CAPTURE,
        ST_READ_DONE,
        ST_WRITE_SETUP,
        ST_WRITE_PULSE,
        ST_WRITE_DONE
    );

    signal state        : ft_state_t := ST_IDLE;
    signal wait_cnt     : unsigned(15 downto 0) := (others => '0');

    signal ft_data_out  : std_logic_vector(7 downto 0) := (others => '0');
    signal ft_data_oe   : std_logic := '0';

    signal rxf_sync     : std_logic_vector(2 downto 0) := (others => '1');
    signal txe_sync     : std_logic_vector(2 downto 0) := (others => '1');
    signal rxf_n_sync   : std_logic := '1';
    signal txe_n_sync   : std_logic := '1';

    signal rx_valid_reg : std_logic := '0';
    signal rx_data_reg  : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_ready_reg : std_logic := '0';

begin

    ft_siwu_n <= '0';
    ft_data <= ft_data_out when ft_data_oe = '1' else (others => 'Z');
    rx_valid <= rx_valid_reg;
    rx_data <= rx_data_reg;
    tx_ready <= tx_ready_reg;

    process(clk)
    begin
        if rising_edge(clk) then
            rx_valid_reg <= '0';

            if rst_n = '0' then
                state <= ST_IDLE;
                wait_cnt <= (others => '0');
                ft_data_out <= (others => '0');
                ft_data_oe <= '0';
                ft_rd_n <= '1';
                ft_wr_n <= '1';
                rxf_sync <= (others => '1');
                txe_sync <= (others => '1');
                rxf_n_sync <= '1';
                txe_n_sync <= '1';
                rx_data_reg <= (others => '0');
                tx_ready_reg <= '0';
            else
                rxf_sync <= rxf_sync(1 downto 0) & ft_rxf_n;
                txe_sync <= txe_sync(1 downto 0) & ft_txe_n;
                rxf_n_sync <= rxf_sync(2);
                txe_n_sync <= txe_sync(2);

                if state = ST_IDLE and txe_n_sync = '0' then
                    tx_ready_reg <= '1';
                else
                    tx_ready_reg <= '0';
                end if;

                case state is
                    when ST_IDLE =>
                        ft_rd_n <= '1';
                        ft_wr_n <= '1';
                        ft_data_oe <= '0';

                        if tx_valid = '1' and txe_n_sync = '0' then
                            ft_data_out <= tx_data;
                            ft_data_oe <= '1';
                            wait_cnt <= to_unsigned(2, wait_cnt'length);
                            state <= ST_WRITE_SETUP;
                        elsif rxf_n_sync = '0' then
                            ft_rd_n <= '0';
                            wait_cnt <= to_unsigned(3, wait_cnt'length);
                            state <= ST_READ_PULSE;
                        end if;

                    when ST_READ_PULSE =>
                        if wait_cnt = 0 then
                            state <= ST_READ_CAPTURE;
                        else
                            wait_cnt <= wait_cnt - 1;
                        end if;

                    when ST_READ_CAPTURE =>
                        rx_data_reg <= ft_data;
                        ft_rd_n <= '1';
                        wait_cnt <= to_unsigned(2, wait_cnt'length);
                        state <= ST_READ_DONE;

                    when ST_READ_DONE =>
                        if wait_cnt = 0 then
                            rx_valid_reg <= '1';
                            state <= ST_IDLE;
                        else
                            wait_cnt <= wait_cnt - 1;
                        end if;

                    when ST_WRITE_SETUP =>
                        if wait_cnt = 0 then
                            ft_wr_n <= '0';
                            wait_cnt <= to_unsigned(3, wait_cnt'length);
                            state <= ST_WRITE_PULSE;
                        else
                            wait_cnt <= wait_cnt - 1;
                        end if;

                    when ST_WRITE_PULSE =>
                        if wait_cnt = 0 then
                            ft_wr_n <= '1';
                            wait_cnt <= to_unsigned(2, wait_cnt'length);
                            state <= ST_WRITE_DONE;
                        else
                            wait_cnt <= wait_cnt - 1;
                        end if;

                    when ST_WRITE_DONE =>
                        ft_data_oe <= '0';
                        if wait_cnt = 0 then
                            state <= ST_IDLE;
                        else
                            wait_cnt <= wait_cnt - 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

end architecture;
