#!/bin/bash

#
#-----------------------------------------------------------------------
#
# Source the variable definitions file and the bash utility functions.
#
#-----------------------------------------------------------------------
#
. $USHdir/source_util_funcs.sh
source_config_for_task "task_process_radarref|task_run_fcst" ${GLOBAL_VAR_DEFNS_FP}
#
#-----------------------------------------------------------------------
#
# Save current shell options (in a global array).  Then set new options
# for this script/function.
#
#-----------------------------------------------------------------------
#
{ save_shell_opts; . $USHdir/preamble.sh; } > /dev/null 2>&1
#
#-----------------------------------------------------------------------
#
# Get the full path to the file in which this script/function is located 
# (scrfunc_fp), the name of that file (scrfunc_fn), and the directory in
# which the file is located (scrfunc_dir).
#
#-----------------------------------------------------------------------
#
scrfunc_fp=$( readlink -f "${BASH_SOURCE[0]}" )
scrfunc_fn=$( basename "${scrfunc_fp}" )
scrfunc_dir=$( dirname "${scrfunc_fp}" )
#
#-----------------------------------------------------------------------
#
# Print message indicating entry into script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
Entering script:  \"${scrfunc_fn}\"
In directory:     \"${scrfunc_dir}\"
This is the ex-script for the task that runs radar reflectivity preprocess
with FV3 for the specified cycle.
========================================================================"
#
#-----------------------------------------------------------------------
#
# Load modules.
#
#-----------------------------------------------------------------------
#
eval ${PRE_TASK_CMDS}

nprocs=$(( NNODES_PROCESS_RADARREF*PPN_PROCESS_RADARREF))

#
#-----------------------------------------------------------------------
#
# Extract from CDATE the starting year, month, day, and hour of the
# forecast.  These are needed below for various operations.
#
#-----------------------------------------------------------------------
#
START_DATE=$(echo "${PDY} ${cyc}")
YYYYMMDDHH=$(date +%Y%m%d%H -d "${START_DATE}")

YYYY=${YYYYMMDDHH:0:4}
MM=${YYYYMMDDHH:4:2}
DD=${YYYYMMDDHH:6:2}

#
#-----------------------------------------------------------------------
#
# Find cycle type: cold or warm 
#  BKTYPE=0: warm start
#  BKTYPE=1: cold start
#
#-----------------------------------------------------------------------
#
BKTYPE=0
if [ ${DO_SPINUP} == "TRUE" ]; then
  if [ ${CYCLE_TYPE} == "spinup" ]; then
    if [[ ${CYCL_HRS_SPINSTART[@]} =~ "$cyc" ]] ; then
      BKTYPE=1
    fi
  fi
else
  if [[ ${CYCL_HRS_PRODSTART[@]} =~ "$cyc" ]] ; then
    BKTYPE=1
  fi
fi

n_iolayouty=$(($IO_LAYOUT_Y-1))

#
#-----------------------------------------------------------------------
#
# Loop through different time levels
# Get into working directory
#
#-----------------------------------------------------------------------
#
print_info_msg "$VERBOSE" "
Getting into working directory for radar reflectivity process ..."

for timelevel in ${RADARREFL_TIMELEVEL[@]}; do
  timelevel=$( printf %2.2i $timelevel )
  mkdir_vrfy ${DATA}/${timelevel}
  cd ${DATA}/${timelevel}

  pregen_grid_dir=$DOMAIN_PREGEN_BASEDIR/${PREDEF_GRID_NAME}

  print_info_msg "$VERBOSE" "pregen_grid_dir is $pregen_grid_dir"

#
#-----------------------------------------------------------------------
#
# link or copy background files
#
#-----------------------------------------------------------------------

  if [ ${BKTYPE} -eq 1 ]; then
    cp_vrfy ${pregen_grid_dir}/fv3_grid_spec fv3sar_grid_spec.nc
  else
    if [ "${IO_LAYOUT_Y}" == "1" ]; then
      cp_vrfy ${pregen_grid_dir}/fv3_grid_spec fv3sar_grid_spec.nc
    else
      for iii in $(seq -w 0 $(printf %4.4i $n_iolayouty))
      do
        cp_vrfy ${pregen_grid_dir}/fv3_grid_spec.${iii} fv3sar_grid_spec.nc.${iii}
      done
    fi
  fi

#
#-----------------------------------------------------------------------
#
# link/copy observation files to working directory 
#
#-----------------------------------------------------------------------

  NSSL=${OBSPATH_NSSLMOSIAC}

  mrms="MergedReflectivityQC"

# Link to the MRMS operational data
  echo "timelevel = ${timelevel}"
  echo "RADARREFL_MINS = ${RADARREFL_MINS[@]}"

# Link to the MRMS operational data
# This loop finds files closest to the given "timelevel"
  for min in ${RADARREFL_MINS[@]}
  do
    min=$( printf %2.2i $((timelevel+min)) )
    echo "Looking for data valid:"${YYYY}"-"${MM}"-"${DD}" "${cyc}":"${min}
    sec=0
    while [[ $sec -le 59 ]]; do
      ss=$(printf %2.2i ${sec})
      nsslfile=${NSSL}/*${mrms}_00.50_${YYYY}${MM}${DD}-${cyc}${min}${ss}.${OBS_SUFFIX}
      if [ -s $nsslfile ]; then
        echo 'Found '${nsslfile}
        nsslfile1=*${mrms}_*_${YYYY}${MM}${DD}-${cyc}${min}*.${OBS_SUFFIX}
        numgrib2=$(ls ${NSSL}/${nsslfile1} | wc -l)
        echo 'Number of GRIB-2 files: '${numgrib2}
        if [ ${numgrib2} -ge 10 ] && [ ! -e filelist_mrms ]; then
          cp ${NSSL}/${nsslfile1} . 
          ls ${nsslfile1} > filelist_mrms 
          echo 'Creating links for ${YYYY}${MM}${DD}-${cyc}${min}'
        fi
      fi
      ((sec+=1))
    done
  done

  if [ -s filelist_mrms ]; then

     if [ ${OBS_SUFFIX} == "grib2.gz" ]; then
        gzip -d *.gz
        mv filelist_mrms filelist_mrms_org
        ls MergedReflectivityQC_*_${YYYY}${MM}${DD}-${cyc}????.grib2 > filelist_mrms
     fi

     numgrib2=$(more filelist_mrms | wc -l)
     print_info_msg "$VERBOSE" "Using radar data from: `head -1 filelist_mrms | cut -c10-15`"
     print_info_msg "$VERBOSE" "NSSL grib2 file levels = $numgrib2"
  else
     # remove filelist_mrms if zero bytes
     rm -f filelist_mrms

     echo "WARNING: Not enough radar reflectivity files available for loop ${timelevel}."
     continue
  fi


#-----------------------------------------------------------------------
#
# copy bufr table from fix directory
#
#-----------------------------------------------------------------------
  BUFR_TABLE=${FIXgsi}/prepobs_prep_RAP.bufrtable

  cp_vrfy $BUFR_TABLE prepobs_prep.bufrtable

#-----------------------------------------------------------------------
#
# Build namelist and run executable 
#
#   tversion      : data source version
#                   = 1 NSSL 1 tile grib2 for single level
#                   = 4 NSSL 4 tiles binary
#                   = 8 NSSL 8 tiles netcdf
#   fv3_io_layout_y : subdomain of restart files
#   analysis_time : process obs used for this analysis date (YYYYMMDDHH)
#   dataPath      : path of the radar reflectivity mosaic files.
#
#-----------------------------------------------------------------------

if [ ${BKTYPE} -eq 1 ]; then
  n_iolayouty=1
else
  n_iolayouty=$(($IO_LAYOUT_Y))
fi

cat << EOF > namelist.mosaic
   &setup
    tversion=1,
    analysis_time = ${YYYYMMDDHH},
    dataPath = './',
    fv3_io_layout_y=${n_iolayouty},
   /
EOF

if [ ${RADAR_REF_THINNING} -eq 2 ]; then
  # heavy data thinning, typically used for EnKF
  precipdbzhorizskip=1
  precipdbzvertskip=2
  clearairdbzhorizskip=5
  clearairdbzvertskip=-1
else
  if [ ${RADAR_REF_THINNING} -eq 1 ]; then
    # light data thinning, typically used for hybrid EnVar
    precipdbzhorizskip=0
    precipdbzvertskip=0
    clearairdbzhorizskip=1
    clearairdbzvertskip=1
  else
    # no data thinning
    precipdbzhorizskip=0
    precipdbzvertskip=0
    clearairdbzhorizskip=0
    clearairdbzvertskip=0
  fi
fi

cat << EOF > namelist.mosaic_netcdf
   &setup_netcdf
    output_netcdf = .true.,
    max_height = 11001.0,
    use_clear_air_type = .true.,
    precip_dbz_thresh = 10.0,
    clear_air_dbz_thresh = 5.0,
    clear_air_dbz_value = 0.0,
    precip_dbz_horiz_skip = ${precipdbzhorizskip},
    precip_dbz_vert_skip = ${precipdbzvertskip},
    clear_air_dbz_horiz_skip = ${clearairdbzhorizskip},
    clear_air_dbz_vert_skip = ${clearairdbzvertskip},
   / 
EOF

#
#-----------------------------------------------------------------------
#
# Copy the executable to the run directory.
#
#-----------------------------------------------------------------------
#
  exec_fn="process_NSSL_mosaic.exe"
  exec_fp="$EXECdir/${exec_fn}"
  
  if [ ! -f "${exec_fp}" ]; then
    print_err_msg_exit "\
  The executable specified in exec_fp does not exist:
    exec_fp = \"$exec_fp\"
  Build lightning process and rerun."
  fi

#
#
#-----------------------------------------------------------------------
#
# Run the process.
#
#-----------------------------------------------------------------------
#
  PREP_STEP
  eval $RUN_CMD_UTILS ${exec_fp} ${REDIRECT_OUT_ERR} || print_info_msg "\
    Call to executable to run radar refl process returned with nonzero exit code."
  POST_STEP

done # done with the timelevel for-loop
#
#-----------------------------------------------------------------------
#
# Print message indicating successful completion of script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
RADAR REFL PROCESS completed successfully!!!
Exiting script:  \"${scrfunc_fn}\"
In directory:    \"${scrfunc_dir}\"
========================================================================"
#
#-----------------------------------------------------------------------
#
# Restore the shell options saved at the beginning of this script/func-
# tion.
#
#-----------------------------------------------------------------------
#
{ restore_shell_opts; } > /dev/null 2>&1
