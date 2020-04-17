#!/bin/bash
#rootdir="/lfs3/projects/wof/fv3_regional"
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
quilt_nodes="6"
quilt_ppn="12"

platppn="12"

npes=$((layout_x * layout_y + quilt_nodes*quilt_ppn))
nodes1=$(( layout_x * layout_y/platppn ))
nodes2=$(( quilt_nodes * quilt_ppn/platppn ))
nodes=$(( nodes1 + nodes2 ))

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

files=(gfs_ctrl.nc gfs_data.tile7.nc sfc_data.tile7.nc)
for hr in $(seq 0 3 60); do
  fhr=$(printf "%03d" $hr)
  files+=(gfs_bndy.tile7.${fhr}.nc)
done
files+=(${emcdone})

#
# 1.1 Try public/data directory first
#
publicdatadir="/public/data/grids/ncep/fv3sar"

if [ ! -f ${emc_event}/${emcdone} ]; then

  if [[ ! -d ${emc_event} ]]; then
    mkdir -p ${emc_event}
  fi

  currjdate=$(date +%j)
  curryyval=$(date +%g)

  jdate=$(date -d "$eventdate" +%j)
  yyval=$(date -d "$eventdate" +%g)

  waitmaxseconds=7200   # wait for at most 1-hour
  waitseconds=0;  found=0; orgdatasize=-1

  while [[ $waitseconds -lt $waitmaxseconds ]]; do

    if [[ $curryyval -eq $yyval && $currjdate -le $((jdate+2)) ]]; then

      gfsdatafile="${publicdatadir}/${yyval}${jdate}0000.gfs_data.tile7.nc"

      if [[ -f ${gfsdatafile} ]]; then
        gfsdatasize=$(stat --printf="%s" ${gfsdatafile})

        filesizediff=$(( gfsdatasize - orgdatasize ))

        if [[ $filesizediff -le 0 ]]; then
        #if [[ -f ${publicdatadir}/${yyval}${jdate}0000.${emcdone} ]]; then
          found=1
          break
        else
          echo "File ${gfsdatafile} is actively changing at $waitseconds seconds (${orgdatasize} -> $gfsdatasize) ..."
          orgdatasize=${gfsdatasize}
        fi
      else
        echo "Waiting for EMC datasets ${publicdatadir}/${yyval}${jdate}0000.* ($waitseconds)..."
      fi

      sleep 20
      waitseconds=$(( waitseconds+=20 ))
    else
      #echo "$jdate, $currjdate"
      break         # case is older than 2 days
    fi
  done

  if [[ $found -gt 0 ]]; then
    for fn in ${files[@]}; do
      echo "Copying $fn ....."
      cp -v ${publicdatadir}/${yyval}${jdate}0000.$fn ${emc_event}/$fn
    done

    #touch ${emc_event}/${emcdone}
  fi
fi

#
# 1.2 Try the ftp server if not found in publicdatadir
#
emcurl="ftp://ftp.emc.ncep.noaa.gov/mmb/mmbpll/fv3sar/fv3sar.${eventdate}/${CYCLE}"

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
  #cp ${template_dir}/suite_FV3_GFS_2017_thompson_mynn.xml .
  cp ${template_dir}/suite_FV3_GFS_v15_thompson_mynn.xml .

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
  rm global_o3prdlos.f77
  ln -s ${runfix_dir}/ozprdlos_2015_new_sbuvO3_tclm15_nuchem.f77 global_o3prdlos.f77
  rm global_soilmgldas.t126.384.190.grb
  ln -s ${runfix_dir}/fix.C768/global_soilmgldas.t1534.3072.1536.grb .
  ln -s ${runfix_dir}/CCN_ACTIVATE.BIN .


  ymd=`echo ${eventdate} |cut -c 1-8`
  yyy=`echo ${eventdate} |cut -c 1-4`
  mmm=`echo ${eventdate} |cut -c 5-6`
  ddd=`echo ${eventdate} |cut -c 7-8`

  sed -i -e "/NPES/s/NPES/${npes}/;/YYYY/s/YYYY/$yyy/;/MM/s/MM/$mmm/;/DD/s/DD/$ddd/" model_configure
  sed -i -e "s/NODES2/${quilt_nodes}/;s/PPN2/${quilt_ppn}/" model_configure
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

EXEPRO="$rootdir/fv3sar.mine/exec/fv3_GFSL81_HAIL.exe"

if [ ! -f $donefv3 ]; then
  #echo "Waiting for ${chgresfile} ..."
  #while [[ ! -f ${chgresfile} ]]; do
  #  sleep 10
  #  #echo "Waiting for ${chgresfile} ..."
  #done
  #ls -l ${chgresfile}

  cd ${eventdir}

  jobscript=run_fv3sar_$eventdate${CYCLE}.slurm
  cp ${template_dir}/run_on_Jet_EMC.job ${jobscript}
  sed -i -e "/WWWDDD/s#WWWDDD#$eventdir#;s#EXEPPP#$EXEPRO#;s#NNNNNN#${nodes}#;s#PPPPPP#${platppn}#g;s#NPES#${npes}#" ${jobscript}
  #sed -i -e "/WWWDDD/s#WWWDDD#$eventdir#;s#EXEPPP#$EXEPRO#;s#NNNNNN#${nodes1}#;s#PPPPP1#${platppn}#g;s#MMMMMM#${nodes2}#;s#PPPPP2#${quilt_ppn}#g" ${jobscript}

  #module load slurm

  echo "sbatch $jobscript"
  sbatch $jobscript

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
