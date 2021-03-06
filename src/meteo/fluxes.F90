#include "cppdefs.h"
!-----------------------------------------------------------------------
!BOP
!
! !ROUTINE: Heat and momentum fluxes.
!
! !INTERFACE:
!   subroutine fluxes(lat,u10,v10,airt,tcc,sst,hf,taux,tauy)
   subroutine fluxes(lat,u10,v10,airt,tcc,sst,precip,hf,taux,tauy,evap)
!
! !DESCRIPTION:
!  The sum of the latent and sensible heat fluxes + longwave
!  net-radiation is calculated and returned in \emph{hf} [$W/m^2$]. Also the
!  sea surface stresses are calculated and returned in \emph{taux} and
!  \emph{tauy} [$N/m^2$], respectively. Sensible heat and stress coming
!  from rain are considered. Further the fresh water flux due to
!  evaporation/kondensation is calculated here.
!  The wind velocities are following the
!  meteorological convention (from where) and are in $m/s$. The
!  temperatures \emph{airt} and \emph{sst} can be in Kelvin or Celcius -
!  if they are $>$ 100 - Kelvin is assumed. \emph{tcc} - the total cloud
!  cover is specified as fraction between 0 and 1. Net long wave radiation according
!  to the Josey ea. JGR, 2003 formula 2, considering the effect of water vapor on
!  the long wave radiation is in the moment the best available parameterization and
!  therefore recommended for use.
!
! !SEE ALSO:
!  meteo.F90, exchange_coefficients.F90
!
! !USES:
#ifdef OLD_WRONG_FLUXES
#define EA_ZERO
#endif
   use meteo, only: cpa,emiss,bolz,KELVIN
#ifdef EA_ZERO
   use meteo, only: w,L,rho_air,qs,qa
#else
   use meteo, only: w,L,rho_air,qs,qa,ea
#endif
   use meteo, only: cd_mom,cd_heat,cd_latent
   use meteo, only: fwf_method,cd_precip
   use parameters, only: rho_0
   IMPLICIT NONE
!
! !INPUT PARAMETERS:
   REALTYPE, intent(in)                :: lat,u10,v10,airt,tcc,sst,precip
!
! !OUTPUT PARAMETERS:
   REALTYPE, intent(out)               :: hf,taux,tauy,evap
!
! !REVISION HISTORY:
!  Original author(s): Karsten Bolding and Hans Burchard
!
! !DEFINED PARAMETERS:
   integer, parameter   :: clark=1      ! Clark et. al, 1974
   integer, parameter   :: hastenrath=2 ! Hastenrath and Lamb, 1978
   integer, parameter   :: bignami=3    ! Bignami 1995 -Medsea
   integer, parameter   :: berliand=4   ! Berliand 1952 -ROMS
   integer, parameter   :: josey1=5     ! Josey 2003, 1
   integer, parameter   :: josey2=6     ! Josey 2003, 2
!
#ifndef OLD_WRONG_FLUXES
   real, parameter, dimension(91)  :: cloud_correction_factor = (/ &
     0.497202,     0.501885,     0.506568,     0.511250,     0.515933, &
     0.520616,     0.525299,     0.529982,     0.534665,     0.539348, &
     0.544031,     0.548714,     0.553397,     0.558080,     0.562763, &
     0.567446,     0.572129,     0.576812,     0.581495,     0.586178, &
     0.590861,     0.595544,     0.600227,     0.604910,     0.609593, &
     0.614276,     0.618959,     0.623641,     0.628324,     0.633007, &
     0.637690,     0.642373,     0.647056,     0.651739,     0.656422, &
     0.661105,     0.665788,     0.670471,     0.675154,     0.679837, &
     0.684520,     0.689203,     0.693886,     0.698569,     0.703252, &
     0.707935,     0.712618,     0.717301,     0.721984,     0.726667, &
     0.731350,     0.736032,     0.740715,     0.745398,     0.750081, &
     0.754764,     0.759447,     0.764130,     0.768813,     0.773496, &
     0.778179,     0.782862,     0.787545,     0.792228,     0.796911, &
     0.801594,     0.806277,     0.810960,     0.815643,     0.820326, &
     0.825009,     0.829692,     0.834375,     0.839058,     0.843741, &
     0.848423,     0.853106,     0.857789,     0.862472,     0.867155, &
     0.871838,     0.876521,     0.881204,     0.885887,     0.890570, &
     0.895253,     0.899936,     0.904619,     0.909302,     0.913985, &
     0.918668 /)
#endif
!
! !LOCAL VARIABLES:
#ifdef EA_ZERO
   REALTYPE                  :: ea=_ZERO_
#endif
   REALTYPE                  :: tmp,ccf=0.8
   REALTYPE                  :: qe,qh,qb
   REALTYPE                  :: ta,ta_k,tw,tw_k
   integer                   :: back_radiation_method=clark
   REALTYPE                  :: x1,x2,x3,x
   REALTYPE, parameter       :: rho_precip=1000.
!
!EOP
!-----------------------------------------------------------------------
!BOC
   if (sst .lt. 100.) then
      tw  = sst
      tw_k= sst+KELVIN
   else
      tw  = sst-KELVIN
      tw_k= sst
   end if

   if (airt .lt. 100.) then
      ta = airt
      ta_k  = airt + KELVIN
   else
      ta = airt - KELVIN
      ta_k = airt
   end if

   qe=cd_heat*cpa*rho_air*w*(tw-ta)            ! sensible
   qh=cd_latent*L*rho_air*w*(qs-qa)            ! latent

#ifndef OLD_WRONG_FLUXES
!  calculate cloud correction factor North and South are equal
   ccf = cloud_correction_factor(nint(abs(lat))+1)
#endif

   select case(back_radiation_method)          ! back radiation
      case(clark)
!        AS unit of ea is Pascal, must hPa
!        Black body defect term, clouds, water vapor correction
         x1=(1.0-ccf*tcc*tcc)*(tw_k**4)
         x2=(0.39-0.05*sqrt(ea*0.01))
!        Temperature jump term
         x3=4.0*(tw_k**3)*(tw-ta)
         qb=emiss*bolz*(x1*x2+x3)
      case(hastenrath) ! qa in g(water)/kg(wet air)
!        Black body defect term, clouds, water vapor correction
         x1=(1.0-ccf*tcc*tcc)*(tw_k**4)
         x2=(0.39-0.056*sqrt(1000.0*qa))
!        Temperature jump term
         x3=4.0*(tw_k**3)*(tw-ta)
         qb=emiss*bolz*(x1*x2+x3)
      case(bignami)
!        AS unit of ea is Pascal, must hPa
         ccf=0.1762
!        Black body defect term, clouds, water vapor correction
         x1=(1.0+ccf*tcc*tcc)*ta_k**4
         x2=(0.653+0.00535*(ea*0.01))
!        Temperature jump term
         x3= emiss*(tw_k**4)
         qb=bolz*(-x1*x2+x3)
      case(berliand)
!        Use Berliand (1952) formula (ROMS).
!        Black body defect term, clouds, water vapor correction
         x1=(1.0-0.6823*tcc*tcc)*ta_k**4
         x2=(0.39-0.05*sqrt(0.01*ea))
!        Temperature jump term
         x3=4.0*ta_k**3*(tw-ta)
         qb=emiss*bolz*(x1*x2+x3)
      case(josey1)
!        Use Josey et.al. formula 1 2003
         x1=emiss*tw_k**4
         x2=(10.77*tcc+2.34)*tcc-18.44
         x3=0.955*(ta_k+x2)**4
         qb=bolz*(x1-x3)
      case(josey2)
!        Use Josey et.al. formula 2 2003
         x1=emiss*tw_k**4
!AS avoid zero trap, limit to about 1% rel. humidity ~ 10Pa
         if ( ea .lt. 10.0 ) ea = 10.0
         x2=34.07+4157.0/(log(2.1718e10/ea))
         x2=(10.77*tcc+2.34)*tcc-18.44+0.84*(x2-ta_k+4.01)
         x3=0.955*(ta_k+x2)**4
         qb=bolz*(x1-x3)
      case default
         stop 'fluxes: back_radiation_method'
   end select

   hf = -(qe+qh+qb)

   tmp   = cd_mom*rho_air*w
   taux  = tmp*u10
   tauy  = tmp*v10

   if (precip .gt. _ZERO_) then
!     sensible heat due to rain
      hf = hf - precip*rho_precip* cd_precip
!     momentum flux due to rainfall (in kg/m^2/s)
!     according to Caldwell and Elliott (1971, JPO)
      tmp  = 0.85d0 * precip*rho_precip
      taux  = taux + tmp * u10
      tauy  = tauy + tmp * v10
   end if

   if (fwf_method .ge. 2) then
      evap = rho_air/rho_0*cd_latent*w*(qa-qs)
   end if

   return
   end subroutine fluxes
!EOC

!-----------------------------------------------------------------------
!Copyright (C) 2001 - Karsten Bolding & Hans Burchard
!-----------------------------------------------------------------------
