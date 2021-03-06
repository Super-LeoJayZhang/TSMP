#! /bin/ksh

always_cos(){
route "${cblue}>> always_cos${cnormal}"
route "${cblue}<< always_cos${cnormal}"
}

configure_cos(){
route "${cblue}>> configure_cos${cnormal}"
comment "   cp Makefile to cosmo dir"
   cp $rootdir/bldsva/intf_oas3/${mList[2]}/arch/$platform/config/Makefile $cosdir >> $log_file 2>> $err_file
check
   cp $rootdir/bldsva/intf_oas3/${mList[2]}/arch/$platform/config/Fopts $cosdir >> $log_file 2>> $err_file
check
  c_configure_cos
  if [[ $withOAS == "true" ]]; then
    cplFlag="-DCOUP_OAS_COS " 
  fi
  if [[ $cplscheme == "true" ]] ; then ; cplFlag+=" -DCPL_SCHEME_F " ; fi
  if [[ $readCLM == "true" ]] ; then ; cplFlag+=" -DREADCLM " ; fi 
  file=$cosdir/Fopts 
comment "   sed comflg to cos Makefile"
#  sed -i "s@__comflg__@$optComp -I$ncdfPath/include $cplInc -cpp -DGRIBDWD -DNETCDF -D__COSMO__ $cplFlag -DHYMACS@" $file >> $log_file 2>> $err_file
  sed -i "s@__comflg__@$optComp -I$ncdfPath/include -I$gribPath/include   $cplInc -cpp -DGRIBAPI -DNETCDF -D__COSMO__ $cplFlag -DHYMACS@" $file >> $log_file 2>> $err_file
check
comment "   sed ldflg to cos Makefile"
  sed -i "s@__ldflg__@@" $file >> $log_file 2>> $err_file
check
comment "   sed comF90 to cos Makefile"
  if [[ $profiling == "scalasca" ]]; then
    sed -i "s@__comF90__@scorep-mpif90@" $file >> $log_file 2>> $err_file
  else
    sed -i "s@__comF90__@$profComp $mpiPath/bin/mpif90@" $file >> $log_file 2>> $err_file
  fi
check
comment "   sed ld to cos Makefile"
  if [[ $profiling == "scalasca" ]]; then
    sed -i "s@__ld__@scorep-mpif90@" $file >> $log_file 2>> $err_file
  else
    sed -i "s@__ld__@$profComp $mpiPath/bin/mpif90@" $file >> $log_file 2>> $err_file
  fi
check
comment "   sed libs to cos Makefile, excluding the link to GRIBDWD, girbapi path $gribPath "
#  sed -i "s@__lib__@$gribPath/libgrib.a $cplLib -L$ncdfPath/lib/ -lnetcdff@" $file >> $log_file 2>> $err_file
  sed -i "s@__lib__@$cplLib -L$ncdfPath/lib/ -L$gribPath/lib/ -lgrib_api_f90 -lnetcdff@" $file >> $log_file 2>> $err_file
check
route "${cblue}<< configure_cos${cnormal}"
}

make_cos(){
route "${cblue}>> make_cos${cnormal}"
  c_make_cos
route "${cblue}<< make_cos${cnormal}"
}


substitutions_cos(){
route "${cblue}>> substitutions_cos${cnormal}"
 c_substitutions_cos
 comment "   cp ObjFiles & ObjDependencies in $cosdir"
   patch "$rootdir/bldsva/intf_oas3/${mList[2]}/arch/$platform/config/Obj*" $cosdir 
 check
   if [[ $withOASMCT == "true" ]] ; then
     comment "   sed replace old mod_prism includes from cos oas files"
       sed -i "s/mod_prism_proto/mod_prism/" $cosdir/src/oas3/oas_cos_vardef.F90 >> $log_file 2>> $err_file
     check
       sed -i "s/USE mod_prism.*//" $cosdir/src/oas3/oas_cos_rcv.F90 >> $log_file 2>> $err_file
     check
       sed -i "s/USE mod_prism.*//" $cosdir/src/oas3/oas_cos_snd.F90 >> $log_file 2>> $err_file
     check
       sed -i "s/USE mod_prism.*//" $cosdir/src/oas3/oas_cos_define.F90 >> $log_file 2>> $err_file
     check
   fi
route "${cblue}<< substitutions_cos${cnormal}"
}

setup_cos(){
route "${cblue}>> setupCos${cnormal}"

  c_setup_cos

route "${cblue}<< setupCos${cnormal}" 
}
