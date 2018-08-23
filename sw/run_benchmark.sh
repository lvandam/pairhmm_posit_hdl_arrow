#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

for p in 16 32
do
    for i in 5 10 15
    do
        $DIR/build/pairhmm $p 8 8 $i
        $DIR/build/pairhmm $p 16 16 $i
        $DIR/build/pairhmm $p 24 24 $i
        $DIR/build/pairhmm $p 32 32 $i
        $DIR/build/pairhmm $p 40 40 $i

        $DIR/build/pairhmm $p 8 16 $i

        $DIR/build/pairhmm $p 8 24 $i
        $DIR/build/pairhmm $p 16 24 $i

        $DIR/build/pairhmm $p 8 32 $i
        $DIR/build/pairhmm $p 16 32 $i
        $DIR/build/pairhmm $p 24 32 $i

        $DIR/build/pairhmm $p 8 40 $i
        $DIR/build/pairhmm $p 16 40 $i
        $DIR/build/pairhmm $p 24 40 $i
        $DIR/build/pairhmm $p 32 40 $i

        $DIR/build/pairhmm $p 8 48 $i
        $DIR/build/pairhmm $p 16 48 $i
        $DIR/build/pairhmm $p 24 48 $i
        $DIR/build/pairhmm $p 32 48 $i
        $DIR/build/pairhmm $p 40 48 $i

        $DIR/build/pairhmm $p 8 56 $i
        $DIR/build/pairhmm $p 16 56 $i
        $DIR/build/pairhmm $p 24 56 $i
        $DIR/build/pairhmm $p 32 56 $i
        $DIR/build/pairhmm $p 40 56 $i
    done
done
