#! /bin/ksh


getMachineDefaults(){
route "${cblue}>> getMachineDefaults${cnormal}"
  comment "   init lmod functionality"
  . /gpfs/software/juwels/lmod/lmod/init/ksh >> $log_file 2>> $err_file
  check
  comment "   source and load Modules on JUWELS: loadenvs.$compiler"
  . $rootdir/bldsva/machines/$platform/loadenvs.$compiler >> $log_file 2>> $err_file
  check


  defaultMpiPath="$EBROOTPSMPI"
  defaultNcdfPath="$EBROOTNETCDFMINFORTRAN"
  #defaultGrib1Path="/gpfs/homea/slts/slts00/local/jureca/grib1_DWD/grib1-DWD20110128.jureca_tc2015.07_psintel_opt_KGo/lib"

  #CPS Remove hardwiring of compiler, introducing compiler switch 
#  if [[ $compiler == "Intel" ]] ; then
  #Intel GRIB
#  defaultGribPath="/p/project/cslts/local/juwels/grib1_DWD/lib/"

#  elif [[ $compiler == "Gnu" ]] ; then
  #GNU GRIB
#  defaultGrib1Path="/p/project/cslts/local/juwels/DWD-libgrib1_20110128/lib"
#  fi
  defaultGribPath="$EBROOTGRIB_API"
  defaultGribapiPath="$EBROOTGRIB_API"
  defaultJasperPath="$EBROOTJASPER"
  defaultTclPath="$EBROOTTCL"
  defaultHyprePath="$EBROOTHYPRE"
  defaultSiloPath="$EBROOTSILO"
  defaultLapackPath="$EBROOTIMKL"
  defaultPncdfPath="$EBROOTPARALLELMINNETCDF"

  # Default Compiler/Linker optimization
  defaultOptC="-O2"

  profilingImpl=" no scalasca "  
  if [[ $profiling == "scalasca" ]] ; then ; profComp="" ; profRun="scalasca -analyse" ; profVar=""  ;fi

  # Default Processor settings
  defaultwtime="01:00:00"
  defaultQ="batch"

route "${cblue}<< getMachineDefaults${cnormal}"
}

finalizeMachine(){
route "${cblue}>> finalizeMachine${cnormal}"
route "${cblue}<< finalizeMachine${cnormal}"
}


createRunscript(){
route "${cblue}>> createRunscript${cnormal}"
comment "   copy JUWELS module load script into rundirectory"
  cp $rootdir/bldsva/machines/$platform/loadenvs.$compiler $rundir/loadenvs
check

mpitasks=$((numInst * ($nproc_icon + $nproc_cos + $nproc_clm + $nproc_pfl + $nproc_oas)))
nnodes=`echo "scale = 2; $mpitasks / $nppn" | bc | perl -nl -MPOSIX -e 'print ceil($_);'`

#DA
if [[ $withPDAF == "true" ]] ; then
  srun="srun -n $mpitasks ./tsmp-pdaf -n_modeltasks $(($numInst-$startInst)) -filtertype 2 -subtype 1 -delt_obs $delta_obs -rms_obs 0.03 -obs_filename swc_crp"
else
  srun="srun --multi-prog slm_multiprog_mapping.conf"
fi

cat << EOF >> $rundir/tsmp_slm_run.bsh
#!/bin/bash

#SBATCH --job-name="TerrSysMP"
#SBATCH --nodes=$nnodes
#SBATCH --ntasks=$mpitasks
#SBATCH --ntasks-per-node=$nppn
#SBATCH --output=mpiMPMD-out.%j
#SBATCH --error=mpiMPMD-err.%j
#SBATCH --time=$wtime
#SBATCH --partition=$queue
#SBATCH --mail-type=NONE
#SBATCH --account=hbn33 

export PSP_RENDEZVOUS_OPENIB=-1

cd $rundir
source $rundir/loadenvs
date
echo "started" > started.txt
rm -rf YU*
export $profVar
$srun
date
echo "ready" > ready.txt
exit 0

EOF





counter=0
#for mapfile
start_oas=$counter
end_oas=$(($start_oas+$nproc_oas-1))

start_cos=$(($nproc_oas+$counter))
end_cos=$(($start_cos+($numInst*$nproc_cos)-1))

start_icon=$(($nproc_oas+$counter))
end_icon=$(($start_icon+($numInst*$nproc_icon)-1))

start_pfl=$(($numInst*($nproc_cos+$nproc_icon)+$nproc_oas+$counter))
end_pfl=$(($start_pfl+($numInst*$nproc_pfl)-1))

start_clm=$((($numInst*($nproc_cos+$nproc_icon))+$nproc_oas+($numInst*$nproc_pfl)+$counter))
end_clm=$(($start_clm+($numInst*$nproc_clm)-1))

if [[ $numInst > 1 &&  $withOASMCT == "true" ]] then
 for instance in {$startInst..$(($startInst+$numInst-1))}
 do
  for iter in {1..$nproc_cos}
  do
    if [[ $withCOS == "true" ]] then ; echo $instance >>  $rundir/instanceMap.txt ;fi
    if [[ $withICON == "true" ]] then ; echo $instance >>  $rundir/instanceMap.txt ;fi
  done
 done
fi

if [[ $numInst > 1 &&  $withOASMCT == "true" ]] then
 for instance in {$startInst..$(($startInst+$numInst-1))}
 do
  for iter in {1..$nproc_icon}
  do
    if [[ $withICON == "true" ]] then ; echo $instance >>  $rundir/instanceMap.txt ;fi
  done
 done
 for instance in {$startInst..$(($startInst+$numInst-1))}
 do
  for iter in {1..$nproc_pfl}
  do
    if [[ $withPFL == "true" ]] then ; echo $instance >>  $rundir/instanceMap.txt ;fi
  done
 done
 for instance in {$startInst..$(($startInst+$numInst-1))}
 do
  for iter in {1..$nproc_clm}
  do
    if [[ $withCLM == "true" ]] then ; echo $instance >>  $rundir/instanceMap.txt ;fi
  done
 done
fi


if [[ $withCOS == "true" ]]; then
cat << EOF >> $rundir/slm_multiprog_mapping.conf
__oas__
__cos__
__pfl__
__clm__

EOF
else
cat << EOF >> $rundir/slm_multiprog_mapping.conf
__oas__
__icon__
__pfl__
__clm__

EOF
fi

comment "   sed executables and processors into mapping file"
	if [[ $withOAS == "false" ||  $withOASMCT == "true" ]] then ; sed "s/__oas__//" -i $rundir/slm_multiprog_mapping.conf  >> $log_file 2>> $err_file; check; fi
	if [[ $withCOS == "false" ]] then ; sed "s/__cos__//" -i $rundir/slm_multiprog_mapping.conf  >> $log_file 2>> $err_file; check; fi
	if [[ $withICON == "false" ]] then ; sed "s/__icon__//" -i $rundir/slm_multiprog_mapping.conf  >> $log_file 2>> $err_file; check; fi
        if [[ $withPFL == "false" ]] then ; sed "s/__pfl__//" -i $rundir/slm_multiprog_mapping.conf  >> $log_file 2>> $err_file; check; fi
        if [[ $withCLM == "false" ]] then ; sed "s/__clm__//" -i $rundir/slm_multiprog_mapping.conf  >> $log_file 2>> $err_file; check; fi


sed "s/__oas__/$start_oas  $profRun \.\/oasis3.MPI1.x/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
sed "s/__cos__/$start_cos-$end_cos  $profRun \.\/lmparbin_pur/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
sed "s/__icon__/$start_icon-$end_icon  $profRun \.\/icon/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
sed "s/__pfl__/$start_pfl-$end_pfl  $profRun \.\/parflow $pflrunname/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
sed "s/__clm__/$start_clm-$end_clm  $profRun \.\/clm/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check



comment "   change permission of runscript and mapfile"
chmod 755 $rundir/tsmp_slm_run.bsh >> $log_file 2>> $err_file
check
chmod 755 $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
route "${cblue}<< createRunscript${cnormal}"
}

