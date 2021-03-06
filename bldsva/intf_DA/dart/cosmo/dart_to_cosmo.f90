! DART software - Copyright UCAR. This open source software is provided
! by UCAR, "as is", without charge, subject to all terms of use at
! http://www.image.ucar.edu/DAReS/DART/DART_download
!
! DART $Id: dart_to_cosmo.f90 Wed Apr 11 20:26:43 CEST 2018 $

program dart_to_cosmo

!----------------------------------------------------------------------
! purpose: interface between DART and the cosmo model
!
! method: Read DART state vector and overwrite values in a cosmo restart file.
!         If the DART state vector has an 'advance_to_time' present, a
!         file called cosmo_in.DART is created with a time_manager_nml namelist 
!         appropriate to advance cosmo to the requested time.
!
!         The dart_to_cosmo_nml namelist setting for advance_time_present 
!         determines whether or not the input file has an 'advance_to_time'.
!         Typically, only temporary files like 'assim_model_state_ic' have
!         an 'advance_to_time'.
!----------------------------------------------------------------------

use        types_mod, only : r8

use    utilities_mod, only : initialize_utilities, finalize_utilities, &
                             find_namelist_in_file, check_namelist_read, &
                             logfileunit, open_file, close_file, E_ERR, &
                             E_MSG, error_handler

use  assim_model_mod, only : open_restart_read, aread_state_restart, close_restart

use time_manager_mod, only : time_type, print_time, print_date, operator(-), &
                             get_time, set_time

use        model_mod, only : get_model_size, static_init_model, &
                             write_cosmo_file, write_state_times

implicit none

! version controlled file description for error handling, do not edit
character(len=*), parameter :: source   = "$URL: dart_to_cosmo.f90 $"
character(len=*), parameter :: revision = "$Revision: Bonn $"
character(len=*), parameter :: revdate  = "$Date: Wed Apr 11 2018 $"

!------------------------------------------------------------------
! The namelist variables
!------------------------------------------------------------------

character(len=256) :: dart_output_file        = 'dart_posterior'
character(len=256) :: new_cosmo_analysis_file = 'cosmo_restart'
logical            :: advance_time_present    = .false.

namelist /dart_to_cosmo_nml/ dart_output_file,        &
                             new_cosmo_analysis_file, &
                             advance_time_present

!----------------------------------------------------------------------

integer               :: iunit, io, model_size
type(time_type)       :: model_time, adv_to_time
real(r8), allocatable :: state_vector(:)

!----------------------------------------------------------------------
! Read the namelist to get the output filename. 
!----------------------------------------------------------------------

call initialize_utilities(progname='dart_to_cosmo')

call find_namelist_in_file("input.nml", "dart_to_cosmo_nml", iunit)
read(iunit, nml = dart_to_cosmo_nml, iostat = io)
call check_namelist_read(iunit, io, "dart_to_cosmo_nml")

write(*,*)
write(*,'(''dart_to_cosmo:converting DART file "'',A, &
      &''" to cosmo file "'',A,''"'')') &
     trim(dart_output_file), trim(new_cosmo_analysis_file)

!----------------------------------------------------------------------
! Call model_mod:static_init_model() which reads the cosmo namelists
! to set grid sizes, etc.
!----------------------------------------------------------------------

call static_init_model()

model_size=get_model_size()

allocate(state_vector(1:model_size))

!----------------------------------------------------------------------
! Reads the valid time, the state, and the target time.
!----------------------------------------------------------------------

iunit = open_restart_read(dart_output_file)

if ( advance_time_present ) then
   call aread_state_restart(model_time, state_vector, iunit, adv_to_time)
else
   call aread_state_restart(model_time, state_vector, iunit)
endif
call close_restart(iunit)

!----------------------------------------------------------------------
! update the current cosmo state vector.
! The original restart file comes from input.nml:model_nml:cosmo_restart_file
! The DART posteriors come from the 'dart_output_file'.
! The intersection of the two is written as the 'new_cosmo_analysis_file'
!
! Convey the amount of time to integrate the model ...
! time_manager_nml: stop_option, stop_count increments
!----------------------------------------------------------------------

call write_cosmo_file(state_vector, dart_output_file, new_cosmo_analysis_file)

iunit = open_file('dart_posterior_times.txt', action='write')
call write_state_times(iunit, model_time)
call close_file(iunit)

!----------------------------------------------------------------------
! Log what we think we're doing, and exit.
!----------------------------------------------------------------------

call print_date( model_time,'dart_to_cosmo:cosmo model date')
call print_time( model_time,'dart_to_cosmo:DART  model time')
call print_date( model_time,'dart_to_cosmo:cosmo model date',logfileunit)
call print_time( model_time,'dart_to_cosmo:DART  model time',logfileunit)

if ( advance_time_present ) then
call print_time(adv_to_time,'dart_to_cosmo:advance_to time')
call print_date(adv_to_time,'dart_to_cosmo:advance_to date')
call print_time(adv_to_time,'dart_to_cosmo:advance_to time',logfileunit)
call print_date(adv_to_time,'dart_to_cosmo:advance_to date',logfileunit)
endif

call finalize_utilities()

end program dart_to_cosmo
