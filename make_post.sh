#!/bin/sh
fname=$(date "+%Y-%m-%d"-$1)
fname="_posts/$fname"
if [ -e $fname ]; then
    echo "$fname already exists!"
    exit 1
fi

exec vim $fname
