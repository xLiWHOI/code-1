#include "cppdefs.h"
!-----------------------------------------------------------------------
!BOP
!
! !MODULE: ncdf_meteo -
!
! !INTERFACE:
   module ncdf_meteo
!
! !DESCRIPTION:
!
! !USES:
   use netcdf
   use time, only: string_to_julsecs,time_diff,add_secs,in_interval
   use time, only: jul0,secs0,julianday,secondsofday,timestep,simtime
   use time, only: write_time_string,timestr
   use domain, only: imin,imax,jmin,jmax,az,lonc,latc,convc
   use grid_interpol, only: init_grid_interpol,do_grid_interpol
   use grid_interpol, only: to_rotated_lat_lon
   use meteo, only: meteo_file,on_grid,calc_met,met_method,hum_method
   use meteo, only: RELATIVE_HUM,WET_BULB,DEW_POINT,SPECIFIC_HUM
   use meteo, only: airp,u10,v10,t2,hum,tcc
   use meteo, only: fwf_method,evap,precip
   use meteo, only: tausx,tausy,swr,shf
   use meteo, only: new_meteo,t_1,t_2
   use meteo, only: evap_factor,precip_factor
   use exceptions
   IMPLICIT NONE
!
   private
!
! !PUBLIC MEMBER FUNCTIONS:
   public init_meteo_input_ncdf,get_meteo_data_ncdf
!
! !PRIVATE DATA MEMBERS:
   REALTYPE        :: offset
   integer         :: ncid,ndims,dims(3)
   integer         :: start(3),edges(3)
   integer         :: u10_id,v10_id,airp_id,t2_id
   integer         :: hum_id,convp_id,largep_id,tcc_id
   integer         :: evap_id=-1,precip_id=-1
   integer         :: tausx_id,tausy_id,swr_id,shf_id
   integer         :: iextr,jextr,textr,tmax=-1
   integer         :: grid_scan=1
   logical         :: point_source=.false.
   logical         :: rotated_meteo_grid=.false.

   REALTYPE, allocatable     :: met_lon(:),met_lat(:)
   REALTYPE, allocatable     :: met_times(:)
   REAL_4B, allocatable      :: wrk(:,:)
   REALTYPE, allocatable     :: wrk_dp(:,:)

!  For gridinterpolation
   REALTYPE, allocatable     :: beta(:,:)
   REALTYPE, allocatable     :: ti(:,:),ui(:,:)
   integer, allocatable      :: gridmap(:,:,:)
!
   REALTYPE, parameter       :: pi=3.1415926535897932384626433832795029
   REALTYPE, parameter       :: deg2rad=pi/180.,rad2deg=180./pi
   REALTYPE                  :: southpole(3) = (/0.0,-90.0,0.0/)
   character(len=10)         :: name_lon="lon"
   character(len=10)         :: name_lat="lat"
   character(len=10)         :: name_time="time"
   character(len=10)         :: name_u10="u10"
   character(len=10)         :: name_v10="v10"
   character(len=10)         :: name_airp="slp"
   character(len=10)         :: name_t2="t2"
   character(len=10)         :: name_hum1="sh"
   character(len=10)         :: name_hum2="rh"
   character(len=10)         :: name_hum3="dev2"
   character(len=10)         :: name_hum4="twet"
   character(len=10)         :: name_tcc="tcc"
   character(len=10)         :: name_evap="evap"
   character(len=10)         :: name_precip="precip"

   character(len=10)         :: name_tausx="tausx"
   character(len=10)         :: name_tausy="tausy"
   character(len=10)         :: name_swr="swr"
   character(len=10)         :: name_shf="shf"
   character(len=128)        :: model_time
!
! !REVISION HISTORY:
!  Original author(s): Karsten Bolding & Hans Burchard
!
!EOP
!-----------------------------------------------------------------------

   contains

!-----------------------------------------------------------------------
!BOP
!
! !IROUTINE: init_meteo_input_ncdf -
!
! !INTERFACE:
   subroutine init_meteo_input_ncdf(fn,nstart)
   IMPLICIT NONE
!
! !DESCRIPTION:
!  Prepares reading meteorological forcing from a NetCDF formatted file.
!  Based on names of various variables the corresponding variable ids
!  are obtained from the NetCDF file.
!  The dimensions of the meteological grid is read (x,y,t).
!  If the southpole is not (0,-90,0) a rotated grid is assumed and
!  coefficients for interpolation between the meteorological grid and
!  the model grid are calculated.
!  The arry \emph{met\_times} are filled with the times where forcing is
!  available.
!  Finally, meteorological fields are initialised by a call to
!  \emph{get\_meteo\_data\_ncdf}.
!
! !INPUT PARAMETERS:
   character(len=*), intent(in)        :: fn
   integer, intent(in)                 :: nstart
!
! !REVISION HISTORY:
!
!  See module for log.
!
! !LOCAL VARIABLES:
   integer         :: i,j,n
   integer         :: err
   logical         :: ok=.true.
   REALTYPE        :: olon,olat,rlon,rlat,x
   character(len=10) :: name_thisvar
!EOP
!-------------------------------------------------------------------------
#ifdef DEBUG
   integer, save :: Ncall = 0
   Ncall = Ncall+1
   write(debug,*) 'init_meteo_input_ncdf() # ',Ncall
#endif

   call open_meteo_file(meteo_file)

   allocate(wrk(iextr,jextr),stat=err)
   if (err /= 0) stop 'ncdf_meteo: Error allocating memory (wrk)'
   wrk = 0.

   allocate(wrk_dp(iextr,jextr),stat=err)
   if (err /= 0) stop 'ncdf_meteo: Error allocating memory (wrk_dp)'
   wrk_dp = _ZERO_

   allocate(beta(E2DFIELD),stat=err)
   if (err /= 0) &
       stop 'init_meteo_input_ncdf: Error allocating memory (beta)'
   beta = _ZERO_

   if(iextr .eq. 1 .and. jextr .eq. 1) then
      point_source = .true.
      LEVEL3 'Assuming Point Source meteo forcing'
      if ( .not. on_grid) then
         LEVEL3 'Setting on_grid to true'
         on_grid=.true.
      end if
      if (rotated_meteo_grid) then
         rlon=met_lon(1)
         rlat=met_lat(1)
         call to_rotated_lat_lon(southpole,olon,olat,rlon,rlat,x)
         beta = x
      end if
   else
      if (met_lat(1) .gt. met_lat(2)) then
         LEVEL3 'Reverting lat-axis and setting grid_scan to 0'
         grid_scan = 0
         x = met_lat(1)
         do j=1,jextr/2
            met_lat(j) = met_lat(jextr-j+1)
            met_lat(jextr-j+1) = x
            x = met_lat(j+1)
         end do
      end if
   end if

   if ( .not. on_grid ) then

      allocate(ti(E2DFIELD),stat=err)
      if (err /= 0) &
          stop 'init_meteo_input_ncdf: Error allocating memory (ti)'
      ti = -999.

      allocate(ui(E2DFIELD),stat=err)
      if (err /= 0) stop &
              'init_meteo_input_ncdf: Error allocating memory (ui)'
      ui = -999.

      allocate(gridmap(E2DFIELD,1:2),stat=err)
      if (err /= 0) stop &
              'init_meteo_input_ncdf: Error allocating memory (gridmap)'
      gridmap(:,:,:) = -999

      call init_grid_interpol(imin,imax,jmin,jmax,az,  &
                lonc,latc,met_lon,met_lat,southpole,gridmap,beta,ti,ui)

      LEVEL2 "Checking interpolation coefficients"
      do j=jmin,jmax
         do i=imin,imax
            if ( az(i,j) .gt. 0 .and. &
                (ui(i,j) .lt. _ZERO_ .or. ti(i,j) .lt. _ZERO_ )) then
               ok=.false.
               LEVEL3 "error at (i,j) ",i,j
            end if
         end do
      end do
      if ( ok ) then
         LEVEL2 "done"
      else
         call getm_error("init_meteo_input_ncdf()", &
                          "Some interpolation coefficients are not valid")
      end if
   end if

   if (calc_met) then
      name_thisvar = name_u10
      err = nf90_inq_varid(ncid,name_u10,u10_id)
      if (err .NE. NF90_NOERR) go to 10

      name_thisvar = name_v10
      err = nf90_inq_varid(ncid,name_v10,v10_id)
      if (err .NE. NF90_NOERR) go to 10

      name_thisvar = name_airp
      err = nf90_inq_varid(ncid,name_airp,airp_id)
      if (err .NE. NF90_NOERR) go to 10

      name_thisvar = name_t2
      err = nf90_inq_varid(ncid,name_t2,t2_id)
      if (err .NE. NF90_NOERR) go to 10

      hum_id = -1
      err = nf90_inq_varid(ncid,name_hum1,hum_id)
      if (err .NE. NF90_NOERR) then
         err = nf90_inq_varid(ncid,name_hum2,hum_id)
         if (err .NE. NF90_NOERR) then
            err = nf90_inq_varid(ncid,name_hum3,hum_id)
            if (err .NE. NF90_NOERR) then
               FATAL 'Not able to find valid humidity parameter'
               stop 'init_meteo_input_ncdf()'
            else
               LEVEL2 'Taking hum as dew point temperature'
               hum_method = DEW_POINT
            end if
         else
            LEVEL2 'Taking hum as relative humidity'
            hum_method = RELATIVE_HUM
         end if
      else
         LEVEL2 'Taking hum as atmospheric specific humidity'
         hum_method = SPECIFIC_HUM
      end if
!KBKSTDERR 'Taking hum as wet bulb temperature'

      name_thisvar = name_tcc
      err = nf90_inq_varid(ncid,name_tcc,tcc_id)
      if (err .NE. NF90_NOERR) go to 10

      if (fwf_method .eq. 2) then
         name_thisvar = name_evap
         err = nf90_inq_varid(ncid,name_evap,evap_id)
         if (err .NE. NF90_NOERR) go to 10
      end if
      if (fwf_method .eq. 2 .or. fwf_method .eq. 3) then
         name_thisvar = name_precip
         err = nf90_inq_varid(ncid,name_precip,precip_id)
         if (err .NE. NF90_NOERR) go to 10
      end if

   else

      name_thisvar = name_tausx
      err = nf90_inq_varid(ncid,name_tausx,tausx_id)
      if (err .NE. NF90_NOERR) go to 10

      name_thisvar = name_tausy
      err = nf90_inq_varid(ncid,name_tausy,tausy_id)
      if (err .NE. NF90_NOERR) go to 10

      name_thisvar = name_swr
      err = nf90_inq_varid(ncid,name_swr,swr_id)
      if (err .NE. NF90_NOERR) go to 10

      name_thisvar = name_shf
      err = nf90_inq_varid(ncid,name_shf,shf_id)
      if (err .NE. NF90_NOERR) go to 10

   end if

   if (met_method .eq. 2) then
      start(1) = 1; start(2) = 1;
      edges(1) = iextr; edges(2) = jextr;
      edges(3) = 1
      call get_meteo_data_ncdf(nstart-1)
   end if

#ifdef DEBUG
   write(debug,*) 'Leaving init_meteo_input_ncdf()'
   write(debug,*)
#endif
   return
10 FATAL 'init_meteo_input_ncdf: ',name_thisvar,' ',nf90_strerror(err)
   stop
   end subroutine init_meteo_input_ncdf
!EOC

!-----------------------------------------------------------------------
!BOP
!
! !IROUTINE: get_meteo_data_ncdf - .
!
! !INTERFACE:
   subroutine get_meteo_data_ncdf(loop)
   IMPLICIT NONE
!
! !DESCRIPTION:
!  Do book keeping about when new fields are to be read. Set variables
!  used by \emph{do\_meteo} and finally calls \emph{read\_data} if
!  necessary.
!
! !INPUT PARAMETERS:
   integer, intent(in)                 :: loop
!
! !REVISION HISTORY:
!
!  See module for log.
!
! !LOCAL VARIABLES:
   integer         :: i,indx
   REALTYPE        :: t
   logical, save   :: first=.true.
   integer, save   :: save_n=1
   integer         :: j,s
   character(len=19) :: met_str
!EOP
!-------------------------------------------------------------------------
#ifdef DEBUG
   integer, save   :: Ncall = 0
   Ncall = Ncall+1
   write(debug,*) 'get_meteo_data_ncdf() # ',Ncall
#endif

   if (met_method .eq. 2) then

!     find the right index

      t = loop*timestep
      do indx=save_n,tmax
         if (met_times(indx) .gt. t + offset) EXIT
      end do
      if (first) then
         indx = indx-1
         if (indx .eq. 0) indx = 1
      end if
!     end of simulation?

      if (indx .gt. tmax) then
         LEVEL2 'Need new meteo file'
         call open_meteo_file(meteo_file)
         do indx=1,tmax
            if (met_times(indx) .gt. t + offset) EXIT
         end do
         save_n = indx-1 ! to force reading below
      end if
      start(3) = indx

      ! First time through we have to initialize t_1
      if (first) then
         first = .false.
         new_meteo = .true.
         call write_time_string()
         call add_secs(jul0,secs0,nint(met_times(indx)-offset),j,s)
         call write_time_string(j,s,met_str)
         LEVEL3 timestr,': reading meteo data - ',met_str
         t_1 = met_times(indx) - offset
         t_2 = t_1
         call read_data()
      else
         if (indx .gt. save_n) then
            new_meteo = .true.
            call write_time_string()
            call add_secs(jul0,secs0,nint(met_times(indx)-offset),j,s)
            call write_time_string(j,s,met_str)
            LEVEL3 timestr,': reading meteo data - ',met_str
            t_1 = t_2
            t_2 = met_times(indx) - offset
            call read_data()
         else
            new_meteo = .false.
         end if
      end if
      save_n = indx ! index of the last time read
   end if

#ifdef DEBUG
   write(debug,*) 'Leaving get_meteo_data_ncdf()'
   write(debug,*)
#endif
   return
   end subroutine get_meteo_data_ncdf
!EOC

!-----------------------------------------------------------------------
!BOP
!
! !IROUTINE: open_meteo_file - .
!
! !INTERFACE:
   subroutine open_meteo_file(meteo_file)
   IMPLICIT NONE
!
! !DESCRIPTION:
!  Instead of specifying the name of the meteorological file directly - a list
!  of names can be specified in \emph{meteo\_file}. The rationale for this
!  approach is that output from operational meteorological models are of
!  typically 2-5 days length. Collecting a number of these files allows for
!  longer model integrations without have to reformat the data.
!  It is assumed that the different files contains the same variables
!  and that they are of the same shape.
!
! !INPUT PARAMETERS:
   character(len=*), intent(in)        :: meteo_file
!
! !REVISION HISTORY:
!
!  See module for log.
!
! !LOCAL VARIABLES:
   integer, parameter        :: iunit=55
   character(len=256)        :: fn,time_units
   integer         :: junit,sunit,j1,s1,j2,s2
   integer         :: n,err,idum
   logical         :: first=.true.
   logical         :: found=.false.,first_open=.true.
   integer, save   :: lon_id=-1,lat_id=-1,time_id=-1,id=-1
   integer, save   :: time_var_id=-1
   character(len=256) :: dimname
   logical         :: have_southpole
   character(len=19) :: str1,str2
!
!EOP
!-------------------------------------------------------------------------
#ifdef DEBUG
   integer, save   :: Ncall = 0
   Ncall = Ncall+1
   write(debug,*) 'open_meteo_file() # ',Ncall
#endif

   if (first) then
      first = .false.
      open(iunit,file=meteo_file,status='old',action='read',err=80)
      do
         if (found) EXIT
         read(iunit,*,err=85,end=90) fn
         LEVEL3 'Trying meteo from:'
         LEVEL4 trim(fn)
         err = nf90_open(fn,NF90_NOWRITE,ncid)
         if (err .ne. NF90_NOERR) go to 10

         if (first_open) then
            first_open = .false.
            err = nf90_inquire(ncid,nDimensions=ndims)
            if (err .NE. NF90_NOERR) go to 10

            LEVEL4 'dimensions'
            do n=1,ndims
               err = nf90_inquire_dimension(ncid,n,name=dimname)
               if (err .ne. NF90_NOERR) go to 10
               if( dimname .eq. name_lon ) then
                  lon_id = n
                  err = nf90_inquire_dimension(ncid,lon_id,len=iextr)
                  if (err .ne. NF90_NOERR) go to 10
                  LEVEL4 'lon_id  --> ',lon_id,', len = ',iextr
               end if
               if( dimname .eq. name_lat ) then
                  lat_id = n
                  err = nf90_inquire_dimension(ncid,lat_id,len=jextr)
                  if (err .ne. NF90_NOERR) go to 10
                  LEVEL4 'lat_id  --> ',lat_id,', len = ',jextr
               end if
               if( dimname .eq. name_time ) then
                  time_id = n
                  err = nf90_inquire_dimension(ncid,time_id,len=textr)
                  if (err .ne. NF90_NOERR) go to 10
                  LEVEL4 'time_id --> ',time_id,', len = ',textr
!                  if (tmax .lt. 0) tmax=textr
                  tmax=textr
               end if
            end do
            if(lon_id .eq. -1) then
               FATAL 'could not find longitude coordinate in meteo file'
               stop 'open_meteo_file()'
            end if
            if(lat_id .eq. -1) then
               FATAL 'could not find latitude coordinate in meteo file'
               stop 'open_meteo_file()'
            end if
            if(time_id .eq. -1) then
               FATAL 'could not find time coordinate in meteo file'
               stop 'open_meteo_file()'
            end if

            allocate(met_lon(iextr),stat=err)
            if (err /= 0) stop &
                  'open_meteo_file(): Error allocating memory (met_lon)'
            err = nf90_inq_varid(ncid,name_lon,id)
            if (err .NE. NF90_NOERR) go to 10
            err = nf90_get_var(ncid,id,met_lon)
            if (err .ne. NF90_NOERR) go to 10

            allocate(met_lat(jextr),stat=err)
            if (err /= 0) stop &
                  'open_meteo_file(): Error allocating memory (met_lat)'
            err = nf90_inq_varid(ncid,name_lat,id)
            if (err .NE. NF90_NOERR) go to 10
            err = nf90_get_var(ncid,id,met_lat)
            if (err .ne. NF90_NOERR) go to 10

            allocate(met_times(textr),stat=err)
            if (err /= 0) stop &
                  'open_meteo_file(): Error allocating memory (met_times)'

!           first we check for CF compatible grid_mapping_name
            err = nf90_inq_varid(ncid,'rotated_pole',id)
            if (err .eq. NF90_NOERR) then
               LEVEL4 'Reading CF-compliant rotated grid specification'
               err = nf90_get_att(ncid,id, &
                                  'grid_north_pole_latitude',southpole(1))
               if (err .ne. NF90_NOERR) go to 10
               err = nf90_get_att(ncid,id, &
                                  'grid_north_pole_longitude',southpole(2))
#if 0
STDERR 'Inside rotated_pole'
STDERR 'grid_north_pole_latitude ',southpole(1)
STDERR 'grid_north_pole_longitude ',southpole(2)
#endif
               if (err .ne. NF90_NOERR) go to 10
               err = nf90_get_att(ncid,id, &
                                  'north_pole_grid_longitude',southpole(3))
               if (err .ne. NF90_NOERR) then
                  southpole(3) = _ZERO_
               end if
!              Northpole ---> Southpole transformation
               LEVEL4 'Transforming North Pole to South Pole specification'
               if (southpole(2) .ge. 0) then
                  southpole(2) = southpole(2) - 180.
               else
                  southpole(2) = southpole(2) + 180.
               end if
               southpole(1) = -southpole(1)
#if 0
STDERR 'After transformation:'
STDERR 'grid_north_pole_latitude ',southpole(1)
STDERR 'grid_north_pole_longitude ',southpole(2)
#endif
               southpole(3) = _ZERO_
               have_southpole = .true.
               rotated_meteo_grid = .true.
            else
               have_southpole = .false.
            end if

!           and then we revert to the old way - checking 'southpole' directly
            if (.not. have_southpole) then
               err = nf90_inq_varid(ncid,'southpole',id)
               if (err .ne. NF90_NOERR) then
                  LEVEL4 'Setting southpole to (0,-90,0)'
               else
                  err = nf90_get_var(ncid,id,southpole)
                  if (err .ne. NF90_NOERR) go to 10
                  rotated_meteo_grid = .true.
               end if
            end if
            if (rotated_meteo_grid) then
               LEVEL4 'south pole:'
!              changed indices - kb 2014-12-15
               LEVEL4 '      lon ',southpole(2)
               LEVEL4 '      lat ',southpole(1)
            end if
         end if

         err = nf90_inquire_dimension(ncid,time_id,len=idum)
         if (err .ne. NF90_NOERR) go to 10
         if(idum .gt. size(met_times)) then
            deallocate(met_times,stat=err)
            if (err /= 0) stop      &
               'open_meteo_file(): Error de-allocating memory (met_times)'
            allocate(met_times(idum),stat=err)
            if (err /= 0) stop &
               'open_meteo_file(): Error allocating memory (met_times)'
         end if
         textr = idum
         LEVEL3 'time_id --> ',time_id,', len = ',textr
!        if (tmax .lt. 0) tmax=textr
         tmax=textr

         err = nf90_inq_varid(ncid,name_time,time_var_id)
         if (err .NE. NF90_NOERR) go to 10
         err =  nf90_get_att(ncid,time_var_id,'units',time_units)
         if (err .NE. NF90_NOERR) go to 10
         call string_to_julsecs(time_units,junit,sunit)
         err = nf90_get_var(ncid,time_var_id,met_times(1:textr))
         if (err .ne. NF90_NOERR) go to 10

         call add_secs(junit,sunit,nint(met_times(1)),    j1,s1)
         call add_secs(junit,sunit,nint(met_times(textr)),j2,s2)

         if (in_interval(j1,s1,julianday,secondsofday,j2,s2)) then
            found = .true.
            call write_time_string(j1,s1,str1)
            call write_time_string(j2,s2,str2)
         else
            err = nf90_close(ncid)
            if (err .NE. NF90_NOERR) go to 10
         end if
      end do
   else
      err = nf90_close(ncid)
      if (err .NE. NF90_NOERR) go to 10
!     open next file
      read(iunit,*,err=85,end=90) fn
      err = nf90_open(fn,NF90_NOWRITE,ncid)
      if (err .ne. NF90_NOERR) go to 10

      err = nf90_inquire_dimension(ncid,time_id,len=idum)
      if (err .ne. NF90_NOERR) go to 10
      if(idum .gt. size(met_times)) then
         deallocate(met_times,stat=err)
         if (err /= 0) stop      &
            'open_meteo_file(): Error de-allocating memory (met_times)'
         allocate(met_times(idum),stat=err)
         if (err /= 0) stop &
            'open_meteo_file(): Error allocating memory (met_times)'
      end if
      textr = idum
      LEVEL3 'time_id --> ',time_id,', len = ',textr
!     if (tmax .lt. 0) tmax=textr
      tmax=textr

      err = nf90_inq_varid(ncid,name_time,time_var_id)
      if (err .NE. NF90_NOERR) go to 10
      err =  nf90_get_att(ncid,time_var_id,'units',time_units)
      if (err .NE. NF90_NOERR) go to 10
      call string_to_julsecs(time_units,junit,sunit)
      err = nf90_get_var(ncid,time_var_id,met_times(1:textr))
      if (err .ne. NF90_NOERR) go to 10

      call add_secs(junit,sunit,nint(met_times(1)),    j1,s1)
      call add_secs(junit,sunit,nint(met_times(textr)),j2,s2)
      call write_time_string(j1,s1,str1)
      call write_time_string(j2,s2,str2)
   end if

   if (found) then
      offset = time_diff(jul0,secs0,junit,sunit)
      LEVEL3 'Using meteo from:'
      LEVEL4 trim(fn)
      LEVEL3 'Meteorological offset time ',offset
      LEVEL3 'Data from: ', str1,' to ',str2
!      LEVEL3 'Seconds: ', nint(met_times(1)),' to ',nint(met_times(textr))
   else
      FATAL 'Could not find any valid meteo-files'
      stop 'open_meteo_file'
   end if

   return
10 FATAL 'open_meteo_file: ',nf90_strerror(err)
   stop 'open_meteo_file()'
80 FATAL 'I could not open: ',trim(meteo_file)
   stop 'open_meteo_file()'
85 FATAL 'Error reading: ',trim(meteo_file)
   stop 'open_meteo_file()'
90 FATAL 'Reached eof in: ',trim(meteo_file)
   stop 'open_meteo_file()'

#ifdef DEBUG
   write(debug,*) 'Leaving open_meteo_file()'
   write(debug,*)
#endif
   return
   end subroutine open_meteo_file
!EOC

!-----------------------------------------------------------------------
!BOP
!
! !IROUTINE: read_data -
!
! !INTERFACE:
   subroutine read_data()
   IMPLICIT NONE
!
! !DESCRIPTION:
!  Reads the relevant variables from the NetCDF file. Interpolates to the
!  model grid if necessary. After a call to this routine updated versions
!  of either variables used for calculating stresses and fluxes or directly
!  the stresses/fluxes directly are available to \emph{do\_meteo}.
!
! !REVISION HISTORY:
!
!  See module for log.
!
! !LOCAL VARIABLES:
   integer         :: i1,i2,istr,j1,j2,jstr
   integer         :: i,j,err
   REALTYPE        :: angle,uu,vv,sinconv,cosconv
!EOP
!-----------------------------------------------------------------------
   if (calc_met) then

      err = nf90_get_var(ncid,u10_id,wrk,start,edges)
      if (err .ne. NF90_NOERR) go to 10
      if (on_grid) then
         if (point_source) then
            u10 = wrk(1,1)
         else
            do j=jmin,jmax
               do i=imin,imax
                  u10(i,j) = wrk(i,j)
               end do
            end do
         end if
      else
         !KBKwrk_dp = _ZERO_
         call copy_var(grid_scan,wrk,wrk_dp)
         call do_grid_interpol(az,wrk_dp,gridmap,ti,ui,u10)
      end if

      err = nf90_get_var(ncid,v10_id,wrk,start,edges)
      if (err .ne. NF90_NOERR) go to 10
      if (on_grid) then
         if (point_source) then
            v10 = wrk(1,1)
         else
            do j=jmin,jmax
               do i=imin,imax
                  v10(i,j) = wrk(i,j)
               end do
            end do
         end if
      else
         !KBKwrk_dp = _ZERO_
         call copy_var(grid_scan,wrk,wrk_dp)
         call do_grid_interpol(az,wrk_dp,gridmap,ti,ui,v10)
      end if

!     Rotation of wind due to the combined effect of possible rotation of
!     meteorological grid and possible hydrodynamic grid convergence
!     (cartesian and curvi-linear grids where conv <> 0.)
      do j=jmin-1,jmax+1
         do i=imin-1,imax+1
!KBK            angle=-convc(i,j)*deg2rad
!KBK            angle=beta(i,j)
            angle=beta(i,j)-convc(i,j)*deg2rad
            if(angle .ne. _ZERO_) then
               sinconv=sin(angle)
               cosconv=cos(angle)
               uu=u10(i,j)
               vv=v10(i,j)
               u10(i,j)= uu*cosconv+vv*sinconv
               v10(i,j)=-uu*sinconv+vv*cosconv
            end if
         end do
      end do

      err = nf90_get_var(ncid,airp_id,wrk,start,edges)
      if (err .ne. NF90_NOERR) go to 10
      if (on_grid) then
         if (point_source) then
            airp = wrk(1,1)
         else
            do j=jmin,jmax
               do i=imin,imax
                  airp(i,j) = wrk(i,j)
               end do
            end do
         end if
      else
         !KBKwrk_dp = _ZERO_
         call copy_var(grid_scan,wrk,wrk_dp)
         call do_grid_interpol(az,wrk_dp,gridmap,ti,ui,airp)
      end if

      err = nf90_get_var(ncid,t2_id,wrk,start,edges)
      if (err .ne. NF90_NOERR) go to 10
      if (on_grid) then
         if (point_source) then
            t2 = wrk(1,1)
         else
            do j=jmin,jmax
               do i=imin,imax
                  t2(i,j) = wrk(i,j)
               end do
            end do
         end if
      else
         !KBKwrk_dp = _ZERO_
         call copy_var(grid_scan,wrk,wrk_dp)
         call do_grid_interpol(az,wrk_dp,gridmap,ti,ui,t2)
      end if

      err = nf90_get_var(ncid,hum_id,wrk,start,edges)
      if (err .ne. NF90_NOERR) go to 10
      if (on_grid) then
         if (point_source) then
            hum = wrk(1,1)
         else
            do j=jmin,jmax
               do i=imin,imax
                  hum(i,j) = wrk(i,j)
               end do
            end do
         end if
      else
         !KBKwrk_dp = _ZERO_
         call copy_var(grid_scan,wrk,wrk_dp)
         call do_grid_interpol(az,wrk_dp,gridmap,ti,ui,hum)
      end if

      err = nf90_get_var(ncid,tcc_id,wrk,start,edges)
      if (err .ne. NF90_NOERR) go to 10
      if (on_grid) then
         if (point_source) then
            tcc = wrk(1,1)
         else
            do j=jmin,jmax
               do i=imin,imax
                  tcc(i,j) = wrk(i,j)
               end do
            end do
         end if
      else
         !KBKwrk_dp = _ZERO_
         call copy_var(grid_scan,wrk,wrk_dp)
         call do_grid_interpol(az,wrk_dp,gridmap,ti,ui,tcc)
      end if

      if (evap_id .ge. 0) then
         err = nf90_get_var(ncid,evap_id,wrk,start,edges)
         if (err .ne. NF90_NOERR) go to 10
         if (on_grid) then
            if (point_source) then
               evap = wrk(1,1)
            else
               do j=jmin,jmax
                  do i=imin,imax
                     evap(i,j) = wrk(i,j)
                  end do
               end do
            end if
         else
            call copy_var(grid_scan,wrk,wrk_dp)
            call do_grid_interpol(az,wrk_dp,gridmap,ti,ui,evap)
         end if
         if (evap_factor .ne. _ONE_) then
            evap = evap * evap_factor
         end if
      end if

      if (precip_id .gt. 0) then
         err = nf90_get_var(ncid,precip_id,wrk,start,edges)
         if (err .ne. NF90_NOERR) go to 10
         if (on_grid) then
            if (point_source) then
               precip = wrk(1,1)
            else
               do j=jmin,jmax
                  do i=imin,imax
                     precip(i,j) = wrk(i,j)
                  end do
               end do
            end if
         else
            call copy_var(grid_scan,wrk,wrk_dp)
            call do_grid_interpol(az,wrk_dp,gridmap,ti,ui,precip)
         end if
         if (precip_factor .ne. _ONE_) then
            precip = precip * precip_factor
         end if
      end if

   else

      err = nf90_get_var(ncid,tausx_id,wrk,start,edges)
      if (err .ne. NF90_NOERR) go to 10
      if (point_source) then
         tausx = wrk(1,1)
      else
         do j=jmin,jmax
            do i=imin,imax
               tausx(i,j) = wrk(i,j)
            end do
         end do
      end if

      err = nf90_get_var(ncid,tausy_id,wrk,start,edges)
      if (err .ne. NF90_NOERR) go to 10
      if (point_source) then
         tausy = wrk(1,1)
      else
         do j=jmin,jmax
            do i=imin,imax
               tausy(i,j) = wrk(i,j)
            end do
         end do
      end if

      err = nf90_get_var(ncid,swr_id,wrk,start,edges)
      if (err .ne. NF90_NOERR) go to 10
      if (point_source) then
         swr = wrk(1,1)
      else
         do j=jmin,jmax
            do i=imin,imax
               swr(i,j) = wrk(i,j)
            end do
         end do
      end if

      err = nf90_get_var(ncid,shf_id,wrk,start,edges)
      if (err .ne. NF90_NOERR) go to 10
      if (point_source) then
         shf = wrk(1,1)
      else
         do j=jmin,jmax
            do i=imin,imax
               shf(i,j) = wrk(i,j)
            end do
         end do
      end if

   end if

#ifdef DEBUG
   write(debug,*) 'Leaving read_data()'
   write(debug,*)
#endif
   return
10 FATAL 'read_data: ',nf90_strerror(err)
   stop
   end subroutine read_data
!EOC

!-----------------------------------------------------------------------
!BOP
!
! !IROUTINE: copy_var -
!
! !INTERFACE:
!   subroutine copy_var(grid_scan,var)
   subroutine copy_var(grid_scan,inf,outf)
   IMPLICIT NONE
!
! !DESCRIPTION:
!  Reads the relevant variables from the NetCDF file. Interpolates to the
!  model grid if necessary. After a call to this routine updated versions
!  of either variables used for calculating stresses and fluxes or directly
!  the stresses/fluxes directly are available to \emph{do\_meteo}.
!
! !INPUT PARAMETERS:
   integer, intent(in)                 :: grid_scan
   REAL_4B, intent(in)                 :: inf(:,:)
!
! !INPUT/OUTPUT PARAMETERS:
!
! !OUTPUT PARAMETERS:
   REALTYPE, intent(out)               :: outf(:,:)
!
! !REVISION HISTORY:
!
!  See module for log.
!
! !LOCAL VARIABLES:
   integer         :: i1,i2,istr,j1,j2,jstr
   integer         :: i,j,err
!EOP
!-----------------------------------------------------------------------

   select case (grid_scan)
      case (0)
         do j=1,jextr
            do i=1,iextr
               outf(i,jextr-j+1) = inf(i,j)
            end do
         end do
      case (1) ! ?????
         do j=1,jextr
            do i=1,iextr
               outf(i,j) = inf(i,j)
            end do
         end do
      case default
         FATAL 'Do something here - copy_var'
   end select
   return
   end subroutine copy_var
!EOC

!-----------------------------------------------------------------------

   end module ncdf_meteo

!-----------------------------------------------------------------------
! Copyright (C) 2001 - Hans Burchard and Karsten Bolding (BBH)         !
!-----------------------------------------------------------------------
