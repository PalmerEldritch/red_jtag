library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.jtag_pkg.all;

entity jtag_boundary_scan_top is
    generic (
        BSR_LENGTH      : natural := 362;
        MAX_IR_BITS     : natural := MAX_IR_LENGTH;
        IR_LENGTH       : natural := 4;
        JTAG_DIV_WIDTH  : natural := 8;
        JTAG_DIV_VALUE  : natural := 255;
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

architecture rtl of jtag_boundary_scan_top is

    function max_nat(a : natural; b : natural) return natural is
    begin
        if a > b then
            return a;
        end if;
        return b;
    end function;

    component OSCA
        generic (HF_CLK_DIV : string := "8");
        port (
            HFOUTEN  : in  std_logic;
            HFSDSCEN : in  std_logic;
            HFCLKOUT : out std_logic
        );
    end component;

    constant MAX_RESP_BITS    : natural := max_nat(BSR_LENGTH, 128);

    type exec_state_t is (
        ST_IDLE,
        ST_WAIT_JTAG,
        ST_WAIT_BSCAN,
        ST_SEND_RESPONSE,
        ST_SEND_WAIT_ACCEPT,
        ST_SEND_WAIT_RELEASE
    );

    signal clk               : std_logic;
    signal rst_cnt           : unsigned(7 downto 0) := (others => '0');
    signal rst_done          : std_logic := '0';
    signal rst_n_int         : std_logic := '0';
    signal hb_cnt            : unsigned(25 downto 0) := (others => '0');
    signal led_reg           : std_logic_vector(1 downto 0) := (others => '0');

    signal ft_rx_valid       : std_logic;
    signal ft_rx_data        : std_logic_vector(7 downto 0);
    signal ft_tx_valid       : std_logic := '0';
    signal ft_tx_data        : std_logic_vector(7 downto 0) := (others => '0');
    signal ft_tx_ready       : std_logic;
    signal ft_rd_n_int       : std_logic;
    signal ft_wr_n_int       : std_logic;
    signal ft_siwu_n_int     : std_logic;

    signal parser_req_valid  : std_logic;
    signal parser_req_kind   : host_req_kind_t;
    signal parser_req_byte   : std_logic_vector(7 downto 0);
    signal parser_req_word   : unsigned(15 downto 0);
    signal parser_req_ir_len : unsigned(15 downto 0);
    signal parser_req_ir_data: std_logic_vector(MAX_IR_BITS-1 downto 0);
    signal parser_req_dr_len : unsigned(15 downto 0);
    signal parser_req_dr_data: std_logic_vector(BSR_LENGTH-1 downto 0);
    signal parser_req_pin_num: unsigned(15 downto 0);
    signal parser_req_pin_val: std_logic;
    signal parser_busy       : std_logic;

    signal raw_jtag_req_valid   : std_logic := '0';
    signal raw_jtag_req_kind    : jtag_req_kind_t := JTAG_REQ_NONE;
    signal raw_jtag_req_ir_len  : unsigned(15 downto 0) := (others => '0');
    signal raw_jtag_req_ir      : std_logic_vector(MAX_IR_BITS-1 downto 0) := (others => '0');
    signal raw_jtag_req_dr_len  : unsigned(15 downto 0) := (others => '0');
    signal raw_jtag_req_dr_data : std_logic_vector(BSR_LENGTH-1 downto 0) := (others => '0');
    signal raw_jtag_req_tms     : std_logic := '0';
    signal raw_jtag_req_edges   : unsigned(15 downto 0) := (others => '0');

    signal jtag_req_valid    : std_logic;
    signal jtag_req_kind     : jtag_req_kind_t;
    signal jtag_req_ir_len   : unsigned(15 downto 0);
    signal jtag_req_ir       : std_logic_vector(MAX_IR_BITS-1 downto 0);
    signal jtag_req_dr_len   : unsigned(15 downto 0);
    signal jtag_req_dr_data  : std_logic_vector(BSR_LENGTH-1 downto 0);
    signal jtag_req_tms      : std_logic;
    signal jtag_req_edges    : unsigned(15 downto 0);
    signal jtag_busy         : std_logic;
    signal jtag_done         : std_logic;
    signal jtag_rsp_data     : std_logic_vector(BSR_LENGTH-1 downto 0);
    signal jtag_rsp_len      : unsigned(15 downto 0);

    signal bscan_req_valid   : std_logic := '0';
    signal bscan_req_kind    : bscan_req_kind_t := BSCAN_REQ_NONE;
    signal bscan_req_ir_len  : unsigned(15 downto 0) := (others => '0');
    signal bscan_req_sample_ir : std_logic_vector(MAX_IR_BITS-1 downto 0) := (others => '0');
    signal bscan_req_extest_ir : std_logic_vector(MAX_IR_BITS-1 downto 0) := (others => '0');
    signal bscan_req_dr_len  : unsigned(15 downto 0) := (others => '0');
    signal bscan_req_pin_num : unsigned(15 downto 0) := (others => '0');
    signal bscan_req_pin_val : std_logic := '0';
    signal bscan_req_data    : std_logic_vector(BSR_LENGTH-1 downto 0) := (others => '0');
    signal bscan_busy        : std_logic;
    signal bscan_done        : std_logic;
    signal bscan_rsp_data    : std_logic_vector(BSR_LENGTH-1 downto 0);
    signal bscan_rsp_pin     : std_logic;
    signal bscan_jtag_req_valid : std_logic;
    signal bscan_jtag_req_kind  : jtag_req_kind_t;
    signal bscan_jtag_req_ir_len: unsigned(15 downto 0);
    signal bscan_jtag_req_ir    : std_logic_vector(MAX_IR_BITS-1 downto 0);
    signal bscan_jtag_req_dr_len: unsigned(15 downto 0);
    signal bscan_jtag_req_data  : std_logic_vector(BSR_LENGTH-1 downto 0);

    signal state             : exec_state_t := ST_IDLE;
    signal active_req_kind   : host_req_kind_t := HOST_REQ_NONE;

    signal resp_buf          : std_logic_vector(MAX_RESP_BITS-1 downto 0) := (others => '0');
    signal resp_len          : unsigned(7 downto 0) := (others => '0');
    signal resp_idx          : unsigned(7 downto 0) := (others => '0');
    signal resp_last_byte    : std_logic := '0';

begin

    led(0) <= hb_cnt(22) when led_reg(0) = '0' else '1';
    led(1) <= '1' when led_reg(1) = '0' else '0';

    parser_busy <= '1' when state /= ST_IDLE else '0';
    jtag_req_valid <= bscan_jtag_req_valid when state = ST_WAIT_BSCAN else raw_jtag_req_valid;
    jtag_req_kind <= bscan_jtag_req_kind when state = ST_WAIT_BSCAN else raw_jtag_req_kind;
    jtag_req_ir_len <= bscan_jtag_req_ir_len when state = ST_WAIT_BSCAN else raw_jtag_req_ir_len;
    jtag_req_ir <= bscan_jtag_req_ir when state = ST_WAIT_BSCAN else raw_jtag_req_ir;
    jtag_req_dr_len <= bscan_jtag_req_dr_len when state = ST_WAIT_BSCAN else raw_jtag_req_dr_len;
    jtag_req_dr_data <= bscan_jtag_req_data when state = ST_WAIT_BSCAN else raw_jtag_req_dr_data;
    jtag_req_tms <= '0' when state = ST_WAIT_BSCAN else raw_jtag_req_tms;
    jtag_req_edges <= (others => '0') when state = ST_WAIT_BSCAN else raw_jtag_req_edges;
    ft_rd_n <= ft_rd_n_int;
    ft_wr_n <= ft_wr_n_int;
    ft_siwu_n <= ft_siwu_n_int;

    u_osc: OSCA
        generic map (HF_CLK_DIV => "8")
        port map (
            HFOUTEN => '1',
            HFSDSCEN => '0',
            HFCLKOUT => clk
        );

    u_ft245: entity work.ft245_sync_if
        port map (
            clk => clk,
            rst_n => rst_n_int,
            ft_data => ft_data,
            ft_rxf_n => ft_rxf_n,
            ft_txe_n => ft_txe_n,
            ft_rd_n => ft_rd_n_int,
            ft_wr_n => ft_wr_n_int,
            ft_siwu_n => ft_siwu_n_int,
            rx_valid => ft_rx_valid,
            rx_data => ft_rx_data,
            tx_valid => ft_tx_valid,
            tx_data => ft_tx_data,
            tx_ready => ft_tx_ready
        );

    u_parser: entity work.host_cmd_parser
        generic map (
            LEGACY_BSR_LENGTH => BSR_LENGTH,
            MAX_IR_BITS => MAX_IR_BITS,
            MAX_DR_BITS => BSR_LENGTH
        )
        port map (
            clk => clk,
            rst_n => rst_n_int,
            rx_valid => ft_rx_valid,
            rx_data => ft_rx_data,
            req_valid => parser_req_valid,
            req_kind => parser_req_kind,
            req_byte => parser_req_byte,
            req_word => parser_req_word,
            req_ir_len => parser_req_ir_len,
            req_ir_data => parser_req_ir_data,
            req_dr_len => parser_req_dr_len,
            req_dr_data => parser_req_dr_data,
            req_pin_num => parser_req_pin_num,
            req_pin_val => parser_req_pin_val,
            busy => parser_busy
        );

    u_jtag: entity work.jtag_master
        generic map (
            MAX_SHIFT_BITS => BSR_LENGTH,
            MAX_IR_BITS => MAX_IR_BITS,
            IR_LENGTH => IR_LENGTH,
            JTAG_DIV_WIDTH => JTAG_DIV_WIDTH,
            JTAG_DIV_VALUE => JTAG_DIV_VALUE
        )
        port map (
            clk => clk,
            rst_n => rst_n_int,
            req_valid => jtag_req_valid,
            req_kind => jtag_req_kind,
            req_ir_len => jtag_req_ir_len,
            req_ir_data => jtag_req_ir,
            req_dr_len => jtag_req_dr_len,
            req_dr_data => jtag_req_dr_data,
            req_tms_value => jtag_req_tms,
            req_tck_edges => jtag_req_edges,
            busy => jtag_busy,
            done => jtag_done,
            rsp_dr_data => jtag_rsp_data,
            rsp_dr_len => jtag_rsp_len,
            jtag_tck => jtag_tck,
            jtag_tms => jtag_tms,
            jtag_tdi => jtag_tdi,
            jtag_tdo => jtag_tdo
        );

    u_bscan: entity work.bscan_controller
        generic map (
            MAX_DR_BITS => BSR_LENGTH,
            MAX_IR_BITS => MAX_IR_BITS
        )
        port map (
            clk => clk,
            rst_n => rst_n_int,
            req_valid => bscan_req_valid,
            req_kind => bscan_req_kind,
            req_ir_len => bscan_req_ir_len,
            req_sample_ir => bscan_req_sample_ir,
            req_extest_ir => bscan_req_extest_ir,
            req_dr_len => bscan_req_dr_len,
            req_pin_num => bscan_req_pin_num,
            req_pin_val => bscan_req_pin_val,
            req_dr_data => bscan_req_data,
            busy => bscan_busy,
            done => bscan_done,
            rsp_dr_data => bscan_rsp_data,
            rsp_pin_val => bscan_rsp_pin,
            jtag_req_valid => bscan_jtag_req_valid,
            jtag_req_kind => bscan_jtag_req_kind,
            jtag_req_ir_len => bscan_jtag_req_ir_len,
            jtag_req_ir_data => bscan_jtag_req_ir,
            jtag_req_dr_len => bscan_jtag_req_dr_len,
            jtag_req_dr_data => bscan_jtag_req_data,
            jtag_busy => jtag_busy,
            jtag_done => jtag_done,
            jtag_rsp_data => jtag_rsp_data
        );

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_done = '0' then
                if rst_cnt = 255 then
                    rst_done <= '1';
                else
                    rst_cnt <= rst_cnt + 1;
                end if;
            end if;
            hb_cnt <= hb_cnt + 1;
        end if;
    end process;

    process(clk)
        variable byte_idx : integer;
        variable i2c_rd_len : natural;
    begin
        if rising_edge(clk) then
            ft_tx_valid <= '0';
            raw_jtag_req_valid <= '0';
            bscan_req_valid <= '0';

            if rst_n_int = '0' then
                led_reg <= (others => '0');
                state <= ST_IDLE;
                active_req_kind <= HOST_REQ_NONE;
                resp_buf <= (others => '0');
                resp_len <= (others => '0');
                resp_idx <= (others => '0');
                resp_last_byte <= '0';
                raw_jtag_req_kind <= JTAG_REQ_NONE;
                raw_jtag_req_ir_len <= (others => '0');
                raw_jtag_req_ir <= (others => '0');
                raw_jtag_req_dr_len <= (others => '0');
                raw_jtag_req_dr_data <= (others => '0');
                raw_jtag_req_tms <= '0';
                raw_jtag_req_edges <= (others => '0');
                bscan_req_kind <= BSCAN_REQ_NONE;
                bscan_req_ir_len <= (others => '0');
                bscan_req_sample_ir <= (others => '0');
                bscan_req_extest_ir <= (others => '0');
                bscan_req_dr_len <= (others => '0');
                bscan_req_pin_num <= (others => '0');
                bscan_req_pin_val <= '0';
                bscan_req_data <= (others => '0');
            else
                case state is
                    when ST_IDLE =>
                        if parser_req_valid = '1' then
                            active_req_kind <= parser_req_kind;

                            case parser_req_kind is
                                when HOST_REQ_PING =>
                                    resp_buf <= (others => '0');
                                    resp_buf(7 downto 0) <= x"55";
                                    resp_len <= to_unsigned(1, resp_len'length);
                                    resp_idx <= (others => '0');
                                    resp_last_byte <= '0';
                                    state <= ST_SEND_RESPONSE;

                                when HOST_REQ_LED =>
                                    led_reg <= parser_req_byte(1 downto 0);
                                    resp_buf <= (others => '0');
                                    resp_buf(7 downto 0) <= x"00";
                                    resp_len <= to_unsigned(1, resp_len'length);
                                    resp_idx <= (others => '0');
                                    resp_last_byte <= '0';
                                    state <= ST_SEND_RESPONSE;

                                when HOST_REQ_DEBUG_READ_TDO =>
                                    resp_buf <= (others => '0');
                                    resp_buf(0) <= jtag_tdo;
                                    resp_len <= to_unsigned(1, resp_len'length);
                                    resp_idx <= (others => '0');
                                    resp_last_byte <= '0';
                                    state <= ST_SEND_RESPONSE;

                                when HOST_REQ_DEBUG_SET_TMS =>
                                    raw_jtag_req_kind <= JTAG_REQ_SET_TMS;
                                    raw_jtag_req_ir_len <= (others => '0');
                                    raw_jtag_req_ir <= (others => '0');
                                    raw_jtag_req_dr_len <= (others => '0');
                                    raw_jtag_req_dr_data <= (others => '0');
                                    raw_jtag_req_tms <= parser_req_byte(0);
                                    raw_jtag_req_edges <= (others => '0');
                                    raw_jtag_req_valid <= '1';
                                    state <= ST_WAIT_JTAG;

                                when HOST_REQ_DEBUG_TOGGLE_TCK =>
                                    raw_jtag_req_kind <= JTAG_REQ_TOGGLE_TCK;
                                    raw_jtag_req_ir_len <= (others => '0');
                                    raw_jtag_req_ir <= (others => '0');
                                    raw_jtag_req_dr_len <= (others => '0');
                                    raw_jtag_req_dr_data <= (others => '0');
                                    raw_jtag_req_tms <= '0';
                                    raw_jtag_req_edges <= parser_req_word;
                                    raw_jtag_req_valid <= '1';
                                    state <= ST_WAIT_JTAG;

                                when HOST_REQ_RAW_JTAG_RESET =>
                                    raw_jtag_req_kind <= JTAG_REQ_RESET;
                                    raw_jtag_req_ir_len <= (others => '0');
                                    raw_jtag_req_ir <= (others => '0');
                                    raw_jtag_req_dr_len <= (others => '0');
                                    raw_jtag_req_dr_data <= (others => '0');
                                    raw_jtag_req_tms <= '0';
                                    raw_jtag_req_edges <= parser_req_word;
                                    raw_jtag_req_valid <= '1';
                                    state <= ST_WAIT_JTAG;

                                when HOST_REQ_RAW_JTAG_SHIFT_IR =>
                                    raw_jtag_req_kind <= JTAG_REQ_SHIFT_IR;
                                    raw_jtag_req_ir_len <= parser_req_ir_len;
                                    raw_jtag_req_ir <= parser_req_ir_data;
                                    raw_jtag_req_dr_len <= (others => '0');
                                    raw_jtag_req_dr_data <= (others => '0');
                                    raw_jtag_req_tms <= '0';
                                    raw_jtag_req_edges <= (others => '0');
                                    raw_jtag_req_valid <= '1';
                                    state <= ST_WAIT_JTAG;

                                when HOST_REQ_RAW_JTAG_SHIFT_DR =>
                                    raw_jtag_req_kind <= JTAG_REQ_SHIFT_DR;
                                    raw_jtag_req_ir_len <= (others => '0');
                                    raw_jtag_req_ir <= (others => '0');
                                    raw_jtag_req_dr_len <= parser_req_dr_len;
                                    raw_jtag_req_dr_data <= parser_req_dr_data;
                                    raw_jtag_req_tms <= '0';
                                    raw_jtag_req_edges <= (others => '0');
                                    raw_jtag_req_valid <= '1';
                                    state <= ST_WAIT_JTAG;

                                when HOST_REQ_RAW_JTAG_SHIFT_IR_DR =>
                                    raw_jtag_req_kind <= JTAG_REQ_SHIFT_IR_DR;
                                    raw_jtag_req_ir_len <= parser_req_ir_len;
                                    raw_jtag_req_ir <= parser_req_ir_data;
                                    raw_jtag_req_dr_len <= parser_req_dr_len;
                                    raw_jtag_req_dr_data <= parser_req_dr_data;
                                    raw_jtag_req_tms <= '0';
                                    raw_jtag_req_edges <= (others => '0');
                                    raw_jtag_req_valid <= '1';
                                    state <= ST_WAIT_JTAG;

                                when HOST_REQ_RAW_IDCODE =>
                                    raw_jtag_req_kind <= JTAG_REQ_SHIFT_IR_DR;
                                    raw_jtag_req_ir_len <= to_unsigned(8, 16);
                                    raw_jtag_req_ir <= (others => '0');
                                    raw_jtag_req_ir(7 downto 0) <= x"02";
                                    raw_jtag_req_dr_len <= to_unsigned(32, 16);
                                    raw_jtag_req_dr_data <= (others => '0');
                                    raw_jtag_req_tms <= '0';
                                    raw_jtag_req_edges <= (others => '0');
                                    raw_jtag_req_valid <= '1';
                                    state <= ST_WAIT_JTAG;

                                when HOST_REQ_BSCAN_SAMPLE =>
                                    bscan_req_kind <= BSCAN_REQ_SAMPLE;
                                    bscan_req_ir_len <= to_unsigned(IR_LENGTH, 16);
                                    bscan_req_sample_ir <= (others => '0');
                                    bscan_req_sample_ir(7 downto 0) <= x"05";
                                    bscan_req_extest_ir <= (others => '0');
                                    bscan_req_dr_len <= to_unsigned(BSR_LENGTH, 16);
                                    bscan_req_pin_num <= (others => '0');
                                    bscan_req_pin_val <= '0';
                                    bscan_req_data <= (others => '0');
                                    bscan_req_valid <= '1';
                                    state <= ST_WAIT_BSCAN;

                                when HOST_REQ_BSCAN_LOAD =>
                                    bscan_req_kind <= BSCAN_REQ_LOAD;
                                    bscan_req_ir_len <= to_unsigned(IR_LENGTH, 16);
                                    bscan_req_sample_ir <= (others => '0');
                                    bscan_req_extest_ir <= (others => '0');
                                    bscan_req_extest_ir(7 downto 0) <= x"00";
                                    bscan_req_dr_len <= parser_req_dr_len;
                                    bscan_req_pin_num <= (others => '0');
                                    bscan_req_pin_val <= '0';
                                    bscan_req_data <= parser_req_dr_data;
                                    bscan_req_valid <= '1';
                                    state <= ST_WAIT_BSCAN;

                                when HOST_REQ_BSCAN_SET_PIN =>
                                    bscan_req_kind <= BSCAN_REQ_SET_PIN;
                                    bscan_req_ir_len <= to_unsigned(IR_LENGTH, 16);
                                    bscan_req_sample_ir <= (others => '0');
                                    bscan_req_extest_ir <= (others => '0');
                                    bscan_req_extest_ir(7 downto 0) <= x"00";
                                    bscan_req_dr_len <= to_unsigned(BSR_LENGTH, 16);
                                    bscan_req_pin_num <= parser_req_pin_num;
                                    bscan_req_pin_val <= parser_req_pin_val;
                                    bscan_req_data <= (others => '0');
                                    bscan_req_valid <= '1';
                                    state <= ST_WAIT_BSCAN;

                                when HOST_REQ_BSCAN_READ_PIN =>
                                    bscan_req_kind <= BSCAN_REQ_READ_PIN;
                                    bscan_req_ir_len <= to_unsigned(IR_LENGTH, 16);
                                    bscan_req_sample_ir <= (others => '0');
                                    bscan_req_sample_ir(7 downto 0) <= x"05";
                                    bscan_req_extest_ir <= (others => '0');
                                    bscan_req_dr_len <= to_unsigned(BSR_LENGTH, 16);
                                    bscan_req_pin_num <= parser_req_pin_num;
                                    bscan_req_pin_val <= '0';
                                    bscan_req_data <= (others => '0');
                                    bscan_req_valid <= '1';
                                    state <= ST_WAIT_BSCAN;

                                when HOST_REQ_BSCAN_SAMPLE_EX =>
                                    bscan_req_kind <= BSCAN_REQ_SAMPLE;
                                    bscan_req_ir_len <= parser_req_ir_len;
                                    bscan_req_sample_ir <= parser_req_ir_data;
                                    bscan_req_extest_ir <= (others => '0');
                                    bscan_req_dr_len <= parser_req_dr_len;
                                    bscan_req_pin_num <= (others => '0');
                                    bscan_req_pin_val <= '0';
                                    bscan_req_data <= (others => '0');
                                    bscan_req_valid <= '1';
                                    state <= ST_WAIT_BSCAN;

                                when HOST_REQ_BSCAN_LOAD_EX =>
                                    bscan_req_kind <= BSCAN_REQ_LOAD;
                                    bscan_req_ir_len <= parser_req_ir_len;
                                    bscan_req_sample_ir <= (others => '0');
                                    bscan_req_extest_ir <= parser_req_ir_data;
                                    bscan_req_dr_len <= parser_req_dr_len;
                                    bscan_req_pin_num <= (others => '0');
                                    bscan_req_pin_val <= '0';
                                    bscan_req_data <= parser_req_dr_data;
                                    bscan_req_valid <= '1';
                                    state <= ST_WAIT_BSCAN;

                                when HOST_REQ_BSCAN_SET_PIN_EX =>
                                    bscan_req_kind <= BSCAN_REQ_SET_PIN;
                                    bscan_req_ir_len <= parser_req_ir_len;
                                    bscan_req_sample_ir <= (others => '0');
                                    bscan_req_extest_ir <= parser_req_ir_data;
                                    bscan_req_dr_len <= parser_req_dr_len;
                                    bscan_req_pin_num <= parser_req_pin_num;
                                    bscan_req_pin_val <= parser_req_pin_val;
                                    bscan_req_data <= (others => '0');
                                    bscan_req_valid <= '1';
                                    state <= ST_WAIT_BSCAN;

                                when HOST_REQ_BSCAN_READ_PIN_EX =>
                                    bscan_req_kind <= BSCAN_REQ_READ_PIN;
                                    bscan_req_ir_len <= parser_req_ir_len;
                                    bscan_req_sample_ir <= parser_req_ir_data;
                                    bscan_req_extest_ir <= (others => '0');
                                    bscan_req_dr_len <= parser_req_dr_len;
                                    bscan_req_pin_num <= parser_req_pin_num;
                                    bscan_req_pin_val <= '0';
                                    bscan_req_data <= (others => '0');
                                    bscan_req_valid <= '1';
                                    state <= ST_WAIT_BSCAN;

                                when HOST_REQ_CHAIN_CFG =>
                                    resp_buf <= (others => '0');
                                    resp_buf(7 downto 0) <= x"00";
                                    resp_len <= to_unsigned(1, resp_len'length);
                                    resp_idx <= (others => '0');
                                    resp_last_byte <= '0';
                                    state <= ST_SEND_RESPONSE;

                                when HOST_REQ_I2C_WRITE =>
                                    resp_buf <= (others => '0');
                                    resp_buf(7 downto 0) <= x"00";
                                    resp_len <= to_unsigned(1, resp_len'length);
                                    resp_idx <= (others => '0');
                                    resp_last_byte <= '0';
                                    state <= ST_SEND_RESPONSE;

                                when HOST_REQ_I2C_READ =>
                                    resp_buf <= (others => '0');
                                    i2c_rd_len := to_integer(parser_req_word(7 downto 0));
                                    resp_len <= to_unsigned(i2c_rd_len, resp_len'length);
                                    resp_idx <= (others => '0');
                                    resp_last_byte <= '0';
                                    state <= ST_SEND_RESPONSE;

                                when HOST_REQ_I2C_WR_RD =>
                                    resp_buf <= (others => '0');
                                    i2c_rd_len := to_integer(parser_req_word(15 downto 8));
                                    resp_len <= to_unsigned(i2c_rd_len, resp_len'length);
                                    resp_idx <= (others => '0');
                                    resp_last_byte <= '0';
                                    state <= ST_SEND_RESPONSE;

                                when HOST_REQ_I2C_SCAN =>
                                    resp_buf <= (others => '0');
                                    resp_len <= to_unsigned(16, resp_len'length);
                                    resp_idx <= (others => '0');
                                    resp_last_byte <= '0';
                                    state <= ST_SEND_RESPONSE;

                                when others =>
                                    null;
                            end case;
                        end if;

                    when ST_WAIT_JTAG =>
                        if jtag_done = '1' then
                            resp_buf <= (others => '0');
                            resp_idx <= (others => '0');
                            resp_last_byte <= '0';

                            case active_req_kind is
                                when HOST_REQ_RAW_JTAG_SHIFT_DR =>
                                    resp_buf(BSR_LENGTH-1 downto 0) <= jtag_rsp_data;
                                    resp_len <= to_unsigned(bytes_for_bits(to_integer(jtag_rsp_len)), resp_len'length);
                                when HOST_REQ_RAW_JTAG_SHIFT_IR_DR =>
                                    resp_buf(BSR_LENGTH-1 downto 0) <= jtag_rsp_data;
                                    resp_len <= to_unsigned(bytes_for_bits(to_integer(jtag_rsp_len)), resp_len'length);
                                when HOST_REQ_RAW_IDCODE =>
                                    resp_buf(BSR_LENGTH-1 downto 0) <= jtag_rsp_data;
                                    resp_len <= to_unsigned(4, resp_len'length);
                                when others =>
                                    resp_buf(7 downto 0) <= x"00";
                                    resp_len <= to_unsigned(1, resp_len'length);
                            end case;

                            state <= ST_SEND_RESPONSE;
                        end if;

                    when ST_WAIT_BSCAN =>
                        if bscan_done = '1' then
                            resp_buf <= (others => '0');
                            resp_idx <= (others => '0');
                            resp_last_byte <= '0';

                            case active_req_kind is
                                when HOST_REQ_BSCAN_READ_PIN | HOST_REQ_BSCAN_READ_PIN_EX =>
                                    resp_buf(0) <= bscan_rsp_pin;
                                    resp_len <= to_unsigned(1, resp_len'length);
                                when others =>
                                    resp_buf(BSR_LENGTH-1 downto 0) <= bscan_rsp_data;
                                    resp_len <= to_unsigned(bytes_for_bits(to_integer(bscan_req_dr_len)), resp_len'length);
                            end case;

                            state <= ST_SEND_RESPONSE;
                        end if;

                    when ST_SEND_RESPONSE =>
                        if resp_idx >= resp_len then
                            state <= ST_IDLE;
                        elsif ft_tx_ready = '1' then
                            byte_idx := to_integer(resp_idx);
                            ft_tx_data <= resp_buf(byte_idx * 8 + 7 downto byte_idx * 8);
                            ft_tx_valid <= '1';
                            if resp_idx + 1 >= resp_len then
                                resp_last_byte <= '1';
                            else
                                resp_last_byte <= '0';
                            end if;
                            state <= ST_SEND_WAIT_ACCEPT;
                        end if;

                    when ST_SEND_WAIT_ACCEPT =>
                        ft_tx_valid <= '1';
                        if ft_wr_n_int = '0' then
                            resp_idx <= resp_idx + 1;
                            state <= ST_SEND_WAIT_RELEASE;
                        end if;

                    when ST_SEND_WAIT_RELEASE =>
                        if ft_wr_n_int = '1' then
                            if resp_last_byte = '1' then
                                state <= ST_IDLE;
                            else
                                state <= ST_SEND_RESPONSE;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

    rst_n_int <= rst_done;

end architecture;
