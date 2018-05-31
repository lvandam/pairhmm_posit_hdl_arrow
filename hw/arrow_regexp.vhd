-- Copyright 2018 Delft University of Technology
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;

library work;
use work.Streams.all;
use work.Utils.all;
use work.Arrow.all;

use work.SimUtils.all;

use work.arrow_regexp_pkg.all;

-- In our programming model it is required to have an interface to a
-- memory (host memory, wether or not copied, as long as it retains the
-- Arrow format) and a slave interface for the memory mapped registers.
--
-- This unit uses AXI interconnect to do both, where the slave interface
-- is AXI4-lite and the master interface an AXI4 full interface. For high
-- throughput, the master interface should support bursts.
asdfasfasfd
entity arrow_regexp is
  generic (
    -- Host bus properties
    BUS_ADDR_WIDTH : natural := 64;
    BUS_DATA_WIDTH : natural := 512;

    -- MMIO bus properties
    SLV_BUS_ADDR_WIDTH : natural := 32aaa
    SLV_BUS_DATA_WIDTH : natural := 32

    REG_WIDTH : natural := 32

   -- (Generic defaults are set for SystemVerilog compatibility)
    );

  port (
    clk     : in std_logic;
    reset_n : in std_logic;

    ---------------------------------------------------------------------------
    -- AXI4 master
    --
    -- To be connected to the DDR controllers (through CL_DMA_PCIS_SLV)
    ---------------------------------------------------------------------------
    -- Read address channel
    m_axi_araddr  : out std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
    m_axi_arlen   : out std_logic_vector(7 downto 0);
    m_axi_arvalid : out std_logic;
    m_axi_arready : in  std_logic;
    m_axi_arsize  : out std_logic_vector(2 downto 0);

    -- Read data channel
    m_axi_rdata  : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    m_axi_rresp  : in  std_logic_vector(1 downto 0);
    m_axi_rlast  : in  std_logic;
    m_axi_rvalid : in  std_logic;
    m_axi_rready : out std_logic;

    ---------------------------------------------------------------------------
    -- AXI4-lite slave
    --
    -- To be connected to "sh_cl_sda" a.k.a. "AppPF Bar 1"
    ---------------------------------------------------------------------------
    -- Write adress
    s_axi_awvalid : in  std_logic;
    s_axi_awready : out std_logic;
    s_axi_awaddr  : in  std_logic_vector(SLV_BUS_ADDR_WIDTH-1 downto 0);

    -- Write data
    s_axi_wvalid : in  std_logic;
    s_axi_wready : out std_logic;
    s_axi_wdata  : in  std_logic_vector(SLV_BUS_DATA_WIDTH-1 downto 0);
    s_axi_wstrb  : in  std_logic_vector((SLV_BUS_DATA_WIDTH/8)-1 downto 0);

    -- Write response
    s_axi_bvalid : out std_logic;
    s_axi_bready : in  std_logic;
    s_axi_bresp  : out std_logic_vector(1 downto 0);

    -- Read address
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;
    s_axi_araddr  : in  std_logic_vector(SLV_BUS_ADDR_WIDTH-1 downto 0);

    -- Read data
    s_axi_rvalid : out std_logic;
    s_axi_rready : in  std_logic;
    s_axi_rdata  : out std_logic_vector(SLV_BUS_DATA_WIDTH-1 downto 0);
    s_axi_rresp  : out std_logic_vector(1 downto 0)
    );
end entity arrow_regexp;

architecture rtl of arrow_regexp is

  -----------------------------------------------------------------------------
  -- Memory Mapped Input/Output
  -----------------------------------------------------------------------------

  -----------------------------------
  -- Fletcher registers
  ----------------------------------- Default registers
  --   1 status (uint64)        =  2
  --   1 control (uint64)       =  2
  --   1 return (uint64)        =  2
  ----------------------------------- Buffer addresses
  --   1 index buf address      =  2
  --   1 data  buf address      =  2
  ----------------------------------- Custom registers
  --   1 first idx              =  1
  --   1 last idx               =  1
  --   1 results                =  1
  -----------------------------------
  -- Total:                       13 regs
  constant NUM_FLETCHER_REGS : natural := 13;

  -- The LSB index in the slave address
  constant SLV_ADDR_LSB : natural := log2floor(SLV_BUS_DATA_WIDTH / 4) - 1;

  -- The MSB index in the slave address
  constant SLV_ADDR_MSB : natural := SLV_ADDR_LSB + log2floor(NUM_FLETCHER_REGS);

  -- Fletcher register offsets
  constant REG_STATUS_HI : natural := 0;
  constant REG_STATUS_LO : natural := 1;

  -- Control register offsets
  constant REG_CONTROL_HI : natural := 2;
  constant REG_CONTROL_LO : natural := 3;

  -- Return register
  constant REG_RETURN_HI : natural := 4;
  constant REG_RETURN_LO : natural := 5;

  -- Index/Offset buffer address
  constant REG_OFF_ADDR_HI : natural := 6;
  constant REG_OFF_ADDR_LO : natural := 7;

  -- Data buffer address
  constant REG_UTF8_ADDR_HI : natural := 8;
  constant REG_UTF8_ADDR_LO : natural := 9;

  -- Register offsets to indices for each RegExp unit to work on
  constant REG_FIRST_IDX : natural := 10;
  constant REG_LAST_IDX  : natural := 11;

  -- Register offset for each RegExp unit to put its result
  constant REG_RESULT : natural := 12;

  -- The offsets of the bits to signal busy and done for each of the units
  constant STATUS_BUSY_OFFSET : natural := 0;
  constant STATUS_DONE_OFFSET : natural := 1;

  -- The offsets of the bits to signal start and reset to each of the units
  constant CONTROL_START_OFFSET : natural := 0;
  constant CONTROL_RESET_OFFSET : natural := 0;

  -- Memory mapped register file
  type mm_regs_t is array (0 to NUM_FLETCHER_REGS-1) of std_logic_vector(SLV_BUS_DATA_WIDTH-1 downto 0);
  signal mm_regs : mm_regs_t;

  -- Helper signals to do handshaking on the slave port
  signal read_address    : natural range 0 to NUM_FLETCHER_REGS-1;
  signal write_valid     : std_logic;
  signal read_valid      : std_logic := '0';
  signal write_processed : std_logic;

  signal axi_top : axi_top_t;

  -- Register all ports to ease timing
  signal r_control_reset : std_logic;
  signal r_control_start : std_logic;
  signal r_reset_start   : std_logic;
  signal r_busy          : std_logic;
  signal r_done          : std_logic;
  signal r_firstidx      : std_logic_vector(REG_WIDTH-1 downto 0);
  signal r_lastidx       : std_logic_vector(REG_WIDTH-1 downto 0);
  signal r_off_hi        : std_logic_vector(REG_WIDTH-1 downto 0);
  signal r_off_lo        : std_logic_vector(REG_WIDTH-1 downto 0);
  signal r_utf8_hi       : std_logic_vector(REG_WIDTH-1 downto 0);
  signal r_utf8_lo       : std_logic_vector(REG_WIDTH-1 downto 0);
  signal r_matches       : std_logic_vector(1*REG_WIDTH-1 downto 0);  --NUM_REGEX=1

  -----------------------------------------------------------------------------
  -- ColumnReader Interface
  -----------------------------------------------------------------------------
  constant OFFSET_WIDTH       : natural := 32;
  constant VALUE_ELEM_WIDTH   : natural := 8;
  constant VALUES_PER_CYCLE   : natural := 1;  -- burst size of 1 -> 1 (was 4) ?
  constant NUM_STREAMS        : natural := 1;  -- only 1 stream for char
  constant VALUES_WIDTH       : natural := VALUE_ELEM_WIDTH * VALUES_PER_CYCLE;
  constant VALUES_COUNT_WIDTH : natural := log2ceil(VALUES_PER_CYCLE)+1;
  constant OUT_DATA_WIDTH     : natural := OFFSET_WIDTH + VALUES_WIDTH + VALUES_COUNT_WIDTH;

  -- Command Stream
  type command_t is record
    valid    : std_logic;
    ready    : std_logic;
    firstIdx : std_logic_vector(OFFSET_WIDTH - 1 downto 0);
    lastIdx  : std_logic_vector(OFFSET_WIDTH - 1 downto 0);
    ctrl     : std_logic_vector(2 * BUS_ADDR_WIDTH - 1 downto 0);
  end record;

  signal cmd_ready : std_logic;

  -- Output Streams
  type utf8_stream_in_t is record
    valid  : std_logic;
    dvalid : std_logic;
    last   : std_logic;
    count  : std_logic_vector(VALUES_COUNT_WIDTH-1 downto 0);
    data   : std_logic_vector(VALUES_WIDTH-1 downto 0);
  end record;

  type str_elem_in_t is record
    utf8 : utf8_stream_in_t;
  end record;

  procedure conv_streams_in (
    signal valid       : in  std_logic_vector(NUM_STREAMS-1 downto 0);
    signal dvalid      : in  std_logic_vector(NUM_STREAMS-1 downto 0);
    signal last        : in  std_logic_vector(NUM_STREAMS-1 downto 0);
    signal data        : in  std_logic_vector(OUT_DATA_WIDTH-1 downto 0);
    signal str_elem_in : out str_elem_in_t
    ) is
  begin
    str_elem_in.utf8.count  <= data(VALUES_COUNT_WIDTH + VALUES_WIDTH + OFFSET_WIDTH - 1 downto VALUES_WIDTH + OFFSET_WIDTH);
    str_elem_in.utf8.data   <= data(VALUES_WIDTH + OFFSET_WIDTH - 1 downto OFFSET_WIDTH);
    str_elem_in.utf8.valid  <= valid(0);
    str_elem_in.utf8.dvalid <= dvalid(0);
    str_elem_in.utf8.last   <= last(0);
  end procedure;

  type utf8_stream_out_t is record
    ready : std_logic;
  end record;

  type str_elem_out_t is record
    utf8 : utf8_stream_out_t;
  end record;

  procedure conv_streams_out (
    signal str_elem_out : in  str_elem_out_t;
    signal out_ready    : out std_logic_vector(NUM_STREAMS-1 downto 0)
    ) is
  begin
    out_ready(0) <= str_elem_out.utf8.ready;
  end procedure;

  -----------------------------------------------------------------------------
  -- UserCore
  -----------------------------------------------------------------------------
  type state_t is (STATE_IDLE, STATE_RESET_START, STATE_REQUEST, STATE_BUSY, STATE_DONE);

  -- Control and status bits
  type cs_t is record
    reset_start : std_logic;
    done        : std_logic;
    busy        : std_logic;
  end record;

  type reg is record
    state : state_t;
    cs    : cs_t;

    command : command_t;

    regex : regex_t;

    str_elem_out : str_elem_out_t;
    str_elem_in  : str_elem_in_t;

    processed : reg_array;
    matches   : reg_array;
  end record;

  signal r : reg;
  signal d : reg;

  -----------------------------------------------------------------------------
  -- Registers
  -----------------------------------------------------------------------------
  signal control_reset : std_logic;
  signal control_start : std_logic;

  -- Read request channel
  signal req_addr             : std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);
  signal req_len              : std_logic_vector(BOTTOM_LEN_WIDTH-1 downto 0);
  signal req_valid, req_ready : std_logic;

  -- Read response channel
  signal rsp_data                       : std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
  signal bus_rsp_resp                   : std_logic_vector(1 downto 0);
  signal rsp_ready, rsp_last, rsp_valid : std_logic;

  signal usercore_start       : std_logic;
  signal usercore_busy        : std_logic;
  signal usercore_done        : std_logic;
  signal usercore_reset       : std_logic;
  signal usercore_reset_start : std_logic;

  -----------------------------------------------------------------------------
  -- ColumnWriter helper constants and signals
  -----------------------------------------------------------------------------
  constant CW_DATA_WIDTH : natural := INDEX_WIDTH +
                                      ELEMENT_WIDTH*ELEMENT_COUNT_MAX +
                                      ELEMENT_COUNT_WIDTH;

  -- Get the serialization indices for in_data
  constant ISI : nat_array := cumulative((
    2 => ELEMENT_COUNT_WIDTH,                --
    1 => ELEMENT_WIDTH * ELEMENT_COUNT_MAX,  -- utf8 data
    0 => INDEX_WIDTH                         -- len data
    ));

  constant BUS_LEN_WIDTH : natural := 9;  -- 1 more than AXI

  constant CTRL_WIDTH : natural := 2*BUS_ADDR_WIDTH;
  constant TAG_WIDTH  : natural := 1;

  signal cmd_valid    : std_logic;
  signal cmd_ready    : std_logic;
  signal cmd_firstIdx : std_logic_vector(INDEX_WIDTH-1 downto 0);
  signal cmd_lastIdx  : std_logic_vector(INDEX_WIDTH-1 downto 0);
  signal cmd_ctrl     : std_logic_vector(CTRL_WIDTH-1 downto 0);
  signal cmd_tag      : std_logic_vector(TAG_WIDTH-1 downto 0);

begin
  -----------------------------------------------------------------------------
  -- Memory Mapped Slave Registers
  -----------------------------------------------------------------------------
  write_valid <= s_axi_awvalid and s_axi_wvalid and not write_processed;

  s_axi_awready <= write_valid;
  s_axi_wready  <= write_valid;
  s_axi_bresp   <= "00";                -- Always OK
  s_axi_bvalid  <= write_processed;

  s_axi_arready <= not read_valid;

  -- Mux for reading
  -- Might want to insert a reg slice before getting it to the ColumnReaders
  -- and UserCore
  s_axi_rdata  <= mm_regs(read_address);
  s_axi_rvalid <= read_valid;
  s_axi_rresp  <= "00";                 -- Always OK

  -- Reads
  read_from_regs : process(clk) is
    variable address : natural range 0 to NUM_FLETCHER_REGS-1;
  begin
    address := int(s_axi_araddr(SLV_ADDR_MSB downto SLV_ADDR_LSB));

    if rising_edge(clk) then
      if reset_n = '0' then
        read_valid <= '0';
      else
        if s_axi_arvalid = '1' and read_valid = '0' then
          dumpStdOut("Read request from MMIO: " & integer'image(address) & " value " & integer'image(int(mm_regs(address))));
          read_address <= address;
          read_valid   <= '1';
        elsif s_axi_rready = '1' then
          read_valid <= '0';
        end if;
      end if;
    end if;
  end process;

  -- Writes

  -- TODO: For registers that are split up over two addresses, this is not
  -- very pretty. There should probably be some synchronization mechanism
  -- to only apply the write after both HI and LO addresses have been
  -- written.
  -- Also we don't care about byte enables at the moment.
  write_to_regs : process(clk) is
    variable address : natural range 0 to NUM_FLETCHER_REGS;
  begin

    address := int(s_axi_awaddr(SLV_ADDR_MSB downto SLV_ADDR_LSB));

    if rising_edge(clk) then
      if write_valid = '1' then
        dumpStdOut("Write to MMIO: " & integer'image(address));

        case address is
          -- Read only addresses do nothing
          when REG_STATUS_HI =>         -- no-op
          when REG_STATUS_LO =>         -- no-op
          when REG_RETURN_HI =>         -- no-op
          when REG_RETURN_LO =>         -- no-op
          when REG_RESULT    =>         -- no-op

          -- All others are writeable:
          when others =>
            mm_regs(address) <= s_axi_wdata;
        end case;
      else
        if usercore_reset_start = '1' then
          mm_regs(REG_CONTROL_LO)(0) <= '0';
        end if;
      end if;

      -- Read only register values:

      -- Status registers
      mm_regs(REG_STATUS_HI) <= (others => '0');

      mm_regs(REG_STATUS_LO)(SLV_BUS_DATA_WIDTH - 1 downto STATUS_DONE_OFFSET) <= (others => '0');
      mm_regs(REG_STATUS_LO)(STATUS_BUSY_OFFSET)                               <= '1';  -- TODO Laurens: fill this in
      mm_regs(REG_STATUS_LO)(STATUS_DONE_OFFSET)                               <= '0';  -- TODO Laurens: fill this in

      -- Return registers
      mm_regs(REG_RETURN_HI) <= (others => '0');
      mm_regs(REG_RETURN_LO) <= (others => '1');  -- result here
      mm_regs(REG_RESULT)    <= (others => '1');  -- result here

      if reset_n = '0' then
        mm_regs(REG_CONTROL_LO) <= (others => '0');
        mm_regs(REG_CONTROL_HI) <= (others => '0');
      end if;
    end if;
  end process;

  -- Write response
  write_resp_proc : process(clk) is
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        write_processed <= '0';
      else
        if write_valid = '1' then
          write_processed <= '1';
        elsif s_axi_bready = '1' then
          write_processed <= '0';
        end if;
      end if;
    end if;
  end process;

  -- Slice up (without backpressure) the control signals
  reg_settings : process(clk)
  begin
    if rising_edge(clk) then
      -- Control bits
      usercore_start <= mm_regs(REG_CONTROL_LO)(0);
      usercore_reset <= mm_regs(REG_CONTROL_LO)(1);
    end if;
  end process;

  -----------------------------------------------------------------------------
-- Global control state machine
-----------------------------------------------------------------------------
  global_sm : block is
    type state_type is (IDLE, STRINGGEN, COLUMNWRITER, UNLOCK);

    type reg_record is record
      busy        : std_logic;
      done        : std_logic;
      reset_start : std_logic;
      state       : state_type;
    end record;

    type cmd_record is record
      valid    : std_logic;
      firstIdx : std_logic_vector(INDEX_WIDTH-1 downto 0);
      lastIdx  : std_logic_vector(INDEX_WIDTH-1 downto 0);
      ctrl     : std_logic_vector(CTRL_WIDTH-1 downto 0);
      tag      : std_logic_vector(TAG_WIDTH-1 downto 0);
    end record;

    type str_record is record
      valid : std_logic;
      len   : std_logic_vector(INDEX_WIDTH-1 downto 0);
      min   : std_logic_vector(LEN_WIDTH-1 downto 0);
      mask  : std_logic_vector(LEN_WIDTH-1 downto 0);
    end record;

    type unl_record is record
      ready : std_logic;
    end record;

    type out_record is record
      cmd : cmd_record;
      -- str                       : str_record;
      unl : unl_record;
    end record;

    signal r : reg_record;
    signal d : reg_record;
  begin
    seq_proc : process(clk) is
    begin
      if rising_edge(clk) then
        r <= d;

        -- Reset
        if reset = '1' then
          r.state       <= IDLE;
          r.reset_start <= '0';
          r.busy        <= '0';
          r.done        <= '0';
        end if;
      end if;
    end process;

    comb_proc : process(r,
                        usercore_start,
                        mm_regs(REG_OFF_ADDR_HI), mm_regs(REG_OFF_ADDR_LO),
                        mm_regs(REG_UTF8_ADDR_HI), mm_regs(REG_UTF8_ADDR_LO),
                        cmd_ready,
                        ssg_cmd_ready,
                        unlock_valid, unlock_tag
                        ) is
      variable v : reg_record;
      variable o : out_record;
    begin
      v := r;

      -- Disable command streams by default
      o.cmd.valid := '0';
      o.str.valid := '0';
      o.unl.ready := '0';

      -- Default outputs
      o.cmd.firstIdx := mm_regs(REG_FIRST_IDX);
      o.cmd.lastIdx  := mm_regs(REG_LAST_IDX);
      -- Values buffer at LSBs
      o.cmd.ctrl(BUS_ADDR_WIDTH-1 downto 0)
        := mm_regs(REG_UTF8_ADDR_HI) & mm_regs(REG_UTF8_ADDR_LO);
      -- Index buffer at MSBs
      o.cmd.ctrl(2*BUS_ADDR_WIDTH-1 downto BUS_ADDR_WIDTH)
        := mm_regs(REG_OFF_ADDR_HI) & mm_regs(REG_OFF_ADDR_LO);

      o.cmd.tag := (0 => '1', others => '0');

      -- We use the last index to determine how many strings have to be
      -- generated. This assumes firstIdx is 0.
      -- o.str.len  := mm_regs(REG_LAST_IDX);
      -- o.str.min  := mm_regs(REG_STRLEN_MIN)(LEN_WIDTH-1 downto 0);
      -- o.str.mask := mm_regs(REG_PRNG_MASK)(LEN_WIDTH-1 downto 0);
      -- Note: string lengths that are generated will be:
      -- (minimum string length) + ((PRNG output) bitwise and (PRNG mask))
      -- Set STRLEN_MIN to 0 and PRNG_MASK to all 1's (strongly not
      -- recommended) to generate all possible string lengths.

      -- Reset start is low by default.
      v.reset_start := '0';

      case r.state is
        when IDLE =>
          if usercore_start = '1' then
            v.reset_start := '1';
            v.state       := STRINGGEN;
            v.busy        := '1';
            v.done        := '0';
          end if;

        when STRINGGEN =>
          -- Validate command:
          -- o.str.valid := '1';

          if ssg_cmd_ready = '1' then
            -- Command is accepted, start the ColumnWriter
            v.state := COLUMNWRITER;
          end if;

        when COLUMNWRITER =>
          -- Validate command:
          o.cmd.valid := '1';

          if cmd_ready = '1' then
            -- Command is accepted, wait for unlock.
            v.state := UNLOCK;
          end if;

        when UNLOCK =>
          o.unl.ready := '1';

          if unlock_valid = '1' then
            v.state := IDLE;
            -- Make done and reset busy
            v.done  := '1';
            v.busy  := '0';
          end if;

      end case;

      -- Registered outputs
      d <= v;

      -- Combinatorial outputs
      cmd_valid    <= o.cmd.valid;
      cmd_firstIdx <= o.cmd.firstIdx;
      cmd_lastIdx  <= o.cmd.lastIdx;
      cmd_ctrl     <= o.cmd.ctrl;
      cmd_tag      <= o.cmd.tag;

      ssg_cmd_valid      <= o.str.valid;
      ssg_cmd_len        <= o.str.len;
      ssg_cmd_prng_mask  <= o.str.mask;
      ssg_cmd_strlen_min <= o.str.min;

      unlock_ready <= o.unl.ready;

    end process;

    -- Registered output
    usercore_reset_start <= r.reset_start;
    usercore_busy        <= r.busy;
    usercore_done        <= r.done;

  end block;




  -----------------------------------------------------------------------------
  -- Master
  -----------------------------------------------------------------------------
  -- Read address channel
  axi_top.arready <= m_axi_arready;

  m_axi_arvalid <= axi_top.arvalid;
  m_axi_araddr  <= axi_top.araddr;

  m_axi_arlen <= axi_top.arlen;

  m_axi_arsize <= "110";                --6 for 2^6*8 bits = 512 bits

  -- Read data channel
  m_axi_rready <= axi_top.rready;

  axi_top.rvalid <= m_axi_rvalid;
  axi_top.rdata  <= m_axi_rdata;
  axi_top.rresp  <= m_axi_rresp;
  axi_top.rlast  <= m_axi_rlast;

  -- Convert axi read address channel and read response channel
  -- Scales "len" and "size" according to the master data width
  -- and converts the Fletcher bus "len" to AXI bus "len"
  read_converter_inst : axi_read_converter generic map (
    ADDR_WIDTH        => BUS_ADDR_WIDTH,
    ID_WIDTH          => 1,
    MASTER_DATA_WIDTH => BUS_DATA_WIDTH,
    MASTER_LEN_WIDTH  => 8,
    SLAVE_DATA_WIDTH  => BUS_DATA_WIDTH,
    SLAVE_LEN_WIDTH   => BUS_LEN_WIDTH,
    SLAVE_MAX_BURST   => BUS_BURST_MAX_LEN,
    ENABLE_FIFO       => false
    )
    port map (
      clk             => clk,
      reset_n         => reset_n,
      s_bus_req_addr  => req_addr,
  --     s_bus_req_len   => req_len,
  --     s_bus_req_valid => req_valid,
  --     s_bus_req_ready => req_ready,
  --     s_bus_rsp_data  => rsp_data,
  --     s_bus_rsp_last  => rsp_last,
  --     s_bus_rsp_valid => rsp_valid,
  --     s_bus_rsp_ready => rsp_ready,
  --     m_axi_araddr    => axi_top.araddr,
  --     m_axi_arlen     => axi_top.arlen,
  --     m_axi_arvalid   => axi_top.arvalid,
  --     m_axi_arready   => axi_top.arready,
  --     m_axi_arsize    => axi_top.arsize,
  --     m_axi_rdata     => axi_top.rdata,
  --     m_axi_rlast     => axi_top.rlast,
  --     m_axi_rvalid    => axi_top.rvalid,
  --     m_axi_rready    => axi_top.rready
  --     );
  --
  -- -----------------------------------------------------------------------------
  -- -- ColumnReader
  -- -----------------------------------------------------------------------------
  -- hapl_cr : ColumnReader
  --   generic map (
  --     BUS_ADDR_WIDTH     => BUS_ADDR_WIDTH,
  --     BUS_LEN_WIDTH      => BUS_LEN_WIDTH,
  --     BUS_DATA_WIDTH     => BUS_DATA_WIDTH,
  --     BUS_BURST_STEP_LEN => BUS_BURST_STEP_LEN,
  --     BUS_BURST_MAX_LEN  => BUS_BURST_MAX_LEN,
  --     INDEX_WIDTH        => INDEX_WIDTH,
  --     CFG                => "listprim(8)",  -- char array (haplos)
  --     -- CFG                => "list(struct(prim(8),prim(256)))",  -- struct array (reads)
  --     CMD_TAG_ENABLE     => false,
  --     CMD_TAG_WIDTH      => 1
  --     )
  --   port map (
  --     bus_clk   => clk,
  --     bus_reset => reset_n,
  --     acc_clk   => clk,
  --     acc_reset => reset_n,
  --
  --     cmd_valid    => cmd_valid,
  --     cmd_ready    => cmd_ready,
  --     cmd_firstIdx => cmd_firstIdx,
  --     cmd_lastIdx  => cmd_lastIdx,
  --     cmd_ctrl     => cmd_ctrl,
  --     cmd_tag      => (others => '0'),  -- CMD_TAG_ENABLE is false
  --
  --     unlock_valid => open,
  --     unlock_ready => '1',
  --     unlock_tag   => open,
  --
  --     busReq_valid => req_valid,
  --     busReq_ready => req_ready,
  --     busReq_addr  => req_addr,
  --     busReq_len   => req_len,
  --
  --     busResp_valid => rsp_valid,
  --     busResp_ready => rsp_ready,
  --     busResp_data  => rsp_data,
  --     busResp_last  => rsp_last,
  --
  --     out_valid  => out_valid,
  --     out_ready  => out_ready,
  --     out_last   => out_last,
  --     out_dvalid => out_dvalid,
  --     out_data   => out_databuck
  --     );

  -- sm_seq : process(clk) is
  -- begin
  --   if rising_edge(clk) then
  --     r <= d;
  --
  --     r_control_reset <= control_reset;
  --     r_control_start <= control_start;
  --
  --     busy <= r_busy;
  --     done <= r_done;
  --
  --     r_firstidx <= mm_regs(REG_FIRST_IDX);
  --     r_lastidx  <= mm_regs(REG_LAST_IDX);
  --
  --     r_off_hi <= mm_regs(REG_OFF_ADDR_HI);
  --     r_off_lo <= mm_regs(REG_OFF_ADDR_LO);
  --
  --     r_utf8_hi <= mm_regs(REG_UTF8_ADDR_HI);
  --     r_utf8_lo <= mm_regs(REG_UTF8_ADDR_LO);
  --     matches   <= r_matches;
  --
  --     if control_reset = '1' then
  --       r.state <= STATE_IDLE;
  --     end if;
  --   end if;
  -- end process;
  --
  -- sm_comb : process(r,
  --                   cmd_ready,
  --                   str_elem_in,
  --                   regex_output,
  --                   r_firstidx,
  --                   r_lastidx,
  --                   r_off_hi,
  --                   r_off_lo,
  --                   r_utf8_hi,
  --                   r_utf8_lo,
  --                   r_control_start,
  --                   r_control_reset)
  --   is
  --   variable v : reg;
  -- begin
  --   v               := r;
  --   -- Inputs:
  --   v.command.ready := cmd_ready;
  --   v.str_elem_in   := str_elem_in;
  --   v.regex.output  := regex_output;
  --
  --   -- Default outputs:
  --   v.command.valid := '0';
  --
  --   v.str_elem_out.len.ready  := '0';
  --   v.str_elem_out.utf8.ready := '0';
  --
  --   v.regex.input.valid := '0';
  --   v.regex.input.last  := '0';
  --
  --   case v.state is
  --     when STATE_IDLE =>
  --       v.cs.busy        := '0';
  --       v.cs.done        := '0';
  --       v.cs.reset_start := '0';
  --
  --       v.processed := (others => (others => '0'));
  --       v.matches   := (others => (others => '0'));
  --
  --       v.reset_units := '1';
  --
  --       if control_start = '1' then
  --         v.state          := STATE_RESET_START;
  --         v.cs.reset_start := '1';
  --       end if;
  --
  --     when STATE_RESET_START =>
  --       v.cs.busy := '1';
  --       v.cs.done := '0';
  --
  --       v.reset_units := '0';
  --
  --       if control_start = '0' then
  --         v.state := STATE_REQUEST;
  --       end if;
  --
  --     when STATE_REQUEST =>
  --       v.cs.done        := '0';
  --       v.cs.busy        := '1';
  --       v.cs.reset_start := '0';
  --       v.reset_units    := '0';
  --
  --       -- First four argument registers are buffer addresses
  --       -- MSBs are index buffer address
  --       v.command.ctrl(127 downto 96) := r_off_hi;
  --       v.command.ctrl(95 downto 64)  := r_off_lo;
  --       -- LSBs are data buffer address
  --       v.command.ctrl(63 downto 32)  := r_utf8_hi;
  --       v.command.ctrl(31 downto 0)   := r_utf8_lo;
  --
  --       -- Next two argument registers are first and last index
  --       v.command.firstIdx := r_firstidx;
  --       v.command.lastIdx  := r_lastidx;
  --
  --       -- Make command valid
  --       v.command.valid := '1';
  --
  --       -- Wait for command accepted
  --       if v.command.ready = '1' then
  --         dumpStdOut("RegExp unit requested strings: " &
  --                    integer'image(int(v.command.firstIdx)) &
  --                    " ... "
  --                    & integer'image(int(v.command.lastIdx)));
  --         v.state := STATE_BUSY;
  --       end if;
  --
  --     when STATE_BUSY =>
  --       v.cs.done        := '0';
  --       v.cs.busy        := '1';
  --       v.cs.reset_start := '0';
  --       v.reset_units    := '0';
  --
  --       -- Always ready to receive length
  --       v.str_elem_out.len.ready := '1';
  --
  --       if v.str_elem_in.len.valid = '1' then
  --       -- Do something when this is the last string
  --       end if;
  --       if (v.str_elem_in.len.last = '1') and
  --         (v.processed(0) = u(v.command.lastIdx) - u(v.command.firstIdx))
  --       then
  --         dumpStdOut("RegEx unit is done");
  --         v.state := STATE_DONE;
  --       end if;
  --
  --       -- Always ready to receive utf8 char
  --       v.str_elem_out.utf8.ready := '1';
  --
  --       if v.str_elem_in.utf8.valid = '1' then
  --       -- Do something for every utf8 char
  --       end if;
  --
  --       if v.str_elem_in.utf8.last = '1' then
  --       -- Do something when this is the last utf8 char
  --       end if;
  --
  --     when STATE_DONE =>
  --       v.cs.done        := '1';
  --       v.cs.busy        := '0';
  --       v.cs.reset_start := '0';
  --
  --       if r_control_reset = '1' or r_control_start = '1' then
  --         v.state := STATE_IDLE;
  --       end if;
  --   end case;
  --
  --   d <= v;
  -- end process;

end architecture;
