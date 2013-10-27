#!/bin/bash
#
# File     : gyre.sh
# Purpose  : GYRE testing script

. test_support

# Settings

EXEC=./gyre_ad

IN_FILE_N=gyre_ad.n.in
IN_FILE_1=gyre_ad.1.in

OUT_FILE_N=gyre_ad.n.txt
OUT_FILE_1=gyre_ad.1.txt

FIELDS=1-5

# Do the tests

run_gyre $EXEC $IN_FILE_N "homogeneous compressible model (OpenMP)"
if [ $? -ne 0 ]; then
    exit 1;
fi

export OMP_NUM_THREADS=1

run_gyre $EXEC $IN_FILE_1 ""
if [ $? -ne 0 ]; then
    exit 1;
fi

check_output "" $FIELDS $OUT_FILE_N $OUT_FILE_1
if [ $? -ne 0 ]; then
    exit 1;
fi

# Clean up output files

rm -f $OUT_FILE_N $OUT_FILE_1

# Finish

echo " ...succeeded"
