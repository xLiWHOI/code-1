#include "cppdefs.h"
!-----------------------------------------------------------------------
!BOP
!
! !MODULE:  ncdf_3d_bdy - input in NetCDF format
!
! !INTERFACE:
   module ncdf_3d_bdy
!
! !DESCRIPTION:
!
! !USES:
   use netcdf
   use domain, only: imin,imax,jmin,jmax,kmax,ioff,joff
   use domain, only: nsbv,NWB,NNB,NEB,NSB,bdy_index
   use domain, only: wi,wfj,wlj,nj,nfi,nli,ei,efj,elj,sj,sfi,sli
   use domain, only: H
   use m2d, only: dtm
   use variables_3d, only: hn
   use bdy_3d, only: T_bdy,S_bdy
   use time, only: string_to_julsecs,time_diff,add_secs
   use time, only: julianday,secondsofday,juln,secsn
   use time, only: write_time_string,timestr
   IMPLICIT NONE
!
   private
!
   public                              :: init_3d_bdy_ncdf,do_3d_bdy_ncdf
!
! !PRIVATE DATA MEMBERS:
   integer                             :: ncid
   integer                             :: time_id,temp_id,salt_id
   integer                             :: start(4),edges(4)
   integer                             :: zax_dim,zax_len,zax_pos
   integer                             :: time_dim,time_len,time_pos
   logical                             :: climatology=.false.
   logical                             :: from_3d_fields
   REALTYPE                            :: offset
   REAL_4B, allocatable                :: bdy_times(:),wrk(:)
   REAL_4B,  allocatable, dimension(:)     :: zlev
   REALTYPE, allocatable, dimension(:,:)   :: T_old, T_new
   REAL_4B,  allocatable, dimension(:,:)   :: T_wrk
   REALTYPE, allocatable, dimension(:,:)   :: S_old, S_new
   REAL_4B,  allocatable, dimension(:,:)   :: S_wrk
   REALTYPE, allocatable, dimension(:,:,:) :: T_bdy_clim,S_bdy_clim
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
! !ROUTINE: init_3d_bdy_ncdf -
!
! !INTERFACE:
   subroutine init_3d_bdy_ncdf(fname)
!
! !DESCRIPTION:
!  kurt,kurt
!
! !USES:
   IMPLICIT NONE
!
! !INPUT PARAMETERS:
   character(len=*), intent(in)        :: fname
!
! !REVISION HISTORY:
!  Original author(s): Karsten Bolding & Hans Burchard
!
!  See log for module
!
! !LOCAL VARIABLES:
   character(len=256)        :: units
   character(len=19)         :: tbuf
   integer                   :: j1,s1,j2,s2
   integer                   :: ndims, nvardims
   integer                   :: vardim_ids(4)
   integer, allocatable, dimension(:):: dim_ids,dim_len
   character(len=16), allocatable :: dim_name(:)
   integer                   :: rc,err
   integer                   :: i,j,k,l,m,n,id
!EOP
!-------------------------------------------------------------------------
!BOC
#ifdef DEBUG
   write(debug,*) 'ncdf_init_3d_bdy (NetCDF)'
   write(debug,*) 'Reading from: ',trim(fname)
#endif

   LEVEL3 'init_3d_bdy_ncdf'

   err = nf90_open(fname,NF90_NOWRITE,ncid)
   if (err .NE. NF90_NOERR) go to 10

   err = nf90_inquire(ncid, nDimensions = nDims)
   if (err .NE. NF90_NOERR) go to 10

   allocate(dim_ids(ndims),stat=rc)
   if (rc /= 0) stop 'init_3d_bdy_ncdf: Error allocating memory (dim_ids)'

   allocate(dim_len(ndims),stat=rc)
   if (rc /= 0) stop 'init_3d_bdy_ncdf: Error allocating memory (dim_len)'

   allocate(dim_name(ndims),stat=rc)
   if (rc /= 0) stop 'init_3d_bdy_ncdf: Error allocating memory (dim_name)'

   do n=1,ndims
      err = nf90_inquire_dimension(ncid,n,name=dim_name(n),len=dim_len(n))
      if (err .NE. NF90_NOERR) go to 10
      LEVEL4 n,dim_name(n), dim_len(n)
   end do

   if(ndims .eq. 4) then
!     We are reading boundary values from a full 3D field
!     We assume COARDS conventions
!     1 -> lon,x-axis
!     2 -> lat,y-axis
!     3 -> zax,levels
!     4 -> time
      LEVEL4 'boundary data from 3D fields'
      from_3d_fields=.true.
      zax_pos = 3
      time_pos = 4
   else
!     We are reading boundary values from a special boundary data file
!     The variables 'salt' and 'temp' must both exist and be spanned by
!     dimensions as:
!       1 -> zax,levels
!       2 -> bdy_points
!       3 -> time
      LEVEL4 'special boundary data file'
      from_3d_fields=.false.
      zax_pos = 1
      time_pos = 3
!     Note(BJB): This test may break backward compatibility,
!                so I leave it out for now:
      !if (ndims .NE. 3) stop 'init_3d_bdy_ncdf: Wrong number of dims in file (must be 3)'
   end if

!  We will use this information to actually find the dimension
!  index numbers in the data set.
!  Some of the tests will be repeated later (fixing is possible but not
!  high priority, BJB 2007-04-25).

   LEVEL4 ' ... checking variable "temp"'

   err = nf90_inq_varid(ncid,'temp',temp_id)
   if (err .NE. NF90_NOERR) go to 10

   err = nf90_inquire_variable(ncid,temp_id,ndims=nvardims)
   if (err .NE. NF90_NOERR) go to 10

   if (nvardims .NE. ndims) &
        stop 'init_3d_bdy_ncdf: Wrong number of dims in temp'

   err = nf90_inquire_variable(ncid,temp_id,dimids=vardim_ids)
   if (err .NE. NF90_NOERR) go to 10

   zax_dim  = vardim_ids(zax_pos)
   time_dim = vardim_ids(time_pos)

   ! The 'salt' part is only for error capture.
   LEVEL4 ' ... checking variable "salt"'

   err = nf90_inq_varid(ncid,'salt',salt_id)
   if (err .NE. NF90_NOERR) go to 10

   err = nf90_inquire_variable(ncid,salt_id,ndims=nvardims)
   if (err .NE. NF90_NOERR) go to 10

   if (nvardims .NE. ndims) &
        stop 'init_3d_bdy_ncdf: Wrong number of dims in salt'

   err = nf90_inquire_variable(ncid,salt_id,dimids=vardim_ids)
   if (err .NE. NF90_NOERR) go to 10

   if (zax_dim /= vardim_ids(zax_pos)) &
        stop 'init_3d_bdy_ncdf: Position of zax dimension of salt and temp differs'
   if (time_dim /= vardim_ids(time_pos)) &
        stop 'init_3d_bdy_ncdf: Position of time dimension of salt and temp differs'

   zax_len = dim_len(zax_dim)
   time_len = dim_len(time_dim)

   allocate(zlev(zax_len),stat=rc)
   if (rc /= 0) stop 'init_3d_bdy_ncdf: Error allocating memory (zlev)'

   err = nf90_inq_varid(ncid, dim_name(zax_dim), id)
   if (err .ne. NF90_NOERR) go to 10

   err = nf90_get_var(ncid,id,zlev)
   if (err .ne. NF90_NOERR) go to 10

!  a few sanity checks on the vertical axis for the 3D boundaries
   do n=1,zax_len
      if (zlev(n) .eq. NF90_FILL_REAL) then
         FATAL '3D boundary z-axis contains NF90_FILL_REAL values'
         FATAL 'proper interpolation cant be done'
         stop 'init_3d_bdy_ncdf'
      end if
   end do
!  not sure if this check is safe - kb
   if ( zlev(1) .ge. _ZERO_ .and. zlev(zax_len) .gt. _ZERO_ ) then
      LEVEL4 'converting positive z-axis (depth) values to negative'
      zlev = -_ONE_*zlev
   end if
!  check strict monotonicity
   do n=1,zax_len-1
      if ( .not. zlev(n) .gt. zlev(n+1) ) then
         FATAL '3D boundary z-axis not strict monotone: ',zlev(n),zlev(n+1)
         stop 'init_3d_bdy_ncdf'
      end if
   end do

   if( time_len .eq. 12) then
      climatology=.true.
      LEVEL4 'Assuming climatolgical 3D boundary conditions'
      LEVEL4 '# of times = ',time_len
   end if

   if (climatology) then

      allocate(wrk(zax_len),stat=rc)
      if (rc /= 0) stop 'init_3d_bdy_ncdf: Error allocating memory (wrk)'

      allocate(T_bdy_clim(0:kmax,nsbv,time_len),stat=rc)
      if (rc /= 0) stop 'init_3d_bdy_ncdf: Error allocating memory (T_bdy_clim)'

      allocate(S_bdy_clim(0:kmax,nsbv,time_len),stat=rc)
      if (rc /= 0) stop 'init_3d_bdy_ncdf: Error allocating memory (S_bdy_clim)'

!     Note(KK): We read in the data columnwise for all time stages
!     here we can read from both a 3D field and from a
!     special boundary data file - only the arguments 'start' and 'edges'
!     varies in the calls to 'nf90_get_var()'
!     m counts the time
!     l counts the boundary number
!     k counts the number of the specific point
!     MUST cover the same area as in topo.nc

      edges = 1
      edges(zax_pos) = zax_len
      start(zax_pos) = 1

      do m=1,time_len
         start(time_pos) = m
         l = 0
         do n=1,NWB
            l = l+1
            k = bdy_index(l)
            i = wi(n)
            do j=wfj(n),wlj(n)
               if (from_3d_fields) then
                  start(1) = i+ioff ; start(2) = j+joff
               else
                  start(2) = k
               end if
               err = nf90_get_var(ncid,salt_id,wrk,start,edges)
               if (err .ne. NF90_NOERR) go to 10
               call interpol(zax_len,zlev,wrk,H(i,j),kmax,hn(i,j,:), &
                             S_bdy_clim(:,k,m))
               err = nf90_get_var(ncid,temp_id,wrk,start,edges)
               if (err .ne. NF90_NOERR) go to 10
               call interpol(zax_len,zlev,wrk,H(i,j),kmax,hn(i,j,:), &
                             T_bdy_clim(:,k,m))
               k = k+1
            end do
         end do

         do n = 1,NNB
            l = l+1
            k = bdy_index(l)
            j = nj(n)
            do i = nfi(n),nli(n)
               if (from_3d_fields) then
                  start(1) = i+ioff ; start(2) = j+joff
               else
                  start(2) = k
               end if
               err = nf90_get_var(ncid,salt_id,wrk,start,edges)
               if (err .ne. NF90_NOERR) go to 10
               call interpol(zax_len,zlev,wrk,H(i,j),kmax,hn(i,j,:), &
                             S_bdy_clim(:,k,m))
               err = nf90_get_var(ncid,temp_id,wrk,start,edges)
               if (err .ne. NF90_NOERR) go to 10
               call interpol(zax_len,zlev,wrk,H(i,j),kmax,hn(i,j,:), &
                             T_bdy_clim(:,k,m))
               k = k+1
            end do
         end do

         do n=1,NEB
            l = l+1
            k = bdy_index(l)
            i = ei(n)
            do j=efj(n),elj(n)
               if (from_3d_fields) then
                  start(1) = i+ioff ; start(2) = j+joff
               else
                  start(2) = k
               end if
               err = nf90_get_var(ncid,salt_id,wrk,start,edges)
               if (err .ne. NF90_NOERR) go to 10
               call interpol(zax_len,zlev,wrk,H(i,j),kmax,hn(i,j,:), &
                             S_bdy_clim(:,k,m))
               err = nf90_get_var(ncid,temp_id,wrk,start,edges)
               if (err .ne. NF90_NOERR) go to 10
               call interpol(zax_len,zlev,wrk,H(i,j),kmax,hn(i,j,:), &
                             T_bdy_clim(:,k,m))
               k = k+1
            end do
         end do

         do n = 1,NSB
            l = l+1
            k = bdy_index(l)
            j = sj(n)
            do i = sfi(n),sli(n)
               if (from_3d_fields) then
                  start(1) = i+ioff ; start(2) = j+joff
               else
                  start(2) = k
               end if
               err = nf90_get_var(ncid,salt_id,wrk,start,edges)
               if (err .ne. NF90_NOERR) go to 10
               call interpol(zax_len,zlev,wrk,H(i,j),kmax,hn(i,j,:), &
                             S_bdy_clim(:,k,m))
               err = nf90_get_var(ncid,temp_id,wrk,start,edges)
               if (err .ne. NF90_NOERR) go to 10
               call interpol(zax_len,zlev,wrk,H(i,j),kmax,hn(i,j,:), &
                             T_bdy_clim(:,k,m))
               k = k+1
            end do
         end do
      end do
      err = nf90_close(ncid)

   else

      if (from_3d_fields) then
         FATAL 'non-climatology bdy data only support special bdy data file'
         stop 'init_3d_bdy_ncdf'
      end if

      err = nf90_inq_varid(ncid,'time',time_id)
      if (err .NE. NF90_NOERR) go to 10

      err =  nf90_get_att(ncid,time_id,'units',units)
      if (err .NE. NF90_NOERR) go to 10

      allocate(bdy_times(time_len),stat=err)
      if (err /= 0) stop 'init_3d_bdy_ncdf: Error allocating memory (bdy_times)'

      err = nf90_get_var(ncid,time_id,bdy_times)
      if (err .NE. NF90_NOERR) go to 10

      call string_to_julsecs(units,j1,s1)
      offset = time_diff(julianday,secondsofday,j1,s1)
      if( offset .lt. bdy_times(1) ) then
         FATAL 'Model simulation starts before available boundary data'
         call write_time_string(julianday,secondsofday,tbuf)
         FATAL 'Simulation starts: ',tbuf
         call add_secs(j1,s1,nint(bdy_times(1)),j2,s2)
         call write_time_string(j2,s2,tbuf)
         FATAL 'Datafile starts:   ',tbuf
         stop 'init_3d_bdy_ncdf'
      else
         LEVEL3 'Boundary offset time ',offset
      end if

!     check if the bdy data file is long enough
      if( time_diff(juln,secsn,j1,s1) .gt. bdy_times(time_len) ) then
         FATAL 'Not enough 3D boundary data in file'
         call write_time_string(juln,secsn,tbuf)
         FATAL 'Simulation ends: ',tbuf
         call add_secs(j1,s1,nint(bdy_times(time_len)),j2,s2)
         call write_time_string(j2,s2,tbuf)
         FATAL 'Datafile ends:   ',tbuf
         stop 'init_3d_bdy_ncdf'
      end if

      allocate(T_old(0:kmax,nsbv),stat=err)
      if (err /= 0) stop 'init_3d_bdy_ncdf: Error allocating memory (T_old)'
      allocate(T_new(0:kmax,nsbv),stat=err)
      if (err /= 0) stop 'init_3d_bdy_ncdf: Error allocating memory (T_new)'
      allocate(T_wrk(zax_len,nsbv),stat=err)
      if (err /= 0) stop 'init_3d_bdy_ncdf: Error allocating memory (T_wrk)'

      allocate(S_old(0:kmax,nsbv),stat=err)
      if (err /= 0) stop 'init_3d_bdy_ncdf: Error allocating memory (S_old)'
      allocate(S_new(0:kmax,nsbv),stat=err)
      if (err /= 0) stop 'init_3d_bdy_ncdf: Error allocating memory (S_new)'
      allocate(S_wrk(zax_len,nsbv),stat=err)
      if (err /= 0) stop 'init_3d_bdy_ncdf: Error allocating memory (S_wrk)'

!     Note(KK): We read in at once the data of all points
!               but only for the current time stage

      n = size(bdy_times)
      do i=1,n
         if(bdy_times(i) .ge. real(offset)) then
            EXIT
         end if
      end do

      if(i .gt. 1 .and. bdy_times(i) .gt. real(offset)) then
         i = i-1
      end if

      start(1) = 1; edges(1) = zax_len;
      start(2) = 1; edges(2) = nsbv;
      start(3) = i; edges(3) = 1

      err = nf90_get_var(ncid,temp_id,T_wrk,start,edges)
      if (err .ne. NF90_NOERR) go to 10

      err = nf90_get_var(ncid,salt_id,S_wrk,start,edges)
      if (err .ne. NF90_NOERR) go to 10

      l = 0
      do n=1,NWB
         l = l+1
         k = bdy_index(l)
         i = wi(n)
         do j=wfj(n),wlj(n)
            call interpol(zax_len,zlev,T_wrk(:,k),H(i,j),kmax,hn(i,j,:), &
                          T_new(:,k))
            call interpol(zax_len,zlev,S_wrk(:,k),H(i,j),kmax,hn(i,j,:), &
                          S_new(:,k))
            k = k+1
         end do
      end do

      do n = 1,NNB
         l = l+1
         k = bdy_index(l)
         j = nj(n)
         do i = nfi(n),nli(n)
            call interpol(zax_len,zlev,S_wrk(:,k),H(i,j),kmax,hn(i,j,:), &
                          S_new(:,k))
            call interpol(zax_len,zlev,T_wrk(:,k),H(i,j),kmax,hn(i,j,:), &
                          T_new(:,k))
            k = k+1
         end do
      end do

      do n=1,NEB
         l = l+1
         k = bdy_index(l)
         i = ei(n)
         do j=efj(n),elj(n)
            call interpol(zax_len,zlev,S_wrk(:,k),H(i,j),kmax,hn(i,j,:), &
                          S_new(:,k))
            call interpol(zax_len,zlev,T_wrk(:,k),H(i,j),kmax,hn(i,j,:), &
                          T_new(:,k))
            k = k+1
         end do
      end do

      do n = 1,NSB
         l = l+1
         k = bdy_index(l)
         j = sj(n)
         do i = sfi(n),sli(n)
            call interpol(zax_len,zlev,S_wrk(:,k),H(i,j),kmax,hn(i,j,:), &
                          S_new(:,k))
            call interpol(zax_len,zlev,T_wrk(:,k),H(i,j),kmax,hn(i,j,:), &
                          T_new(:,k))
            k = k+1
         end do
      end do
   end if

#ifdef DEBUG
   write(debug,*) 'Leaving init_3d_bdy_ncdf()'
   write(debug,*)
#endif
   return
10 FATAL 'init_3d_bdy_ncdf: ',nf90_strerror(err)
   stop
   end subroutine init_3d_bdy_ncdf
!EOC

!-----------------------------------------------------------------------
!BOP
!
! !ROUTINE: do_3d_bdy_ncdf -
!
! !INTERFACE:
   subroutine do_3d_bdy_ncdf(loop)
!
! !DESCRIPTION:
!  kurt,kurt
!
! !USES:
   use time, only: day,month,secondsofday,days_in_mon,leapyear,secsprday
   IMPLICIT NONE
!
! !INPUT PARAMETERS:
   integer, intent(in)                 :: loop
!
! !REVISION HISTORY:
!  Original author(s): Karsten Bolding & Hans Burchard
!
! !LOCAL VARIABLES:
   integer         :: err
   REALTYPE        :: rat
   integer         :: monthsecs,prev,this,next
   logical, save   :: first=.true.
   integer, save   :: loop0
   REALTYPE        :: t
   REALTYPE, save  :: t1=_ZERO_,t2=-_ONE_
   integer         :: i,j,k,l,n
!EOP
!-------------------------------------------------------------------------
!BOC
#ifdef DEBUG
   write(debug,*) 'do_3d_bdy_ncdf (NetCDF)'
#endif

   if ( climatology ) then
      if (time_len .eq. 12) then
!        Note(KK): We already read in all data and only need to interpolate in time
         this = month
         monthsecs = secsprday*days_in_mon(leapyear,month)
         rat=((day-1)*secsprday+secondsofday)/float(monthsecs)
         next=this+1
         if (next .gt. time_len) next=1
         prev=this-1
         if (prev .eq. 0) prev=time_len
      else
         STDERR 'do_3d_bdy_ncdf: climatology time_len .ne. 12'
         stop
      end if

      S_bdy=(1.-rat)*0.5*(S_bdy_clim(:,:,prev)+S_bdy_clim(:,:,this))  &
         +     rat*0.5*(S_bdy_clim(:,:,next)+S_bdy_clim(:,:,this))
      T_bdy=(1.-rat)*0.5*(T_bdy_clim(:,:,prev)+T_bdy_clim(:,:,this))  &
         +     rat*0.5*(T_bdy_clim(:,:,next)+T_bdy_clim(:,:,this))
   else

      if (first) then
         loop0=loop-1
      endif
      t = (loop-loop0)*dtm

      if(t .gt. t2 .or. first) then

         if (first) then
            first = .false.
            t2=t
         else
            call write_time_string()
            LEVEL3 timestr,': reading 3D boundary data ...'
         end if

!     Note(KK): We read in at once the data of all points
!               but only for the current time stage

         n = size(bdy_times)
         do i=1,n
            if(bdy_times(i) .ge. real(t + offset)) then
               EXIT
            end if
         end do
         start(1) = 1; edges(1) = zax_len;
         start(2) = 1; edges(2) = nsbv;
         start(3) = i; edges(3) = 1

         t1=t2
         t2 = bdy_times(i) - offset

         T_old = T_new
         S_old = S_new

         err = nf90_get_var(ncid,temp_id,T_wrk,start,edges)
         if (err .ne. NF90_NOERR) go to 10

         err = nf90_get_var(ncid,salt_id,S_wrk,start,edges)
         if (err .ne. NF90_NOERR) go to 10

         l = 0
         do n=1,NWB
            l = l+1
            k = bdy_index(l)
            i = wi(n)
            do j=wfj(n),wlj(n)
               call interpol(zax_len,zlev,T_wrk(:,k),H(i,j),kmax,hn(i,j,:), &
                             T_new(:,k))
               call interpol(zax_len,zlev,S_wrk(:,k),H(i,j),kmax,hn(i,j,:), &
                             S_new(:,k))
               k = k+1
            end do
         end do

         do n = 1,NNB
            l = l+1
            k = bdy_index(l)
            j = nj(n)
            do i = nfi(n),nli(n)
               call interpol(zax_len,zlev,S_wrk(:,k),H(i,j),kmax,hn(i,j,:), &
                             S_new(:,k))
               call interpol(zax_len,zlev,T_wrk(:,k),H(i,j),kmax,hn(i,j,:), &
                             T_new(:,k))
               k = k+1
            end do
         end do

         do n=1,NEB
            l = l+1
            k = bdy_index(l)
            i = ei(n)
            do j=efj(n),elj(n)
               call interpol(zax_len,zlev,S_wrk(:,k),H(i,j),kmax,hn(i,j,:), &
                             S_new(:,k))
               call interpol(zax_len,zlev,T_wrk(:,k),H(i,j),kmax,hn(i,j,:), &
                             T_new(:,k))
               k = k+1
            end do
         end do

         do n = 1,NSB
            l = l+1
            k = bdy_index(l)
            j = sj(n)
            do i = sfi(n),sli(n)
               call interpol(zax_len,zlev,S_wrk(:,k),H(i,j),kmax,hn(i,j,:), &
                             S_new(:,k))
               call interpol(zax_len,zlev,T_wrk(:,k),H(i,j),kmax,hn(i,j,:), &
                             T_new(:,k))
               k = k+1
            end do
         end do
      end if

      T_bdy = T_old + (T_new - T_old)*(t-t1)/(t2-t1)
      S_bdy = S_old + (S_new - S_old)*(t-t1)/(t2-t1)

   end if

#ifdef DEBUG
   write(debug,*) 'Leaving do_3d_bdy_ncdf()'
   write(debug,*)
#endif
   return
10 FATAL 'do_3d_bdy_ncdf: ',nf90_strerror(err)
   stop
   end subroutine do_3d_bdy_ncdf
!EOC

!-----------------------------------------------------------------------

! quick and dirty - should be merged with kbk_interpol.F90 and
! grid_interpol.F90

   subroutine interpol(nlev,zlev,wrk,depth,kmax,zm,col)

! !INPUT PARAMETERS:
   integer, intent(in)       :: nlev
   REAL_4B, intent(in)       :: zlev(nlev),wrk(nlev)
   REALTYPE, intent(in)      :: depth
   integer, intent(in)       :: kmax
   REALTYPE, intent(in)      :: zm(0:kmax)

! !OUTPUT PARAMETERS:
   REALTYPE, intent(out)     :: col(0:kmax)

! !LOCAL VARIABLES:

   REALTYPE                  :: zmodel(kmax),rat
   integer                   :: k,li,n,nn

   zmodel(1) = -depth + 0.5*zm(1)
   do k=2,kmax
      zmodel(k) = zmodel(k-1) + 0.5*(zm(k-1)+zm(k))
   end do

   do k=kmax,1,-1
      if (zmodel(k) .ge. zlev(1)) col(k) = wrk(1)
   end do

!  find largest index with valid value in wrk
   do li=1,nlev
      if (wrk(li) .lt. -999. ) EXIT
   end do
   ! BJB-NOTE: Typically, li will end up as nlev+1, so the first
   !   of the following tests gets false. However, during debug
   !   compilation the second condition *MAY* evaulate wrk(li),
   !   which will result in a "forrtl: severe".
   !if (li .ne. nlev .or. wrk(li) .lt. -999.) li=li-1
   if (li .ne. nlev) then
      li=li-1
   elseif (wrk(li) .lt. -999.) then
      li=li-1
   end if

   do k=1,kmax
      if (zmodel(k) .le. zlev(li)) col(k) = wrk(li)
   end do

   do k=1,kmax
      if (zmodel(k) .gt. zlev(li) .and. zmodel(k) .lt. zlev(1)) then
         nn=nlev+1
224      nn=nn-1
         if(zlev(nn) .le. zmodel(k)) goto 224
         rat = (zmodel(k)-zlev(nn+1))/(zlev(nn)-zlev(nn+1))
         col(k) = (_ONE_-rat)*wrk(nn+1)+rat*wrk(nn)
      end if
   end do
   col(0)=col(1)
   end subroutine interpol
!-----------------------------------------------------------------------

   end module ncdf_3d_bdy

!-----------------------------------------------------------------------
! Copyright (C) 2001 - Hans Burchard and Karsten Bolding (BBH)         !
!-----------------------------------------------------------------------
