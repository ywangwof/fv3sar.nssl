#!/bin/bash
#
# Purpose: send FV3 IC/LBCs to Jet
#
# /scratch/larissa.reames/make_um_icbcs/chgres_icbcs
#

scpdir=$(dirname $0)       # To ensure to use the same dir as this script
#scpdir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

destdir=/lfs3/NAGAPE/hpc-wof1/ywang/regional_fv3/ukmic
srcdir=/scratch/larissa.reames/make_um_icbcs/chgres_icbcs

eventdt=$(date -u +%Y%m%d)

function usage {
    echo " "
    echo "    USAGE: $0 [options] DATETIME [DESTDIR]"
    echo " "
    echo "    PURPOSE: Send FV3 IC/LBCs initialized from UKMet to Jet."
    echo "       NOTE: must run on Odin."
    echo " "
    echo "    DATETIME - Case date and time in YYYYMMDD"
    echo "               empty for current day"
    echo "    DESTDIR  - Work Directory on Jet"
    echo " "
    echo "    OPTIONS:"
    echo "              -h              Display this message"
    echo "              -n              Show command to be run only"
    echo "              -v              Verbose mode"
    echo " "
    echo "   DEFAULTS:"
    echo "              eventdt = $eventdt"
    echo "              srcdir  = $srcdir"
    echo "              destdir = $destdir"
    echo " "
    echo "                                     -- By Y. Wang (2020.04.24)"
    echo " "
    exit $1
}

#-----------------------------------------------------------------------
#
# Default values
#
#-----------------------------------------------------------------------

show=0
verb=0

#-----------------------------------------------------------------------
#
# Handle command line arguments
#
#-----------------------------------------------------------------------

while [[ $# > 0 ]]
    do
    key="$1"

    case $key in
        -h)
            usage 0
            ;;
        -n)
            show=1
            ;;
        -v)
            verb=1
            ;;
        -*)
            echo "Unknown option: $key"
            exit
            ;;
        *)
            if [[ $key =~ ^[0-9]{8}$ ]]; then
                eventdt="$key"
            else
                destdir=$key
            fi
            ;;
    esac
    shift # past argument or value
done


echo "DATETIME: $eventdt"
echo "destdir = $destdir"
echo "srcdir  = $srcdir"
echo " "

#-----------------------------------------------------------------------
#
# retrieve data from Jet
#
#-----------------------------------------------------------------------

tophour=36
inthour=3

eventsrc="$srcdir/$eventdt"
donefile="donefile.chgres.${eventdt}0000"

files=(gfs_ctrl.nc out.atm.tile7.nc out.sfc.tile7.nc)

for hr in $(seq 0 ${inthour} ${tophour}); do
  fhr=$(printf "%03d" $hr)
  files+=(gfs_bndy.tile7.${fhr}.nc)
done
files+=(${donefile})

while [[ ! -f ${eventsrc}/$donefile ]]; do
    echo "Waiting for ${eventsrc}/$donefile ....."
    sleep 10
done

for fn in ${files[@]}; do
    echo "Sending $eventsrc/$fn ......"
    if [[ $fn == "out.atm.tile7.nc" ]]; then
      dfn="gfs_data.tile7.nc"
    elif [[ $fn == "out.sfc.tile7.nc" ]]; then
      dfn="sfc_data.tile7.nc"
    else
      dfn=$fn
    fi
    scp $eventsrc/$fn dtn:$destdir/$dfn
done

exit 0

