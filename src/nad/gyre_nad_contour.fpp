! Program  : gyre_nad_contour
! Purpose  : nonadiabatic discriminant contouring code
!
! Copyright 2013-2015 Rich Townsend
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

program gyre_nad_contour

  ! Uses

  use core_kinds, SP_ => SP
  use gyre_constants
  use core_hgroup
  use core_order
  use core_parallel

  use gyre_bvp
  use gyre_contour_map
  use gyre_contour_seg
  use gyre_discrim_func
  use gyre_ext
  use gyre_grid
  use gyre_grid_par
  use gyre_input
  use gyre_mode
  use gyre_model
  $if($MPI)
  use gyre_model_mpi
  $endif
  use gyre_mode_par
  use gyre_nad_bvp
  use gyre_num_par
  use gyre_osc_par
  use gyre_root
  use gyre_scan_par
  use gyre_search
  use gyre_status
  use gyre_trad
  use gyre_util
  use gyre_version

  use ISO_FORTRAN_ENV

  ! No implicit typing

  implicit none

  ! Variables

  character(:), allocatable        :: filename
  character(:), allocatable        :: gyre_dir
  integer                          :: unit
  real(WP), allocatable            :: x_ml(:)
  class(model_t), pointer          :: ml => null()
  type(mode_par_t), allocatable    :: mp(:)
  type(osc_par_t), allocatable     :: op(:)
  type(num_par_t), allocatable     :: np(:)
  type(grid_par_t), allocatable    :: shoot_gp(:)
  type(grid_par_t), allocatable    :: recon_gp(:)
  type(scan_par_t), allocatable    :: sp(:)
  type(scan_par_t), allocatable    :: sp_re(:)
  type(scan_par_t), allocatable    :: sp_im(:)
  real(WP)                         :: x_i
  real(WP)                         :: x_o
  real(WP), allocatable            :: omega_re(:)
  real(WP), allocatable            :: omega_im(:)
  real(WP)                         :: omega_min
  real(WP)                         :: omega_max
  real(WP), allocatable            :: x_sh(:)
  class(c_bvp_t), allocatable      :: nad_bp
  integer                          :: n_omega_re
  integer                          :: n_omega_im
  type(c_ext_t), allocatable       :: discrim_map(:,:)
  type(contour_map_t)              :: cm_re
  type(contour_map_t)              :: cm_im
  type(contour_seg_t), allocatable :: is_re(:)
  type(contour_seg_t), allocatable :: is_im(:)
  character(FILENAME_LEN)          :: map_filename
  type(hgroup_t)                   :: hg

  ! Initialize

  call init_parallel()
  call init_system(filename, gyre_dir)

  call set_log_level($str($LOG_LEVEL))

  if(check_log_level('INFO')) then

     write(OUTPUT_UNIT, 100) form_header('gyre_nad_map ['//TRIM(version)//']', '=')
100  format(A)

     write(OUTPUT_UNIT, 110) 'Compiler         : ', COMPILER_VERSION()
     write(OUTPUT_UNIT, 110) 'Compiler options : ', COMPILER_OPTIONS()
110  format(2A)

     write(OUTPUT_UNIT, 120) 'OpenMP Threads   : ', OMP_SIZE_MAX
     write(OUTPUT_UNIT, 120) 'MPI Processors   : ', MPI_SIZE
120  format(A,I0)
     
     write(OUTPUT_UNIT, 110) 'Input filename   :', filename
     write(OUTPUT_UNIT, 110) 'GYRE_DIR         :', gyre_dir

     write(OUTPUT_UNIT, 100) form_header('Initialization', '=')

  endif

  call init_trad(gyre_dir)

  ! Process arguments

  if(MPI_RANK == 0) then

     open(NEWUNIT=unit, FILE=filename, STATUS='OLD')

     call read_constants(unit)
     call read_model(unit, x_ml, ml)
     call read_mode_par(unit, mp)
     call read_osc_par(unit, op)
     call read_num_par(unit, np)
     call read_shoot_grid_par(unit, shoot_gp)
     call read_recon_grid_par(unit, recon_gp)
     call read_scan_par(unit, sp)
     call read_out_par(unit, map_filename)

  endif

  $if($MPI)
  call bcast_constants(0)
  call bcast_alloc(x_ml, 0)
  call bcast_alloc(ml, 0)
  call bcast_alloc(mp, 0)
  call bcast_alloc(op, 0)
  call bcast_alloc(np, 0)
  call bcast_alloc(shoot_gp, 0)
  call bcast_alloc(recon_gp, 0)
  call bcast_alloc(sp, 0)
  $endif

  ! Select parameters according to tags

  call select_par(sp, 'REAL', sp_re)
  call select_par(sp, 'IMAG', sp_im)

  $ASSERT(SIZE(op) == 1,No matching osc parameters)
  $ASSERT(SIZE(np) == 1,No matching num parameters)
  $ASSERT(SIZE(shoot_gp) >= 1,No matching shoot_grid parameters)
  $ASSERT(SIZE(recon_gp) >= 1,No matching recon_grid parameters)
  $ASSERT(SIZE(sp_im) == 1,No matching scan parameters)
  $ASSERT(SIZE(sp_re) == 1,No matching scan parameters)

  ! Set up the frequency arrays

  if (allocated(x_ml)) then
     x_i = x_ml(1)
     x_o = x_ml(SIZE(x_ml))
  else
     x_i = 0._WP
     x_o = 1._WP
  endif

  call build_scan(sp_re, ml, mp(1), op(1), x_i, x_o, omega_re)
  call build_scan(sp_im, ml, mp(1), op(1), x_i, x_o, omega_im)

  omega_min = MINVAL(omega_re)
  omega_max = MAXVAL(omega_re)

  ! Set up the shooting grid

  call build_grid(shoot_gp, ml, mp(1), op(1), omega_re, x_ml, x_sh, verbose=.TRUE.)

  ! Set up the bvp

  allocate(nad_bp, SOURCE=nad_bvp_t(x_sh, ml, mp(1), op(1), np(1), omega_min, omega_max))

  ! Evaluate the discriminant map

  call eval_map(nad_bp, omega_re, omega_im, discrim_map)

  ! Create the contour maps

  cm_re = contour_map_t(r_ext_t(omega_re), r_ext_t(omega_im), real_part(discrim_map))
  cm_im = contour_map_t(r_ext_t(omega_re), r_ext_t(omega_im), imag_part(discrim_map))

  ! Search for contour intersections

  call find_isects(cm_re, cm_im, is_re, is_im)

  ! Find roots

  call find_roots(nad_bp, mp(1), np(1), op(1), is_re, is_im)

  ! Write out the segments

  if (MPI_RANK == 0) then
     call write_segs(cm_re, 'cm_re.segs')
     call write_segs(cm_im, 'cm_im.segs')
  endif

  ! Write out the map

  if (MPI_RANK == 0) then

     hg = hgroup_t(map_filename, CREATE_FILE)

     call write_dset(hg, 'omega_re', omega_re)
     call write_dset(hg, 'omega_im', omega_im)

     call write_dset(hg, 'discrim_map_f', FRACTION(discrim_map))
     call write_dset(hg, 'discrim_map_e', EXPONENT(discrim_map))

     call hg%final()

  end if

  ! Finish

  call final_parallel()

contains

  subroutine read_out_par (unit, map_file)

    integer, intent(in)       :: unit
    character(*), intent(out) :: map_file

    namelist /output/ map_file

    ! Read output parameters

    rewind(unit)

    read(unit, NML=output)

    ! Finish
    
    return

  end subroutine read_out_par

!****

  subroutine eval_map (bp, omega_re, omega_im, discrim_map)

    class(c_bvp_t), intent(inout)           :: bp
    real(WP), intent(in)                    :: omega_re(:)
    real(WP), intent(in)                    :: omega_im(:)
    type(c_ext_t), allocatable, intent(out) :: discrim_map(:,:)

    integer              :: n_omega_re
    integer              :: n_omega_im
    integer, allocatable :: k_part(:)
    integer              :: n_percent
    integer              :: k
    integer              :: i(2)
    complex(WP)          :: omega
    integer              :: i_percent
    integer              :: status
    $if ($MPI)
    integer              :: p
    $endif

    ! Allocate the discriminant map

    n_omega_re = SIZE(omega_re)
    n_omega_im = SIZE(omega_im)

    allocate(discrim_map(n_omega_re,n_omega_im))

    allocate(k_part(MPI_SIZE+1))

    ! Evaluate it

    call partition_tasks(n_omega_re*n_omega_im, 1, k_part)

    n_percent = 0

    map_loop : do k = k_part(MPI_RANK+1), k_part(MPI_RANK+2)-1

       i = index_nd(k, [n_omega_re,n_omega_im])

       omega = CMPLX(omega_re(i(1)), omega_im(i(2)), KIND=WP)

       if (MPI_RANK == 0) then
          i_percent = FLOOR(100._WP*REAL(k-k_part(MPI_RANK+1))/REAL(k_part(MPI_RANK+2)-k_part(MPI_RANK+1)-1))
          if (i_percent > n_percent) then
             print *,'Percent complete: ', i_percent
             n_percent = i_percent
          end if
       endif
     
       call bp%eval_discrim(omega, discrim_map(i(1),i(2)), status)
       $ASSERT(status == STATUS_OK,Invalid status)

    end do map_loop

    $if($MPI)

    do p = 1,MPI_SIZE
       call bcast_seq(discrim_map_f, k_part(p), k_part(p+1)-1, p-1)
       call bcast_seq(discrim_map_e, k_part(p), k_part(p+1)-1, p-1)
    end do

    $endif

    ! Finish

    return

  end subroutine eval_map

!****

  subroutine find_isects (cm_re, cm_im, is_re, is_im)

    type(contour_map_t), intent(in)               :: cm_re
    type(contour_map_t), intent(in)               :: cm_im
    type(contour_seg_t), allocatable, intent(out) :: is_re(:)
    type(contour_seg_t), allocatable, intent(out) :: is_im(:)

    integer                          :: i_x
    integer                          :: i_y
    type(contour_seg_t), allocatable :: cs_re(:)
    type(contour_seg_t), allocatable :: cs_im(:)
    integer                          :: j_re
    integer                          :: j_im
    type(r_ext_t)                    :: M(2,2)
    type(r_ext_t)                    :: R(2)
    type(r_ext_t)                    :: D
    type(r_ext_t)                    :: w_im
    type(r_ext_t)                    :: w_re

    $CHECK_BOUNDS(cm_im%n_x,cm_re%n_x)
    $CHECK_BOUNDS(cm_im%n_y,cm_re%n_y)

    ! Loop through the cells of the real/imaginary contour maps,
    ! looking for intersections between the respective contour
    ! segments

    allocate(is_re(0))
    allocate(is_im(0))

    do i_x = 1, cm_re%n_x-1
       do i_y = 1, cm_im%n_y-1

          ! Get the contour segments for the current cell

          call cm_re%get_segs(i_x, i_y, cs_re)
          call cm_im%get_segs(i_x, i_y, cs_im)

          ! Look for pairwise intersections

          do j_re = 1, SIZE(cs_re)
             do j_im = 1, SIZE(cs_im)

                ! Solve for the intersection between the two line segments

                M(1,1) = cs_re(j_re)%x(2) - cs_re(j_re)%x(1)
                M(1,2) = cs_im(j_im)%x(1) - cs_im(j_im)%x(2)
                
                M(2,1) = cs_re(j_re)%y(2) - cs_re(j_re)%y(1)
                M(2,2) = cs_im(j_im)%y(1) - cs_im(j_im)%y(2)

                R(1) = -cs_re(j_re)%x(1) + cs_im(j_im)%x(1)
                R(2) = -cs_re(j_re)%y(1) + cs_im(j_im)%y(1)

                D = M(1,1)*M(2,2) - M(1,2)*M(2,1)

                if (D /= 0._WP) then

                   ! Lines intersect

                   w_re = (M(2,2)*R(1) - M(1,2)*R(2))/D
                   w_im = (M(1,1)*R(2) - M(2,1)*R(1))/D

                   if (w_re >= 0._WP .AND. w_re <= 1._WP .AND. &
                       w_im >= 0._WP .AND. w_im <= 1._WP) then

                      ! Lines intersect within the cell; save the
                      ! intersecting segments

                      is_re = [is_re,cs_re]
                      is_im = [is_im,cs_im]

                   end if

                endif
                         
             end do
          end do

       end do
    end do

    ! Finish
    
    return

  end subroutine find_isects

!****

  subroutine find_roots (bp, mp, np, op, is_re, is_im)

    class(c_bvp_t), target, intent(inout)        :: bp
    type(mode_par_t), intent(in)                 :: mp
    type(num_par_t), intent(in)                  :: np 
    type(osc_par_t), intent(in)                  :: op
    type(contour_seg_t), allocatable, intent(in) :: is_re(:)
    type(contour_seg_t), allocatable, intent(in) :: is_im(:)

    type(c_discrim_func_t) :: df
    integer                :: j
    type(c_ext_t)          :: omega_a
    type(c_ext_t)          :: omega_b
    type(c_ext_t)          :: discrim_a
    type(c_ext_t)          :: discrim_b
    integer                :: status
    type(c_ext_t)          :: omega_root
    integer                :: n_iter

    $CHECK_BOUNDS(SIZE(is_re),SIZE(is_im))

    ! Set up the discriminant function

    df = c_discrim_func_t(bp)

    ! Loop over pairs of intersecting segments

    intseg_loop : do j = 1, SIZE(is_re)

       ! Set up initial guesses

       omega_a = omega_initial(is_re(j), .TRUE.)
       omega_b = omega_initial(is_im(j), .FALSE.)

       call df%eval(omega_a, discrim_a, status)
       $ASSERT(status == STATUS_OK,Invalid status)

       call df%eval(omega_b, discrim_b, status)
       $ASSERT(status == STATUS_OK,Invalid status)

       ! Find the discriminant root

       call solve(df, np, omega_a, omega_b, r_ext_t(0._WP), omega_root, status, &
                  n_iter=n_iter, n_iter_max=np%n_iter_max, f_cx_a=discrim_a, f_cx_b=discrim_b)

       ! Process it

       print *,'Root found:',cmplx(omega_root)

    end do intseg_loop

  end subroutine find_roots

!****

  function omega_initial (cs, real_seg) result (omega)

    type(contour_seg_t), intent(in) :: cs
    logical, intent(in)             :: real_seg
    type(c_ext_t)                   :: omega

    type(c_ext_t) :: omega_a
    type(c_ext_t) :: omega_b
    type(c_ext_t) :: discrim_a
    type(c_ext_t) :: discrim_b
    integer       :: status
    type(r_ext_t) :: w

    ! Evaluate the discriminant at the segment endpoints

    omega_a = c_ext_t(cs%x(1), cs%y(1))
    omega_b = c_ext_t(cs%x(2), cs%y(2))

    call nad_bp%eval_discrim(cmplx(omega_a), discrim_a, status)
    $ASSERT(status == STATUS_OK,Invalid status)

    call nad_bp%eval_discrim(cmplx(omega_b), discrim_b, status)
    $ASSERT(status == STATUS_OK,Invalid status)

    ! Look for the point on the segment where the real/imaginary part of the discriminant changes sign

    if (real_seg) then
       w = -imag_part(discrim_a)/(imag_part(discrim_b) - imag_part(discrim_a))
    else
       w = -real_part(discrim_a)/(real_part(discrim_b) - real_part(discrim_a))
    endif
    
    omega = c_ext_t((1._WP-w)*cs%x(1) + w*cs%x(2), (1._WP-w)*cs%y(1) + w*cs%y(2))

    ! Finish
      
    return

  end function omega_initial

!****

  subroutine write_segs (cm, filename)

    type(contour_map_t), intent(in) :: cm
    character(*), intent(in)        :: filename

    integer                          :: unit
    integer                          :: i_x
    integer                          :: i_y
    type(contour_seg_t), allocatable :: cs(:)
    integer                          :: j

    ! Open the file

    open(NEWUNIT=unit, FILE=filename, STATUS='REPLACE')

    ! Loop through the map, writing out segment info

    do i_x = 1, cm%n_x-1
       do i_y = 1, cm%n_y-1
          call cm%get_segs(i_x, i_y, cs)
          do j = 1, SIZE(cs)
             write(unit, 100) real(cs(j)%x), real(cs(j)%y)
100          format(4(1X,E16.8))
          end do
       end do
    end do

    close(unit)

    ! Finish
    
    return

  end subroutine write_segs

end program gyre_nad_contour
