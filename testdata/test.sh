#!/bin/bash

test -e ssshtest || wget -q https://raw.githubusercontent.com/ryanlayer/ssshtest/master/ssshtest

. ssshtest
set -e


cd csvtk; go build; cd ..;
app=./csvtk/csvtk

set +e


# ----------------------------------------------------------------------------
# test data
# ----------------------------------------------------------------------------

# $1, rows
# $2, cols
# $3, delimiter
# $4, has header row
headers() {
    seq $2 | awk '{print "c"$1}' | paste -s -d $3 -
}
matrix() {
    if [ "$4" = true ]; then
        headers $1 $2 $3
    fi
    for i in $(seq $1); do
        seq $(( $2*($i-1)+1 )) $(( $2*$i )) | paste -s -d $3 -
    done
}

N="1 10"

# ----------------------------------------------------------------------------
# csvtk headers
# ----------------------------------------------------------------------------

for n in $N; do                 # scales
    for d in "," "\t"; do       # delimiters
        for h in true false; do # headerrow
            headrow=""
            if [ $h = false ]; then
                headrow=-H
            fi
            tab=""
            if [ $d == "\t" ]; then
                tab=-t
            fi
            fn() {
                matrix $(($n*2)) $n $d $h | $app $tab $headrow headers 
            }
            run "headers $tab $headrow (n=$n)" fn
            
            if [ $h = true ]; then
                assert_no_stderr
            else
                assert_in_stderr "flag -H (--no-header-row) ignored"
            fi
            assert_equal $(cat $STDOUT_FILE | grep -v '#' | wc -l) $n
        done
    done
done


# ----------------------------------------------------------------------------
# csvtk dim
# ----------------------------------------------------------------------------

for n in $N; do                 # scales
    for d in "," "\t"; do       # delimiters
        for h in true false; do # headerrow
            headrow=""
            if [ $h = false ]; then
                headrow=-H
            fi
            tab=""
            if [ $d == "\t" ]; then
                tab=-t
            fi
            fn() {
                matrix $(($n*2)) $n $d $h | $app $tab $headrow dim
            }
            run "dim $tab $headrow (n=$n)" fn
            
            if [ $h = true ]; then
                assert_no_stderr
            else
                assert_no_stderr
            fi
            
            assert_equal $(cat $STDOUT_FILE | $app space2tab | sed 1d | cut -f 2 | sed 's/,//g') $n
            assert_equal $(cat $STDOUT_FILE | $app space2tab | sed 1d | cut -f 3 | sed 's/,//g') $(($n*2))
        done
    done
done


# ----------------------------------------------------------------------------
# csvtk cut
# ----------------------------------------------------------------------------

for n in $N; do                 # scales
    for d in "," "\t"; do       # delimiters
        for h in true false; do # headerrow
            for c in 3 5 4,6; do
                headrow=""
                if [ $h = false ]; then
                    headrow=-H
                fi
                tab=""
                if [ $d == "\t" ]; then
                    tab=-t
                fi
                fn() {
                    matrix $(($n*2)) $n $d $h | $app $tab $headrow cut -f $c
                }
                run "cut -f $c $tab $headrow (n=$n)" fn
                
                if [ $n -lt $(echo $c | cut -d "," -f 1) ]; then
                    assert_in_stderr "out of range"
                    continue
                else
                    assert_no_stderr
                fi
                
                if [ $d == "\t" ]; then
                    assert_equal $(cat $STDOUT_FILE | md5sum | cut -d " " -f 1) $(matrix $(($n*2)) $n $d $h | cut -f $c | md5sum | cut -d " " -f 1)
                else
                    assert_equal $(cat $STDOUT_FILE | md5sum | cut -d " " -f 1) $(matrix $(($n*2)) $n $d $h | cut -d, -f $c | md5sum | cut -d " " -f 1)
                fi
            done
        done
    done
done

fn() {
    cat testdata/names.csv | $app cut -f id
}
run "cat testdata/names.csv | $app cut -f id" fn
assert_no_stderr
assert_equal $(cat $STDOUT_FILE | md5sum | cut -d " " -f 1) $(cat testdata/names.csv | $app cut -f 1 | md5sum | cut -d " " -f 1)

# ----------------------------------------------------------------------------
# csvtk corr
# ----------------------------------------------------------------------------

CORR_DATA=testdata/corr_data.tsv

float_gt(){
    CODE=$(awk 'BEGIN {PREC="double"; print ("'$1'" >= "'$2'")}')
    return $CODE
}

fun(){
	$app -t corr -f A,B $CORR_DATA > corr.tsv
}
run corr fun
R=$(cut -f 3 corr.tsv)
# scipy result: 0.8892414849570343
float_gt $R 0.889
assert_equal $? 1
float_gt 0.8893 $R
assert_equal $? 1

rm corr.tsv

# ----------------------------------------------------------------------------
# csvtk mutate2/filter2
# ----------------------------------------------------------------------------

# a       b       c
# 1       2.00    0.50
# 2       4.00    0.50
# 3       6.00    0.50
# 4       8.00    0.50
# 5       10.00   0.50
# 6       12.00   0.50
# 7       14.00   0.50
# 8       16.00   0.50
# 9       18.00   0.50
# 10      20.00   0.50

# $a / $b
assert_equal $(seq 10 \
    | $app mutate2 -Ht -e '$1 * 2' \
    | $app add-header -t -n a,b \
    | $app mutate2 -t -n c -e '$a / $b' \
    | $app filter2 -t -f '$c >= 0.5' \
    | $app summary -t -f c:sum -w 0 \
    | $app del-header) \
    5

# $1 / $2
assert_equal $(seq 10 \
    | $app mutate2 -Ht -e '$1 * 2' \
    | $app add-header -t -n a,b \
    | $app mutate2 -t -n c -e '$1 / $2' \
    | $app filter2 -t -f '$c >= 0.5' \
    | $app summary -t -f c:sum -w 0 \
    | $app del-header) \
    5

# $a / $b
# replace filter2 with filter3
assert_equal $(seq 10 \
    | $app mutate2 -Ht -e '$1 * 2' \
    | $app add-header -t -n a,b \
    | $app mutate3 -t -n c -e '$a / $b' \
    | $app filter2 -t -f '$c >= 0.5' \
    | $app summary -t -f c:sum -w 0 \
    | $app del-header) \
    5


# a       b       c
# 1       2.00    2.00
# 2       4.00    2.00
# 3       6.00    2.00
# 4       8.00    2.00
# 5       10.00   2.00
# 6       12.00   2.00
# 7       14.00   2.00
# 8       16.00   2.00
# 9       18.00   2.00
# 10      20.00   2.00

# $b / $a
assert_equal $(seq 10 \
    | $app mutate2 -Ht -e '$1 * 2' \
    | $app add-header -t -n a,b \
    | $app mutate2 -t -n c -e '$b / $a' \
    | $app filter2 -t -f '$c >= 2' \
    | $app summary -t -f c:sum -w 0 \
    | $app del-header) \
    20

# $2 / $1
assert_equal $(seq 10 \
    | $app mutate2 -Ht -e '$1 * 2' \
    | $app add-header -t -n a,b \
    | $app mutate2 -t -n c -e '$2 / $1' \
    | $app filter2 -t -f '$c >= 2' \
    | $app summary -t -f c:sum -w 0 \
    | $app del-header) \
    20

# ----------------------------------------------------------------------------
# csvtk xxx
# ----------------------------------------------------------------------------
