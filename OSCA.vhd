library ieee;
use ieee.std_logic_1164.all;

entity OSCA is
    generic (HF_CLK_DIV : string := "8");
    port (
        HFOUTEN  : in  std_logic;
        HFSDSCEN : in  std_logic;
        HFCLKOUT : out std_logic
    );
end entity;

architecture sim of OSCA is
begin
    process
    begin
        HFCLKOUT <= '0';
        wait for 5 ns;
        loop
            if HFOUTEN = '1' then
                HFCLKOUT <= not HFCLKOUT;
            else
                HFCLKOUT <= '0';
            end if;
            wait for 5 ns;
        end loop;
    end process;
end architecture;
