library ieee, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;
use ieee.std_logic_textio.all;
use std.textio.all;

library work;
use work.Streams.all;
use work.Utils.all;
use work.Arrow.all;

use work.SimUtils.all;

use work.functions.slv8bpslv3;
use work.functions.slv3bp;
use work.functions.bpslv3;

use work.functions.all;
use work.arrow_pairhmm_pkg.all;
use work.pairhmm_package.all;
use work.pe_package.all;
use work.cu_snap_package.all;

entity pairhmm_unit is
  generic (
    -- Host bus properties
    BUS_ADDR_WIDTH : natural := 64;
    BUS_DATA_WIDTH : natural := 512;

    BUS_LEN_WIDTH      : natural := BOTTOM_LEN_WIDTH;
    BUS_BURST_STEP_LEN : natural := BOTTOM_BURST_STEP_LEN;
    BUS_BURST_MAX_LEN  : natural := BOTTOM_BURST_MAX_LEN;

    REG_WIDTH : natural := 32

   -- (Generic defaults are set for SystemVerilog compatibility)
    );

  port (
    clk     : in std_logic;
    reset_n : in std_logic;

    control_reset : in  std_logic;
    control_start : in  std_logic;
    reset_start   : out std_logic;

    busy : out std_logic;
    done : out std_logic;

    -- Haplotypes buffer addresses
    hapl_off_hi, hapl_off_lo : in std_logic_vector(REG_WIDTH-1 downto 0);
    hapl_bp_hi, hapl_bp_lo   : in std_logic_vector(REG_WIDTH-1 downto 0);

    -- Reads buffer addresses
    read_off_hi, read_off_lo     : in std_logic_vector(REG_WIDTH-1 downto 0);
    read_bp_hi, read_bp_lo       : in std_logic_vector(REG_WIDTH-1 downto 0);
    read_probs_hi, read_probs_lo : in std_logic_vector(REG_WIDTH-1 downto 0);

    -- Result buffer address
    result_data_hi, result_data_lo : in std_logic_vector(REG_WIDTH-1 downto 0);

    -- Batch offset (to fetch from Arrow)
    batch_offset : in std_logic_vector(REG_WIDTH-1 downto 0);

    -- Batch information
    x_len      : in std_logic_vector(REG_WIDTH-1 downto 0);
    y_len      : in std_logic_vector(REG_WIDTH-1 downto 0);
    x_size     : in std_logic_vector(REG_WIDTH-1 downto 0);
    x_padded   : in std_logic_vector(REG_WIDTH-1 downto 0);
    y_size     : in std_logic_vector(REG_WIDTH-1 downto 0);
    y_padded   : in std_logic_vector(REG_WIDTH-1 downto 0);
    x_bppadded : in std_logic_vector(REG_WIDTH-1 downto 0);
    initial    : in std_logic_vector(REG_WIDTH-1 downto 0);

    ---------------------------------------------------------------------------
    -- Master bus Haplotypes
    ---------------------------------------------------------------------------
    -- Read request channel
    bus_hapl_req_addr  : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    bus_hapl_req_len   : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    bus_hapl_req_valid : out std_logic;
    bus_hapl_req_ready : in  std_logic;

    -- Read response channel
    bus_hapl_rsp_data  : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    bus_hapl_rsp_resp  : in  std_logic_vector(1 downto 0);
    bus_hapl_rsp_last  : in  std_logic;
    bus_hapl_rsp_valid : in  std_logic;
    bus_hapl_rsp_ready : out std_logic;

    ---------------------------------------------------------------------------
    -- Master bus Reads
    ---------------------------------------------------------------------------
    -- Read request channel
    bus_read_req_addr  : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    bus_read_req_len   : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    bus_read_req_valid : out std_logic;
    bus_read_req_ready : in  std_logic;

    -- Read response channel
    bus_read_rsp_data  : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    bus_read_rsp_resp  : in  std_logic_vector(1 downto 0);
    bus_read_rsp_last  : in  std_logic;
    bus_read_rsp_valid : in  std_logic;
    bus_read_rsp_ready : out std_logic;

    ---------------------------------------------------------------------------
    -- Master bus Result
    ---------------------------------------------------------------------------
    -- Write request channel
    bus_result_wreq_addr  : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    bus_result_wreq_len   : out std_logic_vector(BUS_LEN_WIDTH-1 downto 0);
    bus_result_wreq_valid : out std_logic;
    bus_result_wreq_ready : in  std_logic;

    -- Write response channel
    bus_result_wdat_data   : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    bus_result_wdat_strobe : out std_logic_vector(BUS_DATA_WIDTH/8-1 downto 0);
    bus_result_wdat_last   : out std_logic;
    bus_result_wdat_valid  : out std_logic;
    bus_result_wdat_ready  : in  std_logic
    );
end pairhmm_unit;

architecture pairhmm_unit of pairhmm_unit is
  signal reset : std_logic;

  -- Register all ports to ease timing
  signal r_control_reset                    : std_logic;
  signal r_control_start                    : std_logic;
  signal r_reset_start                      : std_logic;
  signal r_busy                             : std_logic;
  signal r_done                             : std_logic;
  signal r_hapl_off_hi, r_read_off_hi       : std_logic_vector(REG_WIDTH - 1 downto 0);
  signal r_hapl_off_lo, r_read_off_lo       : std_logic_vector(REG_WIDTH - 1 downto 0);
  signal r_hapl_bp_hi, r_hapl_bp_lo         : std_logic_vector(REG_WIDTH - 1 downto 0);
  signal r_read_bp_hi, r_read_bp_lo         : std_logic_vector(REG_WIDTH - 1 downto 0);
  signal r_read_probs_hi, r_read_probs_lo   : std_logic_vector(REG_WIDTH - 1 downto 0);
  signal r_result_data_hi, r_result_data_lo : std_logic_vector(REG_WIDTH - 1 downto 0);

  signal r_batch_offset : std_logic_vector(REG_WIDTH - 1 downto 0);  -- To retrieve the correct data from Arrow columns

  -- Batch information
  signal r_x_len, r_y_len, r_x_size, r_x_padded, r_y_size, r_y_padded, r_x_bppadded, r_initial : std_logic_vector(REG_WIDTH - 1 downto 0);

  -----------------------------------------------------------------------------
  -- HAPLO STREAMS
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- Haplotype ColumnReader Interface
  -----------------------------------------------------------------------------
  constant INDEX_WIDTH_HAPL        : natural := 32;
  constant VALUE_ELEM_WIDTH_HAPL   : natural := 8;
  constant VALUES_PER_CYCLE_HAPL   : natural := 1;
  constant NUM_STREAMS_HAPL        : natural := 2;  -- index stream, data stream
  constant VALUES_WIDTH_HAPL       : natural := VALUE_ELEM_WIDTH_HAPL * VALUES_PER_CYCLE_HAPL;
  constant VALUES_COUNT_WIDTH_HAPL : natural := log2ceil(VALUES_PER_CYCLE_HAPL) + 1;
  constant OUT_DATA_WIDTH_HAPL     : natural := INDEX_WIDTH_HAPL + VALUES_WIDTH_HAPL + VALUES_COUNT_WIDTH_HAPL;

  signal out_hapl_valid  : std_logic_vector(NUM_STREAMS_HAPL - 1 downto 0);
  signal out_hapl_ready  : std_logic_vector(NUM_STREAMS_HAPL - 1 downto 0);
  signal out_hapl_last   : std_logic_vector(NUM_STREAMS_HAPL - 1 downto 0);
  signal out_hapl_dvalid : std_logic_vector(NUM_STREAMS_HAPL - 1 downto 0);
  signal out_hapl_data   : std_logic_vector(OUT_DATA_WIDTH_HAPL - 1 downto 0);

  type len_stream_in_t is record
    valid  : std_logic;
    dvalid : std_logic;
    last   : std_logic;
    data   : std_logic_vector(INDEX_WIDTH_HAPL - 1 downto 0);
  end record;

  type len_stream_out_t is record
    ready : std_logic;
  end record;

  type utf8_stream_in_t is record
    valid  : std_logic;
    dvalid : std_logic;
    last   : std_logic;
    count  : std_logic_vector(VALUES_COUNT_WIDTH_HAPL - 1 downto 0);
    data   : std_logic_vector(VALUES_WIDTH_HAPL - 1 downto 0);
  end record;

  type utf8_stream_out_t is record
    ready : std_logic;
  end record;

  -- Command Stream
  type command_hapl_t is record
    valid    : std_logic;
    ready    : std_logic;
    firstIdx : std_logic_vector(INDEX_WIDTH_HAPL - 1 downto 0);
    lastIdx  : std_logic_vector(INDEX_WIDTH_HAPL - 1 downto 0);
    ctrl     : std_logic_vector(2 * BUS_ADDR_WIDTH - 1 downto 0);
  end record;

  signal hapl_in_data : std_logic_vector(2 * INDEX_WIDTH_HAPL + 2 * BUS_ADDR_WIDTH - 1 downto 0);

  type str_hapl_elem_in_t is record
    len  : len_stream_in_t;
    utf8 : utf8_stream_in_t;
  end record;

  type str_hapl_elem_out_t is record
    len  : len_stream_out_t;
    utf8 : utf8_stream_out_t;
  end record;

  procedure conv_streams_hapl_in (
    signal valid            : in  std_logic_vector(NUM_STREAMS_HAPL - 1 downto 0);
    signal dvalid           : in  std_logic_vector(NUM_STREAMS_HAPL - 1 downto 0);
    signal last             : in  std_logic_vector(NUM_STREAMS_HAPL - 1 downto 0);
    signal data             : in  std_logic_vector(OUT_DATA_WIDTH_HAPL - 1 downto 0);
    signal str_hapl_elem_in : out str_hapl_elem_in_t
    ) is
  begin
    str_hapl_elem_in.len.data   <= data (INDEX_WIDTH_HAPL-1 downto 0);
    str_hapl_elem_in.len.valid  <= valid (0);
    str_hapl_elem_in.len.dvalid <= dvalid(0);
    str_hapl_elem_in.len.last   <= last (0);

    str_hapl_elem_in.utf8.count  <= data(VALUES_COUNT_WIDTH_HAPL + VALUES_WIDTH_HAPL + INDEX_WIDTH_HAPL - 1 downto VALUES_WIDTH_HAPL + INDEX_WIDTH_HAPL);
    str_hapl_elem_in.utf8.data   <= data(VALUES_WIDTH_HAPL + INDEX_WIDTH_HAPL - 1 downto INDEX_WIDTH_HAPL);
    str_hapl_elem_in.utf8.valid  <= valid(1);
    str_hapl_elem_in.utf8.dvalid <= dvalid(1);
    str_hapl_elem_in.utf8.last   <= last(1);
  end procedure;

  procedure conv_streams_hapl_out (
    signal str_hapl_elem_out : in  str_hapl_elem_out_t;
    signal out_ready         : out std_logic_vector(NUM_STREAMS_HAPL - 1 downto 0)
    ) is
  begin
    out_ready(0) <= str_hapl_elem_out.len.ready;
    out_ready(1) <= str_hapl_elem_out.utf8.ready;
  end procedure;

  signal str_hapl_elem_in  : str_hapl_elem_in_t;
  signal str_hapl_elem_out : str_hapl_elem_out_t;

  signal s_cmd_hapl_tmp : std_logic_vector(2 * BUS_ADDR_WIDTH + 2 * INDEX_WIDTH_HAPL - 1 downto 0);
  signal s_cmd_hapl     : command_hapl_t;
  signal cmd_hapl_ready : std_logic;

  -----------------------------------------------------------------------------
  -- READ STREAMS
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- Reads ColumnReader Interface
  -----------------------------------------------------------------------------
  constant INDEX_WIDTH_READ            : natural := 32;
  constant VALUE_ELEM_WIDTH_READ_BP    : natural := 8;  -- 8 bit character
  constant VALUE_ELEM_WIDTH_READ_PROBS : natural := 8 * 32;  -- 8 * 32-bit probabilities
  constant VALUES_PER_CYCLE_READ       : natural := 1;
  constant NUM_STREAMS_READ            : natural := 3;  -- index stream, data stream en nog wat
  constant VALUES_WIDTH_READ           : natural := VALUE_ELEM_WIDTH_READ_BP + VALUE_ELEM_WIDTH_READ_PROBS;
  constant OUT_DATA_WIDTH_READ         : natural := INDEX_WIDTH_READ + VALUES_WIDTH_READ;

  signal out_read_valid  : std_logic_vector(1 downto 0);
  signal out_read_ready  : std_logic_vector(1 downto 0);
  signal out_read_last   : std_logic_vector(1 downto 0);
  signal out_read_dvalid : std_logic_vector(1 downto 0);
  signal out_read_data   : std_logic_vector(OUT_DATA_WIDTH_READ - 1 downto 0);

  -- Command Stream
  type command_read_t is record
    valid    : std_logic;
    ready    : std_logic;
    firstIdx : std_logic_vector(INDEX_WIDTH_READ - 1 downto 0);
    lastIdx  : std_logic_vector(INDEX_WIDTH_READ - 1 downto 0);
    ctrl     : std_logic_vector(NUM_STREAMS_READ * BUS_ADDR_WIDTH - 1 downto 0);
  end record;

  signal read_in_data : std_logic_vector(2 * INDEX_WIDTH_READ + NUM_STREAMS_READ * BUS_ADDR_WIDTH - 1 downto 0);

  type read_data_stream_in_probs_t is record
    eta        : std_logic_vector(31 downto 0);
    zeta       : std_logic_vector(31 downto 0);
    epsilon    : std_logic_vector(31 downto 0);
    delta      : std_logic_vector(31 downto 0);
    beta       : std_logic_vector(31 downto 0);
    alpha      : std_logic_vector(31 downto 0);
    distm_diff : std_logic_vector(31 downto 0);
    distm_simi : std_logic_vector(31 downto 0);
  end record;

  type read_data_stream_in_t is record
    valid  : std_logic;
    dvalid : std_logic;
    last   : std_logic;

    bp   : std_logic_vector(VALUE_ELEM_WIDTH_READ_BP - 1 downto 0);
    prob : read_data_stream_in_probs_t;
  end record;

  type read_data_stream_out_t is record
    ready : std_logic;
  end record;

  type str_read_elem_in_t is record
    len  : len_stream_in_t;
    data : read_data_stream_in_t;
  end record;

  type str_read_elem_out_t is record
    len  : len_stream_out_t;
    data : read_data_stream_out_t;
  end record;

  procedure conv_streams_read_in (
    signal valid            : in  std_logic_vector(1 downto 0);
    signal dvalid           : in  std_logic_vector(1 downto 0);
    signal last             : in  std_logic_vector(1 downto 0);
    signal data             : in  std_logic_vector(OUT_DATA_WIDTH_READ - 1 downto 0);
    signal str_read_elem_in : out str_read_elem_in_t
    ) is
  begin
    str_read_elem_in.len.data   <= data (INDEX_WIDTH_READ - 1 downto 0);
    str_read_elem_in.len.valid  <= valid (0);
    str_read_elem_in.len.dvalid <= dvalid(0);
    str_read_elem_in.len.last   <= last (0);

    str_read_elem_in.data.bp <= data(VALUE_ELEM_WIDTH_READ_BP + VALUE_ELEM_WIDTH_READ_PROBS + INDEX_WIDTH_READ - 1 downto VALUE_ELEM_WIDTH_READ_PROBS + INDEX_WIDTH_READ);

    str_read_elem_in.data.prob.eta        <= data(VALUE_ELEM_WIDTH_READ_PROBS + INDEX_WIDTH_READ - 1 - 7*32 downto INDEX_WIDTH_READ + 0*32);
    str_read_elem_in.data.prob.zeta       <= data(VALUE_ELEM_WIDTH_READ_PROBS + INDEX_WIDTH_READ - 1 - 6*32 downto INDEX_WIDTH_READ + 1*32);
    str_read_elem_in.data.prob.epsilon    <= data(VALUE_ELEM_WIDTH_READ_PROBS + INDEX_WIDTH_READ - 1 - 5*32 downto INDEX_WIDTH_READ + 2*32);
    str_read_elem_in.data.prob.delta      <= data(VALUE_ELEM_WIDTH_READ_PROBS + INDEX_WIDTH_READ - 1 - 4*32 downto INDEX_WIDTH_READ + 3*32);
    str_read_elem_in.data.prob.beta       <= data(VALUE_ELEM_WIDTH_READ_PROBS + INDEX_WIDTH_READ - 1 - 3*32 downto INDEX_WIDTH_READ + 4*32);
    str_read_elem_in.data.prob.alpha      <= data(VALUE_ELEM_WIDTH_READ_PROBS + INDEX_WIDTH_READ - 1 - 2*32 downto INDEX_WIDTH_READ + 5*32);
    str_read_elem_in.data.prob.distm_diff <= data(VALUE_ELEM_WIDTH_READ_PROBS + INDEX_WIDTH_READ - 1 - 1*32 downto INDEX_WIDTH_READ + 6*32);
    str_read_elem_in.data.prob.distm_simi <= data(VALUE_ELEM_WIDTH_READ_PROBS + INDEX_WIDTH_READ - 1 - 0*32 downto INDEX_WIDTH_READ + 7*32);

    str_read_elem_in.data.valid  <= valid(1);
    str_read_elem_in.data.dvalid <= dvalid(1);
    str_read_elem_in.data.last   <= last(1);
  end procedure;

  procedure conv_streams_read_out (
    signal str_read_elem_out : in  str_read_elem_out_t;
    signal out_ready         : out std_logic_vector(1 downto 0)
    ) is
  begin
    out_ready(0) <= str_read_elem_out.len.ready;
    out_ready(1) <= str_read_elem_out.data.ready;
  end procedure;

  signal str_read_elem_in  : str_read_elem_in_t;
  signal str_read_elem_out : str_read_elem_out_t;

  signal s_cmd_read_tmp : std_logic_vector(NUM_STREAMS_READ * BUS_ADDR_WIDTH + 2 * INDEX_WIDTH_READ - 1 downto 0);
  signal s_cmd_read     : command_read_t;
  signal cmd_read_ready : std_logic;

  -----------------------------------------------------------------------------
  -- RESULT STREAMS
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- Result ColumnWriter Interface
  -----------------------------------------------------------------------------
  constant INDEX_WIDTH_RESULT        : natural := 32;
  constant VALUE_ELEM_WIDTH_RESULT   : natural := 32;
  constant VALUES_PER_CYCLE_RESULT   : natural := 1;
  constant NUM_STREAMS_RESULT        : natural := 1;  -- data stream
  constant VALUES_WIDTH_RESULT       : natural := VALUE_ELEM_WIDTH_RESULT * VALUES_PER_CYCLE_RESULT;
  constant VALUES_COUNT_WIDTH_RESULT : natural := log2ceil(VALUES_PER_CYCLE_RESULT) + 1;
  constant IN_DATA_WIDTH_RESULT      : natural := INDEX_WIDTH_RESULT + VALUES_WIDTH_RESULT + VALUES_COUNT_WIDTH_RESULT;
  constant TAG_WIDTH_RESULT          : natural := 1;

  signal in_result_valid  : std_logic_vector(NUM_STREAMS_RESULT - 1 downto 0);
  signal in_result_ready  : std_logic_vector(NUM_STREAMS_RESULT - 1 downto 0);
  signal in_result_last   : std_logic_vector(NUM_STREAMS_RESULT - 1 downto 0);
  signal in_result_dvalid : std_logic_vector(NUM_STREAMS_RESULT - 1 downto 0);
  signal in_result_data   : std_logic_vector(VALUES_WIDTH_RESULT - 1 downto 0);

  -- Command Stream
  type command_result_t is record
    valid    : std_logic;
    tag      : std_logic_vector(TAG_WIDTH_RESULT - 1 downto 0);
    firstIdx : std_logic_vector(INDEX_WIDTH_RESULT - 1 downto 0);
    lastIdx  : std_logic_vector(INDEX_WIDTH_RESULT - 1 downto 0);
    ctrl     : std_logic_vector(BUS_ADDR_WIDTH - 1 downto 0);
  end record;

  type result_data_stream_out_t is record
    valid  : std_logic;
    dvalid : std_logic;
    last   : std_logic;
    data   : std_logic_vector(VALUES_WIDTH_RESULT - 1 downto 0);
  end record;

  type result_data_stream_in_t is record
    ready : std_logic;
  end record;

  type str_result_elem_in_t is record
    data : result_data_stream_in_t;
  end record;

  type str_result_elem_out_t is record
    data : result_data_stream_out_t;
  end record;

  procedure conv_streams_result_out (
    signal valid               : out std_logic_vector(NUM_STREAMS_RESULT - 1 downto 0);
    signal dvalid              : out std_logic_vector(NUM_STREAMS_RESULT - 1 downto 0);
    signal last                : out std_logic_vector(NUM_STREAMS_RESULT - 1 downto 0);
    signal data                : out std_logic_vector(VALUES_WIDTH_RESULT - 1 downto 0);
    signal str_result_elem_out : in  str_result_elem_out_t
    ) is
  begin
    valid(0)                               <= str_result_elem_out.data.valid;
    dvalid(0)                              <= str_result_elem_out.data.dvalid;
    last(0)                                <= str_result_elem_out.data.last;
    data(VALUES_WIDTH_RESULT - 1 downto 0) <= str_result_elem_out.data.data;
  end procedure;

  procedure conv_streams_result_in (
    signal str_result_elem_in : out str_result_elem_in_t;
    signal in_ready           : in  std_logic_vector(NUM_STREAMS_RESULT - 1 downto 0)
    ) is
  begin
    str_result_elem_in.data.ready <= in_ready(0);
  end procedure;

  type unl_record is record
    ready : std_logic;
  end record;

  type out_record is record
    cmd : command_result_t;
    unl : unl_record;
  end record;

  signal str_result_elem_in  : str_result_elem_in_t;
  signal str_result_elem_out : str_result_elem_out_t;

  signal result_cmd_valid    : std_logic;
  signal result_cmd_ready    : std_logic;
  signal result_cmd_firstIdx : std_logic_vector(INDEX_WIDTH_RESULT-1 downto 0);
  signal result_cmd_lastIdx  : std_logic_vector(INDEX_WIDTH_RESULT-1 downto 0);
  signal result_cmd_ctrl     : std_logic_vector(BUS_ADDR_WIDTH -1 downto 0);
  signal result_cmd_tag      : std_logic_vector(TAG_WIDTH_RESULT-1 downto 0);
  signal result_unlock_valid : std_logic;
  signal result_unlock_ready : std_logic;
  signal result_unlock_tag   : std_logic_vector(TAG_WIDTH_RESULT-1 downto 0);

  -----------------------------------------------------------------------------
  -- UserCore
  -----------------------------------------------------------------------------
  type state_t is (STATE_IDLE, STATE_RESET_START, STATE_REQUEST, STATE_BUSY, STATE_DONE);

  type regex_in_t is record
    valid : std_logic;
    data  : std_logic_vector(VALUES_WIDTH_HAPL - 1 downto 0);
    mask  : std_logic_vector(VALUES_PER_CYCLE_HAPL - 1 downto 0);
    last  : std_logic;
  end record;

  type regex_out_t is record
    valid : std_logic;
    match : std_logic;
    error : std_logic;
  end record;

  type regex_t is record
    input  : regex_in_t;
    output : regex_out_t;
  end record;

  -- Control and status bits
  type cs_t is record
    reset_start : std_logic;
    done        : std_logic;
    busy        : std_logic;
  end record;

  type reg is record
    state : state_t;
    cs    : cs_t;

    command_hapl : command_hapl_t;
    command_read : command_read_t;

    regex : regex_t;

    str_hapl_elem_out : str_hapl_elem_out_t;
    str_hapl_elem_in  : str_hapl_elem_in_t;

    str_read_elem_out : str_read_elem_out_t;
    str_read_elem_in  : str_read_elem_in_t;

    reset_units : std_logic;
  end record;

  signal cr_r, cr_d : reg;

  type state_result_t is (IDLE, COLUMNWRITE, WAIT_ACCEPT, UNLOCK);
  type reg_result is record
    state : state_result_t;
    cs    : cs_t;

    result_index : integer;

    command_result : command_result_t;

    str_result_elem_out : str_result_elem_out_t;
    str_result_elem_in  : str_result_elem_in_t;

    reset_units : std_logic;
  end record;
  signal cw_r, cw_d : reg_result;

  -- Pair-HMM SA core signals
  signal q, r   : cu_int;
  signal re     : cu_ext;
  signal qs, rs : cu_sched := cu_sched_empty;

  signal read_delay                        : bp_type;
  signal valid_delay                       : std_logic;
  signal cell_delay                        : pe_cell_type;
  signal ybus_data_delay, ybus_data_delay1 : pe_y_data_type;

  type basedelay_type is array (0 to PE_DEPTH - 1) of bp_type;
  signal readdelay, hapldelay : basedelay_type;

  type probdelay_type is array (0 to PE_DEPTH - 1) of std_logic_vector(PAIRHMM_BITS_PER_PROB - 1 downto 0);
  signal probdelay : probdelay_type;

  signal read_delay_count, hapl_delay_count, prob_delay_count : integer range 0 to 63 := 0;
  signal read_delay_valid, hapl_delay_valid, prob_delay_valid : std_logic;
  signal read_delay_rst, hapl_delay_rst, prob_delay_rst       : std_logic;

begin
  reset <= not reset_n;

  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- HAPLOTYPES
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- Command Stream Slice
  -----------------------------------------------------------------------------
  hapl_in_data <= cr_d.command_hapl.firstIdx & cr_d.command_hapl.lastIdx & cr_d.command_hapl.ctrl;
  slice_inst_hapl : StreamSlice
    generic map (
      DATA_WIDTH => 2 * BUS_ADDR_WIDTH + 2 * INDEX_WIDTH_HAPL
      ) port map (
        clk       => clk,
        reset     => cr_d.reset_units,
        in_valid  => cr_d.command_hapl.valid,
        in_ready  => cmd_hapl_ready,
        in_data   => hapl_in_data,
        out_valid => s_cmd_hapl.valid,
        out_ready => s_cmd_hapl.ready,
        out_data  => s_cmd_hapl_tmp
        );

  s_cmd_hapl.ctrl     <= s_cmd_hapl_tmp(2 * BUS_ADDR_WIDTH - 1 downto 0);
  s_cmd_hapl.lastIdx  <= s_cmd_hapl_tmp(2 * BUS_ADDR_WIDTH + INDEX_WIDTH_HAPL - 1 downto 2 * BUS_ADDR_WIDTH);
  s_cmd_hapl.firstIdx <= s_cmd_hapl_tmp(2 * BUS_ADDR_WIDTH + 2 * INDEX_WIDTH_HAPL - 1 downto 2 * BUS_ADDR_WIDTH + INDEX_WIDTH_HAPL);

  -----------------------------------------------------------------------------
  -- ColumnReader
  -----------------------------------------------------------------------------
  hapl_cr : ColumnReader
    generic map (
      BUS_ADDR_WIDTH     => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH      => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH     => BUS_DATA_WIDTH,
      BUS_BURST_STEP_LEN => BUS_BURST_STEP_LEN,
      BUS_BURST_MAX_LEN  => BUS_BURST_MAX_LEN,
      INDEX_WIDTH        => INDEX_WIDTH_HAPL,
      CFG                => "listprim(8)",
      CMD_TAG_ENABLE     => false,
      CMD_TAG_WIDTH      => 1
      )
    port map (
      bus_clk   => clk,
      bus_reset => cr_r.reset_units,
      acc_clk   => clk,
      acc_reset => cr_r.reset_units,

      cmd_valid    => s_cmd_hapl.valid,
      cmd_ready    => s_cmd_hapl.ready,
      cmd_firstIdx => s_cmd_hapl.firstIdx,
      cmd_lastIdx  => s_cmd_hapl.lastIdx,
      cmd_ctrl     => s_cmd_hapl.ctrl,
      cmd_tag      => (others => '0'),  -- CMD_TAG_ENABLE is false

      unlock_valid => open,
      unlock_ready => '1',
      unlock_tag   => open,

      busReq_valid => bus_hapl_req_valid,
      busReq_ready => bus_hapl_req_ready,
      busReq_addr  => bus_hapl_req_addr,
      busReq_len   => bus_hapl_req_len,

      busResp_valid => bus_hapl_rsp_valid,
      busResp_ready => bus_hapl_rsp_ready,
      busResp_data  => bus_hapl_rsp_data,
      busResp_last  => bus_hapl_rsp_last,

      out_valid  => out_hapl_valid,
      out_ready  => out_hapl_ready,
      out_last   => out_hapl_last,
      out_dvalid => out_hapl_dvalid,
      out_data   => out_hapl_data
      );

  -----------------------------------------------------------------------------
  -- Stream Conversion
  -----------------------------------------------------------------------------
  -- Output
  str_hapl_elem_out <= cr_d.str_hapl_elem_out;

  -- Convert the stream inputs and outputs to something readable
  conv_streams_hapl_in(out_hapl_valid, out_hapl_dvalid, out_hapl_last, out_hapl_data, str_hapl_elem_in);
  conv_streams_hapl_out(str_hapl_elem_out, out_hapl_ready);

  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- READS
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- Command Stream Slice
  -----------------------------------------------------------------------------
  read_in_data <= cr_d.command_read.firstIdx & cr_d.command_read.lastIdx & cr_d.command_read.ctrl;
  slice_inst_read : StreamSlice
    generic map (
      DATA_WIDTH => NUM_STREAMS_READ * BUS_ADDR_WIDTH + 2 * INDEX_WIDTH_READ
      ) port map (
        clk       => clk,
        reset     => cr_d.reset_units,
        in_valid  => cr_d.command_read.valid,
        in_ready  => cmd_read_ready,
        in_data   => read_in_data,
        out_valid => s_cmd_read.valid,
        out_ready => s_cmd_read.ready,
        out_data  => s_cmd_read_tmp
        );

  s_cmd_read.ctrl     <= s_cmd_read_tmp(NUM_STREAMS_READ * BUS_ADDR_WIDTH - 1 downto 0);
  s_cmd_read.lastIdx  <= s_cmd_read_tmp(NUM_STREAMS_READ * BUS_ADDR_WIDTH + INDEX_WIDTH_READ - 1 downto NUM_STREAMS_READ * BUS_ADDR_WIDTH);
  s_cmd_read.firstIdx <= s_cmd_read_tmp(NUM_STREAMS_READ * BUS_ADDR_WIDTH + 2 * INDEX_WIDTH_READ - 1 downto NUM_STREAMS_READ * BUS_ADDR_WIDTH + INDEX_WIDTH_READ);

  -----------------------------------------------------------------------------
  -- ColumnReader
  -----------------------------------------------------------------------------
  read_cr : ColumnReader
    generic map (
      BUS_ADDR_WIDTH     => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH      => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH     => BUS_DATA_WIDTH,
      BUS_BURST_STEP_LEN => BUS_BURST_STEP_LEN,
      BUS_BURST_MAX_LEN  => BUS_BURST_MAX_LEN,
      INDEX_WIDTH        => INDEX_WIDTH_READ,
      CFG                => "list(struct(prim(8),prim(256)))",  -- struct array (reads)
      CMD_TAG_ENABLE     => false,
      CMD_TAG_WIDTH      => 1
      )
    port map (
      bus_clk   => clk,
      bus_reset => cr_r.reset_units,
      acc_clk   => clk,
      acc_reset => cr_r.reset_units,

      cmd_valid    => s_cmd_read.valid,
      cmd_ready    => s_cmd_read.ready,
      cmd_firstIdx => s_cmd_read.firstIdx,
      cmd_lastIdx  => s_cmd_read.lastIdx,
      cmd_ctrl     => s_cmd_read.ctrl,
      cmd_tag      => (others => '0'),  -- CMD_TAG_ENABLE is false

      unlock_valid => open,
      unlock_ready => '1',
      unlock_tag   => open,

      busReq_valid => bus_read_req_valid,
      busReq_ready => bus_read_req_ready,
      busReq_addr  => bus_read_req_addr,
      busReq_len   => bus_read_req_len,

      busResp_valid => bus_read_rsp_valid,
      busResp_ready => bus_read_rsp_ready,
      busResp_data  => bus_read_rsp_data,
      busResp_last  => bus_read_rsp_last,

      out_valid  => out_read_valid,
      out_ready  => out_read_ready,
      out_last   => out_read_last,
      out_dvalid => out_read_dvalid,
      out_data   => out_read_data
      );

  -----------------------------------------------------------------------------
  -- Stream Conversion
  -----------------------------------------------------------------------------
  -- Output
  str_read_elem_out <= cr_d.str_read_elem_out;

  -- Convert the stream inputs and outputs to something readable
  conv_streams_read_in(out_read_valid, out_read_dvalid, out_read_last, out_read_data, str_read_elem_in);
  conv_streams_read_out(str_read_elem_out, out_read_ready);

  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- RESULTS
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- ColumnWriter
  -----------------------------------------------------------------------------
  result_cw : ColumnWriter
    generic map (
      BUS_ADDR_WIDTH     => BUS_ADDR_WIDTH,
      BUS_LEN_WIDTH      => BUS_LEN_WIDTH,
      BUS_DATA_WIDTH     => BUS_DATA_WIDTH,
      BUS_STROBE_WIDTH   => BUS_DATA_WIDTH/8,
      BUS_BURST_STEP_LEN => BUS_BURST_STEP_LEN,
      BUS_BURST_MAX_LEN  => BUS_BURST_MAX_LEN,
      INDEX_WIDTH        => INDEX_WIDTH_RESULT,
      CFG                => "prim(32)",
      CMD_TAG_ENABLE     => true,
      CMD_TAG_WIDTH      => TAG_WIDTH_RESULT
      )
    port map (
      bus_clk   => clk,
      bus_reset => reset,
      acc_clk   => clk,
      acc_reset => reset,

      cmd_valid    => result_cmd_valid,
      cmd_ready    => result_cmd_ready,
      cmd_firstIdx => result_cmd_firstIdx,
      cmd_lastIdx  => result_cmd_lastIdx,
      cmd_ctrl     => result_cmd_ctrl,
      cmd_tag      => result_cmd_tag,

      unlock_valid => result_unlock_valid,
      unlock_ready => result_unlock_ready,
      unlock_tag   => result_unlock_tag,

      bus_wreq_valid => bus_result_wreq_valid,
      bus_wreq_ready => bus_result_wreq_ready,
      bus_wreq_addr  => bus_result_wreq_addr,
      bus_wreq_len   => bus_result_wreq_len,

      bus_wdat_valid  => bus_result_wdat_valid,
      bus_wdat_ready  => bus_result_wdat_ready,
      bus_wdat_data   => bus_result_wdat_data,
      bus_wdat_strobe => bus_result_wdat_strobe,
      bus_wdat_last   => bus_result_wdat_last,

      in_valid  => in_result_valid,
      in_ready  => in_result_ready,
      in_last   => in_result_last,
      in_dvalid => in_result_dvalid,
      in_data   => in_result_data
      );

  -----------------------------------------------------------------------------
  -- Stream Conversion
  -----------------------------------------------------------------------------
  -- Output
  str_result_elem_out <= cw_d.str_result_elem_out;

  -- Convert the stream inputs and outputs to something readable
  conv_streams_result_out(in_result_valid, in_result_dvalid, in_result_last, in_result_data, str_result_elem_out);
  conv_streams_result_in(str_result_elem_in, in_result_ready);


  ---------------------------------------------------------------------------------------------------
  --    ____        _       _       _                     _
  --   |  _ \      | |     | |     | |                   | |
  --   | |_) | __ _| |_ ___| |__   | |     ___   __ _  __| | ___ _ __
  --   |  _ < / _` | __/ __| '_ \  | |    / _ \ / _` |/ _` |/ _ \ '__|
  --   | |_) | (_| | || (__| | | | | |___| (_) | (_| | (_| |  __/ |
  --   |____/ \__,_|\__\___|_| |_| |______\___/ \__,_|\__,_|\___|_|
  ---------------------------------------------------------------------------------------------------
  r_reset_start <= cr_r.cs.reset_start;
  r_done        <= cr_r.cs.done and cw_r.cs.done;
  r_busy        <= cr_r.cs.busy;

  -- Registers
  loader_seq : process(clk) is
  begin
    if rising_edge(clk) then
      cr_r <= cr_d;

      r_control_reset <= control_reset;
      r_control_start <= control_start;
      reset_start     <= r_reset_start;

      busy <= r_busy;
      done <= r_done;

      -- Offset Buffer Addresses
      r_hapl_off_hi <= hapl_off_hi;
      r_hapl_off_lo <= hapl_off_lo;

      r_read_off_hi <= read_off_hi;
      r_read_off_lo <= read_off_lo;

      -- Data Buffer Addresses
      r_hapl_bp_hi <= hapl_bp_hi;
      r_hapl_bp_lo <= hapl_bp_lo;

      r_read_bp_hi <= read_bp_hi;
      r_read_bp_lo <= read_bp_lo;

      r_read_probs_hi <= read_probs_hi;
      r_read_probs_lo <= read_probs_lo;

      r_result_data_hi <= result_data_hi;
      r_result_data_lo <= result_data_lo;

      r_batch_offset <= batch_offset;

      -- Batch information
      r_x_len      <= x_len;
      r_y_len      <= y_len;
      r_x_size     <= x_size;
      r_x_padded   <= x_padded;
      r_y_size     <= y_size;
      r_y_padded   <= y_padded;
      r_x_bppadded <= x_bppadded;
      r_initial    <= initial;

      if control_reset = '1' then
        cu_reset(r);
        cr_r.reset_units <= '1';
      else
        r <= q;
      end if;
    end if;
  end process;

  result_write_seq : process(clk, r.wed.batches_total, result_unlock_valid) is
    variable result_count : integer range 0 to MAX_BATCHES * PE_DEPTH := 0;
  begin
    if rising_edge(clk) then
      cw_r <= cw_d;

      if result_unlock_valid = '1' then
        result_count := result_count + 1;
        if(result_count = to_integer(r.wed.batches_total) * PE_DEPTH) then
          cw_r.cs.done <= '1';
        end if;
      end if;

      -- Reset
      if reset = '1' then
        cw_r.state          <= IDLE;
        cw_r.cs.reset_start <= '0';
        cw_r.cs.busy        <= '0';
        cw_r.cs.done        <= '0';
        cw_r.result_index   <= 0;
      end if;
    end if;
  end process;

  result_write_comb : process(cw_r,
                              re,
                              str_result_elem_in,
                              control_start,
                              r_result_data_hi, r_result_data_lo,
                              result_cmd_ready,
                              result_unlock_valid, result_unlock_tag)
    variable cw_v : reg_result;
    variable o    : out_record;
  begin
    cw_v := cw_r;

    -- ColumnReader Inputs:
    cw_v.str_result_elem_in := str_result_elem_in;

    -- Default ColumnWriter input
    cw_v.str_result_elem_out.data.valid  := '0';
    cw_v.str_result_elem_out.data.dvalid := '0';
    cw_v.str_result_elem_out.data.last   := '0';
    cw_v.str_result_elem_out.data.data   := x"00000000";

    -- Disable command streams by default
    o.cmd.valid := '0';
    o.unl.ready := '0';

    -- Values buffer
    o.cmd.ctrl(BUS_ADDR_WIDTH-1 downto 0) := r_result_data_hi & r_result_data_lo;

    o.cmd.tag := (0 => '1', others => '0');

    -- Reset start is low by default.
    cw_v.cs.reset_start := '0';

    case cw_r.state is
      when IDLE =>
        re.outfifo.c.rd_en <= '0';
        if control_start = '1' then
          cw_v.cs.reset_start := '1';
          cw_v.state          := COLUMNWRITE;
          cw_v.cs.busy        := '1';
        end if;

      when COLUMNWRITE =>
        -- Write in case of valid output FIFO data
        if re.outfifo.c.empty = '0' then
          re.outfifo.c.rd_en <= '1';

          cw_v.str_result_elem_out.data.valid  := '1';
          cw_v.str_result_elem_out.data.dvalid := '1';
          cw_v.str_result_elem_out.data.last   := '1';
          cw_v.str_result_elem_out.data.data   := re.outfifo.dout;

          o.cmd.firstIdx := slvec(cw_v.result_index, VALUES_WIDTH_RESULT);
          o.cmd.lastIdx  := slvec(cw_v.result_index + 1, VALUES_WIDTH_RESULT);

          cw_v.result_index := cw_r.result_index + 1;

          cw_v.state := WAIT_ACCEPT;
        end if;

      when WAIT_ACCEPT =>
        re.outfifo.c.rd_en <= '0';

        if result_cmd_ready = '1' then
          o.cmd.valid := '1';
          -- Command is accepted, wait for unlock.
          cw_v.state  := UNLOCK;
        end if;

      when UNLOCK =>
        o.unl.ready := '1';
        if result_unlock_valid = '1' then
          cw_v.state   := COLUMNWRITE;
          cw_v.cs.busy := '0';
        end if;
    end case;

    -- Registered outputs
    cw_d <= cw_v;

    -- Combinatorial outputs
    result_cmd_valid    <= o.cmd.valid;
    result_cmd_firstIdx <= o.cmd.firstIdx;
    result_cmd_lastIdx  <= o.cmd.lastIdx;
    result_cmd_ctrl     <= o.cmd.ctrl;
    result_cmd_tag      <= o.cmd.tag;

    result_unlock_ready <= o.unl.ready;

  end process;

  loader_comb : process(r,
                        rs.state,
                        cr_r,
                        r_control_start,
                        r_control_reset,
                        cmd_hapl_ready,
                        cmd_read_ready,
                        str_hapl_elem_in,
                        str_read_elem_in,
                        r_hapl_off_hi, r_hapl_off_lo,
                        r_read_off_hi, r_read_off_lo,
                        r_hapl_bp_hi, r_hapl_bp_lo,
                        r_read_bp_hi, r_read_bp_lo,
                        r_read_probs_hi, r_read_probs_lo)
    variable v    : cu_int;
    variable cr_v : reg;
  begin
    cr_v := cr_r;

    -- ColumnReader Inputs:
    cr_v.command_hapl.ready := cmd_hapl_ready;
    cr_v.command_read.ready := cmd_read_ready;

    cr_v.str_hapl_elem_in := str_hapl_elem_in;
    cr_v.str_read_elem_in := str_read_elem_in;

    -- Default outputs:
    cr_v.command_hapl.valid := '0';
    cr_v.command_read.valid := '0';

    cr_v.str_hapl_elem_out.len.ready  := '0';
    cr_v.str_hapl_elem_out.utf8.ready := '0';

    cr_v.str_read_elem_out.len.ready  := '0';
    cr_v.str_read_elem_out.data.ready := '0';

    --------------------------------------------------------------------------------------------------- default assignments
    v := r;

    v.read_wren := "0";
    v.hapl_wren := "0";
    v.prob_wren := '0';
    --------------------------------------------------------------------------------------------------- state machine
    case r.state is

      when LOAD_IDLE =>
        cr_v.cs.done        := '0';
        cr_v.cs.busy        := '0';
        cr_v.cs.reset_start := '0';

        cr_v.reset_units := '1';

        -- When start signal is received:
        if r_control_start = '1' then
          v.state             := LOAD_RESET_START;
          cr_v.cs.reset_start := '1';
        end if;

      when LOAD_RESET_START =>
        cr_v.cs.done := '0';
        cr_v.cs.busy := '1';

        cr_v.reset_units := '0';

        if r_control_start = '0' then
          v.state := LOAD_LOAD_INIT;
        end if;

      -- State to register the initial values of the first row of D
      when LOAD_LOAD_INIT =>
        v.initial := r_initial;

        v.wed.batches_total := to_unsigned(2, 32);  -- TODO make this variable
        v.wed.batches       := to_unsigned(2, 32);  -- TODO make this variable
        v.inits.x_len       := u(r_x_len);
        v.inits.y_len       := u(r_y_len);
        v.inits.x_size      := u(r_x_size);
        v.inits.x_padded    := u(r_x_padded);
        v.inits.y_size      := u(r_y_size);
        v.inits.y_padded    := u(r_y_padded);
        v.inits.x_bppadded  := u(r_x_bppadded);

        v.state := LOAD_REQUEST_DATA;

      -- Request all data
      when LOAD_REQUEST_DATA =>
        -- Reset all counters etc...
        v.x_reads := (others => '0');
        v.y_reads := (others => '0');
        v.p_reads := (others => '0');
        v.filled  := '0';

        -- ColumnReader
        cr_v.cs.done        := '0';
        cr_v.cs.busy        := '1';
        cr_v.cs.reset_start := '0';
        cr_v.reset_units    := '0';

        -- Haplotypes
        -- First four argument registers are buffer addresses
        -- MSBs are index buffer address
        cr_v.command_hapl.ctrl(127 downto 96) := r_hapl_off_hi;
        cr_v.command_hapl.ctrl(95 downto 64)  := r_hapl_off_lo;
        -- LSBs are data buffer address
        cr_v.command_hapl.ctrl(63 downto 32)  := r_hapl_bp_hi;
        cr_v.command_hapl.ctrl(31 downto 0)   := r_hapl_bp_lo;

        -- Reads Buffer Addresses
        cr_v.command_read.ctrl(191 downto 160) := r_read_off_hi;
        cr_v.command_read.ctrl(159 downto 128) := r_read_off_lo;

        cr_v.command_read.ctrl(127 downto 96) := r_read_bp_hi;
        cr_v.command_read.ctrl(95 downto 64)  := r_read_bp_lo;

        cr_v.command_read.ctrl(63 downto 32) := r_read_probs_hi;
        cr_v.command_read.ctrl(31 downto 0)  := r_read_probs_lo;

        -- First and Last index for haplotypes and reads
        cr_v.command_hapl.firstIdx := slvec(idx(r_batch_offset) + idx(r.wed.batches) - 1, INDEX_WIDTH_HAPL);
        cr_v.command_hapl.lastIdx  := slvec(idx(r_batch_offset) + idx(r.wed.batches), INDEX_WIDTH_HAPL);

        cr_v.command_read.firstIdx := slvec(idx(r_batch_offset) + idx(r.wed.batches) - 1, INDEX_WIDTH_READ);
        cr_v.command_read.lastIdx  := slvec(idx(r_batch_offset) + idx(r.wed.batches), INDEX_WIDTH_READ);

        -- Make command valid
        cr_v.command_hapl.valid := '1';
        cr_v.command_read.valid := '1';

        -- Wait for command accepted
        if cr_r.command_hapl.ready = '1' and cr_r.command_read.ready = '1' then
          -- dumpStdOut("Requested haplotype arrays: " & integer'image(int(cr_r.command_hapl.firstIdx)) & " ... " & integer'image(int(cr_v.command_hapl.lastIdx)));
          -- dumpStdOut("Requested read arrays: " & integer'image(int(cr_r.command_read.firstIdx)) & " ... " & integer'image(int(cr_v.command_read.lastIdx)));

          v.state := LOAD_LOADX_LOADY;  -- Load reads and haplotypes
        end if;

      -- Load the values for the read X, Load the values for the haplotype Y, State to stream in the probabilities
      when LOAD_LOADX_LOADY =>
        cr_v.cs.done        := '0';
        cr_v.cs.busy        := '1';
        cr_v.cs.reset_start := '0';
        cr_v.reset_units    := '0';

        -- Always ready to receive length
        cr_v.str_hapl_elem_out.len.ready := '1';
        cr_v.str_read_elem_out.len.ready := '1';

        -- Always ready to receive utf8 char (haplo basepair)
        cr_v.str_hapl_elem_out.utf8.ready := '1';

        -- Always ready to receive utf8 char (read basepair)
        cr_v.str_read_elem_out.data.ready := '1';

        -- Store the bases of the haplotype in the RAM
        if r.y_reads /= r.inits.y_padded + r.inits.y_len - 1 and cr_r.str_hapl_elem_in.utf8.valid = '1' then
          v.y_reads   := r.y_reads + 1;
          v.hapl_wren := "1";
          v.hapl_data := cr_r.str_hapl_elem_in.utf8.data(7 downto 0);
        else
          v.y_reads   := r.y_reads;
          v.hapl_wren := "0";
          v.hapl_data := (others => '1');
        end if;

        -- Store the bases of the read in the RAM
        if r.x_reads /= r.inits.x_padded + r.inits.x_len - 1 and cr_r.str_read_elem_in.data.valid = '1' then
          v.x_reads   := r.x_reads + 1;
          v.read_wren := "1";
          v.read_data := cr_r.str_read_elem_in.data.bp(7 downto 0);
        else
          v.x_reads   := r.x_reads;
          v.read_wren := "0";
          v.read_data := (others => '1');
        end if;

        -- Store the probabilities of the read in the RAM
        -- Probabilities load:
        -- Enable FIFO read if read is valid:
        if r.p_reads /= r.inits.x_padded + r.inits.x_len - 1 and cr_r.str_read_elem_in.data.valid = '1' then
          v.p_reads   := r.p_reads + 1;
          v.prob_wren := '1';

          v.prob_data := cr_r.str_read_elem_in.data.prob.eta
                         & cr_r.str_read_elem_in.data.prob.zeta
                         & cr_r.str_read_elem_in.data.prob.epsilon
                         & cr_r.str_read_elem_in.data.prob.delta
                         & cr_r.str_read_elem_in.data.prob.beta
                         & cr_r.str_read_elem_in.data.prob.alpha
                         & cr_r.str_read_elem_in.data.prob.distm_diff
                         & cr_r.str_read_elem_in.data.prob.distm_simi;
        end if;

        -- If all (padded) bases of all reads and haplotypes are completely loaded,
        -- and if we have loaded all the (padded) probabilities of the batch into the FIFO's
        -- go to the next state to load the next batch information
        if r.x_reads = r.inits.x_padded + r.inits.x_len - 1 and r.y_reads = r.inits.y_padded + r.inits.y_len - 1 and r.p_reads = r.inits.x_padded + r.inits.x_len - 1 then
          v.wed.batches := r.wed.batches - 1;
          v.p_reads     := (others => '0');
          v.state       := LOAD_LOADNEXTINIT;
        end if;

        -- Copy the initials into the scheduler registers to make room for the new inits.
        v.sched := v.inits;

      -- Load next batch information
      when LOAD_LOADNEXTINIT =>
        v.initial := r_initial;

        v.inits.x_size     := u(r_x_size);
        v.inits.x_padded   := u(r_x_padded);
        v.inits.y_size     := u(r_y_size);
        v.inits.y_padded   := u(r_y_padded);
        v.inits.x_bppadded := u(r_x_bppadded);

        v.state := LOAD_LAUNCH;

      -- A new batch is ready to be started
      when LOAD_LAUNCH =>
        -- If we told the scheduler to start a new batch
        if r.filled = '1' then
          -- And it's not idle anymore, it's busy with the new batch
          if rs.state /= SCHED_IDLE then
            -- We can reset the filled bit to 0.
            v.filled := '0';
            -- If there is still work to do:
            if v.wed.batches /= 0 then
              -- We can start loading a new batch
              v.state := LOAD_REQUEST_DATA;
            else
              v.state := LOAD_DONE;
            end if;
          end if;
        end if;

        -- If the scheduler is idle
        if rs.state = SCHED_IDLE and v.state /= LOAD_DONE then
          -- We can signal the scheduler to start processing:
          v.filled := '1';
        end if;

      -- State where we wait for the scheduler to stop
      when LOAD_DONE =>
        if rs.state = SCHED_IDLE then
          cr_v.cs.done        := '1';
          cr_v.cs.busy        := '0';
          cr_v.cs.reset_start := '0';
          cr_v.reset_units    := '0';

          if r_control_reset = '1' or r_control_start = '1' then
            v.state := LOAD_IDLE;
          end if;
        end if;

      when others => null;
    end case;

    --------------------------------------------------------------------------------------------------- outputs
    -- drive input registers
    q    <= v;
    cr_d <= cr_v;
  end process;


  --  ____                           ______   _____   ______    ____
  -- |  _ \                         |  ____| |_   _| |  ____|  / __ \
  -- | |_) |   __ _   ___    ___    | |__      | |   | |__    | |  | |  ___
  -- |  _ <   / _` | / __|  / _ \   |  __|     | |   |  __|   | |  | | / __|
  -- | |_) | | (_| | \__ \ |  __/   | |       _| |_  | |      | |__| | \__ \
  -- |____/   \__,_| |___/  \___|   |_|      |_____| |_|       \____/  |___/

  -- Read shift register
  process(re, rs, read_delay_count, read_delay_rst)
  begin
    read_delay_valid <= '0';
    if(read_delay_count > PE_DEPTH-1) then
      read_delay_valid <= '1';
    end if;

    if(rising_edge(re.clk_kernel)) then
      re.readfifo.c.rd_en1 <= re.readfifo.c.rd_en;

      if re.readfifo.c.valid = '1' then
        for K in 1 to PE_DEPTH - 1 loop
          readdelay(K) <= readdelay(K - 1);
        end loop;
        readdelay(0) <= slv3bp(re.readfifo.dout);

        read_delay_count <= read_delay_count + 1;
      end if;

      re.readfifo.c.rd_en <= '0';
      if(re.readfifo.c.empty = '0') then
        if re.readfifo.c.valid = '1' then
          if read_delay_count > PE_DEPTH-3 then
            if rs.shift_read_buffer = '1' then
              re.readfifo.c.rd_en <= '1';
            end if;
          else
            re.readfifo.c.rd_en <= '1';
          end if;
        else
          if re.readfifo.c.rd_en = '1' then
            if read_delay_count > PE_DEPTH-3 then
              if rs.shift_read_buffer = '1' then
                re.readfifo.c.rd_en <= '1';
              end if;
            end if;
          elsif re.readfifo.c.rd_en1 = '1' then
            if read_delay_count > PE_DEPTH-2 then
              if rs.shift_read_buffer = '1' then
                re.readfifo.c.rd_en <= '1';
              end if;
            end if;
          else
            if read_delay_count > PE_DEPTH-1 then
              if rs.shift_read_buffer = '1' then
                re.readfifo.c.rd_en <= '1';
              end if;
            else
              re.readfifo.c.rd_en <= '1';
            end if;
          end if;
        end if;
      end if;

      if(read_delay_rst = '1') then
        read_delay_count <= 0;
      end if;
    end if;
  end process;

  -- Prob shift register
  process(re, r, rs, prob_delay_count, prob_delay_rst)
  begin
    prob_delay_valid <= '0';
    if(prob_delay_count > PE_DEPTH-1) then
      prob_delay_valid <= '1';
    end if;

    if(rising_edge(re.clk_kernel)) then
      re.probfifo.c.rd_en1 <= re.probfifo.c.rd_en;

      if re.probfifo.c.valid = '1' then
        for K in 1 to PE_DEPTH - 1 loop
          probdelay(K) <= probdelay(K - 1);
        end loop;
        probdelay(0) <= re.probfifo.dout(PAIRHMM_BITS_PER_PROB - 1 downto 0);

        prob_delay_count <= prob_delay_count + 1;
      end if;

      re.probfifo.c.rd_en <= '0';
      if(re.probfifo.c.empty = '0') then
        if re.probfifo.c.valid = '1' then
          if prob_delay_count > PE_DEPTH-3 then
            if rs.shift_prob_buffer = '1' then
              re.probfifo.c.rd_en <= '1';
            end if;
          else
            re.probfifo.c.rd_en <= '1';
          end if;
        else
          if re.probfifo.c.rd_en = '1' then
            if prob_delay_count > PE_DEPTH-3 then
              if rs.shift_prob_buffer = '1' then
                re.probfifo.c.rd_en <= '1';
              end if;
            end if;
          elsif re.probfifo.c.rd_en1 = '1' then
            if prob_delay_count > PE_DEPTH-2 then
              if rs.shift_prob_buffer = '1' then
                re.probfifo.c.rd_en <= '1';
              end if;
            end if;
          else
            if prob_delay_count > PE_DEPTH-1 then
              if rs.shift_prob_buffer = '1' then
                re.probfifo.c.rd_en <= '1';
              end if;
            else
              re.probfifo.c.rd_en <= '1';
            end if;
          end if;
        end if;
      end if;

      if(prob_delay_rst = '1') then
        prob_delay_count <= 0;
      end if;
    end if;
  end process;

  -- Haplotype shift register
  process(re, rs, hapl_delay_count, hapl_delay_rst)
  begin
    hapl_delay_valid <= '0';
    if(hapl_delay_count > PE_DEPTH-1) then
      hapl_delay_valid <= '1';
    end if;

    if(rising_edge(re.clk_kernel)) then
      re.haplfifo.c.rd_en1 <= re.haplfifo.c.rd_en;

      if re.haplfifo.c.valid = '1' then
        for K in 1 to PE_DEPTH - 1 loop
          hapldelay(K) <= hapldelay(K - 1);
        end loop;
        hapldelay(0) <= slv3bp(re.haplfifo.dout);

        hapl_delay_count <= hapl_delay_count + 1;
      end if;

      re.haplfifo.c.rd_en <= '0';
      if(re.haplfifo.c.empty = '0') then
        if re.haplfifo.c.valid = '1' then
          if hapl_delay_count > PE_DEPTH-3 then
            if rs.shift_hapl_buffer = '1' then
              re.haplfifo.c.rd_en <= '1';
            end if;
          else
            re.haplfifo.c.rd_en <= '1';
          end if;
        else
          if re.haplfifo.c.rd_en = '1' then
            if hapl_delay_count > PE_DEPTH-3 then
              if rs.shift_hapl_buffer = '1' then
                re.haplfifo.c.rd_en <= '1';
              end if;
            end if;
          elsif re.haplfifo.c.rd_en1 = '1' then
            if hapl_delay_count > PE_DEPTH-2 then
              if rs.shift_hapl_buffer = '1' then
                re.haplfifo.c.rd_en <= '1';
              end if;
            end if;
          else
            if hapl_delay_count > PE_DEPTH-1 then
              if rs.shift_hapl_buffer = '1' then
                re.haplfifo.c.rd_en <= '1';
              end if;
            else
              re.haplfifo.c.rd_en <= '1';
            end if;
          end if;
        end if;
      end if;

      if(hapl_delay_rst = '1') then
        hapl_delay_count <= 0;
      end if;
    end if;
  end process;

  read_fifo : base_fifo port map (
    rst       => reset,
    wr_clk    => clk,
    rd_clk    => re.clk_kernel,
    din       => slv8bpslv3(r.read_data(7 downto 0)),
    dout      => re.readfifo.dout,
    wr_en     => re.readfifo.c.wr_en,
    rd_en     => re.readfifo.c.rd_en,
    full      => re.readfifo.c.full,
    wr_ack    => re.readfifo.c.wr_ack,
    overflow  => re.readfifo.c.overflow,
    empty     => re.readfifo.c.empty,
    valid     => re.readfifo.c.valid,
    underflow => re.readfifo.c.underflow
    );
  re.readfifo.c.wr_en <= r.read_wren(0);

  prob_fifo_inst : prob_fifo port map (
    rst       => reset,
    wr_clk    => clk,
    rd_clk    => re.clk_kernel,
    din       => r.prob_data(PAIRHMM_BITS_PER_PROB - 1 downto 0),
    dout      => re.probfifo.dout,
    wr_en     => re.probfifo.c.wr_en,
    rd_en     => re.probfifo.c.rd_en,
    full      => re.probfifo.c.full,
    wr_ack    => re.probfifo.c.wr_ack,
    overflow  => re.probfifo.c.overflow,
    empty     => re.probfifo.c.empty,
    valid     => re.probfifo.c.valid,
    underflow => re.probfifo.c.underflow
    );
  re.probfifo.c.wr_en <= r.prob_wren;

  hapl_fifo : base_fifo port map (
    rst       => reset,
    wr_clk    => clk,
    rd_clk    => re.clk_kernel,
    din       => slv8bpslv3(r.hapl_data(7 downto 0)),
    dout      => re.haplfifo.dout,
    wr_en     => re.haplfifo.c.wr_en,
    rd_en     => re.haplfifo.c.rd_en,
    full      => re.haplfifo.c.full,
    wr_ack    => re.haplfifo.c.wr_ack,
    overflow  => re.haplfifo.c.overflow,
    empty     => re.haplfifo.c.empty,
    valid     => re.haplfifo.c.valid,
    underflow => re.haplfifo.c.underflow
    );
  re.haplfifo.c.wr_en <= r.hapl_wren(0);

  ---------------------------------------------------------------------------------------------------
  --   _____   _                  _
  --  / ____| | |                | |
  -- | |      | |   ___     ___  | | __
  -- | |      | |  / _ \   / __| | |/ /
  -- | |____  | | | (_) | | (__  |   <
  --  \_____| |_|  \___/   \___| |_|\_\
  ---------------------------------------------------------------------------------------------------
  -- In case the kernel has to run slower due to timing constraints not being met, use this to lower the clock frequency
  kernel_clock_gen : psl_to_kernel port map (
    clk_psl    => clk,
    clk_kernel => re.clk_kernel
    );

  -- Use this to keep everything in the same clock domain:
  -- re.clk_kernel <= clk;

  ---------------------------------------------------------------------------------------------------
  --     _____           _        _ _
  --    / ____|         | |      | (_)          /\
  --   | (___  _   _ ___| |_ ___ | |_  ___     /  \   _ __ _ __ __ _ _   _
  --    \___ \| | | / __| __/ _ \| | |/ __|   / /\ \ | '__| '__/ _` | | | |
  --    ____) | |_| \__ \ || (_) | | | (__   / ____ \| |  | | | (_| | |_| |
  --   |_____/ \__, |___/\__\___/|_|_|\___| /_/    \_\_|  |_|  \__,_|\__, |
  --            __/ |                                                 __/ |
  --           |___/                                                 |___/
  ---------------------------------------------------------------------------------------------------
  -- Connect clock and reset
  re.pairhmm_cr <= (clk => re.clk_kernel,
                    rst => rs.pairhmm_rst
                    );

  -- Input for the first PE
  re.pairhmm.i.first <= rs.pe_first;

  -- Base X for the first PE must come from the read RAM or it must come from the feedback FIFO with a latency of 1
  process(re, rs)
  begin
    if(rs.feedback_rd_en1 = '0') then
      if(rs.ybus_addr1 < rs.leny) then
        read_delay <= readdelay(PE_DEPTH - 1 - int(rs.core_schedule));
      else
        read_delay <= BP_STOP;
      end if;
    else
      read_delay <= rs.pe_first.x;
    end if;
  end process;

  re.pairhmm.i.x         <= read_delay;
  re.pairhmm.i.ybus.data <= ybus_data_delay;

  -- Schedule
  re.pairhmm.i.schedule <= rs.core_schedule;

  -- Address for Y bus
  re.pairhmm.i.ybus.addr <= rs.ybus_addr1;
  re.pairhmm.i.ybus.wren <= rs.ybus_en1;

  -- Data for Y bus
  ybus_data_sel : for J in 0 to PE_DEPTH - 1 generate
    ybus_data_delay(J) <= hapldelay(PE_DEPTH - J - 1) when rs.ybus_addr1 < rs.leny else BP_STOP;
  end generate;

  -- Core instantiation
  pairhmm_core : entity work.pairhmm port map (
    cr => re.pairhmm_cr,
    i  => re.pairhmm.i,
    o  => re.pairhmm.o
    );

  ---------------------------------------------------------------------------------------------------
  --  _____                           _
  -- |_   _|                         | |
  --  | |    _ __    _ __    _   _  | |_
  --  | |   | '_ \  | '_ \  | | | | | __|
  -- _| |_  | | | | | |_) | | |_| | | |_
  -- |_____| |_| |_| | .__/   \__,_|  \__|
  --                | |
  --                |_|
  ---------------------------------------------------------------------------------------------------
  -- Connect PAIRHMM inputs
  re.pairhmm_in.en    <= '1';
  re.pairhmm_in.valid <= rs.valid;
  re.pairhmm_in.cell  <= rs.cell;



-- POSIT EXTRACTION
gen_posit_extract_raw_es3 : if POSIT_ES = 3 generate

    -- Set top left input to 1.0 when this is the first cycle of this pair.
    -- Initial input for first PE
    -- extract_initial_es3 : posit_extract_raw_es3 port map (
    --   in1  => r.initial,
    --   absolute => open,
    --   result => re.pairhmm_in.mids.dtl
    --   );
      -- Select initial value to travel with systolic array
      re.pairhmm_in.initial <= value_empty;-- re.pairhmm_in.mids.dtl;

    re.pairhmm_in.mids.itl <= value_empty;
    re.pairhmm_in.mids.mtl <= value_empty;
    re.pairhmm_in.mids.ml  <= value_empty;
    re.pairhmm_in.mids.il  <= value_empty;
    re.pairhmm_in.mids.dl  <= value_empty;
    re.pairhmm_in.mids.mt  <= value_empty;
    re.pairhmm_in.mids.it  <= value_empty;
    re.pairhmm_in.mids.dt  <= value_empty;

--   extract_distm_simi_es3 : posit_extract_raw_es3 port map (
--     in1  => probdelay(int(PE_DEPTH - 1 - rs.schedule))(31 downto 0),
--     absolute => open,
--     result => re.pairhmm_in.emis.distm_simi
--     );
--   extract_distm_diff_es3 : posit_extract_raw_es3 port map (
--     in1  => probdelay(int(PE_DEPTH - 1 - rs.schedule))(63 downto 32),
--     absolute => open,
--     result => re.pairhmm_in.emis.distm_diff
--     );
--   extract_alpha_es3 : posit_extract_raw_es3 port map (
--     in1  => probdelay(int(PE_DEPTH - 1 - rs.schedule))(95 downto 64),
--     absolute => open,
--     result => re.pairhmm_in.tmis.alpha
--     );
--   extract_beta_es3 : posit_extract_raw_es3 port map (
--     in1  => probdelay(int(PE_DEPTH - 1 - rs.schedule))(127 downto 96),
--     absolute => open,
--     result => re.pairhmm_in.tmis.beta
--     );
--   extract_delta_es3 : posit_extract_raw_es3 port map (
--     in1  => probdelay(int(PE_DEPTH - 1 - rs.schedule))(159 downto 128),
--     absolute => open,
--     result => re.pairhmm_in.tmis.delta
--     );
--   extract_epsilon_es3 : posit_extract_raw_es3 port map (
--     in1  => probdelay(int(PE_DEPTH - 1 - rs.schedule))(191 downto 160),
--     absolute => open,
--     result => re.pairhmm_in.tmis.epsilon
--     );
--   extract_zeta_es3 : posit_extract_raw_es3 port map (
--     in1  => probdelay(int(PE_DEPTH - 1 - rs.schedule))(223 downto 192),
--     absolute => open,
--     result => re.pairhmm_in.tmis.zeta
--     );
--   extract_eta_es3 : posit_extract_raw_es3 port map (
--     in1  => probdelay(int(PE_DEPTH - 1 - rs.schedule))(255 downto 224),
--     absolute => open,
--     result => re.pairhmm_in.tmis.eta
--     );
end generate;

  process(probdelay, rs.schedule)
  begin
    re.pairhmm_in.emis.distm_simi <= value_empty;--probdelay(int(PE_DEPTH - 1 - rs.schedule))(31 downto 0);
    re.pairhmm_in.emis.distm_diff <= value_empty;--probdelay(int(PE_DEPTH - 1 - rs.schedule))(63 downto 32);
    re.pairhmm_in.tmis.alpha      <= value_empty;--probdelay(int(PE_DEPTH - 1 - rs.schedule))(95 downto 64);
    re.pairhmm_in.tmis.beta       <= value_empty;--probdelay(int(PE_DEPTH - 1 - rs.schedule))(127 downto 96);
    re.pairhmm_in.tmis.delta      <= value_empty;--probdelay(int(PE_DEPTH - 1 - rs.schedule))(159 downto 128);
    re.pairhmm_in.tmis.epsilon    <= value_empty;--probdelay(int(PE_DEPTH - 1 - rs.schedule))(191 downto 160);
    re.pairhmm_in.tmis.zeta       <= value_empty;--probdelay(int(PE_DEPTH - 1 - rs.schedule))(223 downto 192);
    re.pairhmm_in.tmis.eta        <= value_empty;--probdelay(int(PE_DEPTH - 1 - rs.schedule))(255 downto 224);
  end process;

  ---------------------------------------------------------------------------------------------------
  --   ____            _                     _
  --  / __ \          | |                   | |
  -- | |  | |  _   _  | |_   _ __    _   _  | |_
  -- | |  | | | | | | | __| | '_ \  | | | | | __|
  -- | |__| | | |_| | | |_  | |_) | | |_| | | |_
  --  \____/   \__,_|  \__| | .__/   \__,_|  \__|
  --                        | |
  --                        |_|
  ---------------------------------------------------------------------------------------------------
  re.outfifo.din(31 downto 0) <= re.pairhmm.o.score;
  re.outfifo.c.wr_en          <= re.pairhmm.o.score_valid;

  outfifo : output_fifo
    port map (
      wr_clk => re.clk_kernel,
      rd_clk => clk,
      din    => re.outfifo.din,
      wr_en  => re.outfifo.c.wr_en,
      rd_en  => re.outfifo.c.rd_en,

      dout      => re.outfifo.dout,
      full      => re.outfifo.c.full,
      wr_ack    => re.outfifo.c.wr_ack,
      overflow  => re.outfifo.c.overflow,
      empty     => re.outfifo.c.empty,
      valid     => re.outfifo.c.valid,
      underflow => re.outfifo.c.underflow
      );

  ---------------------------------------------------------------------------------------------------
  --  ______                  _   _                      _
  -- |  ____|                | | | |                    | |
  -- | |__   ___    ___    __| | | |__     __ _    ___  | | __
  -- |  __| / _ \  / _ \  / _` | | '_ \   / _` |  / __| | |/ /
  -- | |   |  __/ |  __/ | (_| | | |_) | | (_| | | (__  |   <
  -- |_|    \___|  \___|  \__,_| |_.__/   \__,_|  \___| |_|\_\
  ---------------------------------------------------------------------------------------------------
  -- Output data that is written back to the memory, goes into the fifo first
  gen_fb_in_es3 : if POSIT_ES = 3 generate
    re.fbfifo.din(37 downto 0)    <= re.pairhmm.o.last.mids.ml;
    re.fbfifo.din(113 downto 76)  <= re.pairhmm.o.last.mids.dl;
    re.fbfifo.din(151 downto 114) <= re.pairhmm.o.last.emis.distm_simi;
    re.fbfifo.din(189 downto 152) <= re.pairhmm.o.last.emis.distm_diff;
    re.fbfifo.din(227 downto 190) <= re.pairhmm.o.last.tmis.alpha;
    re.fbfifo.din(265 downto 228) <= re.pairhmm.o.last.tmis.beta;
    re.fbfifo.din(303 downto 266) <= re.pairhmm.o.last.tmis.delta;
    re.fbfifo.din(341 downto 304) <= re.pairhmm.o.last.tmis.epsilon;
    re.fbfifo.din(379 downto 342) <= re.pairhmm.o.last.tmis.zeta;
    re.fbfifo.din(417 downto 380) <= re.pairhmm.o.last.tmis.eta;
    re.fbfifo.din(420 downto 418) <= bpslv3(re.pairhmm.o.last.x);
    re.fbfifo.din(458 downto 421) <= re.pairhmm.o.last.initial;

    -- latency of 1 to match delay of read and hapl rams
    re.fbfifo.c.rd_en <= rs.feedback_rd_en;
    re.fbfifo.c.wr_en <= rs.feedback_wr_en and re.pairhmm.o.last.valid;

    fbfifo : feedback_fifo_es3 port map (
      din       => re.fbfifo.din,
      dout      => re.fbfifo.dout,
      clk       => re.clk_kernel,
      srst      => re.fbfifo.c.rst,
      wr_en     => re.fbfifo.c.wr_en,
      rd_en     => re.fbfifo.c.rd_en,
      wr_ack    => re.fbfifo.c.wr_ack,
      valid     => re.fbfifo.c.valid,
      full      => re.fbfifo.c.full,
      empty     => re.fbfifo.c.empty,
      overflow  => re.fbfifo.c.overflow,
      underflow => re.fbfifo.c.underflow
      );

    re.fbfifo.c.rst <= rs.feedback_rst;

    -- Set top left input to 1.0 when this is the first cycle of this pair.
    -- with rs.cycle select
    re.fbpairhmm.mids.mtl <= value_one when rs.cycle = CYCLE_ZERO else value_empty;  --X"40000000" when CYCLE_ZERO,
                                                --  value_empty when others;  --X"00000000" when others;


    re.fbpairhmm.mids.itl <= value_es3_empty;
    re.fbpairhmm.mids.dtl <= value_es3_empty;
    re.fbpairhmm.mids.mt  <= value_es3_empty;
    re.fbpairhmm.mids.it  <= value_es3_empty;
    re.fbpairhmm.mids.dt  <= value_es3_empty;

    re.fbpairhmm.mids.ml         <= re.fbfifo.dout(37 downto 0);
    re.fbpairhmm.mids.il         <= re.fbfifo.dout(75 downto 38);
    re.fbpairhmm.mids.dl         <= re.fbfifo.dout(113 downto 76);
    re.fbpairhmm.emis.distm_simi <= re.fbfifo.dout(151 downto 114);
    re.fbpairhmm.emis.distm_diff <= re.fbfifo.dout(189 downto 152);
    re.fbpairhmm.tmis.alpha      <= re.fbfifo.dout(227 downto 190);
    re.fbpairhmm.tmis.beta       <= re.fbfifo.dout(265 downto 228);
    re.fbpairhmm.tmis.delta      <= re.fbfifo.dout(303 downto 266);
    re.fbpairhmm.tmis.epsilon    <= re.fbfifo.dout(341 downto 304);
    re.fbpairhmm.tmis.zeta       <= re.fbfifo.dout(379 downto 342);
    re.fbpairhmm.tmis.eta        <= re.fbfifo.dout(417 downto 380);
    re.fbpairhmm.x               <= slv3bp(re.fbfifo.dout(420 downto 418));
    re.fbpairhmm.initial         <= re.fbfifo.dout(458 downto 421);
  end generate;

  re.fbpairhmm.en    <= '1';
  re.fbpairhmm.valid <= rs.valid;
  re.fbpairhmm.cell  <= rs.cell;


  ---------------------------------------------------------------------------------------------------
  --     _____      _              _       _
  --    / ____|    | |            | |     | |
  --   | (___   ___| |__   ___  __| |_   _| | ___ _ __
  --    \___ \ / __| '_ \ / _ \/ _` | | | | |/ _ \ '__|
  --    ____) | (__| | | |  __/ (_| | |_| | |  __/ |
  --   |_____/ \___|_| |_|\___|\__,_|\__,_|_|\___|_|
  ---------------------------------------------------------------------------------------------------
  -- This implements a round-robin scheduler to fill pipeline stage n with the output of FIFO n
  ---------------------------------------------------------------------------------------------------

  scheduler_comb : process(r, re, rs, read_delay_valid)
    variable vs : cu_sched;
  begin
--------------------------------------------------------------------------------------------------- default assignments
    vs := rs;

    vs.ybus_en := '0';

    vs.shift_read_buffer := '0';
    vs.shift_prob_buffer := '0';
    vs.shift_hapl_buffer := '0';

    -- Select the proper input, also correct for latency of 1 of the hapl and read RAMs:
    if rs.feedback_rd_en = '0' then
      vs.pe_first := re.pairhmm_in;
    else
      vs.pe_first := re.fbpairhmm;
    end if;

    -- Control signals that also need a latency of 1 for this reason:
    vs.ybus_addr1      := rs.ybus_addr;
    vs.core_schedule   := rs.schedule;
    vs.feedback_rd_en1 := rs.feedback_rd_en;
    vs.ybus_en1        := rs.ybus_en;

--------------------------------------------------------------------------------------------------- round robin schedule
    -- Schedule is always running, this is to keep the PairHMM core running even when the scheduler
    -- itself is idle. This allows the scheduler to start a new batch while there is still an old
    -- batch somewhere in the Systolic Array

    -- Go to next pair
    vs.schedule := rs.schedule + 1;

    -- Wrap around (required when log2(PE_DEPTH) is not an integer
    if vs.schedule = PE_DEPTH then
      vs.schedule := (others => '0');
    end if;

    read_delay_rst <= '0';
    hapl_delay_rst <= '0';
    prob_delay_rst <= '0';

--------------------------------------------------------------------------------------------------- state machine
    case rs.state is
      when SCHED_IDLE =>
        -- Gather the sizes, bases and initial D row value from the other clock domain
        vs.leny  := r.sched.y_len(log2e(PAIRHMM_MAX_SIZE) downto 0);
        vs.sizey := r.sched.y_size(log2e(PAIRHMM_MAX_SIZE) downto 0);

        vs.lenx   := r.sched.x_len(log2e(PAIRHMM_MAX_SIZE) downto 0);
        vs.sizex  := r.sched.x_size(log2e(PAIRHMM_MAX_SIZE) downto 0);
        vs.sizexp := r.sched.x_padded(log2e(PAIRHMM_MAX_SIZE) downto 0);

        vs.cycle       := (others => '0');
        vs.basepair    := (others => '0');
        vs.element     := (others => '0');
        vs.supercolumn := (others => '0');

        vs.valid := '0';
        vs.cell  := PE_NORMAL;

        vs.ybus_addr := (others => '0');

        vs.feedback_rd_en := '0';
        vs.feedback_wr_en := '0';
        vs.feedback_rst   := '1';

        vs.shift_read_buffer := '0';
        vs.shift_prob_buffer := '0';
        vs.shift_hapl_buffer := '0';

        -- Start everything when the FIFO's are filled and align with the scheduler
        -- Starting up takes two cycles, thus we wait until the scheduler is at PE_DEPTH - 2.
        if r.filled = '1' and rs.schedule = PE_DEPTH - 2 and read_delay_valid = '1' then
          vs.state        := SCHED_STARTUP;
          vs.feedback_rst := '0';
          vs.pairhmm_rst  := '0';
        end if;

      when SCHED_STARTUP =>
        vs.state     := SCHED_PROCESSING;  -- Go to processing state
        vs.valid     := '1';            -- Enable data valid on the next cycle
        vs.cell      := PE_TOP;  -- First cycle we will be at top of matrix
        vs.startflag := '1';
        vs.ybus_en   := '1';

      when SCHED_PROCESSING =>
        if(rs.ybus_addr = rs.leny and rs.schedule = PE_DEPTH-1) then
          read_delay_rst <= '1';
          hapl_delay_rst <= '1';
          prob_delay_rst <= '1';
        end if;

        -- Unset the startflag
        vs.startflag := '0';

        -- Increase PairHMM cycle, except when this is the first cycle, which we can check by looking at the last bit of fifo_rd_en
        -- Everything inside this if statement is triggered when a new cell update cycle starts
        if vs.schedule = u(PE_DEPTH - 4, PE_DEPTH_BITS) and rs.startflag = '0' and rs.ybus_addr1 < rs.leny-1 then
          vs.shift_prob_buffer := '1';
        end if;

        if vs.schedule = u(PE_DEPTH - 3, PE_DEPTH_BITS) and rs.startflag = '0' and rs.ybus_addr1 < rs.leny-1 then
          vs.shift_prob_buffer := '0';
          vs.shift_read_buffer := '1';

          if rs.element /= PAIRHMM_NUM_PES - 1 then
            vs.shift_hapl_buffer := '1';
          end if;
        end if;

        if vs.schedule = u(PE_DEPTH - 2, PE_DEPTH_BITS) and rs.startflag = '0' then
          vs.shift_read_buffer := '0';
          vs.shift_hapl_buffer := '0';
          vs.shift_prob_buffer := '0';
        end if;

        if vs.schedule = u(0, PE_DEPTH_BITS) and rs.startflag = '0' then
          vs.cycle             := rs.cycle + 1;  -- Increase the total cycle counter
          vs.basepair          := rs.basepair + 1;  -- Increase the counter of Y
          vs.shift_read_buffer := '0';
          vs.shift_hapl_buffer := '0';
          vs.shift_prob_buffer := '0';

          if rs.element /= PAIRHMM_NUM_PES - 1 then
            vs.element   := rs.element + 1;  -- Increase processing highest active element in supercolumn counter
            vs.ybus_addr := rs.ybus_addr + 1;  -- Increase X Bus address
            vs.ybus_en   := '1';        -- Write to next element
          end if;

          -- If we are done with the last padded base of X
          if vs.basepair = rs.sizexp then
            -- If this is not the last base
            if rs.cell /= PE_LAST then
              vs.supercolumn := rs.supercolumn + 1;  -- Advance to the next supercolumn
              vs.element     := (others => '0');  -- Reset the highest active element in supercolumn counter
              vs.ybus_addr   := (others => '0');
              vs.basepair    := (others => '0');  -- Reset the basepair counter of Y
              vs.sizey       := rs.sizey - PAIRHMM_NUM_PES;  -- Subtract size in the X direction
              vs.ybus_en     := '1';    -- Write to first element in next cycle
            end if;
          end if;

          -- Default PE cell state is normal:
          vs.cell := PE_NORMAL;

          -- If the vertical basepair we're working on is 0, we are at the top of the matrix
          if vs.basepair = 0 then
            vs.cell := PE_TOP;
          end if;

                                        -- If we are at the last base of the read
          if vs.basepair = rs.sizex - 1 then
            vs.cell     := PE_BOTTOM;   -- Assert the "bottom" signal
            if rs.sizey <= PAIRHMM_NUM_PES then
              vs.cell := PE_LAST;       -- Assert the "last" signal
            end if;
          end if;

                                        -- If we fed the last base of the whole pair in the previous cell update cycle
          if rs.cell = PE_LAST then
            vs.valid := '0';            -- Next inputs are not valid anymore
            vs.cell  := PE_NORMAL;      -- Not last anymore
            vs.state := SCHED_DONE;
          end if;
        end if;

                                        -- Enable feedback FIFO writing when we passed the number of PE's the first time.
        if vs.cycle = PAIRHMM_NUM_PES then
          vs.feedback_wr_en := '1';
        end if;

                                        -- Enable feedback FIFO reading when we passed the number of padded bases the first time.
        if vs.cycle = rs.sizexp then
          vs.feedback_rd_en := '1';
        end if;

      when SCHED_DONE =>
                                        -- Reset the feedback FIFO
        vs.feedback_rd_en := '0';
        vs.feedback_wr_en := '0';
        vs.feedback_rst   := '1';
        vs.state          := SCHED_IDLE;

      when others =>
        null;

    end case;
--------------------------------------------------------------------------------------------------- outputs
    qs <= vs;
  end process;
--------------------------------------------------------------------------------------------------- registers
  scheduler_reg : process(re.clk_kernel)
  begin
    if rising_edge(re.clk_kernel) then
      if reset = '1' then
        rs.state          <= SCHED_IDLE;
        rs.cycle          <= (others => '0');
        rs.basepair       <= (others => '0');
        rs.schedule       <= (others => '0');
        rs.valid          <= '0';
        rs.cell           <= PE_NORMAL;
        rs.pairhmm_rst    <= '1';
        rs.feedback_rd_en <= '0';
        rs.feedback_wr_en <= '0';
        rs.feedback_rst   <= '1';
        rs.ybus_en        <= '0';
        rs.ybus_en1       <= '0';
      else
        rs <= qs;
      end if;
    end if;
  end process;

end pairhmm_unit;
