library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.jtag_pkg.all;

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

architecture rtl of bscan_controller is

    constant BSCAN_OP_SAMPLE   : std_logic_vector(2 downto 0) := "000";
    constant BSCAN_OP_LOAD     : std_logic_vector(2 downto 0) := "001";
    constant BSCAN_OP_SET_PIN  : std_logic_vector(2 downto 0) := "010";
    constant BSCAN_OP_READ_PIN : std_logic_vector(2 downto 0) := "011";

    constant JTAG_EXTEST : std_logic_vector(7 downto 0) := x"00";
    constant JTAG_SAMPLE : std_logic_vector(7 downto 0) := x"05";

    type ctrl_state_t is (
        ST_IDLE,
        ST_START_JTAG,
        ST_WAIT_JTAG,
        ST_DONE
    );

    type active_op_t is (
        OP_NONE,
        OP_SAMPLE,
        OP_LOAD,
        OP_SET_PIN,
        OP_READ_PIN
    );

    signal state             : ctrl_state_t := ST_IDLE;
    signal active_op         : active_op_t := OP_NONE;

    signal busy_reg          : std_logic := '0';
    signal done_reg          : std_logic := '0';
    signal rsp_bsr_data_reg  : std_logic_vector(BSR_LENGTH-1 downto 0) := (others => '0');
    signal rsp_pin_val_reg   : std_logic := '0';

    signal jtag_req_valid_reg : std_logic := '0';
    signal jtag_req_kind_reg  : jtag_req_kind_t := JTAG_REQ_NONE;
    signal jtag_req_ir_reg    : std_logic_vector(7 downto 0) := (others => '0');
    signal jtag_req_dr_len_reg: unsigned(15 downto 0) := (others => '0');
    signal jtag_req_data_reg  : std_logic_vector(BSR_LENGTH-1 downto 0) := (others => '0');

    signal bsr_shadow        : std_logic_vector(BSR_LENGTH-1 downto 0) := (others => '0');
    signal bsr_last_capture  : std_logic_vector(BSR_LENGTH-1 downto 0) := (others => '0');

    signal req_pin_num_lat   : unsigned(15 downto 0) := (others => '0');
    signal req_pin_val_lat   : std_logic := '0';
    signal req_bsr_data_lat  : std_logic_vector(BSR_LENGTH-1 downto 0) := (others => '0');

begin

    busy <= busy_reg;
    done <= done_reg;
    rsp_bsr_data <= rsp_bsr_data_reg;
    rsp_pin_val <= rsp_pin_val_reg;

    jtag_req_valid <= jtag_req_valid_reg;
    jtag_req_kind <= jtag_req_kind_reg;
    jtag_req_ir <= jtag_req_ir_reg;
    jtag_req_dr_len <= jtag_req_dr_len_reg;
    jtag_req_dr_data <= jtag_req_data_reg;

    process(clk)
        variable next_shadow : std_logic_vector(BSR_LENGTH-1 downto 0);
    begin
        if rising_edge(clk) then
            done_reg <= '0';
            jtag_req_valid_reg <= '0';

            if rst_n = '0' then
                state <= ST_IDLE;
                active_op <= OP_NONE;
                busy_reg <= '0';
                rsp_bsr_data_reg <= (others => '0');
                rsp_pin_val_reg <= '0';
                jtag_req_kind_reg <= JTAG_REQ_NONE;
                jtag_req_ir_reg <= (others => '0');
                jtag_req_dr_len_reg <= (others => '0');
                jtag_req_data_reg <= (others => '0');
                bsr_shadow <= (others => '0');
                bsr_last_capture <= (others => '0');
                req_pin_num_lat <= (others => '0');
                req_pin_val_lat <= '0';
                req_bsr_data_lat <= (others => '0');
            else
                case state is
                    when ST_IDLE =>
                        busy_reg <= '0';

                        if req_valid = '1' then
                            req_pin_num_lat <= req_pin_num;
                            req_pin_val_lat <= req_pin_val;
                            req_bsr_data_lat <= req_bsr_data;
                            busy_reg <= '1';

                            case req_op is
                                when BSCAN_OP_SAMPLE =>
                                    active_op <= OP_SAMPLE;
                                    state <= ST_START_JTAG;

                                when BSCAN_OP_LOAD =>
                                    active_op <= OP_LOAD;
                                    state <= ST_START_JTAG;

                                when BSCAN_OP_SET_PIN =>
                                    active_op <= OP_SET_PIN;
                                    state <= ST_START_JTAG;

                                when BSCAN_OP_READ_PIN =>
                                    active_op <= OP_READ_PIN;
                                    state <= ST_START_JTAG;

                                when others =>
                                    active_op <= OP_NONE;
                                    state <= ST_DONE;
                            end case;
                        end if;

                    when ST_START_JTAG =>
                        if jtag_busy = '0' then
                            jtag_req_valid_reg <= '1';
                            jtag_req_kind_reg <= JTAG_REQ_SHIFT_IR_DR;
                            jtag_req_dr_len_reg <= to_unsigned(BSR_LENGTH, 16);

                            case active_op is
                                when OP_SAMPLE =>
                                    jtag_req_ir_reg <= JTAG_SAMPLE;
                                    jtag_req_data_reg <= (others => '0');

                                when OP_LOAD =>
                                    bsr_shadow <= req_bsr_data_lat;
                                    jtag_req_ir_reg <= JTAG_EXTEST;
                                    jtag_req_data_reg <= req_bsr_data_lat;

                                when OP_SET_PIN =>
                                    next_shadow := bsr_shadow;
                                    if to_integer(req_pin_num_lat) < BSR_LENGTH then
                                        next_shadow(to_integer(req_pin_num_lat)) := req_pin_val_lat;
                                    end if;
                                    bsr_shadow <= next_shadow;
                                    jtag_req_ir_reg <= JTAG_EXTEST;
                                    jtag_req_data_reg <= next_shadow;

                                when OP_READ_PIN =>
                                    jtag_req_ir_reg <= JTAG_SAMPLE;
                                    jtag_req_data_reg <= (others => '0');

                                when others =>
                                    jtag_req_kind_reg <= JTAG_REQ_NONE;
                                    jtag_req_ir_reg <= (others => '0');
                                    jtag_req_dr_len_reg <= (others => '0');
                                    jtag_req_data_reg <= (others => '0');
                            end case;

                            state <= ST_WAIT_JTAG;
                        end if;

                    when ST_WAIT_JTAG =>
                        if jtag_done = '1' then
                            bsr_last_capture <= jtag_rsp_data;

                            case active_op is
                                when OP_SAMPLE =>
                                    rsp_bsr_data_reg <= jtag_rsp_data;

                                when OP_LOAD =>
                                    rsp_bsr_data_reg <= jtag_rsp_data;

                                when OP_SET_PIN =>
                                    rsp_bsr_data_reg <= jtag_rsp_data;

                                when OP_READ_PIN =>
                                    rsp_bsr_data_reg <= jtag_rsp_data;
                                    if to_integer(req_pin_num_lat) < BSR_LENGTH then
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
                        active_op <= OP_NONE;
                        state <= ST_IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture;
