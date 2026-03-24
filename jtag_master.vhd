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

architecture rtl of jtag_master is

    function min_nat(a : natural; b : natural) return natural is
    begin
        if a < b then
            return a;
        end if;
        return b;
    end function;

    type jtag_state_t is (
        ST_IDLE,
        ST_SET_TMS_DONE,
        ST_TOGGLE_TCK,
        ST_RESET,
        ST_GOTO_SHIFT_IR,
        ST_SHIFT_IR,
        ST_EXIT_IR,
        ST_GOTO_SHIFT_DR,
        ST_SHIFT_DR,
        ST_EXIT_DR,
        ST_RETURN_IDLE,
        ST_DONE
    );

    signal state            : jtag_state_t := ST_IDLE;
    signal next_after_ir    : jtag_state_t := ST_DONE;

    signal req_kind_lat     : jtag_req_kind_t := JTAG_REQ_NONE;
    signal req_ir_lat       : std_logic_vector(7 downto 0) := (others => '0');
    signal req_dr_len_lat   : unsigned(15 downto 0) := (others => '0');
    signal req_dr_data_lat  : std_logic_vector(MAX_SHIFT_BITS-1 downto 0) := (others => '0');
    signal req_tms_lat      : std_logic := '0';
    signal req_tck_lat      : unsigned(15 downto 0) := (others => '0');

    signal busy_reg         : std_logic := '0';
    signal done_reg         : std_logic := '0';

    signal tck_reg          : std_logic := '0';
    signal tms_reg          : std_logic := '1';
    signal tdi_reg          : std_logic := '0';
    signal tdo_sample       : std_logic := '0';

    signal div_cnt          : unsigned(JTAG_DIV_WIDTH-1 downto 0) := (others => '0');
    signal nav_cnt          : unsigned(15 downto 0) := (others => '0');
    signal shift_cnt        : unsigned(15 downto 0) := (others => '0');
    signal edge_cnt         : unsigned(15 downto 0) := (others => '0');
    signal shift_len        : unsigned(15 downto 0) := (others => '0');
    signal shift_buf        : std_logic_vector(MAX_SHIFT_BITS-1 downto 0) := (others => '0');

    constant EFFECTIVE_IR_LENGTH : natural := min_nat(IR_LENGTH, 8);
    constant DIV_RELOAD     : unsigned(JTAG_DIV_WIDTH-1 downto 0) :=
        to_unsigned(JTAG_DIV_VALUE, JTAG_DIV_WIDTH);

begin

    busy <= busy_reg;
    done <= done_reg;
    rsp_dr_data <= shift_buf;
    rsp_dr_len <= shift_len;
    jtag_tck <= tck_reg;
    jtag_tms <= tms_reg;
    jtag_tdi <= tdi_reg;

    process(clk)
        variable clamped_dr_len : unsigned(15 downto 0);
        variable ir_len_u       : unsigned(15 downto 0);
    begin
        if rising_edge(clk) then
            done_reg <= '0';

            if rst_n = '0' then
                state <= ST_IDLE;
                next_after_ir <= ST_DONE;
                req_kind_lat <= JTAG_REQ_NONE;
                req_ir_lat <= (others => '0');
                req_dr_len_lat <= (others => '0');
                req_dr_data_lat <= (others => '0');
                req_tms_lat <= '0';
                req_tck_lat <= (others => '0');
                busy_reg <= '0';
                tck_reg <= '0';
                tms_reg <= '1';
                tdi_reg <= '0';
                tdo_sample <= '0';
                div_cnt <= (others => '0');
                nav_cnt <= (others => '0');
                shift_cnt <= (others => '0');
                edge_cnt <= (others => '0');
                shift_len <= (others => '0');
                shift_buf <= (others => '0');
            else
                if div_cnt /= 0 then
                    div_cnt <= div_cnt - 1;
                end if;

                case state is
                    when ST_IDLE =>
                        busy_reg <= '0';

                        if req_valid = '1' then
                            req_kind_lat <= req_kind;
                            req_ir_lat <= req_ir;
                            req_dr_data_lat <= req_dr_data;
                            req_tms_lat <= req_tms_value;
                            req_tck_lat <= req_tck_edges;
                            nav_cnt <= (others => '0');
                            shift_cnt <= (others => '0');
                            edge_cnt <= (others => '0');
                            tdo_sample <= '0';

                            if to_integer(req_dr_len) > MAX_SHIFT_BITS then
                                clamped_dr_len := to_unsigned(MAX_SHIFT_BITS, 16);
                            else
                                clamped_dr_len := req_dr_len;
                            end if;

                            req_dr_len_lat <= clamped_dr_len;
                            busy_reg <= '1';

                            case req_kind is
                                when JTAG_REQ_SET_TMS =>
                                    shift_len <= (others => '0');
                                    shift_buf <= (others => '0');
                                    tms_reg <= req_tms_value;
                                    state <= ST_SET_TMS_DONE;

                                when JTAG_REQ_TOGGLE_TCK =>
                                    shift_len <= (others => '0');
                                    shift_buf <= (others => '0');
                                    edge_cnt <= req_tck_edges;
                                    if req_tck_edges = 0 then
                                        state <= ST_DONE;
                                    else
                                        div_cnt <= DIV_RELOAD;
                                        state <= ST_TOGGLE_TCK;
                                    end if;

                                when JTAG_REQ_RESET =>
                                    shift_len <= (others => '0');
                                    shift_buf <= (others => '0');
                                    edge_cnt <= req_tck_edges;
                                    tms_reg <= '1';
                                    if req_tck_edges = 0 then
                                        tms_reg <= '0';
                                        state <= ST_DONE;
                                    else
                                        div_cnt <= DIV_RELOAD;
                                        state <= ST_RESET;
                                    end if;

                                when JTAG_REQ_SHIFT_IR =>
                                    shift_len <= (others => '0');
                                    shift_buf <= (others => '0');
                                    if EFFECTIVE_IR_LENGTH = 0 then
                                        state <= ST_DONE;
                                    else
                                        next_after_ir <= ST_RETURN_IDLE;
                                        div_cnt <= DIV_RELOAD;
                                        nav_cnt <= (others => '0');
                                        state <= ST_GOTO_SHIFT_IR;
                                    end if;

                                when JTAG_REQ_SHIFT_DR =>
                                    shift_len <= clamped_dr_len;
                                    shift_buf <= req_dr_data;
                                    if clamped_dr_len = 0 then
                                        state <= ST_DONE;
                                    else
                                        div_cnt <= DIV_RELOAD;
                                        nav_cnt <= (others => '0');
                                        state <= ST_GOTO_SHIFT_DR;
                                    end if;

                                when JTAG_REQ_SHIFT_IR_DR =>
                                    shift_len <= clamped_dr_len;
                                    shift_buf <= req_dr_data;
                                    if EFFECTIVE_IR_LENGTH = 0 then
                                        if clamped_dr_len = 0 then
                                            state <= ST_DONE;
                                        else
                                            div_cnt <= DIV_RELOAD;
                                            nav_cnt <= (others => '0');
                                            state <= ST_GOTO_SHIFT_DR;
                                        end if;
                                    else
                                        if clamped_dr_len = 0 then
                                            next_after_ir <= ST_RETURN_IDLE;
                                        else
                                            next_after_ir <= ST_GOTO_SHIFT_DR;
                                        end if;
                                        div_cnt <= DIV_RELOAD;
                                        nav_cnt <= (others => '0');
                                        state <= ST_GOTO_SHIFT_IR;
                                    end if;

                                when others =>
                                    shift_len <= (others => '0');
                                    shift_buf <= (others => '0');
                                    state <= ST_DONE;
                            end case;
                        end if;

                    when ST_SET_TMS_DONE =>
                        state <= ST_DONE;

                    when ST_TOGGLE_TCK =>
                        if div_cnt = 0 then
                            tck_reg <= not tck_reg;
                            div_cnt <= DIV_RELOAD;

                            if edge_cnt = 1 then
                                state <= ST_DONE;
                            else
                                edge_cnt <= edge_cnt - 1;
                            end if;
                        end if;

                    when ST_RESET =>
                        if div_cnt = 0 then
                            tck_reg <= not tck_reg;
                            div_cnt <= DIV_RELOAD;

                            if edge_cnt = 1 then
                                tms_reg <= '0';
                                state <= ST_DONE;
                            else
                                edge_cnt <= edge_cnt - 1;
                            end if;
                        end if;

                    when ST_GOTO_SHIFT_IR =>
                        if div_cnt = 0 then
                            tck_reg <= not tck_reg;
                            div_cnt <= DIV_RELOAD;

                            if tck_reg = '1' then
                                case to_integer(nav_cnt) is
                                    when 0 =>
                                        tms_reg <= '1';
                                        nav_cnt <= nav_cnt + 1;
                                    when 1 =>
                                        tms_reg <= '1';
                                        nav_cnt <= nav_cnt + 1;
                                    when 2 =>
                                        tms_reg <= '0';
                                        nav_cnt <= nav_cnt + 1;
                                    when 3 =>
                                        tms_reg <= '0';
                                        nav_cnt <= (others => '0');
                                        ir_len_u := to_unsigned(EFFECTIVE_IR_LENGTH, 16);
                                        shift_cnt <= ir_len_u;
                                        tdi_reg <= req_ir_lat(0);
                                        state <= ST_SHIFT_IR;
                                    when others =>
                                        null;
                                end case;
                            end if;
                        end if;

                    when ST_SHIFT_IR =>
                        if div_cnt = 0 then
                            tck_reg <= not tck_reg;
                            div_cnt <= DIV_RELOAD;

                            if tck_reg = '1' then
                                shift_cnt <= shift_cnt - 1;

                                if shift_cnt = 1 then
                                    tms_reg <= '1';
                                    nav_cnt <= (others => '0');
                                    state <= ST_EXIT_IR;
                                else
                                    tdi_reg <= req_ir_lat(to_integer(to_unsigned(EFFECTIVE_IR_LENGTH, 16) - shift_cnt + 1));
                                end if;
                            end if;
                        end if;

                    when ST_EXIT_IR =>
                        if div_cnt = 0 then
                            tck_reg <= not tck_reg;
                            div_cnt <= DIV_RELOAD;

                            if tck_reg = '1' then
                                case to_integer(nav_cnt) is
                                    when 0 =>
                                        tms_reg <= '1';
                                        nav_cnt <= nav_cnt + 1;
                                    when 1 =>
                                        nav_cnt <= (others => '0');
                                        state <= next_after_ir;
                                        if next_after_ir = ST_GOTO_SHIFT_DR then
                                            tms_reg <= '1';
                                        else
                                            tms_reg <= '0';
                                        end if;
                                    when others =>
                                        null;
                                end case;
                            end if;
                        end if;

                    when ST_GOTO_SHIFT_DR =>
                        if div_cnt = 0 then
                            tck_reg <= not tck_reg;
                            div_cnt <= DIV_RELOAD;

                            if tck_reg = '1' then
                                case to_integer(nav_cnt) is
                                    when 0 =>
                                        tms_reg <= '1';
                                        nav_cnt <= nav_cnt + 1;
                                    when 1 =>
                                        tms_reg <= '0';
                                        nav_cnt <= nav_cnt + 1;
                                    when 2 =>
                                        tms_reg <= '0';
                                        nav_cnt <= (others => '0');
                                        shift_cnt <= req_dr_len_lat;
                                        tdi_reg <= req_dr_data_lat(to_integer(req_dr_len_lat) - 1);
                                        state <= ST_SHIFT_DR;
                                    when others =>
                                        null;
                                end case;
                            end if;
                        end if;

                    when ST_SHIFT_DR =>
                        if div_cnt = 0 then
                            tck_reg <= not tck_reg;
                            div_cnt <= DIV_RELOAD;

                            if tck_reg = '0' then
                                tdo_sample <= jtag_tdo;
                            else
                                shift_buf <= shift_buf(MAX_SHIFT_BITS-2 downto 0) & tdo_sample;
                                shift_cnt <= shift_cnt - 1;

                                if shift_cnt = 1 then
                                    tms_reg <= '1';
                                    nav_cnt <= (others => '0');
                                    state <= ST_EXIT_DR;
                                else
                                    tdi_reg <= req_dr_data_lat(to_integer(shift_cnt) - 2);
                                end if;
                            end if;
                        end if;

                    when ST_EXIT_DR =>
                        if div_cnt = 0 then
                            tck_reg <= not tck_reg;
                            div_cnt <= DIV_RELOAD;

                            if tck_reg = '1' then
                                case to_integer(nav_cnt) is
                                    when 0 =>
                                        tms_reg <= '1';
                                        nav_cnt <= nav_cnt + 1;
                                    when 1 =>
                                        tms_reg <= '0';
                                        nav_cnt <= (others => '0');
                                        state <= ST_RETURN_IDLE;
                                    when others =>
                                        null;
                                end case;
                            end if;
                        end if;

                    when ST_RETURN_IDLE =>
                        if div_cnt = 0 then
                            tck_reg <= not tck_reg;
                            div_cnt <= DIV_RELOAD;

                            if tck_reg = '1' then
                                tms_reg <= '0';
                                state <= ST_DONE;
                            end if;
                        end if;

                    when ST_DONE =>
                        busy_reg <= '0';
                        done_reg <= '1';
                        state <= ST_IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture;
