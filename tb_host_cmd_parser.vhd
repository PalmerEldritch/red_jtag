library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.jtag_pkg.all;

entity tb_host_cmd_parser is
end entity;

architecture sim of tb_host_cmd_parser is

    constant CLK_PERIOD : time := 10 ns;
    constant BSR_LENGTH : natural := 18;

    signal clk          : std_logic := '0';
    signal rst_n        : std_logic := '0';

    signal rx_valid     : std_logic := '0';
    signal rx_data      : std_logic_vector(7 downto 0) := (others => '0');
    signal req_valid    : std_logic;
    signal req_kind     : host_req_kind_t;
    signal req_byte     : std_logic_vector(7 downto 0);
    signal req_word     : unsigned(15 downto 0);
    signal req_data     : std_logic_vector(BSR_LENGTH-1 downto 0);
    signal req_data_len : unsigned(15 downto 0);
    signal busy         : std_logic := '0';

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut: entity work.host_cmd_parser
        generic map (
            BSR_LENGTH => BSR_LENGTH
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
            req_data => req_data,
            req_data_len => req_data_len,
            busy => busy
        );

    stim_proc: process
        variable expected_data : std_logic_vector(BSR_LENGTH-1 downto 0);

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
        assert req_kind = HOST_REQ_RAW_JTAG_LOAD_IR report "LOAD_IR kind mismatch" severity failure;
        assert req_byte = x"5A" report "LOAD_IR data mismatch" severity failure;

        send_byte(CMD_SHIFT_DR);
        send_byte(x"0C");
        send_byte(x"00");
        send_byte(x"A5");
        send_byte(x"03");
        wait_req;
        assert req_kind = HOST_REQ_RAW_JTAG_SHIFT_DR report "SHIFT_DR kind mismatch" severity failure;
        assert req_data_len = to_unsigned(12, req_data_len'length) report "SHIFT_DR length mismatch" severity failure;
        assert req_data(7 downto 0) = x"A5" report "SHIFT_DR byte 0 mismatch" severity failure;
        assert req_data(11 downto 8) = "0011" report "SHIFT_DR byte 1 low nibble mismatch" severity failure;

        send_byte(CMD_SET_PIN);
        send_byte(x"11");
        send_byte(x"00");
        send_byte(x"01");
        wait_req;
        assert req_kind = HOST_REQ_BSCAN_SET_PIN report "SET_PIN kind mismatch" severity failure;
        assert req_word = to_unsigned(16#0011#, req_word'length) report "SET_PIN pin index mismatch" severity failure;
        assert req_byte(0) = '1' report "SET_PIN value mismatch" severity failure;

        send_byte(CMD_READ_PIN);
        send_byte(x"04");
        send_byte(x"01");
        wait_req;
        assert req_kind = HOST_REQ_BSCAN_READ_PIN report "READ_PIN kind mismatch" severity failure;
        assert req_word = to_unsigned(16#0104#, req_word'length) report "READ_PIN pin index mismatch" severity failure;

        expected_data := (others => '0');
        send_byte(CMD_LOAD_BSR);
        send_byte(x"12");
        send_byte(x"34");
        send_byte(x"03");
        wait_req;
        expected_data(7 downto 0) := x"12";
        expected_data(15 downto 8) := x"34";
        expected_data(17 downto 16) := "11";
        assert req_kind = HOST_REQ_BSCAN_LOAD report "LOAD_BSR kind mismatch" severity failure;
        assert req_data_len = to_unsigned(BSR_LENGTH, req_data_len'length) report "LOAD_BSR length mismatch" severity failure;
        assert req_data = expected_data report "LOAD_BSR data mismatch" severity failure;

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
