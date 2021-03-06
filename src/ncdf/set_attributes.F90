#include "cppdefs.h"
!-----------------------------------------------------------------------
!BOP
!
! !ROUTINE: Sets various attributes for a NetCDF variable.
!
! !INTERFACE:
   subroutine set_attributes(ncid,id,                            &
                             units,long_name,                    &
                             netcdf_real,                        &
                             valid_min,valid_max,valid_range,    &
                             scale_factor,add_offset,            &
                             FillValue,missing_value,            &
                             C_format,FORTRAN_format)
!
! !DESCRIPTION:
!  This routine is used to set a number of attributes for the various
!  variables. The routine make heavy use of the {\em optional} keyword.
!  The list of recognized keywords is very easy expandable. We have
!  included a sub-set of the COARDS conventions.
!
! !USES:
   use netcdf
!  IMPLICIT NONE
!
! !INPUT PARAMETERS:
   integer, intent(in)                 :: ncid,id
   integer, optional                   :: netcdf_real
   character(len=*), optional          :: units,long_name
#if 1
   REALTYPE, optional                  :: valid_min,valid_max,valid_range(2)
   REALTYPE, optional                  :: scale_factor,add_offset
   REALTYPE, optional                  :: FillValue,missing_value
#else
   REAL_4B, optional                  :: valid_min,valid_max,valid_range(2)
   REAL_4B, optional                  :: scale_factor,add_offset
   REAL_4B, optional                  :: FillValue,missing_value
#endif
   character(len=*), optional          :: C_format,FORTRAN_format
!
! !REVISION HISTORY:
!  Original author(s): Karsten Bolding & Hans Burchard
!
!  See ncdfout module
!
! !LOCAL VARIABLES:
   integer, parameter :: kind_real_single = SELECTED_REAL_KIND(p=5)
   integer, parameter :: kind_real_double = SELECTED_REAL_KIND(p=14)
   integer                   :: iret
   integer                   :: ft
!EOP
!-----------------------------------------------------------------------
!BOC
   if(present(netcdf_real)) then
      ft=netcdf_real
   else
      ft=NCDF_FLOAT_PRECISION
   end if

   if(present(units)) then
      iret = nf90_put_att(ncid,id,'units',trim(units))
   end if

   if(present(long_name)) then
      iret = nf90_put_att(ncid,id,'long_name',trim(long_name))
   end if

   if(present(C_format)) then
      iret = nf90_put_att(ncid,id,'C_format',trim(C_format))
   end if

   if(present(FORTRAN_format)) then
      iret = nf90_put_att(ncid,id,'FORTRAN_format',trim(FORTRAN_format))
   end if

   if(present(valid_min)) then
      if (ft .eq. NF90_DOUBLE) then
         iret = nf90_put_att(ncid,id,'valid_min',real(valid_min,kind=kind_real_double))
      else
         iret = nf90_put_att(ncid,id,'valid_min',real(valid_min,kind=kind_real_single))
      end if
   end if

   if(present(valid_max)) then
      if (ft .eq. NF90_DOUBLE) then
         iret = nf90_put_att(ncid,id,'valid_max',real(valid_max,kind=kind_real_double))
      else
         iret = nf90_put_att(ncid,id,'valid_max',real(valid_max,kind=kind_real_single))
      end if
   end if

   if(present(valid_range)) then
      if (ft .eq. NF90_DOUBLE) then
         iret = nf90_put_att(ncid,id,'valid_range',real(valid_range,kind=kind_real_double))
      else
         iret = nf90_put_att(ncid,id,'valid_range',real(valid_range,kind=kind_real_single))
      end if
   end if

   if(present(scale_factor)) then
      if (ft .eq. NF90_DOUBLE) then
         iret = nf90_put_att(ncid,id,'scale_factor',real(scale_factor,kind=kind_real_double))
      else
         iret = nf90_put_att(ncid,id,'scale_factor',real(scale_factor,kind=kind_real_single))
      end if
   end if

   if(present(add_offset)) then
      if (ft .eq. NF90_DOUBLE) then
         iret = nf90_put_att(ncid,id,'add_offset',real(add_offset,kind=kind_real_double))
      else
         iret = nf90_put_att(ncid,id,'add_offset',real(add_offset,kind=kind_real_single))
      end if
   end if

   if(present(FillValue)) then
      if (ft .eq. NF90_DOUBLE) then
         iret = nf90_put_att(ncid,id,'_FillValue',real(FillValue,kind=kind_real_double))
      else
         iret = nf90_put_att(ncid,id,'_FillValue',real(FillValue,kind=kind_real_single))
      end if
   end if

   if(present(missing_value)) then
      if (ft .eq. NF90_DOUBLE) then
         iret = nf90_put_att(ncid,id,'missing_value',real(missing_value,kind=kind_real_double))
      else
         iret = nf90_put_att(ncid,id,'missing_value',real(missing_value,kind=kind_real_single))
      end if
   end if

   return
   end subroutine set_attributes
!EOC

!-----------------------------------------------------------------------
! Copyright (C) 2001 - Karsten Bolding and Hans Burchard (BBH)         !
!-----------------------------------------------------------------------
