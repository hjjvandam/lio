!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%!
subroutine ehrendyn_main( energy_o, dipmom_o )
!------------------------------------------------------------------------------!
!
!  stored_densM1 and stored_densM2 are stored in ON basis, except for the 
!  first step
!
!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%!
   use garcha_mod, &
   &  only: M, natom, atom_mass, nucpos, nucvel, qm_forces_ds, qm_forces_total

   use td_data, &
   &  only: tdstep

   use lionml_data, &
   &  only: ndyn_steps, edyn_steps, propagator &
   &      , rsti_loads, rsti_fname, rsto_saves, rsto_nfreq, rsto_fname

   use ehrendata, &
   &  only: stored_time, stored_energy, stored_densM1, stored_densM2           &
   &      , rsti_funit, rsto_funit, nustep_count, elstep_count

   implicit none
   real*8,intent(inout) :: dipmom_o(3), energy_o
   real*8               :: dipmom(3)  , energy  , energy0
   real*8               :: dipmom_norm

   real*8  :: time, dtn, dte, dtaux
   integer :: elstep_local, elstep_keeps
   integer :: substep, substeps
   integer :: nn, kk

   logical :: first_nustep
   logical :: load_restart
   logical :: rhomid_in_ao
   logical :: missing_last

   real*8, allocatable, dimension(:,:) :: kept_forces
   real*8, allocatable, dimension(:,:) :: Smat, Sinv
   real*8, allocatable, dimension(:,:) :: Lmat, Umat, Linv, Uinv
   real*8, allocatable, dimension(:,:) :: Fock, Fock0
   real*8, allocatable, dimension(:,:) :: Bmat, Dmat

   complex*16, allocatable, dimension(:,:) :: RhoOld, RhoMid, RhoNew
   complex*16, allocatable, dimension(:,:) :: RhoMidF
   complex*16, allocatable, dimension(:,:) :: Tmat
!
!
!
!  Preliminaries
!------------------------------------------------------------------------------!
   call g2g_timer_start('ehrendyn - nuclear step')
   nustep_count = nustep_count + 1
   time = stored_time

   allocate( kept_forces(3,natom) )
   allocate( Smat(M,M), Sinv(M,M) )
   allocate( Lmat(M,M), Umat(M,M), Linv(M,M), Uinv(M,M) )
   allocate( Fock(M,M), Fock0(M,M) )
   allocate( RhoOld(M,M), RhoMid(M,M), RhoNew(M,M), RhoMidF(M,M) )
   allocate( Bmat(M,M), Dmat(M,M), Tmat(M,M) )

   dtn = tdstep
   dte = ( tdstep / edyn_steps )

   first_nustep = (nustep_count == 1)
   load_restart = (first_nustep).and.(rsti_loads)
   rhomid_in_ao = (first_nustep).and.(.not.rsti_loads)
   missing_last = (first_nustep).and.(.not.rsti_loads)

   if (load_restart) then
      print*,'RESTART LOAD DISABLED FOR MAINTENANCE'
!      call ehrenaux_rsti( rsti_fname, rsti_funit, natom, qm_forces_total,  &
!                         & nucvel, M, stored_densM1, stored_densM2 )
   endif

!
!
!
!  Update velocities, calculate fixed fock, load last step dens matrices
!------------------------------------------------------------------------------!
   call ehrenaux_updatevel( natom, atom_mass, qm_forces_total, nucvel, dtn )

   energy0 = 0.0d0
   call RMMcalc0_Init()
   call RMMcalc1_Overlap( Smat, energy0 )
   call ehrenaux_cholesky( M, Smat, Lmat, Umat, Linv, Uinv, Sinv )
   call RMMcalc2_FockMao( Fock0, energy0 )

   RhoOld = stored_densM1
   RhoMid = stored_densM2
   if (rhomid_in_ao) then
      RhoMid = matmul(RhoMid, Lmat)
      RhoMid = matmul(Umat, RhoMid)
      stored_densM2 = RhoMid
   endif
!
!
!
!  ELECTRONIC STEP CYCLE
!------------------------------------------------------------------------------!
   elstep_keeps = ceiling( real(edyn_steps) / 2.0 )

   do elstep_local = 1, edyn_steps
      call g2g_timer_start('ehrendyn - electronic step')
      elstep_count = elstep_count + 1
      dipmom(:) = 0.0d0
      energy = energy0
      Fock = Fock0
      substeps = 20

      if (missing_last) then
         dtaux = (-dte) / ( (2.0d0)*(substeps) )
         RhoOld = RhoMid
         call ehrendyn_step( 1, time, dtaux, M, natom, nucpos, nucvel,             &
                       & qm_forces_ds, Sinv, Uinv, Linv, RhoOld, RhoMid,       &
                       & RhoNew, Fock, energy, dipmom )
         RhoOld = RhoNew
         dtaux = (dte) / (substeps)

         do substep = 1, substeps
            dipmom(:) = 0.0d0
            energy = energy0
            Fock = Fock0
            call ehrendyn_step( 1, time, dtaux, M, natom, nucpos, nucvel,          &
                          & qm_forces_ds, Sinv, Uinv, Linv, RhoOld, RhoMid,    &
                          & RhoNew, Fock, energy, dipmom )
            RhoOld = RhoMid
            RhoMid = RhoNew
         enddo
         RhoOld = stored_densM2
         missing_last = .false.

      else
         call ehrendyn_step( propagator, time, dte, M, natom, nucpos, nucvel,      &
                       & qm_forces_ds, Sinv, Uinv, Linv, RhoOld, RhoMid,       &
                       & RhoNew, Fock, energy, dipmom )
         RhoOld = RhoMid
         RhoMid = RhoNew

      end if

      call ehrenaux_updatevel( natom, atom_mass, qm_forces_total, nucvel, dte )
      if ( elstep_local == elstep_keeps ) kept_forces = qm_forces_ds
      time = time + dte * 0.0241888d0
      call g2g_timer_stop('ehrendyn - electronic step')

   enddo

   stored_densM1 = RhoOld
   stored_densM2 = RhoMid
   qm_forces_ds = kept_forces
!
!
!
!  Finalizations
!------------------------------------------------------------------------------!
   call ehrenaux_writedip(nustep_count, 1, time, dipmom, "dipole_moment.dat")
   if (rsto_saves) then
      print*,'RESTART SAVE DISABLED FOR MAINTENANCE'
!      call ehrenaux_rsto( rsto_fname, rsto_funit, rsto_nfreq, ndyn_steps,     &
!         & nustep_count, Natom, qm_forces_total, nucvel,                       &
!         & M, stored_densM1, stored_densM2)
   endif

   dipmom_o = dipmom
   energy_o = stored_energy
   stored_energy = energy
   stored_time = time

   deallocate( Smat, Sinv )
   deallocate( Lmat, Umat, Linv, Uinv )
   deallocate( Fock, Fock0 )
   deallocate( RhoOld, RhoMid, RhoNew, RhoMidF )
   deallocate( Bmat, Dmat, Tmat )
   call g2g_timer_stop('ehrendyn - nuclear step')

901 format(F15.9,2x,F15.9)
end subroutine ehrendyn_main
!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%!