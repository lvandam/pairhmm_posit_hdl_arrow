---------------------------------------------------------------------------------------------------
--    _____      _      _    _ __  __ __  __
--   |  __ \    (_)    | |  | |  \/  |  \/  |
--   | |__) |_ _ _ _ __| |__| | \  / | \  / |
--   |  ___/ _` | | '__|  __  | |\/| | |\/| |
--   | |  | (_| | | |  | |  | | |  | | |  | |
--   |_|   \__,_|_|_|  |_|  |_|_|  |_|_|  |_|
---------------------------------------------------------------------------------------------------
-- Processing Element package
---------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.functions.all;

package pe_package is

  constant POSIT_NBITS            : natural := 32;
  constant POSIT_ES               : natural := 3;
  constant POSIT_WIDE_ACCUMULATOR : natural := 1;  -- 0: dont use wide accumulator in pairhmm.vhd

  constant PE_DW         : natural := 32;               -- data width
  constant PE_MUL_CYCLES : natural := 4;
  constant PE_ADD_CYCLES : natural := 4;
  constant PE_CYCLES     : natural := 2 * PE_MUL_CYCLES + 2 * PE_ADD_CYCLES;
  constant PE_DEPTH      : natural := PE_CYCLES;
  constant PE_DEPTH_BITS : natural := log2e(PE_DEPTH);  -- should be round_up(log_2(PE_DEPTH)).
  constant PE_BCC        : natural := PE_MUL_CYCLES + 2 * PE_ADD_CYCLES;  -- base compare cycle

  -- Internal type for values
  subtype prob is std_logic_vector(PE_DW-1 downto 0);
  type pe_cell_type is (PE_NORMAL, PE_TOP, PE_LAST, PE_BOTTOM);

  type matchindels is record
    mtl : prob;
    itl : prob;
    dtl : prob;

    mt : prob;
    it : prob;
    dt : prob;

    ml : prob;
    il : prob;
    dl : prob;
  end record;

  constant mids_mlone : matchindels := (
    mtl => (others => '0'),
    itl => (others => '0'),
    dtl => (others => '0'),
    mt  => (others => '0'),
    it  => (others => '0'),
    dt  => (others => '0'),
    ml  => X"40000000",                 -- posit<32,2>/posit<32,3>: 40000000
    il  => (others => '0'),
    dl  => (others => '0')
    );

  type transmissions is record
    alpha : prob;
    beta  : prob;

    delta   : prob;
    epsilon : prob;

    zeta : prob;
    eta  : prob;
  end record;

  type emissions is record
    distm_simi : prob;
    distm_diff : prob;
    theta      : prob;
    upsilon    : prob;
  end record;

  type probabilities is record
    distm_simi : std_logic_vector(31 downto 0);
    distm_diff : std_logic_vector(31 downto 0);
    theta      : std_logic_vector(31 downto 0);
    upsilon    : std_logic_vector(31 downto 0);
    alpha      : std_logic_vector(31 downto 0);
    beta       : std_logic_vector(31 downto 0);
    delta      : std_logic_vector(31 downto 0);
    epsilon    : std_logic_vector(31 downto 0);
    zeta       : std_logic_vector(31 downto 0);
    eta        : std_logic_vector(31 downto 0);
  end record;

  type step_init_type is record
    initial : prob;
    tmis    : transmissions;
    emis    : emissions;
    mids    : matchindels;
    valid   : std_logic;
    cell    : pe_cell_type;
    x       : bp_type;
    y       : bp_type;
  end record;

  type step_trans_type is record
    almtl : prob;
    beitl : prob;
    gadtl : prob;
    demt  : prob;
    epit  : prob;
    zeml  : prob;
    etdl  : prob;

    tmis : transmissions;
    emis : emissions;
    mids : matchindels;
  end record;

  type step_add_type is record
    albetl   : prob;
    albegatl : prob;
    deept    : prob;
    zeett    : prob;

    tmis : transmissions;
    emis : emissions;
    mids : matchindels;
  end record;

  type step_emult_type is record
    m : prob;
    i : prob;
    d : prob;

    tmis : transmissions;
    emis : emissions;
    mids : matchindels;
  end record;

  type step_type is record
    init  : step_init_type;
    trans : step_trans_type;
    add   : step_add_type;
    emult : step_emult_type;
  end record;

  constant emis_empty : emissions := (
    distm_simi => (others => '0'),
    distm_diff => (others => '0'),
    theta      => (others => '0'),
    upsilon    => (others => '0')
    );

  constant tmis_empty : transmissions := (
    alpha   => (others => '0'),
    beta    => (others => '0'),
    delta   => (others => '0'),
    epsilon => (others => '0'),
    zeta    => (others => '0'),
    eta     => (others => '0')
    );

  constant mids_empty : matchindels := (
    mtl => (others => '0'),
    itl => (others => '0'),
    dtl => (others => '0'),
    mt  => (others => '0'),
    it  => (others => '0'),
    dt  => (others => '0'),
    ml  => (others => '0'),
    il  => (others => '0'),
    dl  => (others => '0')
    );

  constant step_add_empty : step_add_type := (
    albetl   => (others => '0'),
    albegatl => (others => '0'),
    deept    => (others => '0'),
    zeett    => (others => '0'),
    tmis     => tmis_empty,
    emis     => emis_empty,
    mids     => mids_empty
    );

  constant step_emult_empty : step_emult_type := (
    m    => (others => '0'),
    i    => (others => '0'),
    d    => (others => '0'),
    tmis => tmis_empty,
    emis => emis_empty,
    mids => mids_empty
    );

  constant step_init_empty : step_init_type := (
    initial => (others => '0'),
    tmis    => tmis_empty,
    emis    => emis_empty,
    mids    => mids_empty,
    valid   => '0',
    cell    => PE_NORMAL,
    x       => BP_IGNORE,
    y       => BP_IGNORE
    );

  constant step_trans_empty : step_trans_type := (
    almtl => (others => '0'),
    beitl => (others => '0'),
    gadtl => (others => '0'),
    demt  => (others => '0'),
    epit  => (others => '0'),
    zeml  => (others => '0'),
    etdl  => (others => '0'),
    tmis  => tmis_empty,
    emis  => emis_empty,
    mids  => mids_empty
    );

  constant step_type_init : step_type := (
    init  => step_init_empty,
    trans => step_trans_empty,
    add   => step_add_empty,
    emult => step_emult_empty
    );

  -- POSIT SPECIFIC (Raw)
  constant POSIT_SERIALIZED_WIDTH_ES3         : natural := 1+9+26+1+1;
  constant POSIT_SERIALIZED_WIDTH_SUM_ES3     : natural := 1+9+30+1+1;
  constant POSIT_SERIALIZED_WIDTH_PRODUCT_ES3 : natural := 1+10+54+1+1;

  subtype value is std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);

  constant value_empty : value := (POSIT_SERIALIZED_WIDTH_ES3-1 downto 1 => '0', others => '1');
  constant value_one   : value := (others                                => '0');

  subtype value_sum is std_logic_vector(POSIT_SERIALIZED_WIDTH_SUM_ES3-1 downto 0);
  constant value_sum_empty : value_sum := (POSIT_SERIALIZED_WIDTH_SUM_ES3-1 downto 1 => '0', others => '1');

  subtype value_product is std_logic_vector(POSIT_SERIALIZED_WIDTH_PRODUCT_ES3-1 downto 0);
  constant value_product_empty : value_product := (POSIT_SERIALIZED_WIDTH_PRODUCT_ES3-1 downto 1 => '0', others => '1');

  type matchindels_raw is record
    mtl : value;
    itl : value;
    dtl : value;

    mt : value;
    it : value;
    dt : value;

    ml : value;
    il : value;
    dl : value;
  end record;

  constant mids_raw_empty : matchindels_raw := (
    mtl => value_empty,
    itl => value_empty,
    dtl => value_empty,
    mt  => value_empty,
    it  => value_empty,
    dt  => value_empty,
    ml  => value_empty,
    il  => value_empty,
    dl  => value_empty
    );

  type transmissions_raw is record
    alpha : value;
    beta  : value;

    delta   : value;
    epsilon : value;

    zeta : value;
    eta  : value;
  end record;

  constant tmis_raw_empty : transmissions_raw := (
    alpha   => value_empty,
    beta    => value_empty,
    delta   => value_empty,
    epsilon => value_empty,
    zeta    => value_empty,
    eta     => value_empty
    );

  type emissions_raw is record
    distm_simi : value;
    distm_diff : value;
    theta      : value;
    upsilon    : value;
  end record;

  constant emis_raw_empty : emissions_raw := (
    distm_simi => value_empty,
    distm_diff => value_empty,
    theta      => value_empty,
    upsilon    => value_empty
    );

  type step_init_raw_type is record
    initial : value;
    tmis    : transmissions_raw;
    emis    : emissions_raw;
    mids    : matchindels_raw;
    valid   : std_logic;
    cell    : pe_cell_type;
    x       : bp_type;
    y       : bp_type;
  end record;

  constant step_init_raw_empty : step_init_raw_type := (
    initial => value_empty,
    tmis    => tmis_raw_empty,
    emis    => emis_raw_empty,
    mids    => mids_raw_empty,
    valid   => '0',
    cell    => PE_NORMAL,
    x       => BP_IGNORE,
    y       => BP_IGNORE
    );

  type step_trans_raw_type is record
    almtl : value_product;
    beitl : value_product;
    gadtl : value_product;
    demt  : value_product;
    epit  : value_product;
    zeml  : value_product;
    etdl  : value_product;

    tmis : transmissions_raw;
    emis : emissions_raw;
    mids : matchindels_raw;
  end record;

  constant step_trans_raw_empty : step_trans_raw_type := (
    almtl => value_product_empty,
    beitl => value_product_empty,
    gadtl => value_product_empty,
    demt  => value_product_empty,
    epit  => value_product_empty,
    zeml  => value_product_empty,
    etdl  => value_product_empty,
    tmis  => tmis_raw_empty,
    emis  => emis_raw_empty,
    mids  => mids_raw_empty
    );

  type step_add_raw_type is record
    albetl   : value_sum;
    albegatl : value_sum;
    deept    : value_sum;
    zeett    : value_sum;

    tmis : transmissions_raw;
    emis : emissions_raw;
    mids : matchindels_raw;
  end record;

  constant step_add_raw_empty : step_add_raw_type := (
    albetl   => value_sum_empty,
    albegatl => value_sum_empty,
    deept    => value_sum_empty,
    zeett    => value_sum_empty,
    tmis     => tmis_raw_empty,
    emis     => emis_raw_empty,
    mids     => mids_raw_empty
    );

  type step_emult_raw_type is record
    m : value_product;
    i : value_product;
    d : value_product;

    tmis : transmissions_raw;
    emis : emissions_raw;
    mids : matchindels_raw;
  end record;

  constant step_emult_raw_empty : step_emult_raw_type := (
    m    => value_product_empty,
    i    => value_product_empty,
    d    => value_product_empty,
    tmis => tmis_raw_empty,
    emis => emis_raw_empty,
    mids => mids_raw_empty
    );

  type step_raw_type is record
    init  : step_init_raw_type;
    trans : step_trans_raw_type;
    add   : step_add_raw_type;
    emult : step_emult_raw_type;
  end record;

  constant step_raw_init : step_raw_type := (
    init  => step_init_raw_empty,
    trans => step_trans_raw_empty,
    add   => step_add_raw_empty,
    emult => step_emult_raw_empty
    );

  type bps is array (0 to PE_DEPTH-1) of bp_type;
  constant bps_empty : bps := (others => BP_IGNORE);

  type pe_in is record
    en      : std_logic;
    valid   : std_logic;
    cell    : pe_cell_type;
    initial : value;
    tmis    : transmissions_raw;
    emis    : emissions_raw;
    mids    : matchindels_raw;
    x       : bp_type;
    y       : bp_type;
  end record;

  constant pe_in_empty : pe_in := (
    en      => '0',
    valid   => '0',
    cell    => PE_NORMAL,
    initial => value_empty,
    mids    => mids_raw_empty,
    tmis    => tmis_raw_empty,
    emis    => emis_raw_empty,
    x       => BP_IGNORE,
    y       => BP_IGNORE
    );

  type pe_out is record
    ready   : std_logic;
    valid   : std_logic;
    cell    : pe_cell_type;
    initial : value;
    tmis    : transmissions_raw;
    emis    : emissions_raw;
    mids    : matchindels_raw;
    x       : bp_type;
    y       : bp_type;
  end record;

  component posit_normalize_sum_es3
    port (
      in1    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_SUM_ES3-1 downto 0);
      result : out std_logic_vector(POSIT_NBITS-1 downto 0);
      inf    : out std_logic;
      zero   : out std_logic
      );
  end component;

  component posit_extract_raw_es3
    port (
      in1      : in  std_logic_vector(POSIT_NBITS-1 downto 0);
      absolute : out std_logic_vector(31-1 downto 0);
      result   : out std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0)
      );
  end component;

  component positadd_4_raw_es3
    port (
      clk    : in  std_logic;
      in1    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
      in2    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(POSIT_SERIALIZED_WIDTH_SUM_ES3-1 downto 0);
      done   : out std_logic
      );
  end component;

  component posit_normalize_es3
    port (
      in1    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
      result : out std_logic_vector(POSIT_NBITS-1 downto 0);
      inf    : out std_logic;
      zero   : out std_logic
      );
  end component;

  component positadd_8_raw_es3
    port (
      clk    : in  std_logic;
      in1    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
      in2    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(POSIT_SERIALIZED_WIDTH_SUM_ES3-1 downto 0);
      done   : out std_logic
      );
  end component;

  component positmult_4_raw_es3
    port (
      clk    : in  std_logic;
      in1    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
      in2    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(POSIT_SERIALIZED_WIDTH_PRODUCT_ES3-1 downto 0);
      done   : out std_logic
      );
  end component;

  component positmult_4_raw_sumval_es3
    port (
      clk    : in  std_logic;
      in1    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_SUM_ES3-1 downto 0);
      in2    : in  std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(POSIT_SERIALIZED_WIDTH_PRODUCT_ES3-1 downto 0);
      done   : out std_logic
      );
  end component;

  component positadd_4_es3
    port (
      clk    : in  std_logic;
      in1    : in  std_logic_vector(31 downto 0);
      in2    : in  std_logic_vector(31 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(31 downto 0);
      inf    : out std_logic;
      zero   : out std_logic;
      done   : out std_logic
      );
  end component;

  component positadd_8_es3
    port (
      clk    : in  std_logic;
      in1    : in  std_logic_vector(31 downto 0);
      in2    : in  std_logic_vector(31 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(31 downto 0);
      inf    : out std_logic;
      zero   : out std_logic;
      done   : out std_logic
      );
  end component;

  component positmult_4_es3
    port (
      clk    : in  std_logic;
      in1    : in  std_logic_vector(31 downto 0);
      in2    : in  std_logic_vector(31 downto 0);
      start  : in  std_logic;
      result : out std_logic_vector(31 downto 0);
      inf    : out std_logic;
      zero   : out std_logic;
      done   : out std_logic
      );
  end component;

  type initial_array_pe is array (0 to PE_CYCLES-1) of prob;
  type initial_array_pe_raw is array (0 to PE_CYCLES-1) of value;
  type emissions_array is array (0 to PE_CYCLES-1) of emissions;
  type transmissions_array is array (0 to PE_CYCLES-1) of transmissions;
  type valid_array is array (0 to PE_CYCLES-1) of std_logic;
  type cell_array is array (0 to PE_CYCLES-1) of pe_cell_type;

  type emissions_raw_array is array (0 to PE_CYCLES-1) of emissions_raw;
  type transmissions_raw_array is array (0 to PE_CYCLES-1) of transmissions_raw;
  type mids_raw_array is array (0 to PE_CYCLES-1) of matchindels_raw;

  function prod2val (a : in value_product) return value;
  function sum2val (a  : in value_sum) return value;

end package;

package body pe_package is
  -- Product layout:
  -- 67 1       sign
  -- 66 10      scale
  -- 56 54      fraction
  -- 2  1       inf
  -- 1  1       zero
  -- 0
  function prod2val (a : in value_product) return value is
    variable tmp : std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
  begin
    tmp(0)            := a(0);
    tmp(1)            := a(1);
    tmp(27 downto 2)  := a(55 downto 30);
    tmp(36 downto 28) := a(64 downto 56);
    tmp(37)           := a(66);
    assert signed(tmp(36 downto 28)) = signed(a(64 downto 56)) report "Scale loss (prod2val), val=" & integer'image(to_integer(signed(tmp(36 downto 28)))) & ", prod=" & integer'image(to_integer(signed(a(64 downto 56)))) severity error;
    return tmp;
  end function prod2val;

  -- Sum layout:
  -- 42 1       sign
  -- 41 9       scale
  -- 32 30      fraction
  -- 2  1       inf
  -- 1  1       zero
  -- 0
  function sum2val (a : in value_sum) return value is
    variable tmp : std_logic_vector(POSIT_SERIALIZED_WIDTH_ES3-1 downto 0);
  begin
    tmp(0)            := a(0);
    tmp(1)            := a(1);
    tmp(27 downto 2)  := a(31 downto 6);
    tmp(36 downto 28) := a(40 downto 32);
    tmp(37)           := a(41);
    assert signed(tmp(36 downto 28)) = signed(a(40 downto 32)) report "Scale loss (sum2val), val=" & integer'image(to_integer(signed(tmp(36 downto 28)))) & ", sum=" & integer'image(to_integer(signed(a(40 downto 32)))) severity error;
    return tmp;
  end function sum2val;

end package body;
