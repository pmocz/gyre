! Module   : gyre_mech_coeffs_poly
! Purpose  : Adiabatic structure coefficients for polytropic models
!
! Copyright 2013 Rich Townsend
!
! This file is part of GYRE. GYRE is free software: you can
! redistribute it and/or modify it under the terms of the GNU General
! Public License as published by the Free Software Foundation, version 3.
!
! GYRE is distributed in the hope that it will be useful, but WITHOUT
! ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
! or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
! License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.

$include 'core.inc'

module gyre_mech_coeffs_poly

  ! Uses

  use core_kinds
  use core_parallel
  use core_spline
  use core_hgroup

  use gyre_mech_coeffs

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Derived-type definitions

  $define $PROC_DECL $sub
    $local $NAME $1
    procedure :: get_${NAME}_1
    procedure :: get_${NAME}_v
  $endsub

  type, extends(mech_coeffs_t) :: mech_coeffs_poly_t
     private
     type(spline_t) :: sp_Theta
     type(spline_t) :: sp_dTheta
     real(WP)       :: n_poly
     real(WP)       :: dt_Gamma_1
     real(WP)       :: xi_1
   contains
     private
     procedure, public :: init
     $if($MPI)
     procedure, public :: bcast => bcast_mc
     $endif
     procedure, public :: read
     $PROC_DECL(V)
     $PROC_DECL(As)
     $PROC_DECL(U)
     $PROC_DECL(c_1)
     $PROC_DECL(Gamma_1)
     procedure, public :: conv_freq
  end type mech_coeffs_poly_t

  ! Access specifiers

  private

  public :: mech_coeffs_poly_t

  ! Procedures

contains

  subroutine init (this, xi, Theta, dTheta, n_poly, Gamma_1)

    class(mech_coeffs_poly_t), intent(out) :: this
    real(WP), intent(in)                   :: xi(:)
    real(WP), intent(in)                   :: Theta(:)
    real(WP), intent(in)                   :: dTheta(:)
    real(WP), intent(in)                   :: n_poly
    real(WP), intent(in)                   :: Gamma_1

    integer :: n

    $CHECK_BOUNDS(SIZE(Theta),SIZE(xi))

    ! Initialize the mech_coeffs

    n = SIZE(xi)

    call this%sp_Theta%init(xi, Theta, dy_dx_a=0._WP, dy_dx_b=dTheta(n))
    call this%sp_dTheta%init(xi, dTheta, dy_dx_a=-1._WP/3._WP, dy_dx_b=-2._WP*dTheta(n)/xi(n))

    this%n_poly = n_poly
    this%dt_Gamma_1 = Gamma_1
    this%xi_1 = xi(n)

    ! Finish

    return

  end subroutine init

!****

  $if($MPI)

  subroutine bcast_mc (this, root_rank)

    class(mech_coeffs_poly_t), intent(inout) :: this
    integer, intent(in)                      :: root_rank

    ! Broadcast the mech_coeffs

    call this%sp_Theta%bcast(root_rank)
    call this%sp_dTheta%bcast(root_rank)

    call bcast(this%n_poly, root_rank)
    call bcast(this%dt_Gamma_1, root_rank)
    call bcast(this%xi_1, root_rank)

    ! Finish

    return

  end subroutine bcast_mc

  $endif

!****

  subroutine read (this, file, x)

    class(mech_coeffs_poly_t), intent(out)       :: this
    character(LEN=*), intent(in)                 :: file
    real(WP), allocatable, intent(out), optional :: x(:)

    type(hgroup_t)        :: hg
    real(WP)              :: n_poly
    real(WP)              :: Gamma_1
    real(WP), allocatable :: xi(:)
    real(WP), allocatable :: Theta(:)
    real(WP), allocatable :: dTheta(:)

    ! Read the mech_coeffs from the file

    call hg%init(file, OPEN_FILE)

    call read_attr(hg, 'n_poly', n_poly)
    call read_attr(hg, 'Gamma_1', Gamma_1)

    call read_dset(hg, 'xi', xi, alloc=.TRUE.)
    call read_dset(hg, 'Theta', Theta, alloc=.TRUE.)
    call read_dset(hg, 'dTheta', dTheta, alloc=.TRUE.)

    call hg%final()

    ! Initialize the ad_coeffs

    call this%init(xi, Theta, dTheta, n_poly, Gamma_1)

    ! If necessary, return the grid

    if(PRESENT(x)) then
       x = xi/xi(SIZE(xi))
    endif

    ! Finish

    return

  end subroutine read

!****

  function get_V_1 (this, x) result (V)

    class(mech_coeffs_poly_t), intent(in) :: this
    real(WP), intent(in)                  :: x
    real(WP)                              :: V

    real(WP) :: xi
    real(WP) :: Theta
    real(WP) :: dTheta

    ! Calculate V

    xi = x*this%xi_1

    Theta = this%sp_Theta%interp(xi)
    dTheta = this%sp_dTheta%interp(xi)

    V = -(this%n_poly + 1._WP)*xi*dTheta/Theta

    ! Finish

    return

  end function get_V_1

!****

  function get_V_v (this, x) result (V)

    class(mech_coeffs_poly_t), intent(in) :: this
    real(WP), intent(in)                  :: x(:)
    real(WP)                              :: V(SIZE(x))

    integer :: i

    ! Calculate V

    x_loop : do i = 1,SIZE(x)
       V(i) = this%V(x(i))
    end do x_loop

    ! Finish

    return

  end function get_V_v

!****

  function get_As_1 (this, x) result (As)

    class(mech_coeffs_poly_t), intent(in) :: this
    real(WP), intent(in)                  :: x
    real(WP)                              :: As

    ! Calculate As

    As = this%V(x)*(this%n_poly/(this%n_poly + 1._WP) - 1._WP/this%Gamma_1(x))

    ! Finish

    return

  end function get_As_1

!****

  function get_As_v (this, x) result (As)

    class(mech_coeffs_poly_t), intent(in) :: this
    real(WP), intent(in)                  :: x(:)
    real(WP)                              :: As(SIZE(x))

    integer :: i

    ! Calculate As

    x_loop : do i = 1,SIZE(x)
       As(i) = this%As(x(i))
    end do x_loop

    ! Finish

    return

  end function get_As_v

!****

  function get_U_1 (this, x) result (U)

    class(mech_coeffs_poly_t), intent(in) :: this
    real(WP), intent(in)                  :: x
    real(WP)                              :: U

    real(WP) :: xi
    real(WP) :: Theta
    real(WP) :: dTheta

    ! Calculate U

    xi = x*this%xi_1

    Theta = this%sp_Theta%interp(xi)
    dTheta = this%sp_dTheta%interp(xi)

    if(x /= 0._WP) then
       U = -xi*Theta**this%n_poly/dTheta
    else
       U = 3._WP
    endif

    ! Finish

    return

  end function get_U_1

!****

  function get_U_v (this, x) result (U)

    class(mech_coeffs_poly_t), intent(in) :: this
    real(WP), intent(in)                  :: x(:)
    real(WP)                              :: U(SIZE(x))

    integer :: i

    ! Calculate U

    x_loop : do i = 1,SIZE(x)
       U(i) = this%U(x(i))
    end do x_loop

    ! Finish

    return

  end function get_U_v

!****

  function get_c_1_1 (this, x) result (c_1)

    class(mech_coeffs_poly_t), intent(in) :: this
    real(WP), intent(in)                  :: x
    real(WP)                              :: c_1

    real(WP) :: xi
    real(WP) :: dTheta
    real(WP) :: dTheta_1

    ! Calculate c_1

    xi = x*this%xi_1

    dTheta = this%sp_dTheta%interp(xi)
    dTheta_1 = this%sp_dTheta%interp(this%xi_1)

    if(x /= 0._WP) then
       c_1 = x*dTheta_1/dTheta
    else
       c_1 = -3._WP*dTheta_1/this%xi_1
    endif

    ! Finish

    return

  end function get_c_1_1

!****

  function get_c_1_v (this, x) result (c_1)

    class(mech_coeffs_poly_t), intent(in) :: this
    real(WP), intent(in)                  :: x(:)
    real(WP)                              :: c_1(SIZE(x))

    integer :: i

    ! Calculate c_1

    x_loop : do i = 1,SIZE(x)
       c_1(i) = this%c_1(x(i))
    end do x_loop

    ! Finish

    return
    
  end function get_c_1_v

!****

  function get_Gamma_1_1 (this, x) result (Gamma_1)

    class(mech_coeffs_poly_t), intent(in) :: this
    real(WP), intent(in)                  :: x
    real(WP)                              :: Gamma_1

    ! Calculate Gamma_1

    Gamma_1 = this%dt_Gamma_1

    ! Finish

    return

  end function get_Gamma_1_1

!****
  
  function get_Gamma_1_v (this, x) result (Gamma_1)

    class(mech_coeffs_poly_t), intent(in) :: this
    real(WP), intent(in)                  :: x(:)
    real(WP)                              :: Gamma_1(SIZE(x))

    integer :: i

    ! Calculate Gamma_1
    
    x_loop : do i = 1,SIZE(x)
       Gamma_1(i) = this%Gamma_1(x(i))
    end do x_loop

    ! Finish

    return

  end function get_Gamma_1_v

!****

  function conv_freq (this, freq, from_units, to_units)

    class(mech_coeffs_poly_t), intent(in) :: this
    complex(WP), intent(in)               :: freq
    character(LEN=*), intent(in)          :: from_units
    character(LEN=*), intent(in)          :: to_units
    complex(WP)                           :: conv_freq

    ! Convert the frequency

    conv_freq = freq/freq_scale(from_units)*freq_scale(to_units)

    ! Finish

    return

  contains

    function freq_scale (units)

      character(LEN=*), intent(in) :: units
      real(WP)                     :: freq_scale

      ! Calculate the scale factor to convert a dimensionless angular
      ! frequency to a dimensioned frequency

      select case (units)
      case ('NONE')
         freq_scale = 1._WP
      case default
         $ABORT(Invalid units)
      end select

      ! Finish

      return

    end function freq_scale

  end function conv_freq

end module gyre_mech_coeffs_poly
