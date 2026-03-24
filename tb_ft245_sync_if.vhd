library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ft245_sync_if is
end entity;

architecture sim of tb_ft245_sync_if is

    constant CLK_PERIOD : time := 10 ns;

    signal clk          : std_logic := '0';
    signal rst_n        : std_logic := '0';

    signal ft_data      : std_logic_vector(7 downto 0) := (others => 'Z');
    signal ft_data_tb   : std_logic_vector(7 downto 0) := (others => 'Z');
    signal ft_rxf_n     : std_logic := '1';
    signal ft_txe_n     : std_logic := '1';
    signal ft_rd_n      : std_logic;
    signal ft_wr_n      : std_logic;
    signal ft_siwu_n    : std_logic;

    signal rx_valid     : std_logic;
    signal rx_data      : std_logic_vector(7 downto 0);
    signal tx_valid     : std_logic := '0';
    signal tx_data      : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_ready     : std_logic;

begin

    clk <= not clk after CLK_PERIOD / 2;
    ft_data <= ft_data_tb;

    dut: entity work.ft245_sync_if
        port map (
            clk => clk,
            rst_n => rst_n,
            ft_data => ft_data,
            ft_rxf_n => ft_rxf_n,
            ft_txe_n => ft_txe_n,
            ft_rd_n => ft_rd_n,
            ft_wr_n => ft_wr_n,
            ft_siwu_n => ft_siwu_n,
            rx_valid => rx_valid,
            rx_data => rx_data,
            tx_valid => tx_valid,
            tx_data => tx_data,
            tx_ready => tx_ready
        );

    stim_proc: process
    begin
        wait for 3 * CLK_PERIOD;
        rst_n <= '1';
        wait until rising_edge(clk);

        assert ft_siwu_n = '0' report "SIWU should be tied low" severity failure;
        assert ft_rd_n = '1' report "RD should idle high" severity failure;
        assert ft_wr_n = '1' report "WR should idle high" severity failure;
        assert rx_valid = '0' report "RX valid should idle low" severity failure;

        ft_rxf_n <= '0';
        ft_data_tb <= x"A5";

        loop
            wait until rising_edge(clk);
            exit when ft_rd_n = '0';
        end loop;

        loop
            wait until rising_edge(clk);
            exit when ft_rd_n = '1';
        end loop;

        ft_rxf_n <= '1';
        ft_data_tb <= (others => 'Z');

        loop
            wait until rising_edge(clk);
            exit when rx_valid = '1';
        end loop;

        assert rx_data = x"A5" report "RX data mismatch" severity failure;
        wait until rising_edge(clk);
        assert rx_valid = '0' report "RX valid must pulse for one cycle" severity failure;

        ft_txe_n <= '0';

        loop
            wait until rising_edge(clk);
            exit when tx_ready = '1';
        end loop;

        tx_data <= x"3C";
        tx_valid <= '1';
        wait until rising_edge(clk);
        tx_valid <= '0';

        loop
            wait until rising_edge(clk);
            exit when ft_wr_n = '0';
        end loop;

        assert ft_data = x"3C" report "TX data bus mismatch during write" severity failure;

        loop
            wait until rising_edge(clk);
            exit when ft_wr_n = '1' and tx_ready = '1';
        end loop;

        ft_txe_n <= '1';

        loop
            wait until rising_edge(clk);
            exit when tx_ready = '0';
        end loop;

        assert false report "tb_ft245_sync_if completed" severity note;
        wait;
    end process;

end architecture;
