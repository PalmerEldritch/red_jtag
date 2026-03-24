library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bscan_controller is
    generic (
        BSR_LENGTH  : natural := 362;
        IR_LENGTH   : natural := 4
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;

        req_valid       : in  std_logic;
        req_op          : in  std_logic_vector(2 downto 0);
        req_pin_num     : in  unsigned(15 downto 0);
        req_pin_val     : in  std_logic;
        req_bsr_data    : in  std_logic_vector(BSR_LENGTH-1 downto 0);

        busy            : out std_logic;
        done            : out std_logic;
        rsp_bsr_data    : out std_logic_vector(BSR_LENGTH-1 downto 0);
        rsp_pin_val     : out std_logic;

        jtag_req_valid  : out std_logic;
        jtag_req_kind   : out jtag_req_kind_t;
        jtag_req_ir     : out std_logic_vector(7 downto 0);
        jtag_req_dr_len : out unsigned(15 downto 0);
        jtag_req_dr_data: out std_logic_vector(BSR_LENGTH-1 downto 0);

        jtag_busy       : in  std_logic;
        jtag_done       : in  std_logic;
        jtag_rsp_data   : in  std_logic_vector(BSR_LENGTH-1 downto 0)
    );
end entity;