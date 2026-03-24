library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.jtag_pkg.all;

entity tb_bscan_controller is
end entity;

architecture sim of tb_bscan_controller is

    constant CLK_PERIOD : time := 10 ns;
    constant BSR_LENGTH : natural := 18;

    constant BSCAN_OP_SAMPLE   : std_logic_vector(2 downto 0) := "000";
    constant BSCAN_OP_LOAD     : std_logic_vector(2 downto 0) := "001";
    constant BSCAN_OP_SET_PIN  : std_logic_vector(2 downto 0) := "010";
    constant BSCAN_OP_READ_PIN : std_logic_vector(2 downto 0) := "011";

    signal clk              : std_logic := '0';
    signal rst_n            : std_logic := '0';

    signal req_valid        : std_logic := '0';
    signal req_op           : std_logic_vector(2 downto 0) := (others => '0');
    signal req_pin_num      : unsigned(15 downto 0) := (others => '0');
    signal req_pin_val      : std_logic := '0';
    signal req_bsr_data     : std_logic_vector(BSR_LENGTH-1 downto 0) := (others => '0');

    signal busy             : std_logic;
    signal done             : std_logic;
    signal rsp_bsr_data     : std_logic_vector(BSR_LENGTH-1 downto 0);
    signal rsp_pin_val      : std_logic;

    signal jtag_req_valid   : std_logic;
    signal jtag_req_kind    : jtag_req_kind_t;
    signal jtag_req_ir      : std_logic_vector(7 downto 0);
    signal jtag_req_dr_len  : unsigned(15 downto 0);
    signal jtag_req_dr_data : std_logic_vector(BSR_LENGTH-1 downto 0);
    signal jtag_busy        : std_logic := '0';
    signal jtag_done        : std_logic := '0';
    signal jtag_rsp_data    : std_logic_vector(BSR_LENGTH-1 downto 0) := (others => '0');

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut: entity work.bscan_controller
        generic map (
            BSR_LENGTH => BSR_LENGTH,
            IR_LENGTH => 4
        )
        port map (
            clk => clk,
            rst_n => rst_n,
            req_valid => req_valid,
            req_op => req_op,
            req_pin_num => req_pin_num,
            req_pin_val => req_pin_val,
            req_bsr_data => req_bsr_data,
            busy => busy,
            done => done,
            rsp_bsr_data => rsp_bsr_data,
            rsp_pin_val => rsp_pin_val,
            jtag_req_valid => jtag_req_valid,
            jtag_req_kind => jtag_req_kind,
            jtag_req_ir => jtag_req_ir,
            jtag_req_dr_len => jtag_req_dr_len,
            jtag_req_dr_data => jtag_req_dr_data,
            jtag_busy => jtag_busy,
            jtag_done => jtag_done,
            jtag_rsp_data => jtag_rsp_data
        );

    mock_jtag_proc: process
    begin
        loop
            wait until rising_edge(clk);
            jtag_done <= '0';

            if jtag_req_valid = '1' then
                jtag_busy <= '1';
                wait until rising_edge(clk);
                wait until rising_edge(clk);
                jtag_busy <= '0';
                jtag_done <= '1';
            end if;
        end loop;
    end process;

    stim_proc: process
        variable expected_shadow : std_logic_vector(BSR_LENGTH-1 downto 0);

        procedure issue_req(
            constant op      : in std_logic_vector(2 downto 0);
            constant pin_num : in natural;
            constant pin_val : in std_logic;
            constant bsr_val : in std_logic_vector(BSR_LENGTH-1 downto 0)
        ) is
        begin
            wait until rising_edge(clk);
            req_op <= op;
            req_pin_num <= to_unsigned(pin_num, req_pin_num'length);
            req_pin_val <= pin_val;
            req_bsr_data <= bsr_val;
            req_valid <= '1';
            wait until rising_edge(clk);
            req_valid <= '0';
        end procedure;

        procedure wait_done is
        begin
            loop
                wait until rising_edge(clk);
                exit when done = '1';
            end loop;
            wait until rising_edge(clk);
            assert done = '0' report "done must pulse for one cycle" severity failure;
        end procedure;
    begin
        wait for 3 * CLK_PERIOD;
        rst_n <= '1';
        wait until rising_edge(clk);

        assert busy = '0' report "busy should idle low" severity failure;

        jtag_rsp_data <= (others => '0');
        jtag_rsp_data(5) <= '1';
        issue_req(BSCAN_OP_SAMPLE, 0, '0', (others => '0'));
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        assert jtag_req_valid = '1' report "sample should launch a JTAG request" severity failure;
        assert jtag_req_kind = JTAG_REQ_SHIFT_IR_DR report "sample should use combined IR/DR shift" severity failure;
        assert jtag_req_ir = x"05" report "sample should use SAMPLE instruction" severity failure;
        wait_done;
        assert rsp_bsr_data(5) = '1' report "sample response mismatch" severity failure;

        expected_shadow := (others => '0');
        expected_shadow(7 downto 0) := x"5A";
        expected_shadow(15 downto 8) := x"01";
        jtag_rsp_data <= expected_shadow;
        issue_req(BSCAN_OP_LOAD, 0, '0', expected_shadow);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        assert jtag_req_ir = x"00" report "load should use EXTEST instruction" severity failure;
        assert jtag_req_dr_data = expected_shadow report "load should shift supplied BSR data" severity failure;
        wait_done;
        assert rsp_bsr_data = expected_shadow report "load response mismatch" severity failure;

        expected_shadow := (others => '0');
        expected_shadow(7 downto 0) := x"5A";
        expected_shadow(15 downto 8) := x"01";
        expected_shadow(3) := '1';
        jtag_rsp_data <= expected_shadow;
        issue_req(BSCAN_OP_SET_PIN, 3, '1', (others => '0'));
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        assert jtag_req_dr_data(3) = '1' report "set_pin should update the shadow bit before shifting" severity failure;
        wait_done;
        assert rsp_bsr_data = expected_shadow report "set_pin response mismatch" severity failure;

        jtag_rsp_data <= (others => '0');
        jtag_rsp_data(9) <= '1';
        issue_req(BSCAN_OP_READ_PIN, 9, '0', (others => '0'));
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        assert jtag_req_ir = x"05" report "read_pin should use SAMPLE instruction" severity failure;
        wait_done;
        assert rsp_pin_val = '1' report "read_pin should return the sampled bit" severity failure;

        assert false report "tb_bscan_controller completed" severity note;
        wait;
    end process;

end architecture;
