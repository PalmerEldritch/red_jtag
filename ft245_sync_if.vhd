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