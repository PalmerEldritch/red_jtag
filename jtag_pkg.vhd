library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package jtag_pkg is

    constant MAX_BSR_LENGTH : natural := 1024;
    constant MAX_BSR_BYTES  : natural := (MAX_BSR_LENGTH + 7) / 8;

    -- Host commands
    constant CMD_JTAG_RESET   : std_logic_vector(7 downto 0) := x"10";
    constant CMD_READ_IDCODE  : std_logic_vector(7 downto 0) := x"11";
    constant CMD_LOAD_IR      : std_logic_vector(7 downto 0) := x"12";
    constant CMD_SHIFT_DR     : std_logic_vector(7 downto 0) := x"13";
    constant CMD_SAMPLE_BSR   : std_logic_vector(7 downto 0) := x"14";
    constant CMD_LOAD_BSR     : std_logic_vector(7 downto 0) := x"15";
    constant CMD_SET_PIN      : std_logic_vector(7 downto 0) := x"16";
    constant CMD_READ_PIN     : std_logic_vector(7 downto 0) := x"17";
    constant CMD_READ_TDO     : std_logic_vector(7 downto 0) := x"18";
    constant CMD_TOGGLE_TCK   : std_logic_vector(7 downto 0) := x"19";
    constant CMD_SET_TMS_HI   : std_logic_vector(7 downto 0) := x"1A";
    constant CMD_SET_TMS_LO   : std_logic_vector(7 downto 0) := x"1B";
    constant CMD_I2C_WRITE    : std_logic_vector(7 downto 0) := x"20";
    constant CMD_I2C_READ     : std_logic_vector(7 downto 0) := x"21";
    constant CMD_I2C_WR_RD    : std_logic_vector(7 downto 0) := x"22";
    constant CMD_I2C_SCAN     : std_logic_vector(7 downto 0) := x"23";
    constant CMD_LED          : std_logic_vector(7 downto 0) := x"40";
    constant CMD_PING         : std_logic_vector(7 downto 0) := x"FF";

    type jtag_req_kind_t is (
        JTAG_REQ_NONE,
        JTAG_REQ_RESET,
        JTAG_REQ_SHIFT_IR,
        JTAG_REQ_SHIFT_DR,
        JTAG_REQ_SHIFT_IR_DR,
        JTAG_REQ_TOGGLE_TCK,
        JTAG_REQ_SET_TMS
    );

    type host_req_kind_t is (
        HOST_REQ_NONE,
        HOST_REQ_PING,
        HOST_REQ_LED,
        HOST_REQ_RAW_JTAG_RESET,
        HOST_REQ_RAW_JTAG_LOAD_IR,
        HOST_REQ_RAW_JTAG_SHIFT_DR,
        HOST_REQ_RAW_IDCODE,
        HOST_REQ_BSCAN_SAMPLE,
        HOST_REQ_BSCAN_LOAD,
        HOST_REQ_BSCAN_SET_PIN,
        HOST_REQ_BSCAN_READ_PIN,
        HOST_REQ_DEBUG_READ_TDO,
        HOST_REQ_DEBUG_TOGGLE_TCK,
        HOST_REQ_DEBUG_SET_TMS,
        HOST_REQ_I2C_WRITE,
        HOST_REQ_I2C_READ,
        HOST_REQ_I2C_WR_RD,
        HOST_REQ_I2C_SCAN
    );

    function bytes_for_bits(nbits : natural) return natural;

end package;

package body jtag_pkg is

    function bytes_for_bits(nbits : natural) return natural is
    begin
        return (nbits + 7) / 8;
    end function;

end package body;