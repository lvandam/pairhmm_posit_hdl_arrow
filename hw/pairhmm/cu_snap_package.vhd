library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.wed.all;
use work.functions.all;
use work.pairhmm_package.all;
use work.pe_package.all;

package cu_snap_package is

  constant PAIRHMM_MAX_SIZE : natural       := 64;
  type bp_array_type is array (0 to PAIRHMM_MAX_SIZE-1) of bp_type;

  constant bp_array_empty   : bp_array_type := (others => BP_IGNORE);
  type bp_all_type is array (0 to PE_DEPTH-1) of bp_array_type;

  constant bp_all_empty     : bp_all_type   := (others => bp_array_empty);

  constant CU_MAX_CYCLES          : natural := PAIRHMM_MAX_SIZE / PE_DEPTH * 2 * PAIRHMM_MAX_SIZE;
  constant CU_CYCLE_BITS          : natural := log2(CU_MAX_CYCLES);
  constant CU_BPS_PER_RAM_ADDR    : natural := 1; -- 1024 / (8 * PE_DEPTH); -- TODO: Correct?
  constant CU_RAM_ADDRS_PER_BATCH : natural := PAIRHMM_MAX_SIZE / CU_BPS_PER_RAM_ADDR;
  constant CU_RESULT_SIZE         : natural := 4 * PE_DW;
----------------------------------------------------------------------------------------------------------------------- internals

  type fifo_controls is record
    rd_en : std_logic;
    valid : std_logic;

    wr_en  : std_logic;
    wr_ack : std_logic;

    empty : std_logic;
    full  : std_logic;

    overflow  : std_logic;
    underflow : std_logic;

    rst    : std_logic;
    rd_rst : std_logic;
    wr_rst : std_logic;
  end record;

  type pfifo_item is record
    din  : std_logic_vector(PAIRHMM_BITS_PER_PROB - 1 downto 0);
    dout : std_logic_vector(PAIRHMM_BITS_PER_PROB - 1 downto 0);
    c    : fifo_controls;
  end record;

  type outfifo_item is record
    din  : std_logic_vector(31 downto 0);
    dout : std_logic_vector(31 downto 0);
    c    : fifo_controls;
  end record;

  type fbfifo_item is record
    din  : std_logic_vector(386 downto 0);
    dout : std_logic_vector(386 downto 0);
    c    : fifo_controls;
  end record;

  type ram_item is record
    clka  : std_logic;
    wea   : std_logic;
    addra : unsigned(6 downto 0);
    dina  : std_logic_vector(BP_SIZE - 1 downto 0);
    clkb  : std_logic;
    addrb : unsigned(8 downto 0);
    doutb : std_logic_vector(3 * PE_DEPTH - 1 downto 0);
  end record;

  type prob_ram_item is record
    clka  : std_logic;
    wea   : std_logic;
    addra : unsigned(6 downto 0);
    dina  : std_logic_vector(PAIRHMM_BITS_PER_PROB - 1 downto 0);
    clkb  : std_logic;
    addrb : unsigned(8 downto 0);
    doutb : std_logic_vector(PE_DEPTH * PAIRHMM_BITS_PER_PROB - 1 downto 0);
  end record;

  type cu_state is (
    LOAD_IDLE,
    LOAD_RESET_START,
    LOAD_LOAD_INIT,
    LOAD_REQUEST_DATA,
    LOAD_LOADX_LOADY,
    LOAD_LOADNEXTINIT,
    LOAD_LAUNCH,
    LOAD_DONE
    );

  type cu_inits is record
    x_len      : unsigned(31 downto 0);
    y_len      : unsigned(31 downto 0);
    x_size     : unsigned(31 downto 0);
    x_padded   : unsigned(31 downto 0);
    x_bppadded : unsigned(31 downto 0);
    y_size     : unsigned(31 downto 0);
    y_padded   : unsigned(31 downto 0);
  end record;

  type initial_array_type is array (0 to PE_DEPTH - 1) of prob;

  -- To distribute data to FIFO's
  type readdata_array is array (0 to 1) of std_logic_vector(8 * 32 - 1 downto 0);

  type cu_int is record
    state : cu_state;
    wed   : wed_type;

    inits         : cu_inits;
    initial_array : initial_array_type;
    sched         : cu_inits;
    sched_array   : initial_array_type;

    y_reads : unsigned(15 downto 0);
    x_reads : unsigned(15 downto 0);
    p_reads : unsigned(15 downto 0);

    hapl_addr  : unsigned(6 downto 0);
    hapl_addr1 : unsigned(6 downto 0);
    hapl_wren  : std_logic;
    hapl_data  : std_logic_vector(7 downto 0);
    read_addr  : unsigned(6 downto 0);
    read_addr1 : unsigned(6 downto 0);
    prob_addr  : unsigned(6 downto 0);
    prob_addr1 : unsigned(6 downto 0);
    read_wren  : std_logic;
    prob_wren  : std_logic;
    read_data  : std_logic_vector(7 downto 0);
    prob_data  : std_logic_vector(PAIRHMM_BITS_PER_PROB - 1 downto 0);
    ram        : std_logic;

    pair      : unsigned(PE_DEPTH_BITS - 1 downto 0);
    filled    : std_logic;
    fifos_rst : std_logic;

    p_fifo_en, p_fifo_en1, p_fifo_en2 : std_logic;

    p_fifodata : readdata_array;
  end record;

  type cu_sched_state is (
    SCHED_IDLE,
    SCHED_STARTUP,
    SCHED_PROCESSING,
    SCHED_EMPTY_FIFOS,
    SCHED_DONE
    );

  type cu_sched is record
    pairhmm_rst : std_logic; -- Reset

    state               : cu_sched_state; -- State of the scheduler process
    cycle               : unsigned(CU_CYCLE_BITS - 1 downto 0);  -- This must be able to hold up to PAIRHMM_MAX_SIZE / PE_DEPTH * 2 * PAIRHMM_MAX_SIZE-1
    basepair            : unsigned(log2e(PAIRHMM_MAX_SIZE) downto 0); -- This must be able to hold up to PAIRHMM_MAX_SIZE-1 but is 1 larger to compare to size array values
    element             : unsigned(log2e(PAIRHMM_NUM_PES) downto 0); -- This must be able to hold PAIRHMM_NUM_PES-1
    schedule, schedule1 : unsigned(PE_DEPTH_BITS - 1 downto 0); -- To hold the pair that is currently scheduled
    supercolumn         : unsigned(log2e(PAIRHMM_MAX_SIZE / PAIRHMM_NUM_PES) downto 0); -- To keep track in which group of columns we are

    fifo_rd_en : std_logic;
    fifo_reads : unsigned(log2e(PAIRHMM_MAX_SIZE*PE_DEPTH) downto 0); -- To keep track on howmany values were read from the fifo's

    valid : std_logic; -- Valid bit for the PairHMM core
    cell  : pe_cell_type; -- State of the cell for this bunch of data

    feedback                        : std_logic; -- To select the feedback FIFO as PairHMM core input
    feedback_rd_en, feedback_rd_en1 : std_logic; -- Read enable for the feedback FIFO
    feedback_wr_en                  : std_logic; -- Write enable for the feedback FIFO
    feedback_rst                    : std_logic; -- Feedback FIFO reset

    leny          : unsigned(log2e(PAIRHMM_MAX_SIZE) downto 0);
    sizey, sizey1 : unsigned(log2e(PAIRHMM_MAX_SIZE) downto 0); -- To keep track of howmany bp's each pair still has to process in y direction
    lenx          : unsigned(log2e(PAIRHMM_MAX_SIZE) downto 0);
    sizex         : unsigned(log2e(PAIRHMM_MAX_SIZE) downto 0); -- To keep track of howmany bp's each pair still has to process in x direction
    sizexp        : unsigned(log2e(PAIRHMM_MAX_SIZE) downto 0); -- To keep track of howmany bp's each pair still has to process in x direction (padded value)

    ram       : std_logic; -- To keep track of if we're using the top or bottom half of the RAM
    startflag : std_logic; -- To keep track of if we just started up a new pair

    pe_first : pe_in;

    ybus_addr, ybus_addr1, ybus_addr2 : unsigned(log2e(PAIRHMM_NUM_PES) downto 0);
    ybus_en, ybus_en1, ybus_en2       : std_logic;

    core_schedule, core_schedule1 : unsigned(PE_DEPTH_BITS-1 downto 0);

    initial_array : initial_array_type;
  end record;

  constant cu_sched_empty : cu_sched := (
    state           => SCHED_IDLE,
    cycle           => (others => '0'),
    basepair        => (others => '0'),
    element         => (others => '0'),
    schedule        => (others => '0'),
    schedule1       => (others => '0'),
    supercolumn     => (others => '0'),
    fifo_rd_en      => '0',
    valid           => '0',
    cell            => PE_NORMAL,
    pairhmm_rst     => '1',
    feedback        => '0',
    feedback_rd_en  => '0',
    feedback_rd_en1 => '0',
    feedback_wr_en  => '0',
    feedback_rst    => '1',
    leny            => (others => '0'),
    sizey           => (others => '0'),
    sizey1          => (others => '0'),
    lenx            => (others => '0'),
    sizex           => (others => '0'),
    sizexp          => (others => '0'),
    fifo_reads      => (others => '0'),
    ram             => '1',
    startflag       => '1',
    pe_first        => pe_in_empty,
    ybus_addr       => (others => '0'),
    ybus_addr1      => (others => '0'),
    ybus_addr2      => (others => '0'),
    ybus_en         => '0',
    ybus_en1        => '0',
    ybus_en2        => '0',
    core_schedule   => (others => '0'),
    core_schedule1  => (others => '0'),
    initial_array   => (others => (others => '0'))
    );

  constant CYCLE_ZERO : unsigned(CU_CYCLE_BITS-1 downto 0) := usign(0, CU_CYCLE_BITS);

  type cu_ext is record
    pairhmm_cr : cr_in;
    pairhmm    : pairhmm_item;
    pairhmm_in : pe_in;
    pfifo      : pfifo_item;
    outfifo    : outfifo_item;
    fbfifo     : fbfifo_item;
    haplram    : ram_item;
    readram    : ram_item;
    probram    : prob_ram_item;
    fbpairhmm  : pe_in;
    outdata    : std_logic_vector(1023 downto 0);
    clk_kernel : std_logic;
  end record;

  procedure cu_reset (signal r : inout cu_int);

  component base_ram is
    generic (
      WIDTHA     : integer := 8;
      SIZEA      : integer := 256;
      ADDRWIDTHA : integer := 8;
      WIDTHB     : integer := 32;
      SIZEB      : integer := 64;
      ADDRWIDTHB : integer := 6
      );
    port (
      clkA  : in  std_logic;
      clkB  : in  std_logic;
      weA   : in  std_logic;
      addrA : in  std_logic_vector(ADDRWIDTHA - 1 downto 0);
      addrB : in  std_logic_vector(ADDRWIDTHB - 1 downto 0);
      diA   : in  std_logic_vector(WIDTHA - 1 downto 0);
      doB   : out std_logic_vector(WIDTHB - 1 downto 0)
      );
  end component;

  function slvec (a : in integer; b : in natural) return std_logic_vector;
  function slvec (a : in unsigned) return std_logic_vector;

end package cu_snap_package;

package body cu_snap_package is

  procedure cu_reset (signal r : inout cu_int) is
  begin
    r.state  <= LOAD_IDLE;

    r.x_reads <= (others => '0');
    r.y_reads <= (others => '0');
    r.p_reads <= (others => '0');

    r.hapl_addr <= (others => '0');
    r.hapl_wren <= '0';
    r.read_addr <= (others => '0');
    r.read_wren <= '0';

    r.filled    <= '0';
    r.fifos_rst <= '1';
    r.p_fifo_en <= '0';
    r.ram <= '1';
  end procedure cu_reset;

  function slvec (a : in integer; b : in natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(a, b));
  end function slvec;

  function slvec (a : in unsigned) return std_logic_vector is
  begin
    return std_logic_vector(a);
  end function slvec;

end package body cu_snap_package;
