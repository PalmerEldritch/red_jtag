library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.jtag_pkg.all;

entity tb_jtag_master is
end entity;

architecture sim of tb_jtag_master is

    constant CLK_PERIOD     : time := 10 ns;
    constant MAX_SHIFT_BITS : natural := 32;
    constant IR_LENGTH      : natural := 4;

    signal clk             : std_logic := '0';
    signal rst_n           : std_logic := '0';

    signal req_valid       : std_logic := '0';
    signal req_kind        : jtag_req_kind_t := JTAG_REQ_NONE;
    signal req_ir          : std_logic_vector(7 downto 0) := (others => '0');
    signal req_dr_len      : unsigned(15 downto 0) := (others => '0');
    signal req_dr_data     : std_logic_vector(MAX_SHIFT_BITS-1 downto 0) := (others => '0');
    signal req_tms_value   : std_logic := '0';
    signal req_tck_edges   : unsigned(15 downto 0) := (others => '0');

    signal busy            : std_logic;
    signal done            : std_logic;
    signal rsp_dr_data     : std_logic_vector(MAX_SHIFT_BITS-1 downto 0);
    signal rsp_dr_len      : unsigned(15 downto 0);

    signal jtag_tck        : std_logic;
    signal jtag_tms        : std_logic;
    signal jtag_tdi        : std_logic;
    signal jtag_tdo        : std_logic := '0';

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut: entity work.jtag_master
        generic map (
            MAX_SHIFT_BITS => MAX_SHIFT_BITS,
            IR_LENGTH => IR_LENGTH,
            JTAG_DIV_WIDTH => 4,
            JTAG_DIV_VALUE => 0
        )
        port map (
            clk => clk,
            rst_n => rst_n,
            req_valid => req_valid,
            req_kind => req_kind,
            req_ir => req_ir,
            req_dr_len => req_dr_len,
            req_dr_data => req_dr_data,
            req_tms_value => req_tms_value,
            req_tck_edges => req_tck_edges,
            busy => busy,
            done => done,
            rsp_dr_data => rsp_dr_data,
            rsp_dr_len => rsp_dr_len,
            jtag_tck => jtag_tck,
            jtag_tms => jtag_tms,
            jtag_tdi => jtag_tdi,
            jtag_tdo => jtag_tdo
        );

    stim_proc: process
        variable tck_before : std_logic;
        variable tck_edges  : natural;
        variable dr_payload : std_logic_vector(MAX_SHIFT_BITS-1 downto 0);

        procedure issue_req(
            constant kind      : in jtag_req_kind_t;
            constant ir_val    : in std_logic_vector(7 downto 0);
            constant dr_len_v  : in natural;
            constant dr_data_v : in std_logic_vector(MAX_SHIFT_BITS-1 downto 0);
            constant tms_val   : in std_logic;
            constant tck_v     : in natural
        ) is
        begin
            wait until rising_edge(clk);
            req_kind <= kind;
            req_ir <= ir_val;
            req_dr_len <= to_unsigned(dr_len_v, req_dr_len'length);
            req_dr_data <= dr_data_v;
            req_tms_value <= tms_val;
            req_tck_edges <= to_unsigned(tck_v, req_tck_edges'length);
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
            assert done = '0' report "done must pulse for exactly one cycle" severity failure;
        end procedure;
    begin
        wait for 3 * CLK_PERIOD;
        rst_n <= '1';
        wait until rising_edge(clk);

        assert busy = '0' report "busy should be low after reset" severity failure;
        assert done = '0' report "done should be low after reset" severity failure;
        assert jtag_tck = '0' report "TCK reset value mismatch" severity failure;
        assert jtag_tms = '1' report "TMS reset value mismatch" severity failure;
        assert jtag_tdi = '0' report "TDI reset value mismatch" severity failure;

        issue_req(JTAG_REQ_SET_TMS, x"00", 0, (others => '0'), '0', 0);
        wait_done;
        assert jtag_tms = '0' report "SET_TMS low failed" severity failure;
        assert rsp_dr_len = 0 report "SET_TMS should clear DR length" severity failure;

        issue_req(JTAG_REQ_SET_TMS, x"00", 0, (others => '0'), '1', 0);
        wait_done;
        assert jtag_tms = '1' report "SET_TMS high failed" severity failure;

        tck_before := jtag_tck;
        tck_edges := 0;
        issue_req(JTAG_REQ_TOGGLE_TCK, x"00", 0, (others => '0'), '0', 5);
        while busy = '0' loop
            wait until rising_edge(clk);
        end loop;
        while busy = '1' loop
            wait until rising_edge(clk);
            if jtag_tck /= tck_before then
                tck_edges := tck_edges + 1;
                tck_before := jtag_tck;
            end if;
        end loop;
        assert tck_edges = 5 report "TOGGLE_TCK edge count mismatch" severity failure;
        assert done = '1' report "TOGGLE_TCK should complete with done pulse" severity failure;
        wait until rising_edge(clk);

        issue_req(JTAG_REQ_RESET, x"00", 0, (others => '0'), '0', 4);
        wait_done;
        assert jtag_tms = '0' report "RESET should finish in Run-Test/Idle" severity failure;

        jtag_tdo <= '1';
        dr_payload := (others => '0');
        dr_payload(3 downto 0) := "1010";
        issue_req(JTAG_REQ_SHIFT_DR, x"00", 4, dr_payload, '0', 0);
        wait_done;
        assert rsp_dr_len = 4 report "SHIFT_DR response length mismatch" severity failure;
        assert rsp_dr_data(3 downto 0) = "1111" report "SHIFT_DR capture mismatch" severity failure;

        jtag_tdo <= '0';
        issue_req(JTAG_REQ_SHIFT_IR, x"05", 0, (others => '0'), '0', 0);
        wait_done;
        assert jtag_tms = '0' report "SHIFT_IR should return to idle" severity failure;

        dr_payload := (others => '0');
        dr_payload(3 downto 0) := "1100";
        jtag_tdo <= '1';
        issue_req(JTAG_REQ_SHIFT_IR_DR, x"03", 4, dr_payload, '0', 0);
        wait_done;
        assert rsp_dr_len = 4 report "SHIFT_IR_DR response length mismatch" severity failure;
        assert jtag_tms = '0' report "SHIFT_IR_DR should finish in idle" severity failure;

        jtag_tdo <= '0';
        issue_req(JTAG_REQ_SHIFT_DR, x"00", 0, (others => '0'), '0', 0);
        wait_done;
        assert rsp_dr_len = 0 report "Zero-length DR should report zero length" severity failure;

        issue_req(JTAG_REQ_TOGGLE_TCK, x"00", 0, (others => '0'), '0', 0);
        wait_done;

        issue_req(JTAG_REQ_TOGGLE_TCK, x"00", 0, (others => '0'), '0', 6);
        while busy = '0' loop
            wait until rising_edge(clk);
        end loop;
        req_kind <= JTAG_REQ_SET_TMS;
        req_tms_value <= '0';
        req_valid <= '1';
        wait until rising_edge(clk);
        req_valid <= '0';
        wait_done;
        assert busy = '0' report "busy should be low after completed operation" severity failure;

        assert false report "tb_jtag_master completed" severity note;
        wait;
    end process;

end architecture;
