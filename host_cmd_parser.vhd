library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.jtag_pkg.all;

entity host_cmd_parser is
    generic (
        LEGACY_BSR_LENGTH : natural := 362;
        MAX_IR_BITS       : natural := MAX_IR_LENGTH;
        MAX_DR_BITS       : natural := MAX_BSR_LENGTH
    );
    port (
        clk        : in  std_logic;
        rst_n      : in  std_logic;
        rx_valid   : in  std_logic;
        rx_data    : in  std_logic_vector(7 downto 0);
        req_valid  : out std_logic;
        req_kind   : out host_req_kind_t;
        req_byte   : out std_logic_vector(7 downto 0);
        req_word   : out unsigned(15 downto 0);
        req_ir_len : out unsigned(15 downto 0);
        req_ir_data: out std_logic_vector(MAX_IR_BITS-1 downto 0);
        req_dr_len : out unsigned(15 downto 0);
        req_dr_data: out std_logic_vector(MAX_DR_BITS-1 downto 0);
        req_pin_num: out unsigned(15 downto 0);
        req_pin_val: out std_logic;
        busy       : in  std_logic
    );
end entity;

architecture rtl of host_cmd_parser is
    function store_byte(data_in : std_logic_vector; index : natural; value : std_logic_vector(7 downto 0)) return std_logic_vector is
        variable result : std_logic_vector(data_in'range) := data_in;
        variable bitpos : natural;
    begin
        for i in 0 to 7 loop
            bitpos := index * 8 + i;
            if bitpos < data_in'length then
                result(result'low + bitpos) := value(i);
            end if;
        end loop;
        return result;
    end function;

    function make_u16(lo_byte : unsigned(7 downto 0); hi_byte : std_logic_vector(7 downto 0)) return unsigned is
    begin
        return unsigned(hi_byte) & lo_byte;
    end function;

    type parser_state_t is (ST_IDLE, ST_WAIT_PARAM);

    signal state          : parser_state_t := ST_IDLE;
    signal active_cmd     : std_logic_vector(7 downto 0) := (others => '0');
    signal param_cnt      : unsigned(15 downto 0) := (others => '0');
    signal req_valid_reg  : std_logic := '0';
    signal req_kind_reg   : host_req_kind_t := HOST_REQ_NONE;
    signal req_byte_reg   : std_logic_vector(7 downto 0) := (others => '0');
    signal req_word_reg   : unsigned(15 downto 0) := (others => '0');
    signal req_ir_len_reg : unsigned(15 downto 0) := (others => '0');
    signal req_ir_data_reg: std_logic_vector(MAX_IR_BITS-1 downto 0) := (others => '0');
    signal req_dr_len_reg : unsigned(15 downto 0) := (others => '0');
    signal req_dr_data_reg: std_logic_vector(MAX_DR_BITS-1 downto 0) := (others => '0');
    signal req_pin_num_reg: unsigned(15 downto 0) := (others => '0');
    signal req_pin_val_reg: std_logic := '0';
    signal pend_valid     : std_logic := '0';
    signal pend_kind      : host_req_kind_t := HOST_REQ_NONE;
    signal pend_byte      : std_logic_vector(7 downto 0) := (others => '0');
    signal pend_word      : unsigned(15 downto 0) := (others => '0');
    signal pend_ir_len    : unsigned(15 downto 0) := (others => '0');
    signal pend_ir_data   : std_logic_vector(MAX_IR_BITS-1 downto 0) := (others => '0');
    signal pend_dr_len    : unsigned(15 downto 0) := (others => '0');
    signal pend_dr_data   : std_logic_vector(MAX_DR_BITS-1 downto 0) := (others => '0');
    signal pend_pin_num   : unsigned(15 downto 0) := (others => '0');
    signal pend_pin_val   : std_logic := '0';
    signal temp_byte      : std_logic_vector(7 downto 0) := (others => '0');
    signal temp_lo        : unsigned(7 downto 0) := (others => '0');
    signal temp_ir_len    : unsigned(15 downto 0) := (others => '0');
    signal temp_dr_len    : unsigned(15 downto 0) := (others => '0');
    signal temp_ir_data   : std_logic_vector(MAX_IR_BITS-1 downto 0) := (others => '0');
    signal temp_dr_data   : std_logic_vector(MAX_DR_BITS-1 downto 0) := (others => '0');
    signal temp_pin_num   : unsigned(15 downto 0) := (others => '0');
    signal temp_pin_val   : std_logic := '0';
begin
    req_valid <= req_valid_reg;
    req_kind <= req_kind_reg;
    req_byte <= req_byte_reg;
    req_word <= req_word_reg;
    req_ir_len <= req_ir_len_reg;
    req_ir_data <= req_ir_data_reg;
    req_dr_len <= req_dr_len_reg;
    req_dr_data <= req_dr_data_reg;
    req_pin_num <= req_pin_num_reg;
    req_pin_val <= req_pin_val_reg;

    process(clk)
        variable next_ir_data : std_logic_vector(MAX_IR_BITS-1 downto 0);
        variable next_dr_data : std_logic_vector(MAX_DR_BITS-1 downto 0);
        variable ir_bytes     : natural;
        variable dr_bytes     : natural;
        variable byte_index   : natural;
    begin
        if rising_edge(clk) then
            req_valid_reg <= '0';
            if rst_n = '0' then
                state <= ST_IDLE;
                active_cmd <= (others => '0');
                param_cnt <= (others => '0');
                req_kind_reg <= HOST_REQ_NONE;
                req_byte_reg <= (others => '0');
                req_word_reg <= (others => '0');
                req_ir_len_reg <= (others => '0');
                req_ir_data_reg <= (others => '0');
                req_dr_len_reg <= (others => '0');
                req_dr_data_reg <= (others => '0');
                req_pin_num_reg <= (others => '0');
                req_pin_val_reg <= '0';
                pend_valid <= '0';
                pend_kind <= HOST_REQ_NONE;
                pend_byte <= (others => '0');
                pend_word <= (others => '0');
                pend_ir_len <= (others => '0');
                pend_ir_data <= (others => '0');
                pend_dr_len <= (others => '0');
                pend_dr_data <= (others => '0');
                pend_pin_num <= (others => '0');
                pend_pin_val <= '0';
                temp_byte <= (others => '0');
                temp_lo <= (others => '0');
                temp_ir_len <= (others => '0');
                temp_dr_len <= (others => '0');
                temp_ir_data <= (others => '0');
                temp_dr_data <= (others => '0');
                temp_pin_num <= (others => '0');
                temp_pin_val <= '0';
            else
                if pend_valid = '1' and busy = '0' then
                    req_valid_reg <= '1';
                    req_kind_reg <= pend_kind;
                    req_byte_reg <= pend_byte;
                    req_word_reg <= pend_word;
                    req_ir_len_reg <= pend_ir_len;
                    req_ir_data_reg <= pend_ir_data;
                    req_dr_len_reg <= pend_dr_len;
                    req_dr_data_reg <= pend_dr_data;
                    req_pin_num_reg <= pend_pin_num;
                    req_pin_val_reg <= pend_pin_val;
                    pend_valid <= '0';
                    pend_kind <= HOST_REQ_NONE;
                end if;

                if rx_valid = '1' and pend_valid = '0' then
                    case state is
                        when ST_IDLE =>
                            active_cmd <= rx_data;
                            param_cnt <= (others => '0');
                            temp_byte <= (others => '0');
                            temp_lo <= (others => '0');
                            temp_ir_len <= (others => '0');
                            temp_dr_len <= (others => '0');
                            temp_ir_data <= (others => '0');
                            temp_dr_data <= (others => '0');
                            temp_pin_num <= (others => '0');
                            temp_pin_val <= '0';
                            case rx_data is
                                when CMD_PING => pend_valid <= '1'; pend_kind <= HOST_REQ_PING;
                                when CMD_LED | CMD_LOAD_IR | CMD_SHIFT_DR | CMD_LOAD_BSR | CMD_SET_PIN |
                                     CMD_READ_PIN | CMD_CHAIN_CFG | CMD_SHIFT_IR_EX | CMD_SHIFT_DR_EX |
                                     CMD_SHIFT_IR_DR_EX | CMD_BSCAN_SAMPLE_EX | CMD_BSCAN_LOAD_EX |
                                     CMD_BSCAN_SET_PIN_EX | CMD_BSCAN_READ_PIN_EX => state <= ST_WAIT_PARAM;
                                when CMD_JTAG_RESET => pend_valid <= '1'; pend_kind <= HOST_REQ_RAW_JTAG_RESET; pend_word <= to_unsigned(10, 16);
                                when CMD_READ_IDCODE => pend_valid <= '1'; pend_kind <= HOST_REQ_RAW_IDCODE;
                                when CMD_SAMPLE_BSR => pend_valid <= '1'; pend_kind <= HOST_REQ_BSCAN_SAMPLE; pend_dr_len <= to_unsigned(LEGACY_BSR_LENGTH, 16);
                                when CMD_READ_TDO => pend_valid <= '1'; pend_kind <= HOST_REQ_DEBUG_READ_TDO;
                                when CMD_TOGGLE_TCK => pend_valid <= '1'; pend_kind <= HOST_REQ_DEBUG_TOGGLE_TCK; pend_word <= to_unsigned(20, 16);
                                when CMD_SET_TMS_HI => pend_valid <= '1'; pend_kind <= HOST_REQ_DEBUG_SET_TMS; pend_byte <= x"01";
                                when CMD_SET_TMS_LO => pend_valid <= '1'; pend_kind <= HOST_REQ_DEBUG_SET_TMS; pend_byte <= x"00";
                                when others => active_cmd <= (others => '0');
                            end case;

                        when ST_WAIT_PARAM =>
                            case active_cmd is
                                when CMD_LED =>
                                    pend_valid <= '1'; pend_kind <= HOST_REQ_LED; pend_byte <= rx_data; active_cmd <= (others => '0'); state <= ST_IDLE;
                                when CMD_LOAD_IR =>
                                    pend_valid <= '1'; pend_kind <= HOST_REQ_RAW_JTAG_SHIFT_IR; pend_ir_len <= to_unsigned(8, 16); pend_ir_data <= (others => '0'); pend_ir_data(7 downto 0) <= rx_data; active_cmd <= (others => '0'); state <= ST_IDLE;
                                when CMD_SHIFT_DR =>
                                    if param_cnt = 0 then
                                        temp_lo <= unsigned(rx_data); param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 1 then
                                        temp_dr_len <= make_u16(temp_lo, rx_data); param_cnt <= param_cnt + 1;
                                    else
                                        next_dr_data := store_byte(temp_dr_data, to_integer(param_cnt) - 2, rx_data);
                                        temp_dr_data <= next_dr_data;
                                        dr_bytes := bytes_for_bits(to_integer(temp_dr_len));
                                        if to_integer(param_cnt) = dr_bytes + 1 then
                                            pend_valid <= '1'; pend_kind <= HOST_REQ_RAW_JTAG_SHIFT_DR; pend_dr_len <= temp_dr_len; pend_dr_data <= next_dr_data; active_cmd <= (others => '0'); state <= ST_IDLE;
                                        end if;
                                        param_cnt <= param_cnt + 1;
                                    end if;
                                when CMD_LOAD_BSR =>
                                    next_dr_data := store_byte(temp_dr_data, to_integer(param_cnt), rx_data);
                                    temp_dr_data <= next_dr_data;
                                    if to_integer(param_cnt) + 1 >= bytes_for_bits(LEGACY_BSR_LENGTH) then
                                        pend_valid <= '1'; pend_kind <= HOST_REQ_BSCAN_LOAD; pend_dr_len <= to_unsigned(LEGACY_BSR_LENGTH, 16); pend_dr_data <= next_dr_data; active_cmd <= (others => '0'); state <= ST_IDLE;
                                    end if;
                                    param_cnt <= param_cnt + 1;
                                when CMD_SET_PIN =>
                                    if param_cnt = 0 then
                                        temp_lo <= unsigned(rx_data); param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 1 then
                                        temp_pin_num <= make_u16(temp_lo, rx_data); param_cnt <= param_cnt + 1;
                                    else
                                        pend_valid <= '1'; pend_kind <= HOST_REQ_BSCAN_SET_PIN; pend_pin_num <= temp_pin_num; pend_pin_val <= rx_data(0); active_cmd <= (others => '0'); state <= ST_IDLE;
                                    end if;
                                when CMD_READ_PIN =>
                                    if param_cnt = 0 then
                                        temp_lo <= unsigned(rx_data); param_cnt <= param_cnt + 1;
                                    else
                                        pend_valid <= '1'; pend_kind <= HOST_REQ_BSCAN_READ_PIN; pend_pin_num <= make_u16(temp_lo, rx_data); active_cmd <= (others => '0'); state <= ST_IDLE;
                                    end if;
                                when CMD_CHAIN_CFG =>
                                    if param_cnt = 0 then
                                        temp_byte <= rx_data; param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 1 then
                                        temp_lo <= unsigned(rx_data); param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 2 then
                                        temp_ir_len <= make_u16(temp_lo, rx_data); param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 3 then
                                        temp_lo <= unsigned(rx_data); param_cnt <= param_cnt + 1;
                                    else
                                        pend_valid <= '1'; pend_kind <= HOST_REQ_CHAIN_CFG; pend_byte <= temp_byte; pend_ir_len <= temp_ir_len; pend_dr_len <= make_u16(temp_lo, rx_data); active_cmd <= (others => '0'); state <= ST_IDLE;
                                    end if;
                                when CMD_SHIFT_IR_EX =>
                                    if param_cnt = 0 then
                                        temp_lo <= unsigned(rx_data); param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 1 then
                                        temp_ir_len <= make_u16(temp_lo, rx_data); param_cnt <= param_cnt + 1;
                                    else
                                        next_ir_data := store_byte(temp_ir_data, to_integer(param_cnt) - 2, rx_data);
                                        temp_ir_data <= next_ir_data;
                                        ir_bytes := bytes_for_bits(to_integer(temp_ir_len));
                                        if to_integer(param_cnt) = ir_bytes + 1 then
                                            pend_valid <= '1'; pend_kind <= HOST_REQ_RAW_JTAG_SHIFT_IR; pend_ir_len <= temp_ir_len; pend_ir_data <= next_ir_data; active_cmd <= (others => '0'); state <= ST_IDLE;
                                        end if;
                                        param_cnt <= param_cnt + 1;
                                    end if;
                                when CMD_SHIFT_DR_EX =>
                                    if param_cnt = 0 then
                                        temp_lo <= unsigned(rx_data); param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 1 then
                                        temp_dr_len <= make_u16(temp_lo, rx_data); param_cnt <= param_cnt + 1;
                                    else
                                        next_dr_data := store_byte(temp_dr_data, to_integer(param_cnt) - 2, rx_data);
                                        temp_dr_data <= next_dr_data;
                                        dr_bytes := bytes_for_bits(to_integer(temp_dr_len));
                                        if to_integer(param_cnt) = dr_bytes + 1 then
                                            pend_valid <= '1'; pend_kind <= HOST_REQ_RAW_JTAG_SHIFT_DR; pend_dr_len <= temp_dr_len; pend_dr_data <= next_dr_data; active_cmd <= (others => '0'); state <= ST_IDLE;
                                        end if;
                                        param_cnt <= param_cnt + 1;
                                    end if;
                                when CMD_SHIFT_IR_DR_EX =>
                                    if param_cnt = 0 then
                                        temp_lo <= unsigned(rx_data); param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 1 then
                                        temp_ir_len <= make_u16(temp_lo, rx_data); param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 2 then
                                        temp_lo <= unsigned(rx_data); param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 3 then
                                        temp_dr_len <= make_u16(temp_lo, rx_data); param_cnt <= param_cnt + 1;
                                    else
                                        ir_bytes := bytes_for_bits(to_integer(temp_ir_len));
                                        dr_bytes := bytes_for_bits(to_integer(temp_dr_len));
                                        if to_integer(param_cnt) < ir_bytes + 4 then
                                            next_ir_data := store_byte(temp_ir_data, to_integer(param_cnt) - 4, rx_data);
                                            temp_ir_data <= next_ir_data;
                                        else
                                            byte_index := to_integer(param_cnt) - 4 - ir_bytes;
                                            next_dr_data := store_byte(temp_dr_data, byte_index, rx_data);
                                            temp_dr_data <= next_dr_data;
                                        end if;
                                        if to_integer(param_cnt) = ir_bytes + dr_bytes + 3 then
                                            pend_valid <= '1'; pend_kind <= HOST_REQ_RAW_JTAG_SHIFT_IR_DR; pend_ir_len <= temp_ir_len; pend_ir_data <= temp_ir_data; pend_dr_len <= temp_dr_len;
                                            if dr_bytes = 0 then pend_dr_data <= temp_dr_data; else pend_dr_data <= store_byte(temp_dr_data, dr_bytes - 1, rx_data); end if;
                                            active_cmd <= (others => '0'); state <= ST_IDLE;
                                        end if;
                                        param_cnt <= param_cnt + 1;
                                    end if;
                                when CMD_BSCAN_SAMPLE_EX | CMD_BSCAN_READ_PIN_EX =>
                                    if param_cnt = 0 then
                                        temp_lo <= unsigned(rx_data); param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 1 then
                                        temp_ir_len <= make_u16(temp_lo, rx_data); param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 2 then
                                        temp_lo <= unsigned(rx_data); param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 3 then
                                        temp_dr_len <= make_u16(temp_lo, rx_data); param_cnt <= param_cnt + 1;
                                    elsif active_cmd = CMD_BSCAN_READ_PIN_EX and param_cnt = 4 then
                                        temp_lo <= unsigned(rx_data); param_cnt <= param_cnt + 1;
                                    elsif active_cmd = CMD_BSCAN_READ_PIN_EX and param_cnt = 5 then
                                        temp_pin_num <= make_u16(temp_lo, rx_data); param_cnt <= param_cnt + 1;
                                    else
                                        if active_cmd = CMD_BSCAN_SAMPLE_EX then byte_index := to_integer(param_cnt) - 4; else byte_index := to_integer(param_cnt) - 6; end if;
                                        next_ir_data := store_byte(temp_ir_data, byte_index, rx_data);
                                        temp_ir_data <= next_ir_data;
                                        ir_bytes := bytes_for_bits(to_integer(temp_ir_len));
                                        if (active_cmd = CMD_BSCAN_SAMPLE_EX and to_integer(param_cnt) = ir_bytes + 3) or
                                           (active_cmd = CMD_BSCAN_READ_PIN_EX and to_integer(param_cnt) = ir_bytes + 5) then
                                            pend_valid <= '1';
                                            if active_cmd = CMD_BSCAN_SAMPLE_EX then pend_kind <= HOST_REQ_BSCAN_SAMPLE_EX; else pend_kind <= HOST_REQ_BSCAN_READ_PIN_EX; pend_pin_num <= temp_pin_num; end if;
                                            pend_ir_len <= temp_ir_len; pend_ir_data <= next_ir_data; pend_dr_len <= temp_dr_len; active_cmd <= (others => '0'); state <= ST_IDLE;
                                        end if;
                                        param_cnt <= param_cnt + 1;
                                    end if;
                                when CMD_BSCAN_LOAD_EX | CMD_BSCAN_SET_PIN_EX =>
                                    if param_cnt = 0 then
                                        temp_lo <= unsigned(rx_data); param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 1 then
                                        temp_ir_len <= make_u16(temp_lo, rx_data); param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 2 then
                                        temp_lo <= unsigned(rx_data); param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 3 then
                                        temp_dr_len <= make_u16(temp_lo, rx_data); param_cnt <= param_cnt + 1;
                                    elsif active_cmd = CMD_BSCAN_SET_PIN_EX and param_cnt = 4 then
                                        temp_lo <= unsigned(rx_data); param_cnt <= param_cnt + 1;
                                    elsif active_cmd = CMD_BSCAN_SET_PIN_EX and param_cnt = 5 then
                                        temp_pin_num <= make_u16(temp_lo, rx_data); param_cnt <= param_cnt + 1;
                                    elsif active_cmd = CMD_BSCAN_SET_PIN_EX and param_cnt = 6 then
                                        temp_pin_val <= rx_data(0); param_cnt <= param_cnt + 1;
                                    else
                                        ir_bytes := bytes_for_bits(to_integer(temp_ir_len));
                                        if active_cmd = CMD_BSCAN_LOAD_EX then
                                            dr_bytes := bytes_for_bits(to_integer(temp_dr_len));
                                            if to_integer(param_cnt) < ir_bytes + 4 then
                                                next_ir_data := store_byte(temp_ir_data, to_integer(param_cnt) - 4, rx_data);
                                                temp_ir_data <= next_ir_data;
                                            else
                                                byte_index := to_integer(param_cnt) - 4 - ir_bytes;
                                                next_dr_data := store_byte(temp_dr_data, byte_index, rx_data);
                                                temp_dr_data <= next_dr_data;
                                            end if;
                                            if to_integer(param_cnt) = ir_bytes + dr_bytes + 3 then
                                                pend_valid <= '1'; pend_kind <= HOST_REQ_BSCAN_LOAD_EX; pend_ir_len <= temp_ir_len; pend_ir_data <= temp_ir_data; pend_dr_len <= temp_dr_len;
                                                if dr_bytes = 0 then pend_dr_data <= temp_dr_data; else pend_dr_data <= store_byte(temp_dr_data, dr_bytes - 1, rx_data); end if;
                                                active_cmd <= (others => '0'); state <= ST_IDLE;
                                            end if;
                                        else
                                            byte_index := to_integer(param_cnt) - 7;
                                            next_ir_data := store_byte(temp_ir_data, byte_index, rx_data);
                                            temp_ir_data <= next_ir_data;
                                            if to_integer(param_cnt) = ir_bytes + 6 then
                                                pend_valid <= '1'; pend_kind <= HOST_REQ_BSCAN_SET_PIN_EX; pend_ir_len <= temp_ir_len; pend_ir_data <= next_ir_data; pend_dr_len <= temp_dr_len; pend_pin_num <= temp_pin_num; pend_pin_val <= temp_pin_val; active_cmd <= (others => '0'); state <= ST_IDLE;
                                            end if;
                                        end if;
                                        param_cnt <= param_cnt + 1;
                                    end if;
                                when others =>
                                    active_cmd <= (others => '0'); state <= ST_IDLE;
                            end case;
                    end case;
                end if;
            end if;
        end if;
    end process;
end architecture;
