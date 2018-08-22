#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

for p in 16 32 #64
do
    for x in 10 20 30 40 50 60 70 80 90 100 200 300 400 500 600 700 800 900 1000
    do
        $DIR/build/pairhmm $p $x $x 10 # TODO make initial constant (10) variable
    done
done
