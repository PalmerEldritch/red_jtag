library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.jtag_pkg.all;

entity host_cmd_parser is
    generic (
        BSR_LENGTH : natural := 362
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;

        rx_valid        : in  std_logic;
        rx_data         : in  std_logic_vector(7 downto 0);

        req_valid       : out std_logic;
        req_kind        : out host_req_kind_t;

        req_byte        : out std_logic_vector(7 downto 0);
        req_word        : out unsigned(15 downto 0);
        req_data        : out std_logic_vector(BSR_LENGTH-1 downto 0);
        req_data_len    : out unsigned(15 downto 0);

        busy            : in  std_logic
    );
end entity;

architecture rtl of host_cmd_parser is

    function store_byte(
        data_in : std_logic_vector(BSR_LENGTH-1 downto 0);
        index   : natural;
        value   : std_logic_vector(7 downto 0)
    ) return std_logic_vector is
        variable result : std_logic_vector(BSR_LENGTH-1 downto 0) := data_in;
        variable bitpos : natural;
    begin
        for i in 0 to 7 loop
            bitpos := index * 8 + i;
            if bitpos < BSR_LENGTH then
                result(bitpos) := value(i);
            end if;
        end loop;
        return result;
    end function;

    type parser_state_t is (
        ST_IDLE,
        ST_WAIT_PARAM
    );

    signal state            : parser_state_t := ST_IDLE;
    signal active_cmd       : std_logic_vector(7 downto 0) := (others => '0');
    signal param_cnt        : unsigned(15 downto 0) := (others => '0');
    signal param_need       : unsigned(15 downto 0) := (others => '0');

    signal req_valid_reg    : std_logic := '0';
    signal req_kind_reg     : host_req_kind_t := HOST_REQ_NONE;
    signal req_byte_reg     : std_logic_vector(7 downto 0) := (others => '0');
    signal req_word_reg     : unsigned(15 downto 0) := (others => '0');
    signal req_data_reg     : std_logic_vector(BSR_LENGTH-1 downto 0) := (others => '0');
    signal req_data_len_reg : unsigned(15 downto 0) := (others => '0');

    signal pend_valid       : std_logic := '0';
    signal pend_kind        : host_req_kind_t := HOST_REQ_NONE;
    signal pend_byte        : std_logic_vector(7 downto 0) := (others => '0');
    signal pend_word        : unsigned(15 downto 0) := (others => '0');
    signal pend_data        : std_logic_vector(BSR_LENGTH-1 downto 0) := (others => '0');
    signal pend_data_len    : unsigned(15 downto 0) := (others => '0');

    signal temp_byte        : std_logic_vector(7 downto 0) := (others => '0');
    signal temp_word        : unsigned(15 downto 0) := (others => '0');
    signal temp_data        : std_logic_vector(BSR_LENGTH-1 downto 0) := (others => '0');
    signal temp_data_len    : unsigned(15 downto 0) := (others => '0');

begin

    req_valid <= req_valid_reg;
    req_kind <= req_kind_reg;
    req_byte <= req_byte_reg;
    req_word <= req_word_reg;
    req_data <= req_data_reg;
    req_data_len <= req_data_len_reg;

    process(clk)
        variable byte_idx       : integer;
        variable bytes_needed   : natural;
        variable raw_len        : unsigned(15 downto 0);
        variable next_data      : std_logic_vector(BSR_LENGTH-1 downto 0);
        variable next_param_cnt : unsigned(15 downto 0);
    begin
        if rising_edge(clk) then
            req_valid_reg <= '0';

            if rst_n = '0' then
                state <= ST_IDLE;
                active_cmd <= (others => '0');
                param_cnt <= (others => '0');
                param_need <= (others => '0');
                req_kind_reg <= HOST_REQ_NONE;
                req_byte_reg <= (others => '0');
                req_word_reg <= (others => '0');
                req_data_reg <= (others => '0');
                req_data_len_reg <= (others => '0');
                pend_valid <= '0';
                pend_kind <= HOST_REQ_NONE;
                pend_byte <= (others => '0');
                pend_word <= (others => '0');
                pend_data <= (others => '0');
                pend_data_len <= (others => '0');
                temp_byte <= (others => '0');
                temp_word <= (others => '0');
                temp_data <= (others => '0');
                temp_data_len <= (others => '0');
            else
                if pend_valid = '1' and busy = '0' then
                    req_valid_reg <= '1';
                    req_kind_reg <= pend_kind;
                    req_byte_reg <= pend_byte;
                    req_word_reg <= pend_word;
                    req_data_reg <= pend_data;
                    req_data_len_reg <= pend_data_len;
                    pend_valid <= '0';
                    pend_kind <= HOST_REQ_NONE;
                end if;

                if rx_valid = '1' and pend_valid = '0' then
                    case state is
                        when ST_IDLE =>
                            active_cmd <= rx_data;
                            param_cnt <= (others => '0');
                            param_need <= (others => '0');
                            temp_byte <= (others => '0');
                            temp_word <= (others => '0');
                            temp_data <= (others => '0');
                            temp_data_len <= (others => '0');

                            case rx_data is
                                when CMD_PING =>
                                    pend_valid <= '1';
                                    pend_kind <= HOST_REQ_PING;
                                    pend_byte <= (others => '0');
                                    pend_word <= (others => '0');
                                    pend_data <= (others => '0');
                                    pend_data_len <= (others => '0');

                                when CMD_LED =>
                                    state <= ST_WAIT_PARAM;
                                    param_need <= to_unsigned(1, param_need'length);

                                when CMD_JTAG_RESET =>
                                    pend_valid <= '1';
                                    pend_kind <= HOST_REQ_RAW_JTAG_RESET;
                                    pend_byte <= (others => '0');
                                    pend_word <= to_unsigned(10, 16);
                                    pend_data <= (others => '0');
                                    pend_data_len <= (others => '0');

                                when CMD_READ_IDCODE =>
                                    pend_valid <= '1';
                                    pend_kind <= HOST_REQ_RAW_IDCODE;
                                    pend_byte <= (others => '0');
                                    pend_word <= (others => '0');
                                    pend_data <= (others => '0');
                                    pend_data_len <= (others => '0');

                                when CMD_LOAD_IR =>
                                    state <= ST_WAIT_PARAM;
                                    param_need <= to_unsigned(1, param_need'length);

                                when CMD_SHIFT_DR =>
                                    state <= ST_WAIT_PARAM;
                                    param_need <= to_unsigned(2, param_need'length);

                                when CMD_SAMPLE_BSR =>
                                    pend_valid <= '1';
                                    pend_kind <= HOST_REQ_BSCAN_SAMPLE;
                                    pend_byte <= (others => '0');
                                    pend_word <= (others => '0');
                                    pend_data <= (others => '0');
                                    pend_data_len <= to_unsigned(BSR_LENGTH, 16);

                                when CMD_LOAD_BSR =>
                                    state <= ST_WAIT_PARAM;
                                    param_need <= to_unsigned(bytes_for_bits(BSR_LENGTH), param_need'length);
                                    temp_data_len <= to_unsigned(BSR_LENGTH, 16);

                                when CMD_SET_PIN =>
                                    state <= ST_WAIT_PARAM;
                                    param_need <= to_unsigned(3, param_need'length);

                                when CMD_READ_PIN =>
                                    state <= ST_WAIT_PARAM;
                                    param_need <= to_unsigned(2, param_need'length);

                                when CMD_READ_TDO =>
                                    pend_valid <= '1';
                                    pend_kind <= HOST_REQ_DEBUG_READ_TDO;
                                    pend_byte <= (others => '0');
                                    pend_word <= (others => '0');
                                    pend_data <= (others => '0');
                                    pend_data_len <= (others => '0');

                                when CMD_TOGGLE_TCK =>
                                    pend_valid <= '1';
                                    pend_kind <= HOST_REQ_DEBUG_TOGGLE_TCK;
                                    pend_byte <= (others => '0');
                                    pend_word <= to_unsigned(20, 16);
                                    pend_data <= (others => '0');
                                    pend_data_len <= (others => '0');

                                when CMD_SET_TMS_HI =>
                                    pend_valid <= '1';
                                    pend_kind <= HOST_REQ_DEBUG_SET_TMS;
                                    pend_byte <= x"01";
                                    pend_word <= (others => '0');
                                    pend_data <= (others => '0');
                                    pend_data_len <= (others => '0');

                                when CMD_SET_TMS_LO =>
                                    pend_valid <= '1';
                                    pend_kind <= HOST_REQ_DEBUG_SET_TMS;
                                    pend_byte <= x"00";
                                    pend_word <= (others => '0');
                                    pend_data <= (others => '0');
                                    pend_data_len <= (others => '0');

                                when CMD_I2C_WRITE =>
                                    state <= ST_WAIT_PARAM;
                                    param_need <= to_unsigned(2, param_need'length);

                                when CMD_I2C_READ =>
                                    state <= ST_WAIT_PARAM;
                                    param_need <= to_unsigned(2, param_need'length);

                                when CMD_I2C_WR_RD =>
                                    state <= ST_WAIT_PARAM;
                                    param_need <= to_unsigned(3, param_need'length);

                                when CMD_I2C_SCAN =>
                                    pend_valid <= '1';
                                    pend_kind <= HOST_REQ_I2C_SCAN;
                                    pend_byte <= (others => '0');
                                    pend_word <= (others => '0');
                                    pend_data <= (others => '0');
                                    pend_data_len <= (others => '0');

                                when others =>
                                    active_cmd <= (others => '0');
                                    state <= ST_IDLE;
                            end case;

                        when ST_WAIT_PARAM =>
                            case active_cmd is
                                when CMD_LED =>
                                    pend_valid <= '1';
                                    pend_kind <= HOST_REQ_LED;
                                    pend_byte <= rx_data;
                                    pend_word <= (others => '0');
                                    pend_data <= (others => '0');
                                    pend_data_len <= (others => '0');
                                    active_cmd <= (others => '0');
                                    state <= ST_IDLE;

                                when CMD_LOAD_IR =>
                                    pend_valid <= '1';
                                    pend_kind <= HOST_REQ_RAW_JTAG_LOAD_IR;
                                    pend_byte <= rx_data;
                                    pend_word <= (others => '0');
                                    pend_data <= (others => '0');
                                    pend_data_len <= (others => '0');
                                    active_cmd <= (others => '0');
                                    state <= ST_IDLE;

                                when CMD_SHIFT_DR =>
                                    if param_cnt = 0 then
                                        temp_data_len(7 downto 0) <= unsigned(rx_data);
                                        param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 1 then
                                        raw_len := unsigned(rx_data) & temp_data_len(7 downto 0);
                                        temp_data_len <= raw_len;
                                        bytes_needed := bytes_for_bits(to_integer(raw_len));
                                        param_need <= to_unsigned(bytes_needed + 2, param_need'length);
                                        param_cnt <= param_cnt + 1;
                                        temp_data <= (others => '0');
                                    else
                                        next_data := store_byte(temp_data, to_integer(param_cnt) - 2, rx_data);
                                        byte_idx := to_integer(param_cnt) - 2;
                                        temp_data <= next_data;
                                        next_param_cnt := param_cnt + 1;
                                        param_cnt <= next_param_cnt;

                                        if next_param_cnt >= param_need then
                                            pend_valid <= '1';
                                            pend_kind <= HOST_REQ_RAW_JTAG_SHIFT_DR;
                                            pend_byte <= (others => '0');
                                            pend_word <= (others => '0');
                                            pend_data <= next_data;
                                            pend_data_len <= temp_data_len;
                                            active_cmd <= (others => '0');
                                            state <= ST_IDLE;
                                        end if;
                                    end if;

                                when CMD_LOAD_BSR =>
                                    byte_idx := to_integer(param_cnt);
                                    next_data := store_byte(temp_data, byte_idx, rx_data);
                                    temp_data <= next_data;
                                    next_param_cnt := param_cnt + 1;
                                    param_cnt <= next_param_cnt;

                                    if next_param_cnt >= param_need then
                                        pend_valid <= '1';
                                        pend_kind <= HOST_REQ_BSCAN_LOAD;
                                        pend_byte <= (others => '0');
                                        pend_word <= (others => '0');
                                        pend_data <= next_data;
                                        pend_data_len <= temp_data_len;
                                        active_cmd <= (others => '0');
                                        state <= ST_IDLE;
                                    end if;

                                when CMD_SET_PIN =>
                                    if param_cnt = 0 then
                                        temp_word(7 downto 0) <= unsigned(rx_data);
                                        param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 1 then
                                        temp_word(15 downto 8) <= unsigned(rx_data);
                                        param_cnt <= param_cnt + 1;
                                    else
                                        pend_valid <= '1';
                                        pend_kind <= HOST_REQ_BSCAN_SET_PIN;
                                        pend_byte <= (7 downto 1 => '0', 0 => rx_data(0));
                                        pend_word <= temp_word;
                                        pend_data <= (others => '0');
                                        pend_data_len <= (others => '0');
                                        active_cmd <= (others => '0');
                                        state <= ST_IDLE;
                                    end if;

                                when CMD_READ_PIN =>
                                    if param_cnt = 0 then
                                        temp_word(7 downto 0) <= unsigned(rx_data);
                                        param_cnt <= param_cnt + 1;
                                    else
                                        temp_word(15 downto 8) <= unsigned(rx_data);
                                        pend_valid <= '1';
                                        pend_kind <= HOST_REQ_BSCAN_READ_PIN;
                                        pend_byte <= (others => '0');
                                        pend_word <= unsigned(rx_data) & temp_word(7 downto 0);
                                        pend_data <= (others => '0');
                                        pend_data_len <= (others => '0');
                                        active_cmd <= (others => '0');
                                        state <= ST_IDLE;
                                    end if;

                                when CMD_I2C_WRITE =>
                                    if param_cnt = 0 then
                                        temp_byte <= rx_data;
                                        param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 1 then
                                        temp_word(7 downto 0) <= unsigned(rx_data);
                                        temp_word(15 downto 8) <= (others => '0');
                                        temp_data_len <= to_unsigned(to_integer(unsigned(rx_data)) * 8, 16);
                                        param_cnt <= param_cnt + 1;
                                        temp_data <= (others => '0');
                                        if unsigned(rx_data) = 0 then
                                            pend_valid <= '1';
                                            pend_kind <= HOST_REQ_I2C_WRITE;
                                            pend_byte <= temp_byte;
                                            pend_word <= temp_word(15 downto 8) & unsigned(rx_data);
                                            pend_data <= (others => '0');
                                            pend_data_len <= (others => '0');
                                            active_cmd <= (others => '0');
                                            state <= ST_IDLE;
                                        else
                                            param_need <= resize(unsigned(rx_data) + 2, param_need'length);
                                        end if;
                                    else
                                        next_data := store_byte(temp_data, to_integer(param_cnt) - 2, rx_data);
                                        byte_idx := to_integer(param_cnt) - 2;
                                        temp_data <= next_data;
                                        next_param_cnt := param_cnt + 1;
                                        param_cnt <= next_param_cnt;
                                        if next_param_cnt >= param_need then
                                            pend_valid <= '1';
                                            pend_kind <= HOST_REQ_I2C_WRITE;
                                            pend_byte <= temp_byte;
                                            pend_word <= temp_word;
                                            pend_data <= next_data;
                                            pend_data_len <= temp_data_len;
                                            active_cmd <= (others => '0');
                                            state <= ST_IDLE;
                                        end if;
                                    end if;

                                when CMD_I2C_READ =>
                                    if param_cnt = 0 then
                                        temp_byte <= rx_data;
                                        param_cnt <= param_cnt + 1;
                                    else
                                        pend_valid <= '1';
                                        pend_kind <= HOST_REQ_I2C_READ;
                                        pend_byte <= temp_byte;
                                        pend_word <= resize(unsigned(rx_data), 16);
                                        pend_data <= (others => '0');
                                        pend_data_len <= (others => '0');
                                        active_cmd <= (others => '0');
                                        state <= ST_IDLE;
                                    end if;

                                when CMD_I2C_WR_RD =>
                                    if param_cnt = 0 then
                                        temp_byte <= rx_data;
                                        param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 1 then
                                        temp_word(7 downto 0) <= unsigned(rx_data);
                                        temp_data_len <= to_unsigned(to_integer(unsigned(rx_data)) * 8, 16);
                                        param_cnt <= param_cnt + 1;
                                    elsif param_cnt = 2 then
                                        temp_word(15 downto 8) <= unsigned(rx_data);
                                        temp_data <= (others => '0');
                                        next_param_cnt := param_cnt + 1;
                                        param_cnt <= next_param_cnt;
                                        if temp_word(7 downto 0) = 0 then
                                            pend_valid <= '1';
                                            pend_kind <= HOST_REQ_I2C_WR_RD;
                                            pend_byte <= temp_byte;
                                            pend_word <= unsigned(rx_data) & temp_word(7 downto 0);
                                            pend_data <= (others => '0');
                                            pend_data_len <= (others => '0');
                                            active_cmd <= (others => '0');
                                            state <= ST_IDLE;
                                        else
                                            param_need <= resize(temp_word(7 downto 0), param_need'length) + 3;
                                        end if;
                                    else
                                        next_data := store_byte(temp_data, to_integer(param_cnt) - 3, rx_data);
                                        byte_idx := to_integer(param_cnt) - 3;
                                        temp_data <= next_data;
                                        next_param_cnt := param_cnt + 1;
                                        param_cnt <= next_param_cnt;
                                        if next_param_cnt >= param_need then
                                            pend_valid <= '1';
                                            pend_kind <= HOST_REQ_I2C_WR_RD;
                                            pend_byte <= temp_byte;
                                            pend_word <= temp_word;
                                            pend_data <= next_data;
                                            pend_data_len <= temp_data_len;
                                            active_cmd <= (others => '0');
                                            state <= ST_IDLE;
                                        end if;
                                    end if;

                                when others =>
                                    active_cmd <= (others => '0');
                                    state <= ST_IDLE;
                            end case;
                    end case;
                end if;
            end if;
        end if;
    end process;

end architecture;
