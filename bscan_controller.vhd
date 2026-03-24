library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.jtag_pkg.all;

entity bscan_controller is
    generic (
        MAX_DR_BITS : natural := MAX_BSR_LENGTH;
        MAX_IR_BITS : natural := MAX_IR_LENGTH
    );
    port (
        clk               : in  std_logic;
        rst_n             : in  std_logic;

        req_valid         : in  std_logic;
        req_kind          : in  bscan_req_kind_t;
        req_ir_len        : in  unsigned(15 downto 0);
        req_sample_ir     : in  std_logic_vector(MAX_IR_BITS-1 downto 0);
        req_extest_ir     : in  std_logic_vector(MAX_IR_BITS-1 downto 0);
        req_dr_len        : in  unsigned(15 downto 0);
        req_pin_num       : in  unsigned(15 downto 0);
        req_pin_val       : in  std_logic;
        req_dr_data       : in  std_logic_vector(MAX_DR_BITS-1 downto 0);

        busy              : out std_logic;
        done              : out std_logic;
        rsp_dr_data       : out std_logic_vector(MAX_DR_BITS-1 downto 0);
        rsp_pin_val       : out std_logic;

        jtag_req_valid    : out std_logic;
        jtag_req_kind     : out jtag_req_kind_t;
        jtag_req_ir_len   : out unsigned(15 downto 0);
        jtag_req_ir_data  : out std_logic_vector(MAX_IR_BITS-1 downto 0);
        jtag_req_dr_len   : out unsigned(15 downto 0);
        jtag_req_dr_data  : out std_logic_vector(MAX_DR_BITS-1 downto 0);

        jtag_busy         : in  std_logic;
        jtag_done         : in  std_logic;
        jtag_rsp_data     : in  std_logic_vector(MAX_DR_BITS-1 downto 0)
    );
end entity;

architecture rtl of bscan_controller is

    type ctrl_state_t is (
        ST_IDLE,
        ST_START_JTAG,
        ST_WAIT_JTAG,
        ST_DONE
    );

    signal state              : ctrl_state_t := ST_IDLE;
    signal req_kind_lat       : bscan_req_kind_t := BSCAN_REQ_NONE;
    signal req_ir_len_lat     : unsigned(15 downto 0) := (others => '0');
    signal req_sample_ir_lat  : std_logic_vector(MAX_IR_BITS-1 downto 0) := (others => '0');
    signal req_extest_ir_lat  : std_logic_vector(MAX_IR_BITS-1 downto 0) := (others => '0');
    signal req_dr_len_lat     : unsigned(15 downto 0) := (others => '0');
    signal req_pin_num_lat    : unsigned(15 downto 0) := (others => '0');
    signal req_pin_val_lat    : std_logic := '0';
    signal req_dr_data_lat    : std_logic_vector(MAX_DR_BITS-1 downto 0) := (others => '0');

    signal busy_reg           : std_logic := '0';
    signal done_reg           : std_logic := '0';
    signal rsp_dr_data_reg    : std_logic_vector(MAX_DR_BITS-1 downto 0) := (others => '0');
    signal rsp_pin_val_reg    : std_logic := '0';

    signal jtag_req_valid_reg : std_logic := '0';
    signal jtag_req_kind_reg  : jtag_req_kind_t := JTAG_REQ_NONE;
    signal jtag_req_ir_len_reg: unsigned(15 downto 0) := (others => '0');
    signal jtag_req_ir_reg    : std_logic_vector(MAX_IR_BITS-1 downto 0) := (others => '0');
    signal jtag_req_dr_len_reg: unsigned(15 downto 0) := (others => '0');
    signal jtag_req_data_reg  : std_logic_vector(MAX_DR_BITS-1 downto 0) := (others => '0');

    signal dr_shadow          : std_logic_vector(MAX_DR_BITS-1 downto 0) := (others => '0');

begin

    busy <= busy_reg;
    done <= done_reg;
    rsp_dr_data <= rsp_dr_data_reg;
    rsp_pin_val <= rsp_pin_val_reg;

    jtag_req_valid <= jtag_req_valid_reg;
    jtag_req_kind <= jtag_req_kind_reg;
    jtag_req_ir_len <= jtag_req_ir_len_reg;
    jtag_req_ir_data <= jtag_req_ir_reg;
    jtag_req_dr_len <= jtag_req_dr_len_reg;
    jtag_req_dr_data <= jtag_req_data_reg;

    process(clk)
        variable next_shadow : std_logic_vector(MAX_DR_BITS-1 downto 0);
    begin
        if rising_edge(clk) then
            done_reg <= '0';
            jtag_req_valid_reg <= '0';

            if rst_n = '0' then
                state <= ST_IDLE;
                req_kind_lat <= BSCAN_REQ_NONE;
                req_ir_len_lat <= (others => '0');
                req_sample_ir_lat <= (others => '0');
                req_extest_ir_lat <= (others => '0');
                req_dr_len_lat <= (others => '0');
                req_pin_num_lat <= (others => '0');
                req_pin_val_lat <= '0';
                req_dr_data_lat <= (others => '0');
                busy_reg <= '0';
                rsp_dr_data_reg <= (others => '0');
                rsp_pin_val_reg <= '0';
                jtag_req_kind_reg <= JTAG_REQ_NONE;
                jtag_req_ir_len_reg <= (others => '0');
                jtag_req_ir_reg <= (others => '0');
                jtag_req_dr_len_reg <= (others => '0');
                jtag_req_data_reg <= (others => '0');
                dr_shadow <= (others => '0');
            else
                case state is
                    when ST_IDLE =>
                        busy_reg <= '0';

                        if req_valid = '1' then
                            req_kind_lat <= req_kind;
                            req_ir_len_lat <= req_ir_len;
                            req_sample_ir_lat <= req_sample_ir;
                            req_extest_ir_lat <= req_extest_ir;
                            req_dr_len_lat <= req_dr_len;
                            req_pin_num_lat <= req_pin_num;
                            req_pin_val_lat <= req_pin_val;
                            req_dr_data_lat <= req_dr_data;
                            busy_reg <= '1';
                            state <= ST_START_JTAG;
                        end if;

                    when ST_START_JTAG =>
                        if jtag_busy = '0' then
                            jtag_req_valid_reg <= '1';
                            jtag_req_kind_reg <= JTAG_REQ_SHIFT_IR_DR;
                            jtag_req_ir_len_reg <= req_ir_len_lat;
                            jtag_req_dr_len_reg <= req_dr_len_lat;

                            case req_kind_lat is
                                when BSCAN_REQ_SAMPLE =>
                                    jtag_req_ir_reg <= req_sample_ir_lat;
                                    jtag_req_data_reg <= (others => '0');

                                when BSCAN_REQ_LOAD =>
                                    dr_shadow <= req_dr_data_lat;
                                    jtag_req_ir_reg <= req_extest_ir_lat;
                                    jtag_req_data_reg <= req_dr_data_lat;

                                when BSCAN_REQ_SET_PIN =>
                                    next_shadow := dr_shadow;
                                    if to_integer(req_pin_num_lat) < MAX_DR_BITS then
                                        next_shadow(to_integer(req_pin_num_lat)) := req_pin_val_lat;
                                    end if;
                                    dr_shadow <= next_shadow;
                                    jtag_req_ir_reg <= req_extest_ir_lat;
                                    jtag_req_data_reg <= next_shadow;

                                when BSCAN_REQ_READ_PIN =>
                                    jtag_req_ir_reg <= req_sample_ir_lat;
                                    jtag_req_data_reg <= (others => '0');

                                when others =>
                                    jtag_req_kind_reg <= JTAG_REQ_NONE;
                                    jtag_req_ir_len_reg <= (others => '0');
                                    jtag_req_ir_reg <= (others => '0');
                                    jtag_req_dr_len_reg <= (others => '0');
                                    jtag_req_data_reg <= (others => '0');
                            end case;

                            state <= ST_WAIT_JTAG;
                        end if;

                    when ST_WAIT_JTAG =>
                        if jtag_done = '1' then
                            rsp_dr_data_reg <= jtag_rsp_data;

                            case req_kind_lat is
                                when BSCAN_REQ_SAMPLE =>
                                    dr_shadow <= jtag_rsp_data;

                                when BSCAN_REQ_READ_PIN =>
                                    dr_shadow <= jtag_rsp_data;
                                    if to_integer(req_pin_num_lat) < MAX_DR_BITS then
                                        rsp_pin_val_reg <= jtag_rsp_data(to_integer(req_pin_num_lat));
                                    else
                                        rsp_pin_val_reg <= '0';
                                    end if;

                                when others =>
                                    null;
                            end case;

                            state <= ST_DONE;
                        end if;

                    when ST_DONE =>
                        busy_reg <= '0';
                        done_reg <= '1';
                        req_kind_lat <= BSCAN_REQ_NONE;
                        state <= ST_IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture;
