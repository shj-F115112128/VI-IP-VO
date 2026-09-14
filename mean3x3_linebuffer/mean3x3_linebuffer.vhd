-- 3x3 grayscale mean filter - teaching / functional-simulation version.
-- One pixel is accepted on each pixel_valid clock, left-to-right and
-- top-to-bottom. IMAGE_WIDTH valid pixels form one image line.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mean3x3_linebuffer is
    generic (
        IMAGE_WIDTH : positive := 5;
        PIXEL_BITS  : positive := 8
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        pixel_valid : in  std_logic;
        pixel_in    : in  std_logic_vector(PIXEL_BITS - 1 downto 0);
        out_valid   : out std_logic;
        pixel_out   : out std_logic_vector(PIXEL_BITS - 1 downto 0);
        out_x       : out natural range 0 to IMAGE_WIDTH - 1;
        out_y       : out natural range 0 to 65535
    );
end entity;

architecture rtl of mean3x3_linebuffer is
    type line_memory_t is array (0 to IMAGE_WIDTH - 1) of unsigned(PIXEL_BITS - 1 downto 0);

    signal line1 : line_memory_t := (others => (others => '0'));
    signal line2 : line_memory_t := (others => (others => '0'));

    signal x_cnt : natural range 0 to IMAGE_WIDTH - 1 := 0;
    signal y_cnt : natural range 0 to 65535 := 0;

    signal top0, top1, top2 : unsigned(PIXEL_BITS - 1 downto 0) := (others => '0');
    signal mid0, mid1, mid2 : unsigned(PIXEL_BITS - 1 downto 0) := (others => '0');
    signal bot0, bot1, bot2 : unsigned(PIXEL_BITS - 1 downto 0) := (others => '0');
begin
    process (clk)
        variable previous_line_pixel : unsigned(PIXEL_BITS - 1 downto 0);
        variable two_lines_back_pixel : unsigned(PIXEL_BITS - 1 downto 0);
        variable sum_value : natural;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                x_cnt <= 0;
                y_cnt <= 0;
                out_valid <= '0';
                pixel_out <= (others => '0');
                out_x <= 0;
                out_y <= 0;
                top0 <= (others => '0'); top1 <= (others => '0'); top2 <= (others => '0');
                mid0 <= (others => '0'); mid1 <= (others => '0'); mid2 <= (others => '0');
                bot0 <= (others => '0'); bot1 <= (others => '0'); bot2 <= (others => '0');
                for i in 0 to IMAGE_WIDTH - 1 loop
                    line1(i) <= (others => '0');
                    line2(i) <= (others => '0');
                end loop;
            else
                out_valid <= '0';

                if pixel_valid = '1' then
                    -- Read old values, then overwrite line1 with the current image line.
                    previous_line_pixel := line1(x_cnt);
                    two_lines_back_pixel := line2(x_cnt);
                    line1(x_cnt) <= unsigned(pixel_in);
                    line2(x_cnt) <= previous_line_pixel;

                    if x_cnt = 0 then
                        -- A new line must not inherit the last two pixels of the prior line.
                        top0 <= (others => '0'); top1 <= (others => '0'); top2 <= two_lines_back_pixel;
                        mid0 <= (others => '0'); mid1 <= (others => '0'); mid2 <= previous_line_pixel;
                        bot0 <= (others => '0'); bot1 <= (others => '0'); bot2 <= unsigned(pixel_in);
                    else
                        top0 <= top1; top1 <= top2; top2 <= two_lines_back_pixel;
                        mid0 <= mid1; mid1 <= mid2; mid2 <= previous_line_pixel;
                        bot0 <= bot1; bot1 <= bot2; bot2 <= unsigned(pixel_in);
                    end if;

                    if x_cnt >= 2 and y_cnt >= 2 then
                        -- The current input supplies the new rightmost column of the window.
                        sum_value := to_integer(top1) + to_integer(top2) + to_integer(two_lines_back_pixel)
                                   + to_integer(mid1) + to_integer(mid2) + to_integer(previous_line_pixel)
                                   + to_integer(bot1) + to_integer(bot2) + to_integer(unsigned(pixel_in));
                        pixel_out <= std_logic_vector(to_unsigned(sum_value / 9, PIXEL_BITS));
                        out_valid <= '1';
                        out_x <= x_cnt - 1;
                        out_y <= y_cnt - 1;
                    end if;

                    if x_cnt = IMAGE_WIDTH - 1 then
                        x_cnt <= 0;
                        y_cnt <= y_cnt + 1;
                    else
                        x_cnt <= x_cnt + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
