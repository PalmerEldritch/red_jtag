library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity jtag_boundary_scan_top is
    generic (
        BSR_LENGTH      : natural := 362;
        IR_LENGTH       : natural := 4;
        SDA_OUT_BIT     : natural := 10;
        SDA_OE_BIT      : natural := 11;
        SDA_IN_BIT      : natural := 9;
        SCL_OUT_BIT     : natural := 14;
        SCL_OE_BIT      : natural := 15
    );
    port (
        ft_data         : inout std_logic_vector(7 downto 0);
        ft_rxf_n        : in    std_logic;
        ft_txe_n        : in    std_logic;
        ft_rd_n         : out   std_logic;
        ft_wr_n         : out   std_logic;
        ft_siwu_n       : out   std_logic;

        jtag_tck        : out   std_logic;
        jtag_tms        : out   std_logic;
        jtag_tdi        : out   std_logic;
        jtag_tdo        : in    std_logic;

        led             : out   std_logic_vector(1 downto 0)
    );
end entity;