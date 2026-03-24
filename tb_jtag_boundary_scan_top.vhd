library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.jtag_pkg.all;

entity tb_jtag_boundary_scan_top is
end entity;

architecture sim of tb_jtag_boundary_scan_top is

    constant BSR_LENGTH : natural := 18;

    signal ft_data      : std_logic_vector(7 downto 0) := (others => 'Z');
    signal ft_host_data : std_logic_vector(7 downto 0) := (others => 'Z');
    signal ft_rxf_n     : std_logic := '1';
    signal ft_txe_n     : std_logic := '0';
    signal ft_rd_n      : std_logic;
    signal ft_wr_n      : std_logic;
    signal ft_siwu_n    : std_logic;

    signal jtag_tck     : std_logic;
    signal jtag_tms     : std_logic;
    signal jtag_tdi     : std_logic;
    signal jtag_tdo     : std_logic := '1';
    signal led          : std_logic_vector(1 downto 0);

    signal tx_count     : natural := 0;
    signal tx_last_byte : std_logic_vector(7 downto 0) := (others => '0');

begin

    ft_data <= ft_host_data;

    dut: entity work.jtag_boundary_scan_top
        generic map (
            BSR_LENGTH => BSR_LENGTH,
            IR_LENGTH => 4,
            JTAG_DIV_WIDTH => 4,
            JTAG_DIV_VALUE => 0
        )
        port map (
            ft_data => ft_data,
            ft_rxf_n => ft_rxf_n,
            ft_txe_n => ft_txe_n,
            ft_rd_n => ft_rd_n,
            ft_wr_n => ft_wr_n,
            ft_siwu_n => ft_siwu_n,
            jtag_tck => jtag_tck,
            jtag_tms => jtag_tms,
            jtag_tdi => jtag_tdi,
            jtag_tdo => jtag_tdo,
            led => led
        );

    tx_monitor_proc: process
    begin
        loop
            wait until ft_wr_n'event;
            if ft_wr_n = '0' then
                tx_last_byte <= ft_data;
                tx_count <= tx_count + 1;
            end if;
        end loop;
    end process;

    stim_proc: process
        procedure send_host_byte(constant value : in std_logic_vector(7 downto 0)) is
            variable wait_count : natural;
        begin
            ft_host_data <= value;
            ft_rxf_n <= '0';

            wait_count := 0;
            loop
                wait for 10 ns;
                exit when ft_rd_n = '0';
                wait_count := wait_count + 1;
                assert wait_count < 500
                    report "Timeout waiting for ft_rd_n low while sending host byte"
                    severity failure;
            end loop;

            wait_count := 0;
            loop
                wait for 10 ns;
                exit when ft_rd_n = '1';
                wait_count := wait_count + 1;
                assert wait_count < 500
                    report "Timeout waiting for ft_rd_n high while sending host byte"
                    severity failure;
            end loop;

            ft_rxf_n <= '1';
            ft_host_data <= (others => 'Z');
            wait for 50 ns;
        end procedure;

        procedure expect_tx_byte(constant expected : in std_logic_vector(7 downto 0)) is
            variable start_count : natural;
            variable wait_count  : natural;
        begin
            start_count := tx_count;

            wait_count := 0;
            loop
                wait for 10 ns;
                exit when tx_count > start_count;
                wait_count := wait_count + 1;
                assert wait_count < 2000
                    report "Timeout waiting for transmitted byte"
                    severity failure;
            end loop;

            assert tx_last_byte = expected
                report "Unexpected TX byte" severity failure;

            wait_count := 0;
            loop
                wait for 10 ns;
                exit when ft_wr_n = '1';
                wait_count := wait_count + 1;
                assert wait_count < 500
                    report "Timeout waiting for ft_wr_n to return high"
                    severity failure;
            end loop;

            wait for 50 ns;
        end procedure;
    begin
        wait for 5 us;

        assert ft_siwu_n = '0' report "SIWU should be tied low" severity failure;

        send_host_byte(CMD_PING);
        expect_tx_byte(x"55");
        report "PING ok" severity note;

        send_host_byte(CMD_LED);
        send_host_byte(x"02");
        expect_tx_byte(x"00");
        assert led(1) = '1' report "LED command did not update LED output" severity failure;
        report "LED ok" severity note;

        send_host_byte(CMD_SHIFT_DR);
        send_host_byte(x"08");
        send_host_byte(x"00");
        send_host_byte(x"A5");
        expect_tx_byte(x"FF");
        report "SHIFT_DR ok" severity note;

        send_host_byte(CMD_READ_PIN);
        send_host_byte(x"03");
        send_host_byte(x"00");
        expect_tx_byte(x"01");
        report "READ_PIN ok" severity note;

        send_host_byte(CMD_SAMPLE_BSR);
        expect_tx_byte(x"FF");
        expect_tx_byte(x"FF");
        expect_tx_byte(x"03");
        report "SAMPLE_BSR ok" severity note;

        assert false report "tb_jtag_boundary_scan_top completed" severity note;
        wait;
    end process;

end architecture;
