library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_mean3x3_linebuffer is
end entity;

architecture sim of tb_mean3x3_linebuffer is
    constant CLOCK_PERIOD : time := 10 ns;

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal pixel_valid : std_logic := '0';
    signal pixel_in    : std_logic_vector(7 downto 0) := (others => '0');
    signal out_valid   : std_logic;
    signal pixel_out   : std_logic_vector(7 downto 0);
    signal out_x       : natural range 0 to 4;
    signal out_y       : natural range 0 to 65535;
    signal checked_windows : natural := 0;
begin
    dut : entity work.mean3x3_linebuffer
        generic map (
            IMAGE_WIDTH => 5,
            PIXEL_BITS  => 8
        )
        port map (
            clk => clk, rst => rst,
            pixel_valid => pixel_valid, pixel_in => pixel_in,
            out_valid => out_valid, pixel_out => pixel_out,
            out_x => out_x, out_y => out_y
        );

    clock_process : process
    begin
        while true loop
            clk <= '0'; wait for CLOCK_PERIOD / 2;
            clk <= '1'; wait for CLOCK_PERIOD / 2;
        end loop;
    end process;

    -- Input image: P(x,y) = 10*y + x.
    -- A 3x3 mean in this linear ramp must equal the centre pixel.
    checker : process (clk)
        variable expected : natural;
    begin
        if rising_edge(clk) and out_valid = '1' then
            expected := 10 * out_y + out_x;
            assert to_integer(unsigned(pixel_out)) = expected
                report "FAIL: unexpected output pixel"
                severity failure;
            checked_windows <= checked_windows + 1;
            report "PASS: centre (" & integer'image(out_x) & "," & integer'image(out_y)
                & "), average = " & integer'image(to_integer(unsigned(pixel_out)));
        end if;
    end process;

    stimulus : process
    begin
        wait until falling_edge(clk);
        wait until falling_edge(clk);
        rst <= '0';

        for y in 0 to 4 loop
            for x in 0 to 4 loop
                wait until falling_edge(clk);
                pixel_in <= std_logic_vector(to_unsigned(10 * y + x, pixel_in'length));
                pixel_valid <= '1';
            end loop;
        end loop;

        wait until falling_edge(clk);
        pixel_valid <= '0';
        wait for 3 * CLOCK_PERIOD;

        assert checked_windows = 9
            report "FAIL: the test should produce 9 complete 3x3 windows"
            severity failure;
        report "TEST PASSED: all 9 complete 3x3 windows are correct.";
        finish;
    end process;
end architecture;
