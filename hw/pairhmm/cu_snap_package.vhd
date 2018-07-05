library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.wed.all;
use work.functions.all;
use work.pairhmm_package.all;
use work.pe_package.all;

package cu_snap_package is

  constant MAX_BATCHES      : natural := 3;
  constant PAIRHMM_MAX_SIZE : natural := 64;

  constant CU_MAX_CYCLES : natural := PAIRHMM_MAX_SIZE / PE_DEPTH * 2 * PAIRHMM_MAX_SIZE;
  constant CU_CYCLE_BITS : natural := log2(CU_MAX_CYCLES);
----------------------------------------------------------------------------------------------------------------------- internals

  type fifo_controls is record
    rd_en  : std_logic;
    rd_en1 : std_logic;

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

  type outfifo_item is record
    din  : std_logic_vector(31 downto 0);
    dout : std_logic_vector(31 downto 0);
    c    : fifo_controls;
  end record;

  -- type fbfifo_item is record
  --   din  : std_logic_vector(386 downto 0);
  --   dout : std_logic_vector(386 downto 0);
  --   c    : fifo_controls;
  -- end record;

  type fbfifo_item is record
    din  : std_logic_vector(458 downto 0);
    dout : std_logic_vector(458 downto 0);
    c    : fifo_controls;
  end record;

  type basefifo_item is record
    din  : std_logic_vector(2 downto 0);
    dout : std_logic_vector(2 downto 0);
    c    : fifo_controls;
  end record;

  type probfifo_item is record
    din  : std_logic_vector(PAIRHMM_BITS_PER_PROB - 1 downto 0);
    dout : std_logic_vector(PAIRHMM_BITS_PER_PROB - 1 downto 0);
    c    : fifo_controls;
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

  type cu_int is record
    state : cu_state;
    wed   : wed_type;

    inits   : cu_inits;
    -- initial : prob;
    initial : std_logic_vector(31 downto 0);
    sched   : cu_inits;

    y_reads : unsigned(15 downto 0);
    x_reads : unsigned(15 downto 0);
    p_reads : unsigned(15 downto 0);

    hapl_wren : std_logic_vector(0 downto 0);
    read_wren : std_logic_vector(0 downto 0);
    prob_wren : std_logic;

    hapl_data : std_logic_vector(7 downto 0);
    read_data : std_logic_vector(7 downto 0);
    prob_data : std_logic_vector(PAIRHMM_BITS_PER_PROB - 1 downto 0);

    pair   : unsigned(PE_DEPTH_BITS - 1 downto 0);
    filled : std_logic;
  end record;

  type cu_sched_state is (
    SCHED_IDLE,
    SCHED_STARTUP,
    SCHED_PROCESSING,
    SCHED_EMPTY_FIFOS,
    SCHED_DONE
    );

  type cu_sched is record
    pairhmm_rst : std_logic;            -- Reset

    state       : cu_sched_state;       -- State of the scheduler process
    cycle       : unsigned(CU_CYCLE_BITS - 1 downto 0);  -- This must be able to hold up to PAIRHMM_MAX_SIZE / PE_DEPTH * 2 * PAIRHMM_MAX_SIZE-1
    basepair    : unsigned(log2e(PAIRHMM_MAX_SIZE) downto 0);  -- This must be able to hold up to PAIRHMM_MAX_SIZE-1 but is 1 larger to compare to size array values
    element     : unsigned(log2e(PAIRHMM_NUM_PES) downto 0);  -- This must be able to hold PAIRHMM_NUM_PES-1
    schedule    : unsigned(PE_DEPTH_BITS - 1 downto 0);  -- To hold the pair that is currently scheduled
    supercolumn : unsigned(log2e(PAIRHMM_MAX_SIZE / PAIRHMM_NUM_PES) downto 0);  -- To keep track in which group of columns we are

    valid : std_logic;                  -- Valid bit for the PairHMM core
    cell  : pe_cell_type;  -- State of the cell for this bunch of data

    feedback                        : std_logic;  -- To select the feedback FIFO as PairHMM core input
    feedback_rd_en, feedback_rd_en1 : std_logic;  -- Read enable for the feedback FIFO
    feedback_wr_en                  : std_logic;  -- Write enable for the feedback FIFO
    feedback_rst                    : std_logic;  -- Feedback FIFO reset

    leny   : unsigned(log2e(PAIRHMM_MAX_SIZE) downto 0);
    sizey  : unsigned(log2e(PAIRHMM_MAX_SIZE) downto 0);  -- To keep track of howmany bp's each pair still has to process in y direction
    lenx   : unsigned(log2e(PAIRHMM_MAX_SIZE) downto 0);
    sizex  : unsigned(log2e(PAIRHMM_MAX_SIZE) downto 0);  -- To keep track of howmany bp's each pair still has to process in x direction
    sizexp : unsigned(log2e(PAIRHMM_MAX_SIZE) downto 0);  -- To keep track of howmany bp's each pair still has to process in x direction (padded value)

    startflag : std_logic;  -- To keep track of if we just started up a new pair

    pe_first : pe_in;

    ybus_addr, ybus_addr1 : unsigned(log2e(PAIRHMM_NUM_PES) downto 0);
    ybus_en, ybus_en1     : std_logic;

    core_schedule : unsigned(PE_DEPTH_BITS-1 downto 0);

    shift_read_buffer : std_logic;
    shift_hapl_buffer : std_logic;
    shift_prob_buffer : std_logic;
  end record;

  constant cu_sched_empty : cu_sched := (
    state             => SCHED_IDLE,
    cycle             => (others => '0'),
    basepair          => (others => '0'),
    element           => (others => '0'),
    schedule          => (others => '0'),
    supercolumn       => (others => '0'),
    valid             => '0',
    cell              => PE_NORMAL,
    pairhmm_rst       => '1',
    feedback          => '0',
    feedback_rd_en    => '0',
    feedback_rd_en1   => '0',
    feedback_wr_en    => '0',
    feedback_rst      => '1',
    leny              => (others => '0'),
    sizey             => (others => '0'),
    lenx              => (others => '0'),
    sizex             => (others => '0'),
    sizexp            => (others => '0'),
    startflag         => '1',
    pe_first          => pe_in_empty,
    ybus_addr         => (others => '0'),
    ybus_addr1        => (others => '0'),
    ybus_en           => '0',
    ybus_en1          => '0',
    core_schedule     => (others => '0'),
    shift_read_buffer => '0',
    shift_hapl_buffer => '0',
    shift_prob_buffer => '0'
    );

  constant CYCLE_ZERO : unsigned(CU_CYCLE_BITS-1 downto 0) := usign(0, CU_CYCLE_BITS);

  type cu_ext is record
    pairhmm_cr : cr_in;
    pairhmm    : pairhmm_item;
    pairhmm_in : pe_in;
    outfifo    : outfifo_item;
    fbfifo     : fbfifo_item;

    haplfifo : basefifo_item;
    readfifo : basefifo_item;
    probfifo : probfifo_item;

    fbpairhmm  : pe_in;
    outdata    : std_logic_vector(1023 downto 0);
    clk_kernel : std_logic;
  end record;

  procedure cu_reset (signal r : inout cu_int);

  function slvec (a : in integer; b : in natural) return std_logic_vector;
  function slvec (a : in unsigned) return std_logic_vector;

  component psl_to_kernel is
    port (
      clk_psl    : in  std_logic;
      clk_kernel : out std_logic
      );
  end component;

end package cu_snap_package;

package body cu_snap_package is

  procedure cu_reset (signal r : inout cu_int) is
  begin
    r.state <= LOAD_IDLE;

    r.x_reads <= (others => '0');
    r.y_reads <= (others => '0');
    r.p_reads <= (others => '0');

    r.hapl_wren <= "0";
    r.read_wren <= "0";

    r.read_data <= (others => '0');
    r.prob_data <= (others => '0');
    r.hapl_data <= (others => '0');

    r.initial <= (others => '0');

    r.filled <= '0';
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