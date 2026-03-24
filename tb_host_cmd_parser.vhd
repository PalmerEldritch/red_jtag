library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.jtag_pkg.all;

entity tb_host_cmd_parser is
end entity;

architecture sim of tb_host_cmd_parser is
    constant CLK_PERIOD : time := 10 ns;
    constant MAX_IR_BITS : natural := 24;
    constant MAX_DR_BITS : natural := 32;
    constant LEGACY_BSR_LENGTH : natural := 18;

    signal clk          : std_logic := '0';
    signal rst_n        : std_logic := '0';
    signal rx_valid     : std_logic := '0';
    signal rx_data      : std_logic_vector(7 downto 0) := (others => '0');
    signal req_valid    : std_logic;
    signal req_kind     : host_req_kind_t;
    signal req_byte     : std_logic_vector(7 downto 0);
    signal req_word     : unsigned(15 downto 0);
    signal req_ir_len   : unsigned(15 downto 0);
    signal req_ir_data  : std_logic_vector(MAX_IR_BITS-1 downto 0);
    signal req_dr_len   : unsigned(15 downto 0);
    signal req_dr_data  : std_logic_vector(MAX_DR_BITS-1 downto 0);
    signal req_pin_num  : unsigned(15 downto 0);
    signal req_pin_val  : std_logic;
    signal busy         : std_logic := '0';
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut: entity work.host_cmd_parser
        generic map (
            LEGACY_BSR_LENGTH => LEGACY_BSR_LENGTH,
            MAX_IR_BITS => MAX_IR_BITS,
            MAX_DR_BITS => MAX_DR_BITS
        )
        port map (
            clk => clk,
            rst_n => rst_n,
            rx_valid => rx_valid,
            rx_data => rx_data,
            req_valid => req_valid,
            req_kind => req_kind,
            req_byte => req_byte,
            req_word => req_word,
            req_ir_len => req_ir_len,
            req_ir_data => req_ir_data,
            req_dr_len => req_dr_len,
            req_dr_data => req_dr_data,
            req_pin_num => req_pin_num,
            req_pin_val => req_pin_val,
            busy => busy
        );

    stim_proc: process
        procedure send_byte(constant value : in std_logic_vector(7 downto 0)) is
        begin
            wait until rising_edge(clk);
            rx_data <= value;
            rx_valid <= '1';
            wait until rising_edge(clk);
            rx_valid <= '0';
        end procedure;

        procedure wait_req is
        begin
            loop
                wait until rising_edge(clk);
                exit when req_valid = '1';
            end loop;
            wait until rising_edge(clk);
            assert req_valid = '0' report "req_valid must pulse for one cycle" severity failure;
        end procedure;
    begin
        wait for 3 * CLK_PERIOD;
        rst_n <= '1';
        wait until rising_edge(clk);

        send_byte(CMD_PING);
        wait_req;
        assert req_kind = HOST_REQ_PING report "PING decode mismatch" severity failure;

        send_byte(CMD_LOAD_IR);
        send_byte(x"5A");
        wait_req;
        assert req_kind = HOST_REQ_RAW_JTAG_SHIFT_IR report "legacy LOAD_IR kind mismatch" severity failure;
        assert req_ir_len = to_unsigned(8, 16) report "legacy LOAD_IR length mismatch" severity failure;
        assert req_ir_data(7 downto 0) = x"5A" report "legacy LOAD_IR data mismatch" severity failure;

        send_byte(CMD_SHIFT_IR_EX);
        send_byte(x"0C");
        send_byte(x"00");
        send_byte(x"A5");
        send_byte(x"03");
        wait_req;
        assert req_kind = HOST_REQ_RAW_JTAG_SHIFT_IR report "SHIFT_IR_EX kind mismatch" severity failure;
        assert req_ir_len = to_unsigned(12, 16) report "SHIFT_IR_EX length mismatch" severity failure;
        assert req_ir_data(7 downto 0) = x"A5" report "SHIFT_IR_EX byte 0 mismatch" severity failure;
        assert req_ir_data(11 downto 8) = "0011" report "SHIFT_IR_EX byte 1 low nibble mismatch" severity failure;

        send_byte(CMD_SHIFT_IR_DR_EX);
        send_byte(x"09");
        send_byte(x"00");
        send_byte(x"0C");
        send_byte(x"00");
        send_byte(x"55");
        send_byte(x"01");
        send_byte(x"A5");
        send_byte(x"03");
        wait_req;
        assert req_kind = HOST_REQ_RAW_JTAG_SHIFT_IR_DR report "SHIFT_IR_DR_EX kind mismatch" severity failure;
        assert req_ir_len = to_unsigned(9, 16) report "SHIFT_IR_DR_EX IR length mismatch" severity failure;
        assert req_dr_len = to_unsigned(12, 16) report "SHIFT_IR_DR_EX DR length mismatch" severity failure;

        send_byte(CMD_BSCAN_SET_PIN_EX);
        send_byte(x"08");
        send_byte(x"00");
        send_byte(x"12");
        send_byte(x"00");
        send_byte(x"11");
        send_byte(x"00");
        send_byte(x"01");
        send_byte(x"0F");
        wait_req;
        assert req_kind = HOST_REQ_BSCAN_SET_PIN_EX report "BSCAN_SET_PIN_EX kind mismatch" severity failure;
        assert req_ir_len = to_unsigned(8, 16) report "BSCAN_SET_PIN_EX IR length mismatch" severity failure;
        assert req_dr_len = to_unsigned(18, 16) report "BSCAN_SET_PIN_EX DR length mismatch" severity failure;
        assert req_pin_num = to_unsigned(16#0011#, 16) report "BSCAN_SET_PIN_EX pin index mismatch" severity failure;
        assert req_pin_val = '1' report "BSCAN_SET_PIN_EX pin value mismatch" severity failure;
        assert req_ir_data(7 downto 0) = x"0F" report "BSCAN_SET_PIN_EX IR data mismatch" severity failure;

        busy <= '1';
        send_byte(CMD_LED);
        send_byte(x"02");
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        assert req_valid = '0' report "Request should be held while busy is high" severity failure;
        busy <= '0';
        wait_req;
        assert req_kind = HOST_REQ_LED report "LED kind mismatch" severity failure;
        assert req_byte = x"02" report "LED payload mismatch" severity failure;

        assert false report "tb_host_cmd_parser completed" severity note;
        wait;
    end process;
end architecture;
