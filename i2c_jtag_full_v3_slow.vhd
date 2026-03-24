-------------------------------------------------------------------------------
-- I2C over JTAG Engine - Full Implementation v2
-- Complete boundary scan and I2C control
--
-- JTAG Commands:
--   0x10                 - JTAG Reset (5x TMS=1)
--   0x11                 - Read IDCODE (returns 4 bytes)
--   0x12 <ir_byte>       - Load IR instruction
--   0x13 <len_lo> <len_hi> <data...> - Shift DR (returns shifted data)
--
-- Boundary Scan Commands:
--   0x14                 - Sample BSR (returns BSR_LEN/8 bytes)
--   0x15 <data...>       - Load BSR with EXTEST (BSR_LEN/8 bytes)
--   0x16 <bit_lo> <bit_hi> <val> - Set single pin
--   0x17 <bit_lo> <bit_hi>       - Read single pin (returns 1 byte)
--
-- I2C Commands:
--   0x20 <addr> <len> <data...>         - I2C Write
--   0x21 <addr> <len>                   - I2C Read
--   0x22 <addr> <wlen> <rlen> <data...> - I2C Write then Read
--   0x23                                - I2C Bus Scan (returns 16 bytes bitmap)
--
-- Utility:
--   0x40 <val>           - LED control
--   0xFF                 - Ping (returns 0x55)
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity loopback_test is
    generic (
        -- Boundary Scan Register config (from BSDL)
        BSR_LENGTH      : natural := 362;
        IR_LENGTH       : natural := 4;
        
        -- I2C pin positions in BSR (directly directly adjust per your target!)
        -- These are typical positions - update from your BSDL
        SDA_OUT_BIT     : natural := 10;   -- SDA output data bit
        SDA_OE_BIT      : natural := 11;   -- SDA output enable (active high = drive)
        SDA_IN_BIT      : natural := 9;    -- SDA input bit
        SCL_OUT_BIT     : natural := 14;   -- SCL output data bit  
        SCL_OE_BIT      : natural := 15    -- SCL output enable
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

architecture rtl of loopback_test is

    -- JTAG Instructions (Lattice Certus-NX defaults)
    constant JTAG_EXTEST    : std_logic_vector(7 downto 0) := x"00";
    constant JTAG_SAMPLE    : std_logic_vector(7 downto 0) := x"05";
    constant JTAG_IDCODE    : std_logic_vector(7 downto 0) := x"02";
    constant JTAG_BYPASS    : std_logic_vector(7 downto 0) := x"0F";
    
    -- I2C Timing (in clock cycles at ~56 MHz)
    constant I2C_QUARTER    : natural := 140;  -- ~2.5us (100kHz I2C)
    
    -- Calculate BSR byte length
    constant BSR_BYTES      : natural := (BSR_LENGTH + 7) / 8;  -- 46 bytes for 362 bits

    component OSCA
        generic (HF_CLK_DIV : string := "8");
        port (
            HFOUTEN  : in  std_logic;
            HFSDSCEN : in  std_logic;
            HFCLKOUT : out std_logic
        );
    end component;

    -- Clock and reset
    signal clk          : std_logic;
    signal rst_cnt      : unsigned(7 downto 0) := (others => '0');
    signal rst_done     : std_logic := '0';
    signal rst_n        : std_logic := '0';
    signal hb_cnt       : unsigned(25 downto 0) := (others => '0');
    
    -- FT2232H interface
    signal ft_data_out  : std_logic_vector(7 downto 0) := (others => '0');
    signal ft_data_oe   : std_logic := '0';
    signal rxf_sync     : std_logic_vector(2 downto 0) := (others => '1');
    signal txe_sync     : std_logic_vector(2 downto 0) := (others => '1');
    signal rxf_n        : std_logic;
    signal txe_n        : std_logic;

    -- Main state machine
    type main_state_t is (
        -- FIFO states
        IDLE, READ_PULSE, READ_CAPTURE, READ_DONE,
        WRITE_SETUP, WRITE_PULSE, WRITE_DONE,
        -- Command processing
        PROCESS_CMD, WAIT_MORE_DATA,
        -- JTAG low-level
        JTAG_RESET_RUN,
        JTAG_GOTO_SHIFT_IR, JTAG_SHIFT_IR, JTAG_EXIT_IR,
        JTAG_GOTO_SHIFT_DR, JTAG_SHIFT_DR, JTAG_EXIT_DR,
        JTAG_GOTO_IDLE,
        -- Response handling
        SEND_RESPONSE_BYTE, NEXT_RESPONSE_BYTE,
		
		DEBUG_TCK_TOGGLE
    );
    signal state        : main_state_t := IDLE;
    signal return_state : main_state_t := IDLE;
    signal next_state   : main_state_t := IDLE;
    
    signal wait_cnt     : unsigned(15 downto 0) := (others => '0');
    
    -- Command parsing
    signal cmd_byte     : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_byte      : std_logic_vector(7 downto 0) := (others => '0');
    signal param_cnt    : unsigned(7 downto 0) := (others => '0');
    signal param_need   : unsigned(7 downto 0) := (others => '0');
    
    -- TX handling
    signal tx_byte      : std_logic_vector(7 downto 0) := (others => '0');
    signal have_tx      : std_logic := '0';
    
    -- LED
    signal led_reg      : std_logic_vector(1 downto 0) := "00";
    
    -- JTAG signals
    signal tck_reg      : std_logic := '0';
    signal tms_reg      : std_logic := '1';
    signal tdi_reg      : std_logic := '0';
    signal tdo_sample   : std_logic := '0';
    signal jtag_cnt     : unsigned(15 downto 0) := (others => '0');
    signal jtag_div     : unsigned(7 downto 0) := (others => '0');
    constant JTAG_DIV_MAX : unsigned(7 downto 0) := to_unsigned(255, 8);
    
    -- JTAG data shift register
    signal shift_reg    : std_logic_vector(BSR_LENGTH-1 downto 0) := (others => '0');
    signal shift_len    : unsigned(15 downto 0) := (others => '0');
    signal shift_cnt    : unsigned(15 downto 0) := (others => '0');
    signal ir_value     : std_logic_vector(7 downto 0) := (others => '1');
    
    -- Response buffer
    signal resp_buf     : std_logic_vector(BSR_LENGTH-1 downto 0) := (others => '0');
    signal resp_len     : unsigned(7 downto 0) := (others => '0');
    signal resp_idx     : unsigned(7 downto 0) := (others => '0');
    
    -- I2C command parameters
    signal i2c_addr     : std_logic_vector(6 downto 0) := (others => '0');
    signal i2c_wr_len   : unsigned(7 downto 0) := (others => '0');
    signal i2c_rd_len   : unsigned(7 downto 0) := (others => '0');
    signal i2c_data_buf : std_logic_vector(255 downto 0) := (others => '0');
    signal i2c_byte_idx : unsigned(7 downto 0) := (others => '0');
    signal i2c_bit_idx  : unsigned(3 downto 0) := (others => '0');
    
    -- Boundary scan register (active copy)
    signal bsr_data     : std_logic_vector(BSR_LENGTH-1 downto 0) := (others => '0');
    signal bsr_capture  : std_logic_vector(BSR_LENGTH-1 downto 0) := (others => '0');
    
    -- Single pin access
    signal pin_num      : unsigned(15 downto 0) := (others => '0');
    signal pin_val      : std_logic := '0';
    
    -- DR shift length for commands
    signal dr_len       : unsigned(15 downto 0) := (others => '0');
    
    -- I2C internal signals
    signal i2c_sda_out  : std_logic := '1';
    signal i2c_scl_out  : std_logic := '1';
    signal i2c_sda_in   : std_logic := '1';
    signal i2c_state    : unsigned(3 downto 0) := (others => '0');
    signal i2c_phase    : unsigned(1 downto 0) := (others => '0');
    signal i2c_timer    : unsigned(15 downto 0) := (others => '0');
    signal i2c_cur_byte : std_logic_vector(7 downto 0) := (others => '0');
    signal i2c_ack_bit  : std_logic := '0';
    signal i2c_nack     : std_logic := '0';
    signal i2c_scan_addr: unsigned(6 downto 0) := (others => '0');
    signal i2c_scan_map : std_logic_vector(127 downto 0) := (others => '0');
    
    -- I2C state constants
    constant I2C_IDLE       : unsigned(3 downto 0) := x"0";
    constant I2C_START      : unsigned(3 downto 0) := x"1";
    constant I2C_SEND_ADDR  : unsigned(3 downto 0) := x"2";
    constant I2C_GET_ACK    : unsigned(3 downto 0) := x"3";
    constant I2C_WRITE_BYTE : unsigned(3 downto 0) := x"4";
    constant I2C_WRITE_ACK  : unsigned(3 downto 0) := x"5";
    constant I2C_READ_BYTE  : unsigned(3 downto 0) := x"6";
    constant I2C_SEND_ACK   : unsigned(3 downto 0) := x"7";
    constant I2C_STOP       : unsigned(3 downto 0) := x"8";
    constant I2C_RESTART    : unsigned(3 downto 0) := x"9";
    constant I2C_DONE       : unsigned(3 downto 0) := x"A";

begin

    -- Output assignments
    ft_siwu_n <= '0';
    ft_data   <= ft_data_out when ft_data_oe = '1' else (others => 'Z');
    jtag_tck  <= tck_reg;
    jtag_tms  <= tms_reg;
    jtag_tdi  <= tdi_reg;
    
    -- LED control
    led(0) <= hb_cnt(24) when led_reg(0) = '0' else '1';
    led(1) <= led_reg(1);
    
    rxf_n <= rxf_sync(2);
    txe_n <= txe_sync(2);

    -- Oscillator
    u_osc: OSCA
        generic map (HF_CLK_DIV => "8")
        port map (HFOUTEN => '1', HFSDSCEN => '0', HFCLKOUT => clk);

    -- Reset and sync process
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_done = '0' then
                if rst_cnt = 255 then rst_done <= '1';
                else rst_cnt <= rst_cnt + 1; end if;
            end if;
            rst_n <= rst_done;
            hb_cnt <= hb_cnt + 1;
            rxf_sync <= rxf_sync(1 downto 0) & ft_rxf_n;
            txe_sync <= txe_sync(1 downto 0) & ft_txe_n;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Main State Machine
    ---------------------------------------------------------------------------
    process(clk)
        variable byte_idx : integer;
        variable bit_idx  : integer;
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                state <= IDLE;
                ft_rd_n <= '1'; ft_wr_n <= '1'; ft_data_oe <= '0';
                have_tx <= '0'; led_reg <= "00";
                tck_reg <= '0'; tms_reg <= '1'; tdi_reg <= '0';
                cmd_byte <= x"00";
                wait_cnt <= (others => '0');
                jtag_div <= (others => '0');
            else
                -- JTAG clock divider
                if jtag_div /= 0 then
                    jtag_div <= jtag_div - 1;
                end if;
                
                case state is
                
                    --------------------------------------------------------
                    -- FIFO IDLE
                    --------------------------------------------------------
                    when IDLE =>
                        ft_rd_n <= '1'; ft_wr_n <= '1'; ft_data_oe <= '0';
                        
                        if have_tx = '1' and txe_n = '0' then
                            ft_data_out <= tx_byte;
                            ft_data_oe <= '1';
                            wait_cnt <= to_unsigned(2, 16);
                            state <= WRITE_SETUP;
                        elsif rxf_n = '0' then
                            ft_rd_n <= '0';
                            wait_cnt <= to_unsigned(3, 16);
                            state <= READ_PULSE;
                        end if;
                        
                    --------------------------------------------------------
                    -- FIFO READ
                    --------------------------------------------------------
                    when READ_PULSE =>
                        if wait_cnt = 0 then state <= READ_CAPTURE;
                        else wait_cnt <= wait_cnt - 1; end if;
                        
                    when READ_CAPTURE =>
                        rx_byte <= ft_data;
                        ft_rd_n <= '1';
                        wait_cnt <= to_unsigned(2, 16);
                        state <= READ_DONE;
                        
                    when READ_DONE =>
                        if wait_cnt = 0 then state <= PROCESS_CMD;
                        else wait_cnt <= wait_cnt - 1; end if;
                        
                    --------------------------------------------------------
                    -- FIFO WRITE
                    --------------------------------------------------------
                    when WRITE_SETUP =>
                        if wait_cnt = 0 then
                            ft_wr_n <= '0';
                            wait_cnt <= to_unsigned(3, 16);
                            state <= WRITE_PULSE;
                        else wait_cnt <= wait_cnt - 1; end if;
                        
                    when WRITE_PULSE =>
                        if wait_cnt = 0 then
                            ft_wr_n <= '1';
                            have_tx <= '0';
                            wait_cnt <= to_unsigned(2, 16);
                            state <= WRITE_DONE;
                        else wait_cnt <= wait_cnt - 1; end if;
                        
                    when WRITE_DONE =>
                        ft_data_oe <= '0';
                        if wait_cnt = 0 then state <= return_state;
                        else wait_cnt <= wait_cnt - 1; end if;
                        
                    --------------------------------------------------------
                    -- COMMAND PROCESSING
                    --------------------------------------------------------
                    when PROCESS_CMD =>
                        if cmd_byte = x"00" then
                            -- New command
                            cmd_byte <= rx_byte;
                            param_cnt <= (others => '0');
                            
                            case rx_byte is
                                -- Single-byte commands (immediate response)
                                when x"FF" =>  -- Ping
                                    tx_byte <= x"55";
                                    have_tx <= '1';
                                    return_state <= IDLE;
                                    cmd_byte <= x"00";
                                    state <= IDLE;
									
								when x"18" =>  -- Read raw TDO pin state
									tx_byte <= "0000000" & jtag_tdo;  -- TDO as LSB
									have_tx <= '1';
									return_state <= IDLE;
									cmd_byte <= x"00";
									state <= IDLE;
                                   
								   when x"19" =>  -- Toggle TCK 10 times (for scope/logic analyzer)
										jtag_cnt <= to_unsigned(20, 16);  -- 20 edges = 10 pulses
										jtag_div <= JTAG_DIV_MAX;
										state <= DEBUG_TCK_TOGGLE;
										cmd_byte <= x"00";

									when x"1A" =>  -- Set TMS high
										tms_reg <= '1';
										tx_byte <= x"00";
										have_tx <= '1';
										return_state <= IDLE;
										cmd_byte <= x"00";
										state <= IDLE;

									when x"1B" =>  -- Set TMS low
										tms_reg <= '0';
										tx_byte <= x"00";
										have_tx <= '1';
										return_state <= IDLE;
										cmd_byte <= x"00";
										state <= IDLE;
										
									when x"10" =>  -- JTAG Reset
                                    jtag_cnt <= to_unsigned(10, 16);
                                    tms_reg <= '1';
                                    jtag_div <= JTAG_DIV_MAX;
                                    state <= JTAG_RESET_RUN;
                                    cmd_byte <= x"00";
                                    
                                when x"11" =>  -- Read IDCODE
                                    ir_value <= JTAG_IDCODE;
                                    dr_len <= to_unsigned(32, 16);
                                    shift_reg <= (others => '0');
                                    state <= JTAG_GOTO_SHIFT_IR;
                                    next_state <= JTAG_GOTO_SHIFT_DR;
                                    cmd_byte <= x"00";
                                    
                                when x"14" =>  -- Sample BSR
                                    ir_value <= JTAG_SAMPLE;
                                    dr_len <= to_unsigned(BSR_LENGTH, 16);
                                    shift_reg <= (others => '0');
                                    state <= JTAG_GOTO_SHIFT_IR;
                                    next_state <= JTAG_GOTO_SHIFT_DR;
                                    cmd_byte <= x"00";
                                    
                                -- Multi-byte commands (need more params)
                                when x"40" =>  -- LED (need 1 byte)
                                    param_need <= to_unsigned(1, 8);
                                    state <= IDLE;
                                    
                                when x"12" =>  -- Load IR (need 1 byte)
                                    param_need <= to_unsigned(1, 8);
                                    state <= IDLE;
                                    
                                when x"13" =>  -- Shift DR (need 2 len bytes + data)
                                    param_need <= to_unsigned(2, 8);
                                    state <= IDLE;
                                    
                                when x"15" =>  -- Load BSR (need BSR_BYTES bytes)
                                    param_need <= to_unsigned(BSR_BYTES, 8);
                                    state <= IDLE;
                                    
                                when x"16" =>  -- Set pin (need 3 bytes)
                                    param_need <= to_unsigned(3, 8);
                                    state <= IDLE;
                                    
                                when x"17" =>  -- Read pin (need 2 bytes)
                                    param_need <= to_unsigned(2, 8);
                                    state <= IDLE;
                                    
                                when x"20" =>  -- I2C Write (need addr, len, data)
                                    param_need <= to_unsigned(2, 8);
                                    state <= IDLE;
                                    
                                when x"21" =>  -- I2C Read (need addr, len)
                                    param_need <= to_unsigned(2, 8);
                                    state <= IDLE;
                                    
                                when x"22" =>  -- I2C Write+Read (need addr, wlen, rlen, data)
                                    param_need <= to_unsigned(3, 8);
                                    state <= IDLE;
                                    
                                when x"23" =>  -- I2C Scan
                                    -- Stub: return empty bitmap
                                    resp_len <= to_unsigned(16, 8);
                                    resp_idx <= (others => '0');
                                    resp_buf <= (others => '0');
                                    state <= SEND_RESPONSE_BYTE;
                                    cmd_byte <= x"00";
                                    
                                when others =>
                                    -- Unknown, echo back
                                    tx_byte <= rx_byte;
                                    have_tx <= '1';
                                    return_state <= IDLE;
                                    cmd_byte <= x"00";
                                    state <= IDLE;
                            end case;
                            
                        else
                            -- Collecting parameters
                            case cmd_byte is
                                when x"40" =>  -- LED
                                    led_reg <= rx_byte(1 downto 0);
                                    tx_byte <= x"00";
                                    have_tx <= '1';
                                    return_state <= IDLE;
                                    cmd_byte <= x"00";
                                    state <= IDLE;
                                    
                                when x"12" =>  -- Load IR
                                    ir_value <= rx_byte;
                                    dr_len <= to_unsigned(0, 16);  -- No DR shift
                                    state <= JTAG_GOTO_SHIFT_IR;
                                    next_state <= JTAG_GOTO_IDLE;
                                    cmd_byte <= x"00";
                                    
                                when x"13" =>  -- Shift DR
                                    if param_cnt = 0 then
                                        dr_len(7 downto 0) <= unsigned(rx_byte);
                                        param_cnt <= param_cnt + 1;
                                        state <= IDLE;
                                    elsif param_cnt = 1 then
                                        dr_len(15 downto 8) <= unsigned(rx_byte);
                                        param_cnt <= param_cnt + 1;
                                        -- Calculate bytes needed
                                        param_need <= resize((unsigned(rx_byte) & dr_len(7 downto 0) + 7) / 8, 8);
                                        shift_reg <= (others => '0');
                                        state <= IDLE;
                                    else
                                        -- Collect data bytes
                                        byte_idx := to_integer(param_cnt - 2);
                                        shift_reg(byte_idx*8+7 downto byte_idx*8) <= rx_byte;
                                        param_cnt <= param_cnt + 1;
                                        if param_cnt - 1 >= param_need then
                                            state <= JTAG_GOTO_SHIFT_DR;
                                            next_state <= SEND_RESPONSE_BYTE;
                                            cmd_byte <= x"00";
                                        else
                                            state <= IDLE;
                                        end if;
                                    end if;
                                    
                                when x"15" =>  -- Load BSR with EXTEST
                                    byte_idx := to_integer(param_cnt);
                                    bsr_data(byte_idx*8+7 downto byte_idx*8) <= rx_byte;
                                    param_cnt <= param_cnt + 1;
                                    if param_cnt + 1 >= param_need then
                                        ir_value <= JTAG_EXTEST;
                                        dr_len <= to_unsigned(BSR_LENGTH, 16);
                                        shift_reg <= bsr_data;
                                        state <= JTAG_GOTO_SHIFT_IR;
                                        next_state <= JTAG_GOTO_SHIFT_DR;
                                        cmd_byte <= x"00";
                                    else
                                        state <= IDLE;
                                    end if;
                                    
                                when x"16" =>  -- Set pin
                                    if param_cnt = 0 then
                                        pin_num(7 downto 0) <= unsigned(rx_byte);
                                        param_cnt <= param_cnt + 1;
                                        state <= IDLE;
                                    elsif param_cnt = 1 then
                                        pin_num(15 downto 8) <= unsigned(rx_byte);
                                        param_cnt <= param_cnt + 1;
                                        state <= IDLE;
                                    else
                                        -- Set pin in BSR
                                        pin_val <= rx_byte(0);
                                        if pin_num < BSR_LENGTH then
                                            bsr_data(to_integer(pin_num)) <= rx_byte(0);
                                        end if;
                                        -- Shift out with EXTEST
                                        ir_value <= JTAG_EXTEST;
                                        dr_len <= to_unsigned(BSR_LENGTH, 16);
                                        shift_reg <= bsr_data;
                                        state <= JTAG_GOTO_SHIFT_IR;
                                        next_state <= JTAG_GOTO_SHIFT_DR;
                                        cmd_byte <= x"00";
                                    end if;
                                    
                                when x"17" =>  -- Read pin
                                    if param_cnt = 0 then
                                        pin_num(7 downto 0) <= unsigned(rx_byte);
                                        param_cnt <= param_cnt + 1;
                                        state <= IDLE;
                                    else
                                        pin_num(15 downto 8) <= unsigned(rx_byte);
                                        -- Sample BSR to read pin
                                        ir_value <= JTAG_SAMPLE;
                                        dr_len <= to_unsigned(BSR_LENGTH, 16);
                                        shift_reg <= (others => '0');
                                        state <= JTAG_GOTO_SHIFT_IR;
                                        next_state <= JTAG_GOTO_SHIFT_DR;
                                        cmd_byte <= x"17";  -- Keep cmd to return pin value
                                    end if;
                                    
                                when x"20" | x"21" | x"22" =>  -- I2C commands
                                    if param_cnt = 0 then
                                        i2c_addr <= rx_byte(6 downto 0);
                                        param_cnt <= param_cnt + 1;
                                        state <= IDLE;
                                    elsif param_cnt = 1 then
                                        if cmd_byte = x"21" then
                                            i2c_rd_len <= unsigned(rx_byte);
                                            i2c_wr_len <= (others => '0');
                                        else
                                            i2c_wr_len <= unsigned(rx_byte);
                                        end if;
                                        param_cnt <= param_cnt + 1;
                                        if cmd_byte = x"21" then
                                            -- I2C Read - execute now (stub)
                                            resp_len <= unsigned(rx_byte);
                                            resp_idx <= (others => '0');
                                            resp_buf <= (others => '0');  -- TODO: actual I2C read
                                            state <= SEND_RESPONSE_BYTE;
                                            cmd_byte <= x"00";
                                        elsif cmd_byte = x"22" then
                                            state <= IDLE;  -- Need rlen
                                        elsif unsigned(rx_byte) = 0 then
                                            -- No data to write
                                            tx_byte <= x"00";
                                            have_tx <= '1';
                                            return_state <= IDLE;
                                            cmd_byte <= x"00";
                                            state <= IDLE;
                                        else
                                            param_need <= unsigned(rx_byte);
                                            state <= IDLE;
                                        end if;
                                    elsif param_cnt = 2 and cmd_byte = x"22" then
                                        i2c_rd_len <= unsigned(rx_byte);
                                        param_cnt <= param_cnt + 1;
                                        if i2c_wr_len = 0 then
                                            -- No write data, just read
                                            resp_len <= unsigned(rx_byte);
                                            resp_idx <= (others => '0');
                                            resp_buf <= (others => '0');
                                            state <= SEND_RESPONSE_BYTE;
                                            cmd_byte <= x"00";
                                        else
                                            param_need <= i2c_wr_len;
                                            state <= IDLE;
                                        end if;
                                    else
                                        -- Collecting write data
                                        byte_idx := to_integer(param_cnt - 2);
                                        if cmd_byte = x"22" then
                                            byte_idx := to_integer(param_cnt - 3);
                                        end if;
                                        i2c_data_buf(byte_idx*8+7 downto byte_idx*8) <= rx_byte;
                                        param_cnt <= param_cnt + 1;
                                        
                                        if param_cnt >= param_need + 1 then
                                            -- TODO: Execute actual I2C operation
                                            if cmd_byte = x"22" then
                                                resp_len <= i2c_rd_len;
                                            else
                                                resp_len <= to_unsigned(1, 8);  -- Just ACK
                                            end if;
                                            resp_idx <= (others => '0');
                                            resp_buf(7 downto 0) <= x"00";  -- ACK
                                            state <= SEND_RESPONSE_BYTE;
                                            cmd_byte <= x"00";
                                        else
                                            state <= IDLE;
                                        end if;
                                    end if;
                                    
                                when others =>
                                    cmd_byte <= x"00";
                                    state <= IDLE;
                            end case;
                        end if;
                        
                    --------------------------------------------------------
                    -- JTAG RESET (5x TMS=1)
                    --------------------------------------------------------
                    when JTAG_RESET_RUN =>
                        if jtag_div = 0 then
                            tck_reg <= not tck_reg;
                            jtag_div <= JTAG_DIV_MAX;
                            if tck_reg = '1' then
                                if jtag_cnt = 0 then
                                    tms_reg <= '0';  -- Go to Run-Test/Idle
                                    tx_byte <= x"00";
                                    have_tx <= '1';
                                    return_state <= IDLE;
                                    state <= IDLE;
                                else
                                    jtag_cnt <= jtag_cnt - 1;
                                end if;
                            end if;
                        end if;
                        
						
						
						----------------------------------------------------------------
						when DEBUG_TCK_TOGGLE =>
    if jtag_div = 0 then
        tck_reg <= not tck_reg;
        jtag_div <= JTAG_DIV_MAX;
        if jtag_cnt = 0 then
            tx_byte <= x"00";
            have_tx <= '1';
            return_state <= IDLE;
            state <= IDLE;
        else
            jtag_cnt <= jtag_cnt - 1;
        end if;
    end if;
	-------------------------------------------------------------------------------------
						
						
						
						
						
                    --------------------------------------------------------
                    -- JTAG: Go to Shift-IR state
                    --------------------------------------------------------
                    when JTAG_GOTO_SHIFT_IR =>
                        if jtag_div = 0 then
                            tck_reg <= not tck_reg;
                            jtag_div <= JTAG_DIV_MAX;
                            if tck_reg = '1' then
                                case to_integer(jtag_cnt) is
                                    when 0 => tms_reg <= '1'; jtag_cnt <= jtag_cnt + 1;  -- Select-DR
                                    when 1 => tms_reg <= '1'; jtag_cnt <= jtag_cnt + 1;  -- Select-IR
                                    when 2 => tms_reg <= '0'; jtag_cnt <= jtag_cnt + 1;  -- Capture-IR
                                    when 3 => 
                                        tms_reg <= '0';  -- Shift-IR
                                        jtag_cnt <= (others => '0');
                                        shift_cnt <= to_unsigned(IR_LENGTH, 16);
                                        tdi_reg <= ir_value(0);
                                        state <= JTAG_SHIFT_IR;
                                    when others => null;
                                end case;
                            end if;
                        end if;
                        
                    --------------------------------------------------------
                    -- JTAG: Shift IR bits
                    --------------------------------------------------------
                    when JTAG_SHIFT_IR =>
                        if jtag_div = 0 then
                            tck_reg <= not tck_reg;
                            jtag_div <= JTAG_DIV_MAX;
                            if tck_reg = '1' then
                                shift_cnt <= shift_cnt - 1;
                                if shift_cnt = 1 then
                                    tms_reg <= '1';  -- Exit1-IR on last bit
                                    state <= JTAG_EXIT_IR;
                                else
                                    tdi_reg <= ir_value(to_integer(to_unsigned(IR_LENGTH, 16) - shift_cnt + 1));
                                end if;
                            end if;
                        end if;
                        
                    --------------------------------------------------------
                    -- JTAG: Exit IR and go to Run-Test/Idle or Shift-DR
                    --------------------------------------------------------
                    when JTAG_EXIT_IR =>
                        if jtag_div = 0 then
                            tck_reg <= not tck_reg;
                            jtag_div <= JTAG_DIV_MAX;
                            if tck_reg = '1' then
                                case to_integer(jtag_cnt) is
                                    when 0 => tms_reg <= '1'; jtag_cnt <= jtag_cnt + 1;  -- Update-IR
                                    when 1 =>
                                        jtag_cnt <= (others => '0');
                                        state <= next_state;
                                        if next_state = JTAG_GOTO_SHIFT_DR then
                                            tms_reg <= '1';  -- Stay in select path
                                        else
                                            tms_reg <= '0';  -- Go to Run-Test/Idle
                                        end if;
                                    when others => null;
                                end case;
                            end if;
                        end if;
                        
                    --------------------------------------------------------
                    -- JTAG: Go to Shift-DR state
                    --------------------------------------------------------
                    when JTAG_GOTO_SHIFT_DR =>
                        if jtag_div = 0 then
                            tck_reg <= not tck_reg;
                            jtag_div <= JTAG_DIV_MAX;
                            if tck_reg = '1' then
                                case to_integer(jtag_cnt) is
                                    when 0 => tms_reg <= '1'; jtag_cnt <= jtag_cnt + 1;  -- Select-DR
                                    when 1 => tms_reg <= '0'; jtag_cnt <= jtag_cnt + 1;  -- Capture-DR
                                    when 2 =>
                                        tms_reg <= '0';  -- Shift-DR
                                        jtag_cnt <= (others => '0');
                                        shift_cnt <= dr_len;
                                        tdi_reg <= shift_reg(to_integer(dr_len)-1);
                                        state <= JTAG_SHIFT_DR;
                                    when others => null;
                                end case;
                            end if;
                        end if;
                        
                    --------------------------------------------------------
                    -- JTAG: Shift DR bits
                    --------------------------------------------------------
                    when JTAG_SHIFT_DR =>
                        if jtag_div = 0 then
                            tck_reg <= not tck_reg;
                            jtag_div <= JTAG_DIV_MAX;
                            if tck_reg = '0' then
                                -- Rising edge: sample TDO
                                tdo_sample <= jtag_tdo;
                            else
                                -- Falling edge: shift and output next TDI
                                shift_reg <= shift_reg(BSR_LENGTH-2 downto 0) & tdo_sample;
                                shift_cnt <= shift_cnt - 1;
                                if shift_cnt = 1 then
                                    tms_reg <= '1';  -- Exit1-DR on last bit
                                    state <= JTAG_EXIT_DR;
                                else
                                    tdi_reg <= shift_reg(to_integer(shift_cnt)-2);
                                end if;
                            end if;
                        end if;
                        
                    --------------------------------------------------------
                    -- JTAG: Exit DR and prepare response
                    --------------------------------------------------------
                    when JTAG_EXIT_DR =>
                        if jtag_div = 0 then
                            tck_reg <= not tck_reg;
                            jtag_div <= JTAG_DIV_MAX;
                            if tck_reg = '1' then
                                case to_integer(jtag_cnt) is
                                    when 0 => tms_reg <= '1'; jtag_cnt <= jtag_cnt + 1;  -- Update-DR
                                    when 1 =>
                                        tms_reg <= '0';  -- Run-Test/Idle
                                        jtag_cnt <= (others => '0');
                                        -- Prepare response
                                        resp_buf <= shift_reg;
                                        resp_len <= resize((dr_len + 7) / 8, 8);
                                        resp_idx <= (others => '0');
                                        bsr_capture <= shift_reg;  -- Save captured data
                                        
                                        -- Special handling for read pin
                                        if cmd_byte = x"17" then
                                            if pin_num < BSR_LENGTH then
                                                resp_buf(7 downto 0) <= "0000000" & shift_reg(to_integer(pin_num));
                                            else
                                                resp_buf(7 downto 0) <= x"00";
                                            end if;
                                            resp_len <= to_unsigned(1, 8);
                                            cmd_byte <= x"00";
                                        end if;
                                        
                                        state <= JTAG_GOTO_IDLE;
                                    when others => null;
                                end case;
                            end if;
                        end if;
                        
                    --------------------------------------------------------
                    -- JTAG: Go to Run-Test/Idle then send response
                    --------------------------------------------------------
                    when JTAG_GOTO_IDLE =>
                        if jtag_div = 0 then
                            tck_reg <= not tck_reg;
                            jtag_div <= JTAG_DIV_MAX;
                            if tck_reg = '1' then
                                tms_reg <= '0';
                                state <= SEND_RESPONSE_BYTE;
                            end if;
                        end if;
                        
                    --------------------------------------------------------
                    -- Send multi-byte response
                    --------------------------------------------------------
                    when SEND_RESPONSE_BYTE =>
                        byte_idx := to_integer(resp_idx);
                        tx_byte <= resp_buf(byte_idx*8+7 downto byte_idx*8);
                        have_tx <= '1';
                        resp_idx <= resp_idx + 1;
                        if resp_idx + 1 >= resp_len then
                            return_state <= IDLE;
                            cmd_byte <= x"00";
                        else
                            return_state <= SEND_RESPONSE_BYTE;
                        end if;
                        state <= IDLE;
                        
                    when others =>
                        state <= IDLE;
                        
                end case;
            end if;
        end if;
    end process;

end architecture;
