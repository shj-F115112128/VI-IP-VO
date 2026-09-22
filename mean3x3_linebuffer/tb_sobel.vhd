-- Dedicated testbench for the Sobel edge-detector half of mean3x3_linebuffer.
-- There is no standalone "sobel" entity in this project -- mean3x3_linebuffer
-- computes the Sobel gradient (sobel_mag / sobel_edge) from the same raw-pixel
-- 3x3 window used for the mean filter, so this tb drives that DUT and checks
-- only the Sobel outputs against hand-derived expected values.
--
-- Six sub-images are streamed in sequence, each preceded by a reset so line
-- buffers/window registers don't carry over between them:
--   FLAT                    - uniform image, no gradient at all
--   VEDGE_AT_THRESHOLD      - pure horizontal gradient, |Gx|+|Gy| exactly at
--                              EDGE_THRESHOLD (checks the ">" boundary is NOT tripped)
--   VEDGE_ABOVE_THRESHOLD   - pure horizontal gradient just above threshold
--   HEDGE_AT_THRESHOLD      - pure vertical gradient, exactly at threshold
--   DIAGONAL_BELOW_THRESHOLD- both directions contribute, still below threshold
--   STEP_EDGE               - a real 0/255 step edge (not a constant ramp);
--                              exercises the sobel_mag saturation clamp and a
--                              spatially-localized edge instead of a global one
--
-- For a planar image P(x,y) = a*x + b*y + c, mean3x3_linebuffer's Sobel stage
-- reduces to Gx = 8*a, Gy = -8*b everywhere in the interior, which is what the
-- VEDGE/HEDGE/DIAGONAL expected values below are derived from.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_sobel is
end entity;

architecture sim of tb_sobel is
    constant CLOCK_PERIOD   : time    := 10 ns;
    constant IMAGE_WIDTH    : natural := 8;
    constant IMAGE_HEIGHT   : natural := 5;
    constant PIXEL_BITS     : natural := 8;
    constant EDGE_THRESHOLD : natural := 64;
    constant WINDOWS_PER_IMAGE : natural := (IMAGE_WIDTH - 2) * (IMAGE_HEIGHT - 2);

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal pixel_valid : std_logic := '0';
    signal pixel_in    : std_logic_vector(PIXEL_BITS - 1 downto 0) := (others => '0');
    signal out_valid   : std_logic;
    signal pixel_out   : std_logic_vector(PIXEL_BITS - 1 downto 0);
    signal out_x       : natural range 0 to IMAGE_WIDTH - 1;
    signal out_y       : natural range 0 to 65535;
    signal sobel_mag   : std_logic_vector(PIXEL_BITS - 1 downto 0);
    signal sobel_edge  : std_logic;

    type test_id_t is (FLAT, VEDGE_AT_THRESHOLD, VEDGE_ABOVE_THRESHOLD,
                        HEDGE_AT_THRESHOLD, DIAGONAL_BELOW_THRESHOLD, STEP_EDGE);

    -- Set by the stimulus process before each sub-image; only read by the checker.
    signal current_test : test_id_t := FLAT;
    signal checked_windows : natural := 0;

    function pixel_value(test : test_id_t; x, y : natural) return natural is
    begin
        case test is
            when FLAT                     => return 100;
            when VEDGE_AT_THRESHOLD       => return 64 + 8 * x;    -- Gx=64,  Gy=0
            when VEDGE_ABOVE_THRESHOLD    => return 9 * x;         -- Gx=72,  Gy=0
            when HEDGE_AT_THRESHOLD       => return 8 * y;         -- Gx=0,   Gy=-64
            when DIAGONAL_BELOW_THRESHOLD => return 3 * x + 4 * y; -- Gx=24,  Gy=-32
            when STEP_EDGE =>
                if x < 4 then return 0; else return 255; end if;
        end case;
    end function;

    -- Expected |Gx|+|Gy| at output coordinate out_x (all test images here are
    -- constant along y, or -- for STEP_EDGE -- independent of y entirely).
    function expected_mag(test : test_id_t; x : natural) return natural is
    begin
        case test is
            when FLAT                     => return 0;
            when VEDGE_AT_THRESHOLD       => return 64;
            when VEDGE_ABOVE_THRESHOLD    => return 72;
            when HEDGE_AT_THRESHOLD       => return 64;
            when DIAGONAL_BELOW_THRESHOLD => return 56;
            when STEP_EDGE =>
                -- out_x = x_cnt-1; the step sits between input columns 3 and 4,
                -- so it is only visible in the windows centred there.
                if x = 3 or x = 4 then return 255; else return 0; end if;
        end case;
    end function;
begin
    dut : entity work.mean3x3_linebuffer
        generic map (
            IMAGE_WIDTH    => IMAGE_WIDTH,
            PIXEL_BITS     => PIXEL_BITS,
            EDGE_THRESHOLD => EDGE_THRESHOLD
        )
        port map (
            clk => clk, rst => rst,
            pixel_valid => pixel_valid, pixel_in => pixel_in,
            out_valid => out_valid, pixel_out => pixel_out,
            out_x => out_x, out_y => out_y,
            sobel_mag => sobel_mag, sobel_edge => sobel_edge
        );

    clock_process : process
    begin
        while true loop
            clk <= '0'; wait for CLOCK_PERIOD / 2;
            clk <= '1'; wait for CLOCK_PERIOD / 2;
        end loop;
    end process;

    checker : process (clk)
        variable exp_mag  : natural;
        variable exp_edge : std_logic;
    begin
        if rising_edge(clk) and out_valid = '1' then
            exp_mag := expected_mag(current_test, out_x);
            if exp_mag > EDGE_THRESHOLD then
                exp_edge := '1';
            else
                exp_edge := '0';
            end if;

            assert to_integer(unsigned(sobel_mag)) = exp_mag
                report "FAIL [" & test_id_t'image(current_test) & "] sobel_mag mismatch at (" &
                       integer'image(out_x) & "," & integer'image(out_y) & "): expected " &
                       integer'image(exp_mag) & " got " &
                       integer'image(to_integer(unsigned(sobel_mag)))
                severity failure;

            assert sobel_edge = exp_edge
                report "FAIL [" & test_id_t'image(current_test) & "] sobel_edge mismatch at (" &
                       integer'image(out_x) & "," & integer'image(out_y) & "): expected " &
                       std_logic'image(exp_edge) & " got " & std_logic'image(sobel_edge)
                severity failure;

            checked_windows <= checked_windows + 1;
            report "PASS [" & test_id_t'image(current_test) & "] (" & integer'image(out_x) & "," &
                   integer'image(out_y) & "): sobel_mag=" & integer'image(exp_mag) &
                   ", sobel_edge=" & std_logic'image(exp_edge);
        end if;
    end process;

    stimulus : process
        procedure run_test(test : test_id_t) is
        begin
            current_test <= test;

            rst <= '1';
            wait until falling_edge(clk);
            wait until falling_edge(clk);
            rst <= '0';

            for y in 0 to IMAGE_HEIGHT - 1 loop
                for x in 0 to IMAGE_WIDTH - 1 loop
                    wait until falling_edge(clk);
                    pixel_in    <= std_logic_vector(to_unsigned(pixel_value(test, x, y), PIXEL_BITS));
                    pixel_valid <= '1';
                end loop;
            end loop;

            wait until falling_edge(clk);
            pixel_valid <= '0';
            wait for 3 * CLOCK_PERIOD;
        end procedure;
    begin
        run_test(FLAT);
        run_test(VEDGE_AT_THRESHOLD);
        run_test(VEDGE_ABOVE_THRESHOLD);
        run_test(HEDGE_AT_THRESHOLD);
        run_test(DIAGONAL_BELOW_THRESHOLD);
        run_test(STEP_EDGE);

        assert checked_windows = 6 * WINDOWS_PER_IMAGE
            report "FAIL: expected " & integer'image(6 * WINDOWS_PER_IMAGE) &
                   " total windows checked, got " & integer'image(checked_windows)
            severity failure;
        report "TEST PASSED: all 6 sobel sub-tests (" & integer'image(checked_windows) &
               " windows total) are correct.";
        finish;
    end process;
end architecture;
