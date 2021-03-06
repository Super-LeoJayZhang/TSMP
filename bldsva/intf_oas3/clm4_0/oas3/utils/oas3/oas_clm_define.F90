SUBROUTINE oas_clm_define(SDATM)

!---------------------------------------------------------------------
! Description:
!  This routine sends invariant CESM fields to OASIS3 coupler:
!      1) grid information
!      2) domain decomposition
!      3) coupling variable definition
!
! Current Code Owner: TR32, Z4: Prabhakar Shrestha
!    phone: 0228733453
!    email: pshrestha@uni-bonn.de
!
! History:
! Version    Date       Name
! ---------- ---------- ----
! 2.1.0        2016/02/29 Prabhakar Shrestha
! Implementation for CESM 1.2.1

! Code Description:
! Language: Fortran 90.
! Software Standards: "European Standards for Writing and
! Documenting Exchangeable Fortran 90 Code".
!==============================================================================

! Declarations:
!
! Modules used:

USE oas_clm_vardef
USE mod_prism_grids_writing
USE mod_prism_def_partition_proto
USE shr_strdata_mod
USE mct_mod
USE m_mpif, only : MP_REAL8 => MPI_REAL8
!==============================================================================

IMPLICIT NONE

!==============================================================================

! Local Parmaters 

TYPE(shr_strdata_type), INTENT(IN)      :: SDATM          !CLM GRID Information

! Local Variables
INTEGER                    :: igrid                       ! ids returned by prism_def_grid

INTEGER                    :: var_nodims(2)               ! 
INTEGER                    :: ipshape(2)                  ! 
INTEGER, ALLOCATABLE       :: igparal(:)                  ! shape of arrays passed to PSMILe
INTEGER                    :: NULOUT=6

INTEGER                    :: k, ji, jj, jg, jgm1              ! local loop indicees
INTEGER ,ALLOCATABLE       :: oas_mask(:)

CHARACTER(len=4)           :: clgrd='gclm'                  ! CPS

REAL(KIND=r8)              :: dx,dy
REAL(KIND=r8), ALLOCATABLE :: tmp_2D(:,:)                   ! Store Corners
REAL(KIND=r8), POINTER     :: dmask(:),zlon(:), zlat(:)     ! Global
REAL(KIND=r8), POINTER     :: dmask_s(:),zlon_s(:), zlat_s(:)     ! Local
INTEGER                    :: write_aux_files
INTEGER                    :: rank, nprocs                  ! CPS
!------------------------------------------------------------------------------
!- End of header
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
!- Begin Subroutine oas_clm_define 
!------------------------------------------------------------------------------

! Define coupling scheme between COSMO and CLM
#ifdef CPL_SCHEME_F
 cpl_scheme = .True.  !TRN Scheme
#else
 cpl_scheme = .False. !INV Scheme
#endif

 CALL MPI_Barrier(kl_comm, nerror)
 CALL MPI_Comm_Rank(kl_comm, rank, nerror)  
 IF (nerror /= 0) CALL prism_abort_proto(ncomp_id, 'MPI_Comm_Rank', 'Failure in oas_clm_define') 
 CALL MPI_Comm_Size ( kl_comm, nprocs, nerror )
 IF (nerror /= 0) CALL prism_abort_proto(ncomp_id, 'MPI_Comm_Size', 'Failure in oas_clm_define')

 ! Implicit assumption that always "1d" decomp is used in DATM
 ndlon    = SDATM%nxg                   ! Global Size
 ndlat    = SDATM%nyg                   ! Global Size
 start1d  = SDATM%gsmap%start(rank+1)
 length1d = SDATM%gsmap%length(rank+1)
 pe_loc1d = SDATM%gsmap%pe_loc(rank+1)

 ALLOCATE( dmask_s(length1d), stat = nerror )
 IF ( nerror > 0 ) THEN
   CALL prism_abort_proto( ncomp_id, 'oas_clm_define', 'Failure in allocating dmask_s' )
   RETURN
 ENDIF
 ALLOCATE( zlon_s(length1d), stat = nerror )
 IF ( nerror > 0 ) THEN
   CALL prism_abort_proto( ncomp_id, 'oas_clm_define', 'Failure in allocating zlon_s' )
   RETURN
 ENDIF
 ALLOCATE( zlat_s(length1d), stat = nerror )
 IF ( nerror > 0 ) THEN
   CALL prism_abort_proto( ncomp_id, 'oas_clm_define', 'Failure in allocating zlat_s' )
   RETURN
 ENDIF
 ! ALLOCATE variable exchange buffer for receive
 ALLOCATE( exfld(length1d,krcv), stat = nerror )
 IF ( nerror > 0 ) THEN
   CALL prism_abort_proto( ncomp_id, 'oas_clm_define', 'Failure in allocating exfld' )
   RETURN
 ENDIF

 !Mask
 k       = mct_aVect_indexRA(SDATM%grid%data,'mask')
 dmask_s = SDATM%grid%data%rAttr(k,:)

 ! Longitudes
 k       = mct_aVect_indexRA(SDATM%grid%data,'lon')
 zlon_s  = SDATM%grid%data%rAttr(k,:)

 ! Latitudes
 k       = mct_aVect_indexRA(SDATM%grid%data,'lat')
 zlat_s  = SDATM%grid%data%rAttr(k,:)

! ALLOCATE GLOBAL BUFFER
   ALLOCATE( dmask(ndlon*ndlat), stat = nerror )
   IF ( nerror > 0 ) THEN
     CALL prism_abort_proto( ncomp_id, 'oas_clm_define', 'Failure in allocating dmask' )
     RETURN
   ENDIF
   ALLOCATE( zlon(ndlon*ndlat), stat = nerror )
   IF ( nerror > 0 ) THEN
     CALL prism_abort_proto( ncomp_id, 'oas_clm_define', 'Failure in allocating zlon' )
     RETURN
   ENDIF
   ALLOCATE( zlat(ndlat*ndlon), stat = nerror )
   IF ( nerror > 0 ) THEN
     CALL prism_abort_proto( ncomp_id, 'oas_clm_define', 'Failure in allocating zlat' )
     RETURN
   ENDIF
 
 IF (rank == 0) THEN
   ALLOCATE( llmask(ndlon,ndlat,1), stat = nerror )
   IF ( nerror > 0 ) THEN
      CALL prism_abort_proto( ncomp_id, 'oas_clm_define', 'Failure in allocating llmask' )
      RETURN
   ENDIF
   ALLOCATE( tmp_2D(ndlon*ndlat,8), stat = nerror )
   IF ( nerror > 0 ) THEN
     CALL prism_abort_proto( ncomp_id, 'oas_clm_define', 'Failure in allocating tmp_2D' )
     RETURN
   ENDIF
   ALLOCATE(oas_mask(ndlon*ndlat))
   IF ( nerror > 0 ) THEN
      CALL prism_abort_proto( ncomp_id, 'oas_clm_define', 'Failure in allocating oas_mask' )
      RETURN
   ENDIF
 ENDIF !masterproc

 !CPS,  Gather data to master for writing grid files for OASIS3
 
 CALL MPI_Gatherv(dmask_s,length1d,  MP_REAL8, dmask,SDATM%gsmap%length, SDATM%gsmap%start -1 , MP_REAL8,0, kl_comm, nerror)
 CALL MPI_Gatherv( zlat_s,length1d,  MP_REAL8,  zlat,SDATM%gsmap%length, SDATM%gsmap%start -1 , MP_REAL8,0, kl_comm, nerror)
 CALL MPI_Gatherv( zlon_s,length1d,  MP_REAL8,  zlon,SDATM%gsmap%length, SDATM%gsmap%start -1, MP_REAL8,0, kl_comm, nerror)

 IF (rank == 0) THEN
   ! -----------------------------------------------------------------
   ! ... Define the elements, i.e. specify the corner points for each
   !     volume element. 
   !     We only need to give the 4 horizontal corners
   !     for a volume element plus the vertical position of the upper
   !     and lower face. Nevertheless the volume element has 8 corners.
   ! -----------------------------------------------------------------

   ! -----------------------------------------------------------------
   ! ... Define centers and corners 
   ! -----------------------------------------------------------------
   !  1: lower left corner. 2,: lower right corner.
   !  3: upper right corner. 4,: upper left corner.
   !
    
   ! Grid Resolution 
   dx    = ABS(zlon(2)-zlon(1))
   dy    = ABS(zlat(ndlon+1)-zlat(1))  

   tmp_2D(:,1) = zlon - dx*0.5_r8
   tmp_2D(:,2) = zlon + dx*0.5_r8
   tmp_2D(:,3) = tmp_2D(:,2)
   tmp_2D(:,4) = tmp_2D(:,1) 

   tmp_2D(:,5) = zlat - dy*0.5_r8
   tmp_2D(:,6) = tmp_2D(:,5) 
   tmp_2D(:,7) = zlat + dy*0.5_r8
   tmp_2D(:,8) = tmp_2D(:,7) 

   ! -----------------------------------------------------------------
   ! ... Define the mask
   ! -----------------------------------------------------------------
   DO jj = 1, ndlat
   DO ji = 1, ndlon
     jg    = (jj-1)*ndlon + ji
     IF ( dmask(jg) == 1 ) THEN        
        llmask(ji,jj,1) = .TRUE.
        oas_mask(jg)    = 0
     ELSE
        llmask(ji,jj,1) = .FALSE.
        oas_mask(jg)    = 1
     ENDIF
   ENDDO
   ENDDO

   WRITE(nulout,*) 'oasclm: oas_clm_define: Land point number / total number', COUNT(llmask), ndlon*ndlat
   WRITE(nulout,*) 'oasclm: oas_clm_define: Extent ', MINVAL(zlon), MAXVAL(zlon), MINVAL(zlat), MAXVAL(zlat)   

   CALL flush(nulout)

   ! -----------------------------------------------------------------
   ! ... Write info on OASIS auxillary files (if needed)
   ! ----------------------------------------------------------------
   CALL prism_start_grids_writing (write_aux_files)

  IF ( write_aux_files == 1 ) THEN
 
 
     CALL prism_write_grid (clgrd, ndlon*ndlat, 1, zlon, zlat)

     CALL prism_write_corner (clgrd, ndlon*ndlat, 1, 4, tmp_2D(:,1:4), tmp_2D(:,5:8))

     CALL prism_write_mask (clgrd, ndlon*ndlat, 1, oas_mask)

     CALL prism_terminate_grids_writing()
        
  ENDIF                      ! write_aux_files = 1

  WRITE(nulout,*) ' oasclm: oas_clm_define: prism_terminate_grids'
  CALL flush(nulout)

 ENDIF                       ! masterproc


 CALL MPI_Barrier(kl_comm, nerror)

 ! -----------------------------------------------------------------
 ! ... Define the partition 
 ! -----------------------------------------------------------------

 ! DATM uses simple 1D parallel decomposition for vectors
 ! stored in gsmap%gsize = ndlat*ndlon
 !           gsmap%start = global offsets, 
 !           gsmap%length = (ndlat*ndlon)/npes
 !           gspam%pe_loc = location of processors

  ALLOCATE(igparal(4), stat = nerror)  !Max 200
  IF ( nerror > 0 ) THEN
    CALL prism_abort_proto( ncomp_id, 'oas_clm_define', 'Failure in allocating igparal' )
    RETURN
  ENDIF

  ! Compute global offsets and local extents
  igparal(1) = 3                  ! ORANGE style partition
  igparal(2) = 1                  ! 1 segment per processor)
  igparal(3) = start1d - 1        ! Global offset
  igparal(4) = length1d           ! Local extent

  CALL prism_def_partition_proto( igrid, igparal, nerror )
  IF( nerror /= PRISM_Success )   CALL prism_abort_proto (ncomp_id, 'oas_clm_define',   &
            &                                                        'Failure in prism_def_partition' )

  WRITE(nulout,*) ' oasclm: oas_clm_define: prism_def_partition' 
  CALL flush(nulout)

  ! -----------------------------------------------------------------
  ! ... Variable definition
  ! ----------------------------------------------------------------

  ! Default values
  ssnd(1:nmaxfld)%laction=.FALSE.  ; srcv(1:nmaxfld)%laction=.FALSE.

  ssnd(1)%clname='CLM_TAUX'      !  zonal wind stress
  ssnd(2)%clname='CLM_TAUY'      !  meridional wind stress
  ssnd(3)%clname='CLMLATEN'      !  total latent heat flux (W/m**2)
  ssnd(4)%clname='CLMSENSI'      !  total sensible heat flux (W/m**2)
  ssnd(5)%clname='CLMINFRA'      ! emitted infrared (longwave) radiation (W/m**2)
  ssnd(6)%clname='CLMALBED'      ! direct albedo
  ssnd(7)%clname='CLMALBEI'      ! diffuse albedo
  ssnd(8)%clname='CLMCO2FL'      ! net CO2 flux (now only photosynthesis rate) (umol CO2 m-2s-1)
  ssnd(9)%clname='CLM_RAM1'      ! Aerodynamic resistance (s/m)   !CPS
  ssnd(10)%clname='CLM_RAH1'      ! Aerodynamic resistance (s/m)   !CPS
  ssnd(11)%clname='CLM_RAW1'      ! Aerodynamic resistance (s/m)   !CPS
  ssnd(12)%clname='CLM_TSF1'      ! Surface Temperature (K)   !CPS
  ssnd(13)%clname='CLM_QSF1'      ! Surface Humidity (kg/kg)   !CPS
  ssnd(14)%clname='CLMPHOTO'      ! photosynthesis rate (umol CO2 m-2s-1)
  ssnd(15)%clname='CLMPLRES'      ! plant respiration (umol CO2 m-2s-1)

  ssnd(101)%clname='CLMFLX01'    !  evapotranspiration fluxes sent to PFL for each soil layer  
  ssnd(102)%clname='CLMFLX02'
  ssnd(103)%clname='CLMFLX03'
  ssnd(104)%clname='CLMFLX04'
  ssnd(105)%clname='CLMFLX05'
  ssnd(106)%clname='CLMFLX06'
  ssnd(107)%clname='CLMFLX07'
  ssnd(108)%clname='CLMFLX08'
  ssnd(109)%clname='CLMFLX09'
  ssnd(110)%clname='CLMFLX10'

  srcv(1)%clname='CLMTEMPE'
  srcv(2)%clname='CLMUWIND'
  srcv(3)%clname='CLMVWIND'
  srcv(4)%clname='CLMSPWAT'   ! specific water vapor content
  srcv(5)%clname='CLMTHICK'   ! thickness of lowest level (m)
  srcv(6)%clname='CLMPRESS'   ! surface pressure (Pa)
  srcv(7)%clname='CLMDIRSW'   ! direct shortwave downward radiation (W/m2)
  srcv(8)%clname='CLMDIFSW'   ! diffuse shortwave downward radiation (W/m2)
  srcv(9)%clname='CLMLONGW'   ! longwave downward radiation (W/m2)
  srcv(10)%clname='CLMCVRAI'  ! convective rain precipitation      (kg/m2*s)
  srcv(11)%clname='CLMCVSNW'  ! convective snow precipitation      (kg/m2*s)
  srcv(12)%clname='CLMGSRAI'  ! gridscale rain precipitation
  srcv(13)%clname='CLMGSSNW'  ! gridscale snow precipitation
  srcv(14)%clname='CLMGRAUP'  ! gridscale graupel precipitation
  srcv(15)%clname='CLMCVPRE'  ! total convective precipitation
  srcv(16)%clname='CLMGSPRE'  ! total gridscale precipitation
  srcv(17)%clname='CLMCO2PP'  ! CO2 partial pressure (Pa)  !CMU

  !CMS: from 101 to 200 are the receiving fields from PFL to CLM
  srcv(101)%clname='CLMSAT01' ! water saturation received from PFL for each soil layer
  srcv(102)%clname='CLMSAT02'
  srcv(103)%clname='CLMSAT03'
  srcv(104)%clname='CLMSAT04'   
  srcv(105)%clname='CLMSAT05'  
  srcv(106)%clname='CLMSAT06'
  srcv(107)%clname='CLMSAT07' 
  srcv(108)%clname='CLMSAT08'  
  srcv(109)%clname='CLMSAT09'   
  srcv(110)%clname='CLMSAT10'  

  srcv(101)%level= 1 ! # of soil layer
  srcv(102)%level= 2
  srcv(103)%level= 3
  srcv(104)%level= 4   
  srcv(105)%level= 5  
  srcv(106)%level= 6
  srcv(107)%level= 7 
  srcv(108)%level= 8  
  srcv(109)%level= 9   
  srcv(110)%level= 10  

  srcv(101:110)%ref='SAT'  

  srcv(111)%clname='CLMPSI01' ! pressure head received from PFL for each soil layer
  srcv(112)%clname='CLMPSI02'
  srcv(113)%clname='CLMPSI03'
  srcv(114)%clname='CLMPSI04'   
  srcv(115)%clname='CLMPSI05'  
  srcv(116)%clname='CLMPSI06'
  srcv(117)%clname='CLMPSI07' 
  srcv(118)%clname='CLMPSI08'  
  srcv(119)%clname='CLMPSI09'   
  srcv(120)%clname='CLMPSI10'  
  
  srcv(111)%level= 1 ! # of soil layer
  srcv(112)%level= 2
  srcv(113)%level= 3
  srcv(114)%level= 4   
  srcv(115)%level= 5  
  srcv(116)%level= 6
  srcv(117)%level= 7 
  srcv(118)%level= 8  
  srcv(119)%level= 9   
  srcv(120)%level= 10  

  srcv(111:120)%ref='PSI'
 
! Send/Receive Variable Selection
#ifdef COUP_OAS_COS

 IF (cpl_scheme) THEN        
    ssnd(5:7)%laction  =.TRUE.
    ssnd(8)%laction    =.TRUE.
    ssnd(14)%laction   =.FALSE.
    ssnd(15)%laction   =.FALSE.
    ssnd(9:13)%laction =.TRUE.   
 ELSE
!    ssnd(1)%laction=.TRUE.
    ssnd(1:7)%laction  =.TRUE.
    ssnd(8)%laction    =.TRUE.
    ssnd(14)%laction   =.FALSE.
    ssnd(15)%laction   =.FALSE. 
 ENDIF                        

! srcv(1)%laction=.TRUE.
 srcv(1:9)%laction     =.TRUE.
 srcv(15:16)%laction   =.TRUE. ! Coupling only total convective and gridscale precipitations 
 srcv(17)%laction      =.TRUE. ! Always true
#endif

#ifdef COUP_OAS_PFL
  !SEND VARIABLES 101 to 110
  ssnd(101:110)%laction=.TRUE.
  !RECEIVE VARIABLES  101 to 120 
  srcv(101:110)%laction=.TRUE.
  srcv(111:120)%laction=.TRUE.
#endif

  var_nodims(1) = 1           ! Dimension number of exchanged arrays
  var_nodims(2) = 1           ! number of bundles (always 1 for OASIS3)

  ipshape(1) = 1              ! minimum index for each dimension of the coupling field array
  ipshape(2) = ndlon*ndlat    ! maximum index for each dimension of the coupling field array

  ! ... Announce send variables. 
  !
  DO ji = 1, nmaxfld
    IF ( ssnd(ji)%laction ) THEN 
            
      CALL prism_def_var_proto(ssnd(ji)%nid, ssnd(ji)%clname, igrid, &
                                     var_nodims, PRISM_Out, ipshape, PRISM_Real, nerror )
      IF ( nerror /= PRISM_Success )   CALL prism_abort_proto( ssnd(ji)%nid, 'oas_clm_define',   &
               &                                               'Failure in prism_def_var for '//TRIM(ssnd(ji)%clname))
    ENDIF
  END DO
  !
  ! ... Announce received variables. 
  !
  DO ji = 1, nmaxfld
    IF ( srcv(ji)%laction ) THEN 

    CALL prism_def_var_proto(srcv(ji)%nid, srcv(ji)%clname, igrid, &
                         var_nodims, PRISM_In, ipshape, PRISM_Real, nerror )
    IF ( nerror /= PRISM_Success )   CALL prism_abort_proto( srcv(ji)%nid, 'oas_clm_define',   &
               &                                               'Failure in prism_def_var for '//TRIM(srcv(ji)%clname))
    ENDIF
  END DO
      
  !
  !------------------------------------------------------------------
  ! End of definition phase
  !------------------------------------------------------------------
  IF (rank == 0) THEN
    DEALLOCATE( tmp_2D, dmask, zlon, zlat)
  ENDIF

  DEALLOCATE( zlon_s, zlat_s, dmask_s,igparal)

  ! must be done by coupled processors only (OASIS3)
  CALL prism_enddef_proto( nerror )

  IF ( nerror /= PRISM_Success )   CALL prism_abort_proto ( ncomp_id, 'oas_clm_define', 'Failure in prism_enddef')

 CALL MPI_Barrier(kl_comm, nerror)
 WRITE(nulout,*) 'oasclm: oas_clm_define: prism enddef' 
 CALL flush(nulout)

!------------------------------------------------------------------------------
!- End of the Subroutine
!------------------------------------------------------------------------------

END SUBROUTINE oas_clm_define
