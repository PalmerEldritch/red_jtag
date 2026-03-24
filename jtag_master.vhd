library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.jtag_pkg.all;

entity jtag_master is
    generic (
        MAX_SHIFT_BITS   : natural := 1024;
        IR_LENGTH        : natural := 4;
        JTAG_DIV_WIDTH   : natural := 8;
        JTAG_DIV_VALUE   : natural := 255
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;

        req_valid       : in  std_logic;
        req_kind        : in  jtag_req_kind_t;
        req_ir          : in  std_logic_vector(7 downto 0);
        req_dr_len      : in  unsigned(15 downto 0);
        req_dr_data     : in  std_logic_vector(MAX_SHIFT_BITS-1 downto 0);
        req_tms_value   : in  std_logic;
        req_tck_edges   : in  unsigned(15 downto 0);

        busy            : out std_logic;
        done            : out std_logic;
        rsp_dr_data     : out std_logic_vector(MAX_SHIFT_BITS-1 downto 0);
        rsp_dr_len      : out unsigned(15 downto 0);

        jtag_tck        : out std_logic;
        jtag_tms        : out std_logic;
        jtag_tdi        : out std_logic;
        jtag_tdo        : in  std_logic
    );
end entity;