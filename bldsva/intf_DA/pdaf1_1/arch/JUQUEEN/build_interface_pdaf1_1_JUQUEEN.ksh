#! /bin/ksh
#

always_da(){
route "${cblue}>> always_da${cnormal}"
route "${cblue}<< always_da${cnormal}"
}

substitutions_da(){
route "${cblue}>> substitutions_da${cnormal}"

  comment "   mkdir  $dadir/interface"
    mkdir -p $dadir/interface  >> $log_file 2>> $err_file
  check

  comment "   cp pdaf interface model to $dadir/interface"
    cp -R $rootdir/bldsva/intf_DA/pdaf1_1/model $dadir/interface >> $log_file 2>> $err_file
  check

  comment "   cp pdaf interface framework to $dadir/interface"
    cp -R $rootdir/bldsva/intf_DA/pdaf1_1/framework $dadir/interface >> $log_file 2>> $err_file
  check

route "${cblue}<< substitutions_da${cnormal}"
}

configure_da(){
route "${cblue}>> configure_da${cnormal}"
  export PDAF_DIR=$dadir
  export PDAF_ARCH=ibm_xlf_mpi

#PDAF part
  file=$dadir/make.arch/ibm_xlf_mpi.h
  
  comment "   cp pdaf config to $dadir"
    cp $rootdir/bldsva/intf_DA/pdaf1_1/arch/$platform/config/ibm_xlf_mpi.h $file >> $log_file 2>> $err_file
  check

  comment "   sed MPI dir to $file" 
    sed -i "s@__mpidir__@${mpiPath}@" $file >> $log_file 2>> $err_file  
  check

  comment "   sed LIBS to $file"
    sed -i "s@__LIBS__@ -L${lapackPath}/lib  -L/bgsys/local/lib -llapack -lesslbg @" $file >> $log_file 2>> $err_file
  check

  comment "   sed optimizations to $file"
    sed -i "s@__OPT__@${optComp}@" $file >> $log_file 2>> $err_file
  check

  comment "   cd to $dadir/src"
    cd $dadir/src >> $log_file 2>> $err_file
  check
  comment "   make clean pdaf"
    make clean >> $log_file 2>> $err_file
  check



#PDAF interface part
  file1=$dadir/interface/model/Makefile
  file2=$dadir/interface/framework/Makefile
  comment "   cp pdaf interface Makefiles to $dadir"
    cp $rootdir/bldsva/intf_DA/pdaf1_1/model/Makefile  $file1 >> $log_file 2>> $err_file
  check
    cp $rootdir/bldsva/intf_DA/pdaf1_1/framework/Makefile  $file2 >> $log_file 2>> $err_file
  check

  importFlags=" "
  cppdefs=" "
  fcppdefs=" "
  obj=' ' 
  libs=" "
  pf="-WF,"
 
  if [[ $withOAS == "false" && $withPFL == "true" ]] ; then
     importFlags+="-I$pfldir/pfsimulator/parflow_lib -I$pfldir/pfsimulator/amps/oas3 -I$pfldir/pfsimulator/include "
     cppdefs+=" -DPARFLOW_STAND_ALONE "
     fcppdefs+=" ${pf}-DPARFLOW_STAND_ALONE "
     libs+=" -L$hyprePath/lib -L$siloPath/lib -lparflow -lamps -lamps_common -lamps -lamps_common -lkinsol -lgfortran -lHYPRE -lsilo "
     obj+=' $(OBJPF) '
  fi

  if [[ $withOAS == "false" && $withCLM == "true" ]] ; then
     importFlags+=" -I$clmdir/build/ "
     fcppdefs+=" ${pf}-DCLMSA "
     libs+=" -lclm "
     obj+=' $(OBJCLM) print_update_clm.o'
  fi

  if [[ $withCLM == "true" && $withCOS == "true" && $withPFL == "false" ]] ; then
     importFlags+=" -I$clmdir/build/ -I$oasdir/$platform/build/lib/psmile.MPI1 -I$oasdir/$platform/build/lib/scrip -I$cosdir/obj "
     fcppdefs+=" ${pf}-Duse_comm_da ${pf}-DCOUP_OAS_COS ${pf}-DGRIBDWD ${pf}-DNETCDF ${pf}-DHYMACS ${pf}-DMAXPATCH_PFT=1 "
     if [[ $cplscheme == "true" ]] ; then ; fcppdefs+=" ${pf}-DCPL_SCHEME_F " ; fi
     if [[ $readCLM == "true" ]] ; then ; fcppdefs+=" ${pf}-DREADCLM " ; fi
     libs+=" -lclm -lcosmo -lpsmile.MPI1 -lmct -lmpeu -lscrip $grib1Path/libgrib1.a "
     obj+=' $(OBJCLM) $(OBJCOSMO) '
  fi 

  if [[ $withCLM == "true" && $withCOS == "false" && $withPFL == "true" ]] ; then
     importFlags+=" -I$clmdir/build/ -I$oasdir/$platform/build/lib/psmile.MPI1 -I$oasdir/$platform/build/lib/scrip -I$pfldir/pfsimulator/parflow_lib -I$pfldir/pfsimulator/amps/oas3 -I$pfldir/pfsimulator/include "
     cppdefs+=" -Duse_comm_da -DMAXPATCH_PFT=1 -DCOUP_OAS_PFL "
     fcppdefs+=" ${pf}-Duse_comm_da ${pf}-DCOUP_OAS_PFL ${pf}-DMAXPATCH_PFT=1 "
     if [[ $readCLM == "true" ]] ; then ; cppdefs+=" -DREADCLM " ; fcppdefs+=" ${pf}-DREADCLM " ; fi
     if [[ $freeDrain == "true" ]] ; then ; cppdefs+=" -DFREEDRAINAGE " ; fcppdefs+=" ${pf}-DFREEDRAINAGE " ; fi
     libs+=" -lclm -lpsmile.MPI1 -lmct -lmpeu -lscrip -L$hyprePath/lib -L$siloPath/lib -lparflow -lamps -lamps_common -lamps -lamps_common -lkinsol -lgfortran -lHYPRE -lsilo "
     obj+=' $(OBJCLM) $(OBJPF) '
  fi
  if [[ $withCLM == "true" && $withCOS == "true" && $withPFL == "true" ]] ; then
     importFlags+=" -I$clmdir/build/ -I$oasdir/$platform/build/lib/psmile.MPI1 -I$oasdir/$platform/build/lib/scrip -I$pfldir/pfsimulator/parflow_lib -I$pfldir/pfsimulator/amps/oas3 -I$pfldir/pfsimulator/include -I$cosdir/obj "
     cppdefs+=" -Duse_comm_da -DCOUP_OAS_COS -DGRIBDWD -DNETCDF -DHYMACS -DMAXPATCH_PFT=1 -DCOUP_OAS_PFL "
     fcppdefs+=" ${pf}-Duse_comm_da ${pf}-DCOUP_OAS_COS ${pf}-DGRIBDWD ${pf}-DNETCDF ${pf}-DHYMACS ${pf}-DMAXPATCH_PFT=1 ${pf}-DCOUP_OAS_PFL "
     if [[ $cplscheme == "true" ]] ; then ; cppdefs+=" -DCPL_SCHEME_F " ; fcppdefs+=" ${pf}-DCPL_SCHEME_F " ; fi
     if [[ $readCLM == "true" ]] ; then ; cppdefs+=" -DREADCLM " ; fcppdefs+=" ${pf}-DREADCLM " ; fi
     if [[ $freeDrain == "true" ]] ; then ; cppdefs+=" -DFREEDRAINAGE " ; fcppdefs+=" ${pf}-DFREEDRAINAGE " ; fi
     libs+=" -lclm -lpsmile.MPI1 -lmct -lmpeu -lscrip $grib1Path/libgrib1.a -L$hyprePath/lib -L$siloPath/lib -lparflow -lamps -lamps_common -lamps -lamps_common -lkinsol -lgfortran -lHYPRE -lsilo -lcosmo $grib1Path/libgrib1.a"
     obj+=' $(OBJCLM) $(OBJCOSMO) $(OBJPF) '
  fi

  libs+=" -L$mpiPath/lib -lmpich -L$ncdfPath/lib/ -lnetcdf "

  comment "   sed bindir to Makefiles"
    sed -i "s,__bindir__,$bindir," $file1 $file2 >> $log_file 2>> $err_file
  check
  comment "   sed comp flags to Makefiles"
    sed -i "s,__fflags__, -qfree=f90 -qextname=flush -qfullpath -I$dadir/interface/model -I$ncdfPath/include $importFlags," $file1 $file2 >> $log_file 2>> $err_file
  check
    sed -i "s,__ccflags__, -I$dadir/interface/model -I$ncdfPath/include $importFlags," $file1 $file2 >> $log_file 2>> $err_file
  check
  comment "   sed preproc flags to Makefiles"
    sed -i "s@__cpp_defs__@$cppdefs@" $file1 $file2 >> $log_file 2>> $err_file
  check
    sed -i "s@__fcpp_defs__@$fcppdefs@" $file1 $file2 >> $log_file 2>> $err_file
  check
  comment "   sed libs to Makefiles"
    sed -i "s,__libs__,$libs," $file2 >> $log_file 2>> $err_file
  check
  comment "   sed obj to Makefiles"
    sed -i "s,__obj__,$obj," $file1 >> $log_file 2>> $err_file
  check
  comment "   sed -D prefix to Makefiles"
    sed -i "s@__pf__@$pf@" $file1 $file2 >> $log_file 2>> $err_file
  check


  comment "   cd to $dadir/interface/model"
    cd $dadir/interface/model >> $log_file 2>> $err_file
  check
  comment "   make clean model"
    make clean >> $log_file 2>> $err_file
  check
  comment "   cd to $dadir/src/interface/framework"
    cd $dadir/interface/framework >> $log_file 2>> $err_file
  check
  comment "   make clean framework"
    make clean >> $log_file 2>> $err_file
  check


route "${cblue}<< configure_da${cnormal}"
}

make_da(){
route "${cblue}>> make_da${cnormal}"
  export PDAF_DIR=$dadir
  export PDAF_ARCH=ibm_xlf_mpi

  comment "   cd to $dadir/src"
    cd $dadir/src >> $log_file 2>> $err_file
  check
  comment "   make pdaf"
    make >> $log_file 2>> $err_file
  check

  comment "   cd to $dadir/interface/model"
    cd $dadir/interface/model >> $log_file 2>> $err_file
  check
  comment "   make pdaf model"
    make >> $log_file 2>> $err_file
  check

  comment "   cd to $dadir/interface/framework"
    cd $dadir/interface/framework >> $log_file 2>> $err_file
  check
  comment "   make pdaf framework"
    make >> $log_file 2>> $err_file
  check


route "${cblue}<< make_da${cnormal}"
}


setup_da(){
route "${cblue}>> setup_da${cnormal}"
  c_setup_pdaf
route "${cblue}<< setup_da${cnormal}"
}

