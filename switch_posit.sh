#!/bin/bash
cd hw

ES=$1 # Exponent bits

rm pe_package.vhd
rm -rf posit_rtl

ln -s ../pe_posit_conf/pe_package_es$1.vhd pe_package.vhd
ln -s ../posit/es$1/ posit_rtl
