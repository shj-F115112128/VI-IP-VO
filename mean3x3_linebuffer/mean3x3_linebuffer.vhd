-- 3x3 grayscale mean filter + Sobel edge detector - teaching / functional-simulation version.
-- One pixel is accepted on each pixel_valid clock, left-to-right and
-- top-to-bottom. IMAGE_WIDTH valid pixels form one image line.
--
-- The mean filter and the Sobel gradient are computed from the SAME raw-pixel
-- 3x3 window (top0..top2 / mid0..mid2 / bot0..bot2) built for the mean filter,
-- so no second line buffer is needed. Both outputs share the same out_valid /
-- out_x / out_y timing.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mean3x3_linebuffer is
    generic (
        IMAGE_WIDTH    : positive := 5;
        PIXEL_BITS     : positive := 8;
        EDGE_THRESHOLD : natural  := 64  -- |Gx| + |Gy| above this is flagged as an edge
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        pixel_valid : in  std_logic;
        pixel_in    : in  std_logic_vector(PIXEL_BITS - 1 downto 0);
        out_valid   : out std_logic;
        pixel_out   : out std_logic_vector(PIXEL_BITS - 1 downto 0);
        out_x       : out natural range 0 to IMAGE_WIDTH - 1;
        out_y       : out natural range 0 to 65535;
        sobel_mag   : out std_logic_vector(PIXEL_BITS - 1 downto 0);  -- saturated |Gx|+|Gy|
        sobel_edge  : out std_logic                                  -- '1' when sobel_mag > EDGE_THRESHOLD
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
        variable gx, gy : integer;
        variable gx_abs, gy_abs, mag_value : natural;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                x_cnt <= 0;
                y_cnt <= 0;
                out_valid <= '0';
                pixel_out <= (others => '0');
                out_x <= 0;
                out_y <= 0;
                sobel_mag <= (others => '0');
                sobel_edge <= '0';
                top0 <= (others => '0'); top1 <= (others => '0'); top2 <= (others => '0');
                mid0 <= (others => '0'); mid1 <= (others => '0'); mid2 <= (others => '0');
                bot0 <= (others => '0'); bot1 <= (others => '0'); bot2 <= (others => '0');
                for i in 0 to IMAGE_WIDTH - 1 loop
                    line1(i) <= (others => '0');
                    line2(i) <= (others => '0');
                end loop;
            else
                out_valid <= '0';
                sobel_edge <= '0';

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
                        -- Post-shift window: top(top1,top2,two_lines_back_pixel), mid(mid1,mid2,previous_line_pixel),
                        -- bot(bot1,bot2,pixel_in) -- i.e. columns (x_cnt-2, x_cnt-1, x_cnt) of rows (y_cnt-2, y_cnt-1, y_cnt).
                        sum_value := to_integer(top1) + to_integer(top2) + to_integer(two_lines_back_pixel)
                                   + to_integer(mid1) + to_integer(mid2) + to_integer(previous_line_pixel)
                                   + to_integer(bot1) + to_integer(bot2) + to_integer(unsigned(pixel_in));
                        pixel_out <= std_logic_vector(to_unsigned(sum_value / 9, PIXEL_BITS));
                        out_valid <= '1';
                        out_x <= x_cnt - 1;
                        out_y <= y_cnt - 1;

                        -- Sobel gradient from the same raw-pixel window (not the mean output).
                        -- Window columns are (left=top1/mid1/bot1, mid=top2/mid2/bot2,
                        -- right=two_lines_back_pixel/previous_line_pixel/pixel_in) -- see comment above.
                        -- Gx: [-1 0 1; -2 0 2; -1 0 1] (right column - left column)
                        -- Gy: [1 2 1; 0 0 0; -1 -2 -1] (top row - bottom row)
                        gx := (to_integer(two_lines_back_pixel) + 2 * to_integer(previous_line_pixel) + to_integer(unsigned(pixel_in)))
                            - (to_integer(top1) + 2 * to_integer(mid1) + to_integer(bot1));
                        gy := (to_integer(top1) + 2 * to_integer(top2) + to_integer(two_lines_back_pixel))
                            - (to_integer(bot1) + 2 * to_integer(bot2) + to_integer(unsigned(pixel_in)));

                        if gx >= 0 then gx_abs := gx; else gx_abs := -gx; end if;
                        if gy >= 0 then gy_abs := gy; else gy_abs := -gy; end if;
                        mag_value := gx_abs + gy_abs;

                        if mag_value > 2 ** PIXEL_BITS - 1 then
                            sobel_mag <= std_logic_vector(to_unsigned(2 ** PIXEL_BITS - 1, PIXEL_BITS));
                        else
                            sobel_mag <= std_logic_vector(to_unsigned(mag_value, PIXEL_BITS));
                        end if;

                        if mag_value > EDGE_THRESHOLD then
                            sobel_edge <= '1';
                        else
                            sobel_edge <= '0';
                        end if;
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
