#!/bin/sh -l

rootdir="/lfs3/projects/hpc-wof1/ywang/regional_fv3"

#-----------------------------------------------------------------------
#
# This script runs the post-processor (UPP) on the NetCDF output files
# of the write component of the FV3SAR model.
#
#-----------------------------------------------------------------------
#
UPPDIR="${rootdir}/EMC_post"
UPPFIX="${rootdir}/UPP/fix"
UPPEXE="${rootdir}/fv3sar.mine/exec"
template_dir="${rootdir}/fv3sar.mine/run_templates_EMC"

#
#-----------------------------------------------------------------------
#
# Save current shell options (in a global array).  Then set new options
# for this script/function.
#
#-----------------------------------------------------------------------
#
RUNDIR=$1      # $eventdir
CDATE=$2

nodes1="1"
platppn="24"

#-----------------------------------------------------------------------
#
# Create directory (POSTPRD_DIR) in which to store post-processing out-
# put.  Also, create a temporary work directory (FHR_DIR) for the cur-
# rent output hour being processed.  FHR_DIR will be deleted later be-
# low after the processing for the current hour is complete.
#
#-----------------------------------------------------------------------
POSTPRD_DIR="$RUNDIR/postprd"

for hr in $(seq 0 1 60); do
  fhr=$(printf "%03d" $hr)

  dyn_file=${RUNDIR}/dynf${fhr}.nc
  phy_file=${RUNDIR}/phyf${fhr}.nc

  while [[ ! -f ${dyn_file} ]]; do
    sleep 10
    echo "Waiting for ${dyn_file}"
  done

  while [[ ! -f ${phy_file} ]]; do
    sleep 10
    echo "Waiting for ${phy_file}"
  done

  FHR_DIR="${POSTPRD_DIR}/$fhr"
  if [[ ! -r ${FHR_DIR} ]]; then
    mkdir -p ${FHR_DIR}
  fi

  cd ${FHR_DIR}


#-----------------------------------------------------------------------
#
# Create text file containing arguments to the post-processing executa-
# ble.
#
#-----------------------------------------------------------------------


  POST_TIME=$( date -d "${CDATE} $fhr hours" +%Y%m%d%H%M )
  POST_YYYY=${POST_TIME:0:4}
  POST_MM=${POST_TIME:4:2}
  POST_DD=${POST_TIME:6:2}
  POST_HH=${POST_TIME:8:2}

  cat > itag <<EOF
${dyn_file}
netcdf
grib2
${POST_YYYY}-${POST_MM}-${POST_DD}_${POST_HH}:00:00
FV3R
${phy_file}

&NAMPGB
  KPO=47,PO=1000.,975.,950.,925.,900.,875.,850.,825.,800.,775.,750.,725.,700.,675.,650.,625.,600.,575.,550.,525.,500.,475.,450.,425.,400.,375.,350.,325.,300.,275.,250.,225.,200.,175.,150.,125.,100.,70.,50.,30.,20.,10.,7.,5.,3.,2.,1.,
/
EOF

  rm -f fort.*

#-----------------------------------------------------------------------
#
# Stage files.
#
#-----------------------------------------------------------------------

  ln -s $UPPFIX/nam_micro_lookup.dat ./eta_micro_lookup.dat
  ln -s $UPPFIX/postxconfig-NT-fv3sar.txt ./postxconfig-NT.txt
  ln -s $UPPFIX/params_grib2_tbl_new ./params_grib2_tbl_new

#-----------------------------------------------------------------------
#
# Run the post-processor and move output files from FHR_DIR to POSTPRD_-
# DIR.
#
#-----------------------------------------------------------------------
  jobscript=run_upp_$fhr.job
  cp ${template_dir}/run_upp_on_Jet.job ${jobscript}
  sed -i -e "/WWWDDD/s#WWWDDD#${FHR_DIR}#;s#NNNNNN#${nodes1}#;s#PPPPPP#${platppn}#g;s#UUUPPP#${UPPDIR}#;s#EEEEEE#${UPPEXE}#;s#DDDDDD#${CDATE}#;s#HHHHHH#${fhr}#;" ${jobscript}

  qsub $jobscript

done


