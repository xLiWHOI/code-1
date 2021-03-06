#include "cppdefs.h"
!-----------------------------------------------------------------------
!BOP
!
! !MODULE:  initialise - setup the entire model
!
! !INTERFACE:
   module initialise
!
! !DESCRIPTION:
!
! !USES:
   use register_all_variables
   use output_manager_core, only:output_manager_host=>host, type_output_manager_host=>type_host
   use time, only: CalDat,JulDay
   use output_manager
   IMPLICIT NONE
!
! !PUBLIC DATA MEMBERS:
   public                              :: init_model
   integer                             :: runtype=1
   logical                             :: dryrun=.false.
   logical                             :: list_variables=.false.
!
! !REVISION HISTORY:
!  Original author(s): Karsten Bolding & Hans Burchard

   type,extends(type_output_manager_host) :: type_getm_host
   contains
      procedure :: julian_day => getm_host_julian_day
      procedure :: calendar_date => getm_host_calendar_date
   end type
!
!EOP
!-----------------------------------------------------------------------

   contains

!-----------------------------------------------------------------------
!BOP
!
! !IROUTINE: init_model - initialise getm
!
! !INTERFACE:
   subroutine init_model(dstr,tstr)
!
! !USES:
   use kurt_parallel, only: init_parallel,myid
#ifdef GETM_PARALLEL
   use halo_mpi, only: init_mpi,print_MPI_info
#endif
   use output, only: init_output,do_output,restart_file,out_dir
   use output_processing
   use input,  only: init_input
   use domain, only: init_domain
   use domain, only: H
   use domain, only: iextr,jextr,imin,imax,ioff,jmin,jmax,joff,kmax
   use domain, only: xcord,ycord
   use domain, only: vert_cord,maxdepth,ga
   use time, only: init_time,update_time,write_time_string
   use time, only: start,timestr,timestep
   use time, only: julianday,secondsofday
   use m2d, only: init_2d,postinit_2d, z
   use getm_timers, only: init_getm_timers, tic, toc, TIM_INITIALIZE
#ifndef NO_3D
   use m2d, only: Uint,Vint
   use m3d, only: cord_relax,init_3d,postinit_3d, ssen,ssun,ssvn
#ifndef NO_BAROCLINIC
   use m3d, only: T
#endif
   use turbulence, only: init_turbulence
   use mtridiagonal, only: init_tridiagonal
   use rivers, only: init_rivers
   use variables_3d, only: avmback,avhback
#ifdef SPM
   use suspended_matter, only: init_spm
#endif
#ifdef _FABM_
   use getm_fabm, only: fabm_calc
   use getm_fabm, only: init_getm_fabm_fields
   use getm_fabm, only: init_getm_fabm
   use rivers, only: init_rivers_fabm
#endif
#ifdef GETM_BIO
   use bio, only: bio_calc
   use getm_bio, only: init_getm_bio
   use rivers, only: init_rivers_bio
#endif
#endif
   use meteo, only: init_meteo,do_meteo
   use integration,  only: MinN,MaxN
#ifndef NO_BAROCLINIC
   use eqstate, only: do_eqstate
#endif
   use exceptions
   IMPLICIT NONE
!
! !INPUT PARAMETERS:
   character(len=*)                    :: dstr,tstr
!
! !DESCRIPTION:
!  Reads the namelist and makes calls to the init functions of the
!  various model components.
!
! !REVISION HISTORY:
!  22Nov Author name Initial code
!
! !LOCAL VARIABLES:
   integer:: i,j
   character(len=8)          :: buf
   character(len=64)         :: runid
   character(len=80)         :: title
   logical                   :: parallel=.false.
   logical                   :: hotstart=.false.
   logical                   :: use_epoch=.false.
   logical                   :: save_initial=.false.
#if (defined GETM_PARALLEL && defined INPUT_DIR)
   character(len=PATH_MAX)   :: input_dir=INPUT_DIR
#else
   character(len=PATH_MAX)   :: input_dir='./'
#endif
   character(len=PATH_MAX)   :: hot_in=''

   character(len=16)         :: postfix

   namelist /param/ &
             dryrun,runid,title,parallel,runtype,  &
             hotstart,use_epoch,save_initial
!EOP
!-------------------------------------------------------------------------
!BOC
#ifdef DEBUG
   integer, save :: Ncall = 0
   Ncall = Ncall+1
   write(debug,*) 'init_model() # ',Ncall
#endif
#ifndef NO_TIMERS
   call init_getm_timers()
#endif
   ! Immediately start to time (rest of) init:
   call tic(TIM_INITIALIZE)

   ! We need to pass info about the input directory
#if 0
   call getarg(1,base_dir)
   if(len_trim(base_dir) .eq. 0) then
      call getenv("base_dir",base_dir)
   end if
   if(len_trim(base_dir) .gt. 0) then
      base_dir = trim(base_dir) // '/'
   end if
#endif

!
! In parallel mode it is imperative to let the instances
! "say hello" right away. For MPI this changes the working directory,
! so that input files can be read.
!
#ifdef GETM_PARALLEL
   call init_mpi()
#endif

#if (defined GETM_PARALLEL && defined INPUT_DIR)
   STDERR 'input_dir:'
   STDERR trim(input_dir)
#endif
!
! Open the namelist file to get basic run parameters.
!
   title='A descriptive title can be specified in the param namelist'
   open(NAMLST,status='unknown',file=trim(input_dir) // "/getm.inp")
   read(NAMLST,NML=param)

#ifdef NO_BAROCLINIC
   if(runtype .ge. 3) then
      FATAL 'getm not compiled for baroclinic runs'
      stop 'init_model()'
   end if
#endif

#ifdef NO_3D
   if(runtype .ge. 2) then
      FATAL 'getm not compiled for 3D runs'
      stop 'init_model()'
   end if
#endif

! call all modules init_ ... routines

   if (parallel) then
#ifdef GETM_PARALLEL
      call init_parallel(runid,input_dir)
#else
      STDERR 'You must define GETM_PARALLEL and recompile'
      STDERR 'in order to run in parallel'
      stop 'init_model()'
#endif
   end if

#if (defined GETM_PARALLEL && defined SLICE_MODEL)
    call getm_error('init_model()', &
         'SLICE_MODEL does not work with GETM_PARALLEL - for now')
#endif

   STDERR LINE
   STDERR 'getm: Started on  ',dstr,' ',tstr

   call print_version()
   call compilation_options()

   STDERR 'Initialising....'
   STDERR LINE
   LEVEL1 'the run id is: ',trim(runid)
   LEVEL1 'the title is:  ',trim(title)

   select case (runtype)
      case (1)
         LEVEL1 '2D run (hotstart=',hotstart,')'
      case (2)
         LEVEL1 '3D run - no density (hotstart=',hotstart,')'
      case (3)
         LEVEL1 '3D run - frozen density (hotstart=',hotstart,')'
      case (4)
         LEVEL1 '3D run - full (hotstart=',hotstart,')'
      case default
         FATAL 'A non valid runtype has been specified.'
         stop 'initialise()'
   end select

   call init_time(MinN,MaxN)
   if(use_epoch) then
      LEVEL2 'using "',start,'" as time reference'
   end if

   call init_domain(input_dir,runtype)

   call init_meteo(hotstart)

#ifndef NO_3D
   call init_rivers()
#endif

   call init_2d(runtype,timestep,hotstart)

#ifndef NO_3D
   if (runtype .gt. 1) then
      call init_3d(runtype,timestep,hotstart)
#ifndef CONSTANT_VISCOSITY
      call init_turbulence(60,trim(input_dir) // 'gotmturb.nml',kmax)
#else
      LEVEL3 'turbulent viscosity and diffusivity set to constant (-DCONSTANT_VISCOSITY)'
#endif
      LEVEL2 'background turbulent viscosity set to',avmback
      LEVEL2 'background turbulent diffusivity set to',avhback
      call init_tridiagonal(kmax)

#ifdef SPM
      call init_spm(trim(input_dir) // 'spm.inp',runtype)
#endif
#ifdef _FABM_
      call init_getm_fabm(trim(input_dir) // 'getm_fabm.inp',hotstart)
      call init_rivers_fabm
#endif
#ifdef GETM_BIO
      call init_getm_bio(trim(input_dir) // 'getm_bio.inp')
      call init_rivers_bio
#endif
   end if
#endif
   call init_output_processing()

   call init_register_all_variables(runtype)

   allocate(type_getm_host::output_manager_host)
   if (myid .ge. 0) then
      write(postfix,'(A,I4.4)') '.',myid
      call output_manager_init(fm,title,trim(postfix))
   else
      call output_manager_init(fm,title)
   end if

   call do_register_all_variables(runtype)
   if (list_variables) call fm%list()

!   call init_output(runid,title,start,runtype,dryrun,myid)
   call init_output(runid,title,start,runtype,dryrun,myid,MinN,MaxN,save_initial)

   close(NAMLST)

#if 0
   call init_waves(hotstart)
   call init_biology(hotstart)
#endif

   if (hotstart) then
      LEVEL1 'hotstart'
      if (myid .ge. 0) then
         write(buf,'(I4.4)') myid
         buf = '.' // trim(buf) // '.in'
      else
         buf = '.in'
      end if
      hot_in = trim(out_dir) //'/'// 'restart' // trim(buf)
      call restart_file(READING,trim(hot_in),MinN,runtype,use_epoch)
      LEVEL3 'MinN adjusted to ',MinN

#ifndef NO_3D
      if (runtype .ge. 2) then
         Uint=_ZERO_
         Vint=_ZERO_
      end if
#endif

#ifndef NO_BAROCLINIC
      if (runtype .ge. 3) call do_eqstate()
#endif
      call update_time(MinN)
      call write_time_string()
      LEVEL3 timestr
      MinN = MinN+1
#ifndef NO_3D
#ifdef _FABM_
      if (fabm_calc) then
         LEVEL2 'hotstart getm_fabm:'
         call init_getm_fabm_fields()
      end if
#endif
#endif
   end if

   call postinit_2d(runtype,timestep,hotstart)
#ifndef NO_3D
   if (runtype .gt. 1) then
      call postinit_3d(runtype,timestep,hotstart)
   end if
#endif

   call init_input(input_dir,MinN)

   call toc(TIM_INITIALIZE)
   ! The rest is timed with meteo and output.

   if(runtype .le. 2) then
      call do_meteo(MinN-1)
#ifndef NO_3D
#ifndef NO_BAROCLINIC
   else
      call do_meteo(MinN,T(:,:,kmax))
#endif
#endif
   end if

   call finalize_register_all_variables(runtype)

   if (.not. dryrun) then
      call output_manager_prepare_save(julianday, int(secondsofday), 0, int(MinN-1))
      if (save_initial) then
      call do_output_processing()
      call output_manager_save(julianday,secondsofday,MinN-1)
      end if
      call do_output(runtype,MinN-1,timestep)
   end if

#ifdef DEBUG
   write(debug,*) 'Leaving init_model()'
   write(debug,*)
#endif
   return
   end subroutine init_model
!EOC

!-----------------------------------------------------------------------

   subroutine getm_host_julian_day(self,yyyy,mm,dd,julian)
      class (type_getm_host), intent(in) :: self
      integer, intent(in)  :: yyyy,mm,dd
      integer, intent(out) :: julian
      call JulDay(yyyy,mm,dd,julian)
   end subroutine

   subroutine getm_host_calendar_date(self,julian,yyyy,mm,dd)
      class (type_getm_host), intent(in) :: self
      integer, intent(in)  :: julian
      integer, intent(out) :: yyyy,mm,dd
      call CalDat(julian,yyyy,mm,dd)
   end subroutine

   end module initialise

!-----------------------------------------------------------------------
! Copyright (C) 2001 - Hans Burchard and Karsten Bolding               !
!-----------------------------------------------------------------------
