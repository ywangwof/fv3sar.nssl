#!/bin/bash
rootdir="/lfs3/projects/hpc-wof1/ywang/regional_fv3"
WORKDIRDF="${rootdir}/run_dirs"
eventdateDF=$(date +%Y%m%d)
#export eventdate="20180214"

function usage {
  echo " "
  echo "$0 [YYYYMMDD] [WORKDIR]"
  echo " "
  exit 0
}

export WORKDIR="$WORKDIRDF"
export eventdate="$eventdateDF"
if [[ $# > 1 ]]; then
  export WORKDIR="$2"
  export eventdate="$1"
elif [[ $# > 0 ]]; then
  export eventdate="$1"
fi

export CYCLE="00"
#export FIX_AM="${rootdir}/fix/fix_am"

layout_x="32"
layout_y="36"
quilt_nodes="3"
quilt_ppn="24"

platppn="12"

npes=$((layout_x * layout_y + quilt_nodes*quilt_ppn))
nodes1=$(( layout_x * layout_y/platppn ))
nodes2=$(( quilt_nodes ))

echo "---- Jobs started at $(date +%m-%d_%H:%M:%S) for Event: $eventdate; Working dir: $WORKDIR ----"
#usage

#-----------------------------------------------------------------------
#
# 1. Download EMC IC/BC datasets
#
#-----------------------------------------------------------------------

echo "-- 1: download EMC data files at $(date +%m-%d_%H:%M:%S) ----"
emc_dir="${rootdir}/emcic"   #"/fv3sar.${eventdate}/00"

cd ${emc_dir}

emc_event="${emc_dir}/fv3sar.${eventdate}/${CYCLE}"
emcdone="donefile.${eventdate}${CYCLE}"

emcurl="ftp://ftp.emc.ncep.noaa.gov/mmb/mmbpll/fv3sar/fv3sar.${eventdate}/${CYCLE}"
files=(gfs_ctrl.nc gfs_data.tile7.nc sfc_data.tile7.nc)
for hr in $(seq 0 3 60); do
  fhr=$(printf "%03d" $hr)
  files+=(gfs_bndy.tile7.${fhr}.nc)
done
files+=(${emcdone})

if [ ! -f ${emc_event}/${emcdone} ]; then

  while true; do

    wget -m -nH --cut-dirs=3 ${emcurl}/${emcdone}

    if [[ $? -eq 0 ]]; then
      break
    else
      #echo "Waiting for EMC datasets ..."
      sleep 10
    fi
  done

  rm -f ${emc_event}/${emcdone}
  for fn in ${files[@]}; do
    echo "Downloading $fn ....."
    wget -m -nH --cut-dirs=3 ${emcurl}/$fn > /dev/null 2>&1
  done
fi

echo " "

#-----------------------------------------------------------------------
#
# 2. Prepare working directories
#
#-----------------------------------------------------------------------

eventdir="${WORKDIR}/${eventdate}${CYCLE}"
if [[ ! -r ${eventdir} ]]; then
  mkdir -p ${eventdir}
fi

donefv3="$eventdir/done.fv3"

if [ ! -f $donefv3 ]; then

  echo "-- 2: prepare working directory for FV3SAR at $(date +%m-%d_%H:%M:%S) ----"

  cd ${eventdir}
  mkdir -p INPUT

  cd INPUT
  ln -s ${emc_event}/gfs_bndy.tile7.*.nc .
  ln -s ${emc_event}/gfs_data.tile7.nc gfs_data.nc
  ln -s ${emc_event}/sfc_data.tile7.nc sfc_data.nc
  ln -s ${emc_event}/gfs_ctrl.nc .

  ln -s ${emc_dir}/fv3_grid.regional/C768_grid.tile7.halo3.nc     C768_grid.tile7.nc
  ln -s ${emc_dir}/fv3_grid.regional/C768_grid.tile7.halo4.nc     grid.tile7.halo4.nc
  ln -s ${emc_dir}/fv3_grid.regional/C768_oro_data.tile7.halo0.nc C768_oro_data.tile7.nc
  ln -s ${emc_dir}/fv3_grid.regional/C768_oro_data.tile7.halo0.nc oro_data.nc
  ln -s ${emc_dir}/fv3_grid.regional/C768_oro_data.tile7.halo4.nc oro_data.tile7.halo4.nc
  ln -s ${emc_dir}/fv3_grid.regional/C768_mosaic.nc               grid_spec.nc

  cd ..

  mkdir -p RESTART

  template_dir="${rootdir}/fv3sar.mine/run_templates_EMC"

  cp ${template_dir}/*_table .
  cp ${template_dir}/input.nml .
  cp ${template_dir}/model_configure .
  cp ${template_dir}/nems.configure .
  #ln -s ${template_dir}/suite_FV3_GSD.xml ccpp_suite.xml
  ln -s ${template_dir}/suite_FV3_GFS_2017_updated_thompson_mynn.xml ccpp_suite.xml
  ln -s ${template_dir}/CCN_ACTIVATE.BIN .

  runfix_dir="${rootdir}/fv3sar.mine/run_fix"
  #ln -s ${runfix_dir}/global_o3prdlos.f77 .
  #ln -s ${runfix_dir}/global_h2oprdlos.f77 .
  ln -s ${runfix_dir}/aerosol.dat .
  ln -s ${runfix_dir}/solarconstant_noaa_an.txt .
  ln -s ${runfix_dir}/CFSR.SEAICE.1982.2012.monthly.clim.grb .
  ln -s ${runfix_dir}/RTGSST.1982.2012.monthly.clim.grb .
  ln -s ${runfix_dir}/seaice_newland.grb .
  ln -s ${runfix_dir}/sfc_emissivity_idx.txt .
  ln -s ${runfix_dir}/co2* .
  ln -s ${runfix_dir}/global_* .


  ymd=`echo ${eventdate} |cut -c 1-8`
  yyy=`echo ${eventdate} |cut -c 1-4`
  mmm=`echo ${eventdate} |cut -c 5-6`
  ddd=`echo ${eventdate} |cut -c 7-8`

  sed -i -e "/NPES/s/NPES/${npes}/;/YYYY/s/YYYY/$yyy/;/MM/s/MM/$mmm/;/DD/s/DD/$ddd/" model_configure
  sed -i -e "s/NODES2/${nodes2}/;s/PPN2/${quilt_ppn}/" model_configure
  sed -i -e "/NPES/s/NPES/${npes}/;/YYYY/s/YYYY/$yyy/;/MM/s/MM/$mmm/;/DD/s/DD/$ddd/" diag_table

  sed -i -e "/LAYOUT/s/LAYOUTX/${layout_x}/;s/LAYOUTY/${layout_y}/" input.nml
  sed -i -e "/FIX_AM/s#FIX_AM#${runfix_dir}#"   input.nml
fi

#-----------------------------------------------------------------------
#
# 3. run fv3 model
#
#-----------------------------------------------------------------------

echo "-- 3: run FV3SAR at $(date +%m-%d_%H:%M:%S) ----"

EXEPRO="$rootdir/fv3sar.mine/exec/fv3_32bit.exe"

if [ ! -f $donefv3 ]; then
  #echo "Waiting for ${chgresfile} ..."
  #while [[ ! -f ${chgresfile} ]]; do
  #  sleep 10
  #  #echo "Waiting for ${chgresfile} ..."
  #done
  #ls -l ${chgresfile}

  cd ${eventdir}

  jobscript=run_fv3sar_$eventdate${CYCLE}.job
  cp ${template_dir}/run_on_Jet_EMC.job ${jobscript}
  sed -i -e "/WWWDDD/s#WWWDDD#$eventdir#;s#EXEPPP#$EXEPRO#;s#NNNNNN#${nodes1}#;s#PPPPP1#${platppn}#g;s#PPPPP2#${quilt_ppn}#g;s#MMMMMM#${nodes2}#" ${jobscript}

  echo "qsub $jobscript"
  qsub $jobscript

  echo "Waiting for ${donefv3} ..."
  #while [[ ! -f ${donefv3} ]]; do
  #  sleep 10
  #  #echo "Waiting for ${donefv3} ..."
  #done
  #ls -l ${donefv3}
fi

echo " "

#-----------------------------------------------------------------------
#
# 4. post-processing
#
#-----------------------------------------------------------------------

echo "-- 4: run post-processing at $(date +%m-%d_%H:%M:%S) ----"

export FV3SARDIR="${rootdir}/fv3sar.mine"
${FV3SARDIR}/run_post.sh ${eventdir} ${eventdate}

echo " "

exit

#-----------------------------------------------------------------------
#
# 5. Transfer grib files
#
#-----------------------------------------------------------------------

echo "-- 5: Transfer grib2 file to bigbang3 at $(date +%m-%d_%H:%M:%S) ----"

donetransfer="$WORKDIR/C384_${eventdate}00_VLab/done.transfer"

if [ ! -f $donetransfer ]; then

  echo "Waiting for ${donepost} ..."
  while [[ ! -f ${donepost} ]]; do
    sleep 10
    #echo "Waiting for ${donepost} ..."
  done
  ls -l ${donepost}

  cd $WORKDIR/C384_${eventdate}00_VLab
  echo "scp *.grb2 bigbang3:/raid/efp/se2018/ftp/nssl/fv3_test"
  scp *.grb2 bigbang3:/raid/efp/se2018/ftp/nssl/fv3_test

  touch $donetransfer
fi

echo " "

#-----------------------------------------------------------------------
#
# 6. Clean old runs
#
#-----------------------------------------------------------------------

cleandate=$(date -d "2 days ago" +%Y%m%d )
echo "-- 5: Clean run on ${cleandate} ----"

cd $WORKDIR
rm -r ${cleandate}.00Z_IC C384_${cleandate}00_VLab

echo " "

echo "==== Jobs done at $(date +%m-%d_%H:%M:%S) ===="
echo " "
exit 0
