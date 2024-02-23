#!/bin/bash

#-------------------------------------------------------------------
#=====  Step 1: check out source code and  external compoments  ====
#-------------------------------------------------------------------

./manage_externals/checkout_externals

#-------------------------------------------------------------------
#=====  Step 2: create symbolic links for parm and ush  ============
#-------------------------------------------------------------------

cd ../parm
 rm -rf aqm_utils nexus_config ufs_utils upp
 cp -rp ../sorc/AQM-utils/parm  aqm_utils
 cp -rp ../sorc/arl_nexus/config nexus_config
 cp -rp ../sorc/UFS_UTILS/parm  ufs_utils
 cp -rp ../sorc/UPP/parm upp	
 
cd ../ush
 rm -rf aqm_utils_python nexus_utils
 cp -rp ../sorc/AQM-utils/python_utils  aqm_utils_python	
 cp -rp ../sorc/arl_nexus/utils  nexus_utils

