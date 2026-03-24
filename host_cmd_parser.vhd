library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.jtag_pkg.all;

entity host_cmd_parser is
    generic (
        BSR_LENGTH : natural := 362
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;

        rx_valid        : in  std_logic;
        rx_data         : in  std_logic_vector(7 downto 0);

        req_valid       : out std_logic;
        req_kind        : out host_req_kind_t;

        req_byte        : out std_logic_vector(7 downto 0);
        req_word        : out unsigned(15 downto 0);
        req_data        : out std_logic_vector(BSR_LENGTH-1 downto 0);
        req_data_len    : out unsigned(15 downto 0);

        busy            : in  std_logic
    );
end entity;