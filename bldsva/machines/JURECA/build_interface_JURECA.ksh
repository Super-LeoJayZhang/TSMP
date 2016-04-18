#! /bin/ksh


getMachineDefaults(){
route "${cblue}>> getMachineDefaults${cnormal}"
  comment "   init lmod functionality"
  . /usr/local/software/lmod/lmod/init/ksh >> $log_file 2>> $err_file
  check
  comment "   source and load Modules on JURECA"
  . $rootdir/bldsva/machines/$platform/loadenvs >> $log_file 2>> $err_file
  check


  defaultMpiPath="$EBROOTPSMPI"
  defaultNcdfPath="$EBROOTNETCDFMINFORTRAN"
  defaultGrib1Path="/homea/slts/slts00/sandbox/grib1-DWD20061107.jureca_tc2015.07_psintel_opt_KGo2/lib"
  defaultGribapiPath="$EBROOTGRIB_API"
  defaultJasperPath="$EBROOTJASPER"
  defaultTclPath="$EBROOTTCL"
  defaultHyprePath="$EBROOTHYPRE"
  defaultSiloPath="$EBROOTSILO"

  # Default Compiler/Linker optimization
  defaultOptC="-O2"

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
comment "   copy JURECA module load script into rundirectory"
  cp $rootdir/bldsva/machines/$platform/loadenvs $rundir
check

mpitasks=$((numInst * ($nproc_cos + $nproc_clm + $nproc_pfl + $nproc_oas)))
nnodes=`echo "scale = 2; $mpitasks / $nppn" | bc | perl -nl -MPOSIX -e 'print ceil($_);'`


cat << EOF >> $rundir/tsmp_slm_run.bsh
#!/bin/bash

USAGE="sbatch <scriptname>"

# JUROPATEST module load intel-para/2014.11
# all in same directory, copy beforehand manually to $WORK

#SBATCH --job-name="TerrSysMP"
#SBATCH --nodes=$nnodes
#SBATCH --ntasks=$mpitasks
#SBATCH --ntasks-per-node=$nppn
#SBATCH --output=mpiMPMD-out.%j
#SBATCH --error=mpiMPMD-err.%j
#SBATCH --time=$wtime
#SBATCH --partition=$queue
#SBATCH --mail-type=ALL

source $rundir/loadenvs
date
rm -rf YU*
srun --multi-prog slm_multiprog_mapping.conf
date
echo "ready" > ready.txt
exit 0

EOF





counter=0

for instance in {$startInst..$(($numInst-1))}
do
start_oas=$counter
end_oas=$(($start_oas+$nproc_oas-1))

start_cos=$(($nproc_oas+$counter))
end_cos=$(($start_cos+$nproc_cos-1))

start_pfl=$(($nproc_cos+$nproc_oas+$counter))
end_pfl=$(($start_pfl+$nproc_pfl-1))

start_clm=$(($nproc_cos+$nproc_oas+$nproc_pfl+$counter))
end_clm=$(($start_clm+$nproc_clm-1))

counter=$(($counter+$nproc_clm+$nproc_pfl+$nproc_cos+$nproc_oas))
cat << EOF >> $rundir/slm_multiprog_mapping.conf
__oas__
__cos__
__pfl__
__clm__

EOF

comment "   sed executables and processors into mapping file"
	if [[ $withOAS == "false" ||  $withOASMCT == "true" ]] then ; sed "s/__oas__//" -i $rundir/slm_multiprog_mapping.conf  >> $log_file 2>> $err_file; check; fi

if [[ $withCOS == "true" && $withCLM == "false" ]] then
sed "s/__cos__/$start_cos-$end_cos  \.\/cos_starter.bsh $instance/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
fi
if [[ $withCLM == "true" && $withCOS == "false" && $withPFL == "false" ]] then
sed "s/__clm__/$start_clm-$end_clm  \.\/clm_starter.bsh $instance/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
fi
if [[ $withPFL == "true" && $withCLM == "false" ]] then
sed "s/__pfl__/$start_pfl-$end_pfl  \.\/pfl_starter.bsh $instance/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
fi
if [[ $withCOS == "true" && $withCLM == "true" && $withPFL == "false" ]] then
sed "s/__oas__/$start_oas  \.\/oasis3.MPI1.x/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
sed "s/__cos__/$start_cos-$end_cos  \.\/cos_starter.bsh $instance/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
sed "s/__clm__/$start_clm-$end_clm  \.\/clm_starter.bsh $instance/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
fi
if [[ $withPFL == "true" && $withCLM == "true" && $withCOS == "false" ]] then
sed "s/__oas__/$start_oas  \.\/oasis3.MPI1.x/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
sed "s/__clm__/$start_clm-$end_clm  \.\/clm_starter.bsh $instance/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
sed "s/__pfl__/$start_pfl-$end_pfl  \.\/pfl_starter.bsh $instance/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
fi
if [[ $withCOS == "true" && $withCLM == "true" && $withPFL == "true" ]] then
sed "s/__oas__/$start_oas  \.\/oasis3.MPI1.x/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
sed "s/__clm__/$start_clm-$end_clm  \.\/clm_starter.bsh $instance/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
sed "s/__pfl__/$start_pfl-$end_pfl  \.\/pfl_starter.bsh $instance/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
sed "s/__cos__/$start_cos-$end_cos  \.\/cos_starter.bsh $instance/" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
fi

sed "s/__oas__//" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
sed "s/__cos__//" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
sed "s/__pfl__//" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
sed "s/__clm__//" -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
sed '/^$/d' -i $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check



done





if [[ $numInst > 1 && ( $withOASMCT == "true" || $withOAS == "false"   ) ]] ; then

cat << EOF >> $rundir/cos_starter.bsh
#!/bin/bash
cd tsmp_instance_\$1
./lmparbin_pur
EOF

cat << EOF >> $rundir/clm_starter.bsh
#!/bin/bash
cd tsmp_instance_\$1
./clm
EOF

cat << EOF >> $rundir/pfl_starter.bsh
#!/bin/bash
cd tsmp_instance_\$1
./parflow $pflrunname
EOF

else

cat << EOF >> $rundir/cos_starter.bsh
#!/bin/bash
./lmparbin_pur
EOF

cat << EOF >> $rundir/clm_starter.bsh
#!/bin/bash
./clm
EOF

cat << EOF >> $rundir/pfl_starter.bsh
#!/bin/bash
./parflow $pflrunname
EOF

fi


comment "   change permission of module starter scripts"
chmod 755 $rundir/cos_starter.bsh >> $log_file 2>> $err_file
check
chmod 755 $rundir/clm_starter.bsh >> $log_file 2>> $err_file
check
chmod 755 $rundir/pfl_starter.bsh >> $log_file 2>> $err_file
check


comment "   change permission of runscript and mapfile"
chmod 755 $rundir/tsmp_slm_run.bsh >> $log_file 2>> $err_file
check
chmod 755 $rundir/slm_multiprog_mapping.conf >> $log_file 2>> $err_file
check
route "${cblue}<< createRunscript${cnormal}"
}

