#!/bin/ksh

fname=`basename $0`
fpath=${0%$fname}


if [ -z $ORACLE_HOME ]; then
        echo "ORACLE_HOME is not set"
        exit 1
elif [ -z $ORACLE_SID ]; then
        echo "ORACLE_SID is not set"
        exit 1
fi

if [[ $ORACLE_SID =~ \+ASM(\d) ]]; then

        if [ -x $ORACLE_HOME/perl/bin/perl ]; then
                $ORACLE_HOME/perl/bin/perl $fpath/blk2asm.pl
        else
                echo "No execute permission on $ORACLE_HOME/perl/bin/perl"
                exit 1
        fi
else
        echo "$ORACLE_SID is not set to ASM instance"
        exit 1
fi

