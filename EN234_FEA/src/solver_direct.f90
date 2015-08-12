 !  
!  Routines for solution by LU decomposition with skyline storage
!
!====================Subroutine ASSTIF ======================
subroutine assemble_direct_stiffness(fail)
    use Types
    use ParamIO
    use User_Subroutine_Storage
    use Mesh
    use Boundaryconditions
    use Stiffness
    implicit none

    logical, intent(out) :: fail

    ! Local Variables
    integer      :: i1, i2, icol, irow, iu, ix, j,k, j1, j2, status
    integer      :: lmn, n
    integer      :: nn, node1, node2, nsc, nsr
    integer      :: iof, ns,nc,dof1,dof2,iof1,iof2,nnodes,nset
    integer      :: ipar, npar, idof

    real( prec ), allocatable    :: element_coords(:)
    real( prec ), allocatable    :: element_dof_increment(:)
    real( prec ), allocatable    :: element_dof_total(:)
                                                            
    real( prec ), allocatable   :: element_stiffness(:,:)
    real( prec ), allocatable   :: element_residual(:)
  
    real( prec ) :: diagnorm, lmult

    type (node), allocatable ::  local_nodes(:)

    !     Subroutine to assemble global stiffness matrix

    allocate(element_coords(length_coord_array), stat = status)
    allocate(element_dof_increment(length_dof_array), stat = status)
    allocate(element_dof_total(length_dof_array), stat = status)
    allocate(local_nodes(length_node_array), stat = status)
    allocate(element_stiffness(length_dof_array,length_dof_array), stat = status)
    allocate(element_residual(length_dof_array), stat = status)
  
    if (status/=0) then
        write(IOW,*) ' Error in subroutine assemble_direct_stiffness '
        write(IOW,*) ' Unable to allocate memory for user subroutines '
        stop
    endif


    aupp = 0.d0
    if (unsymmetric_stiffness) alow = 0.d0
    rhs = 0.d0
    diag = 0.d0

    do lmn = 1, n_elements
        !     Extract local coords, DOF for the element
        ix = 0
        iu = 0
        do j = 1, element_list(lmn)%n_nodes
            n = connectivity(element_list(lmn)%connect_index + j - 1)
            local_nodes(j)%n_coords = node_list(n)%n_coords
            local_nodes(j)%coord_index = ix+1
            do k = 1, node_list(n)%n_coords
                ix = ix + 1
                element_coords(ix) = coords(node_list(n)%coord_index + k - 1)
            end do
            local_nodes(j)%n_dof = node_list(n)%n_dof
            local_nodes(j)%dof_index = iu+1
            do k = 1, node_list(n)%n_dof
                iu = iu + 1
                element_dof_increment(iu) = dof_increment(node_list(n)%dof_index + k - 1)
                element_dof_total(iu) = dof_total(node_list(n)%dof_index + k - 1)
            end do
        end do

        !     Form element stiffness
        iof = element_list(lmn)%state_index
        if (iof==0) iof = 1
        ns = element_list(lmn)%n_states
        if (ns==0) ns=1

        call user_element_static(lmn, element_list(lmn)%flag, element_list(lmn)%n_nodes, local_nodes, &       ! Input variables
            element_list(lmn)%n_element_properties, element_properties(element_list(lmn)%element_property_index),  &     ! Input variables
            element_coords, element_dof_increment, element_dof_total,      &                              ! Input variables
            ns, initial_state_variables(iof:iof+ns-1), &                                                  ! Input variables
            updated_state_variables(iof:iof+ns),element_stiffness,element_residual, fail)                 ! Output variables
      

        if (fail) return

        !     --   Add element stiffness and residual to global array

        nsr = 0
        do i1 = 1, element_list(lmn)%n_nodes
            node1 = connectivity(i1 + element_list(lmn)%connect_index - 1)
            do j1 = 1, node_list(node1)%n_dof
                irow = ieqs(j1 + node_list(node1)%dof_index - 1)
                nsr = nsr + 1
                rhs(irow) = rhs(irow) + element_residual(nsr)
                nsc = 0
                do i2 = 1, element_list(lmn)%n_nodes
                    node2 = connectivity(i2 + element_list(lmn)%connect_index - 1)
                    do j2 = 1, node_list(node2)%n_dof
                        icol = ieqs(j2 + node_list(node2)%dof_index - 1)
                        nsc = nsc + 1
                        if ( icol==irow ) then
                            diag(irow) = diag(irow) + element_stiffness(nsr,nsc)
                        else if ( icol>irow ) then
                            nn = jpoin(icol) + irow - (icol - 1)
                            aupp(nn) = aupp(nn) + element_stiffness(nsr,nsc)
                            if ( unsymmetric_stiffness ) alow(nn) = alow(nn) + element_stiffness(nsc,nsr)
                        end if
                    end do
                end do
            end do
        end do
    end do

    diagnorm = sqrt(dot_product(diag(1:neq),diag(1:neq)))/neq         ! Norm of diagonal used to scale penalty in tie constraint
  
    do nc = 1, n_constraints
  
        if (constraint_list(nc)%flag < 3) then          ! Simple two-node tie constraint
            icol = ieqs(length_dofs+nc)
            node1 = constraint_list(nc)%node1
            dof1 = constraint_list(nc)%dof1
            iof1 = dof1 + node_list(node1)%dof_index - 1
            node2 = constraint_list(nc)%node2
            dof2 = constraint_list(nc)%dof2
            iof2 = dof2 + node_list(node2)%dof_index - 1
        
            irow = ieqs(iof1)
            rhs(irow) = rhs(irow) - lagrange_multipliers(nc)
            if (icol>irow) then
                nn = jpoin(icol) + irow - (icol - 1)
            else
                nn = jpoin(irow) + icol - (irow - 1)
            endif
            aupp(nn) = aupp(nn) + 1.d0
            if (unsymmetric_stiffness) alow(nn) = alow(nn) + 1.d0

            irow = ieqs(iof2)
            if (icol>irow) then
                nn = jpoin(icol) + irow - (icol - 1)
            else
                nn = jpoin(irow) + icol - (irow - 1)
            endif
            rhs(irow) = rhs(irow) + lagrange_multipliers(nc)
            aupp(nn) = aupp(nn) - 1.d0
            if (unsymmetric_stiffness) alow(nn) = alow(nn) - 1.d0

            rhs(icol) = dof_total(iof2)+dof_increment(iof2)-&
                       dof_total(iof1)-dof_increment(iof1)-lagrange_multipliers(nc)*1.d-12*diagnorm
            diag(icol) = 1.d-12*diagnorm
        else                                                                    ! General multi-node constraint
            nset = constraint_list(nc)%node1
            nnodes = nodeset_list(nset)%n_nodes
            ix = 0
            iu = 0
            do j = 1, nnodes
                n = node_lists(nodeset_list(nset)%index + j - 1)
                local_nodes(j)%n_coords = node_list(n)%n_coords
                local_nodes(j)%coord_index = ix+1
                do k = 1, node_list(n)%n_coords
                    ix = ix + 1
                    element_coords(ix) = coords(node_list(n)%coord_index + k - 1)
                end do
                local_nodes(j)%dof_index = iu+1
                do k = 1, node_list(n)%n_dof
                    iu = iu + 1
                    element_dof_increment(iu) = dof_increment(node_list(n)%dof_index + k - 1)
                    element_dof_total(iu) = dof_total(node_list(n)%dof_index + k - 1)
                end do
            end do

            ipar = constraintparameter_list(constraint_list(nc)%index_parameters)%index
            npar = constraintparameter_list(constraint_list(nc)%index_parameters)%n_parameters
            idof = constraint_list(nc)%node2                                 ! Index of node set containing DOF list
            lmult = lagrange_multipliers(nc)
            call user_constraint(nc, constraint_list(nc)%flag, nodeset_list(nset)%n_nodes, &
                local_nodes, node_lists(idof:idof+nnodes-1),&    ! Input variables
                npar, constraint_parameters(ipar:ipar+npar-1),element_coords, &                                   ! Input variables
                element_dof_increment, element_dof_total,lmult,  &                           ! Input variables
                element_stiffness,element_residual)      ! Output variables

            nsr = 0
            do i1 = 1, nnodes
                node1 = node_lists(nodeset_list(nset)%index + i1 - 1)
                j1 = node_lists(idof+i1-1)
                irow = ieqs(j1 + node_list(node1)%dof_index - 1)
                nsr = nsr + 1
                rhs(irow) = rhs(irow) + element_residual(nsr)
                nsc = 0
                do i2 = 1, nnodes
                    node2 = node_lists(nodeset_list(nset)%index + i2 - 1)
                    j2 = node_lists(idof+i2-1)
                    icol = ieqs(j2 + node_list(node2)%dof_index - 1)
                    nsc = nsc + 1
                    if ( icol==irow ) then
                        diag(irow) = diag(irow) + element_stiffness(nsr,nsc)
                    else if ( icol>irow ) then
                        nn = jpoin(icol) + irow - (icol - 1)
                        aupp(nn) = aupp(nn) + element_stiffness(nsr,nsc)
                        if ( unsymmetric_stiffness ) alow(nn) = alow(nn) + element_stiffness(nsc,nsr)
                    end if
                end do
            end do
            irow = ieqs(length_dofs+nc)
            nsr = nsr + 1
            rhs(irow) = rhs(irow) + element_residual(nsr)
            do i2 = 1, nnodes
                node2 = node_lists(nodeset_list(nset)%index + i2 - 1)
                j2 = node_lists(idof+i2-1)
                icol = ieqs(j2 + node_list(node2)%dof_index - 1)
                nsc = nsc + 1
                if ( icol==irow ) then
                    diag(irow) = diag(irow) + element_stiffness(nsr,nsc)
                else if ( icol>irow ) then
                    nn = jpoin(icol) + irow - (icol - 1)
                    aupp(nn) = aupp(nn) + element_stiffness(nsr,nsc)
                    if ( unsymmetric_stiffness ) alow(nn) = alow(nn) + element_stiffness(nsc,nsr)
                end if
            end do
            diag(irow) = diag(irow) + element_stiffness(nsr,nsr)
        endif
    end do

    !  Force a cutback if NaN is found in RHS.
    do n = 1, neq
        if (rhs(n)==rhs(n)+1.d0) then
            write(IOW,*) ' NaN detected in residual '
            flush(IOW)
            fail = .true.
            return
        endif
        if (isnan( rhs(n) ))  then
            write(IOW,*) ' NaN detected in residual '
            flush(IOW)
            fail = .true.
            return
        endif
    end do
    ! Store generalized nodal forces
    do n = 1, n_nodes
        do j = 1, node_list(n)%n_dof
            rforce(j + node_list(n)%dof_index - 1) = -rhs(ieqs(j + node_list(n)%dof_index - 1))
        end do
    end do
  
    nodal_force_norm = dsqrt(dot_product(rhs,rhs))
  
    deallocate(element_coords)
    deallocate(element_dof_increment)
    deallocate(element_dof_total)
    deallocate(element_stiffness)
    deallocate(element_residual)
  
  

end subroutine assemble_direct_stiffness



!====================Subroutine apply_direct_boundaryconditions =======================
subroutine apply_direct_boundaryconditions
    use Types
    use ParamIO
    use User_Subroutine_Storage
    use Mesh
    use Boundaryconditions
    use Stiffness
    use Globals, only: TIME,DTIME
    use Element_Utilities, only : facenodes
    implicit none

    interface
        subroutine traction_boundarycondition_static(flag,ndims,ndof,nfacenodes,element_coords,&
            element_dof_increment,element_dof_total,traction,&
            element_stiffness,element_residual)               ! Output variables
            use Types
            use ParamIO
            use Element_Utilities, only : N1 => shape_functions_1D
            use Element_Utilities, only : dNdxi1 => shape_function_derivatives_1D
            use Element_Utilities, only : dNdx1 => shape_function_spatial_derivatives_1D
            use Element_Utilities, only : xi1 => integrationpoints_1D, w1 => integrationweights_1D
            use Element_Utilities, only : N2 => shape_functions_2D
            use Element_Utilities, only : dNdxi2 => shape_function_derivatives_2D
            use Element_Utilities, only : dNdx2 => shape_function_spatial_derivatives_2D
            use Element_Utilities, only : xi2 => integrationpoints_2D, w2 => integrationweights_2D
            use Element_Utilities, only : initialize_integration_points
            use Element_Utilities, only : calculate_shapefunctions

            implicit none

            integer, intent( in )      :: flag                     ! Flag specifying traction type. 1=direct value; 2=history+direct; 3=normal+history
            integer, intent( in )      :: ndims                    ! No. coords for nodes
            integer, intent( in )      :: ndof                     ! No. DOFs for nodes
            integer, intent( in )      :: nfacenodes               ! No. nodes on face
            real( prec ), intent( in ) :: element_coords(:)        ! List of coords
            real( prec ), intent( in ) :: element_dof_total(:)     ! List of DOFs (not currently used, provided for extension to finite deformations)
            real( prec ), intent( in ) :: element_dof_increment(:) ! List of DOF increments (not used)
            real( prec ), intent( in ) :: traction(:)              ! Traction value

            real( prec ), intent( out )   :: element_stiffness(:,:)   ! Element stiffness (ROW,COLUMN)
            real( prec ), intent( out )   :: element_residual(:)      ! Element residual force (ROW)
  
        end subroutine traction_boundarycondition_static
    end interface



    ! Local Variables
    logical :: ignoredof

    real( prec ) :: ucur, dofvalue, dofvalue_correction, dloadvalue, force_value
  
    integer :: idof, ix,iu, i,j,k, lmn, n, iof,iofs, nhist, nparam, nnodes, status
    integer :: load,flag,elset,ifac,nel,param_index,ntract,ndims,ndof,nfacenodes
    integer :: nsr,i1,node1,j1,irow,nsc,i2,node2,j2,icol,nn
    integer :: list(8)
       
       
    real( prec ), allocatable    :: element_coords(:)
    real( prec ), allocatable    :: element_dof_increment(:)
    real( prec ), allocatable    :: element_dof_total(:)
                                                            
    real( prec ), allocatable   :: element_stiffness(:,:)
    real( prec ), allocatable   :: element_residual(:)
  
    real( prec ), allocatable   :: traction(:)
  


    type (node), allocatable ::  local_nodes(:)

    !     Subroutine to apply boundary conditions

    if (n_distributedloads>0) then
        allocate(element_coords(length_coord_array), stat = status)
        allocate(element_dof_increment(length_dof_array), stat = status)
        allocate(element_dof_total(length_dof_array), stat = status)
        allocate(local_nodes(length_node_array), stat = status)
        allocate(element_stiffness(length_dof_array,length_dof_array), stat = status)
        allocate(element_residual(length_dof_array), stat = status)
        allocate(traction(length_dof_array), stat = status)
    
        if (status /=0) then
            write(IOW,*) ' Error in subroutine apply_direct_boundaryconditions '
            write(IOW,*) ' Unable to allocate memory for distributed forces '
            stop
        endif
    endif
       
     !  -- Distributed forces on element faces
   
    do load = 1, n_distributedloads
        flag = distributedload_list(load)%flag
        elset = distributedload_list(load)%element_set
        ifac = distributedload_list(load)%face
        nel = elementset_list(elset)%n_elements
        iof = elementset_list(elset)%index
    
        if (flag<4) then
            do k  = 1, nel
                lmn = element_lists(iof+k-1)
                ndims = node_list(connectivity(element_list(lmn)%connect_index))%n_coords
                ndof = node_list(connectivity(element_list(lmn)%connect_index))%n_dof
                traction = 0.d0
                if (flag<3) then
                    ntract = distributedload_list(load)%n_dload_values
                    do i = 1,ntract
                        traction(i) = dload_values(distributedload_list(load)%index_dload_values+i-1)
                    end do
                else
                    ntract = 1
                    traction(1) = 1.d0
                endif
                if (flag==2) traction = traction/dsqrt(dot_product(traction,traction))
                if (flag>1) then
                    iof = history_list(distributedload_list(load)%history_number)%index
                    nhist = history_list(distributedload_list(load)%history_number)%n_timevals
                    call interpolate_history_table(history_data(1,iof),nhist,TIME+DTIME,dloadvalue)
                    traction = traction*dloadvalue
                endif

                call facenodes(ndims,element_list(lmn)%n_nodes,ifac,list,nfacenodes)
                ix = 0
                iu = 0
                do j = 1,nfacenodes
                    n = connectivity(element_list(lmn)%connect_index + list(j) - 1)
                    do i = 1,ndims
                        ix = ix + 1
                        element_coords(ix) = coords(node_list(n)%coord_index+i-1)
                    end do
                    do i = 1, node_list(n)%n_dof
                        iu = iu + 1
                        element_dof_increment(iu) = dof_increment(node_list(n)%dof_index + i - 1)
                        element_dof_total(iu) = dof_total(node_list(n)%dof_index + i - 1)
                    end do
                end do
  
                call traction_boundarycondition_static(flag,ndims,ndof,nfacenodes,element_coords(1:ix),&
                    element_dof_increment(1:iu),element_dof_total(1:iu),traction(1:ntract),&
                    element_stiffness,element_residual)               ! Output variables

                nsr = 0
                do i1 = 1,nfacenodes
                    node1 = connectivity(element_list(lmn)%connect_index + list(i1) - 1)
                    do j1 = 1, node_list(node1)%n_dof
                        irow = ieqs(j1 + node_list(node1)%dof_index - 1)
                        nsr = nsr + 1
                        rhs(irow) = rhs(irow) + element_residual(nsr)
                        nsc = 0
                        do i2 = 1,nfacenodes
                            node2 = connectivity(element_list(lmn)%connect_index+ list(i2) - 1)
                            do j2 = 1, node_list(node2)%n_dof
                                icol = ieqs(j2 + node_list(node2)%dof_index - 1)
                                nsc = nsc + 1
                                if ( icol==irow ) then
                                    diag(irow) = diag(irow) + element_stiffness(nsr,nsc)
                                else if ( icol>irow ) then
                                    nn = jpoin(icol) + irow - (icol - 1)
                                    aupp(nn) = aupp(nn) + element_stiffness(nsr,nsc)
                                    if ( unsymmetric_stiffness ) alow(nn) = alow(nn) + element_stiffness(nsc,nsr)
                                end if
                            end do
                        end do
                    end do
                end do
            end do
    
        else if (flag==4) then              ! User subroutine controlled distributed load

            param_index = subroutineparameter_list(distributedload_list(load)%subroutine_parameter_number)%index
            nparam = subroutineparameter_list(distributedload_list(load)%subroutine_parameter_number)%index
            if (param_index==0) param_index=1
            if (nparam==0) nparam = 1
            do k  = 1, nel
                lmn = element_lists(iof+k-1)
                !     Extract local coords, DOF for the element
                ix = 0
                iu = 0
                do j = 1, element_list(lmn)%n_nodes
                    n = connectivity(element_list(lmn)%connect_index + j - 1)
                    local_nodes(j)%n_coords = node_list(n)%n_coords
                    local_nodes(j)%coord_index = ix+1
                    do i = 1, node_list(n)%n_coords
                        ix = ix + 1
                        element_coords(ix) = coords(node_list(n)%coord_index + i - 1)
                    end do
                    local_nodes(j)%dof_index = iu+1
                    do i = 1, node_list(n)%n_dof
                        iu = iu + 1
                        element_dof_increment(iu) = dof_increment(node_list(n)%dof_index + i - 1)
                        element_dof_total(iu) = dof_total(node_list(n)%dof_index + i - 1)
                    end do
                end do
     
        
                call user_distributed_load_static(lmn, element_list(lmn)%flag, ifac, &      ! Input variables
                    subroutine_parameters(param_index:param_index+nparam-1),nparam, &       ! Input variables
                    element_list(lmn)%n_nodes, local_nodes, &       ! Input variables
                    element_list(lmn)%n_element_properties, element_properties(element_list(lmn)%element_property_index),  &     ! Input variables
                    element_coords, element_dof_increment, element_dof_total,      &                              ! Input variables
                    element_stiffness,element_residual)               ! Output variables

                !     --   Add element stiffness and residual to global array

                nsr = 0
                do i1 = 1, element_list(lmn)%n_nodes
                    node1 = connectivity(i1 + element_list(lmn)%connect_index - 1)
                    do j1 = 1, node_list(node1)%n_dof
                        irow = ieqs(j1 + node_list(node1)%dof_index - 1)
                        nsr = nsr + 1
                        rhs(irow) = rhs(irow) + element_residual(nsr)
                        nsc = 0
                        do i2 = 1, element_list(lmn)%n_nodes
                            node2 = connectivity(i2 + element_list(lmn)%connect_index - 1)
                            do j2 = 1, node_list(node2)%n_dof
                                icol = ieqs(j2 + node_list(node2)%dof_index - 1)
                                nsc = nsc + 1
                                if ( icol==irow ) then
                                    diag(irow) = diag(irow) + element_stiffness(nsr,nsc)
                                else if ( icol>irow ) then
                                    nn = jpoin(icol) + irow - (icol - 1)
                                    aupp(nn) = aupp(nn) + element_stiffness(nsr,nsc)
                                    if ( unsymmetric_stiffness ) alow(nn) = alow(nn) + element_stiffness(nsc,nsr)
                                end if
                            end do
                        end do
                    end do
                end do
            end do
        endif
    end do

    !     -- Prescribed nodal forces
    do k = 1, n_prescribedforces
        if (prescribedforce_list(k)%flag==1) then                                          ! Prescribe dof directly
            force_value = dof_values(prescribedforce_list(k)%index_dof_values)
        else if (prescribedforce_list(k)%flag==2) then                                     ! Interpolate a history table
            iof = history_list(prescribedforce_list(k)%history_number)%index
            nhist = history_list(prescribedforce_list(k)%history_number)%n_timevals
            call interpolate_history_table(history_data(1,iof),nhist,TIME+DTIME,force_value)
        endif
       
        if (prescribedforce_list(k)%node_set==0) then    ! Constrain a single node
            n = prescribedforce_list(k)%node_number
            idof = prescribedforce_list(k)%dof
 
            if (prescribedforce_list(k)%flag==3) then
                iof = subroutineparameter_list(prescribedforce_list(k)%subroutine_parameter_number)%index
                nparam = subroutineparameter_list(prescribedforce_list(k)%subroutine_parameter_number)%n_parameters
                call user_prescribedforce(n,idof,subroutine_parameters(iof),nparam,force_value)
            endif
            irow = ieqs(idof + node_list(n)%dof_index - 1)
            rhs(irow) = rhs(irow) + force_value
        else  ! Constrain a node set
            nnodes = nodeset_list(prescribedforce_list(k)%node_set)%n_nodes
            iof = nodeset_list(prescribedforce_list(k)%node_set)%index
            do i = 1,nnodes
                n = node_lists(iof+i-1)
                idof = prescribedforce_list(k)%dof
                if (prescribedforce_list(k)%flag==3) then
                    iof = subroutineparameter_list(prescribedforce_list(k)%subroutine_parameter_number)%index
                    nparam = subroutineparameter_list(prescribedforce_list(k)%subroutine_parameter_number)%n_parameters
                    call user_prescribedforce(n,idof,subroutine_parameters(iof),nparam,force_value)
                endif
                irow = ieqs(idof + node_list(n)%dof_index - 1)
                rhs(irow) = rhs(irow) + force_value
            end do
        endif
   
    end do

    !     -- Prescribed DOFs
    do k = 1, n_prescribeddof
        ignoredof = .false.
        if (prescribeddof_list(k)%flag==1) then                                          ! Prescribe dof directly
            dofvalue = dof_values(prescribeddof_list(k)%index_dof_values)
        else if (prescribeddof_list(k)%flag==2) then                                     ! Interpolate a history table
            iof = history_list(prescribeddof_list(k)%history_number)%index
            nhist = history_list(prescribeddof_list(k)%history_number)%n_timevals
            call interpolate_history_table(history_data(1,iof),nhist,TIME+DTIME,dofvalue)
        endif
       
        if (prescribeddof_list(k)%node_set==0) then    ! Constrain a single node
            n = prescribeddof_list(k)%node_number
            idof = prescribeddof_list(k)%dof
            if (prescribeddof_list(k)%rate_flag==0) then
                ucur = dof_increment(idof + node_list(n)%dof_index - 1) + dof_total(idof + node_list(n)%dof_index - 1)
            else
                ucur = dof_increment(idof + node_list(n)%dof_index - 1)
            endif
            if (prescribeddof_list(k)%flag==3) then
                iofs = subroutineparameter_list(prescribeddof_list(k)%subroutine_parameter_number)%index
                nparam = subroutineparameter_list(prescribeddof_list(k)%subroutine_parameter_number)%n_parameters
                call user_prescribeddof(n,idof,subroutine_parameters(iofs),nparam,dofvalue,ignoredof)
            endif
            if (ignoredof) cycle                     ! User subroutine requests this DOF not to be applied
            dofvalue_correction = dofvalue - ucur
            call fixdof_direct(idof, n, dofvalue_correction)
        else  ! Constrain a node set
            nnodes = nodeset_list(prescribeddof_list(k)%node_set)%n_nodes
            iof = nodeset_list(prescribeddof_list(k)%node_set)%index
            do i = 1,nnodes
                ignoredof = .false.
                n = node_lists(iof+i-1)
                idof = prescribeddof_list(k)%dof
                if (prescribeddof_list(k)%rate_flag==0) then
                    ucur = dof_increment(idof + node_list(n)%dof_index - 1) + dof_total(idof + node_list(n)%dof_index - 1)
                else
                    ucur = dof_increment(idof + node_list(n)%dof_index - 1)
                endif
                if (prescribeddof_list(k)%flag==3) then
                    iofs = subroutineparameter_list(prescribeddof_list(k)%subroutine_parameter_number)%index
                    nparam = subroutineparameter_list(prescribeddof_list(k)%subroutine_parameter_number)%n_parameters
                    call user_prescribeddof(n,idof,subroutine_parameters(iofs),nparam,dofvalue,ignoredof)
                endif
                if (ignoredof) cycle                     ! User subroutine requests this DOF not to be applied
                dofvalue_correction = dofvalue - ucur
                call fixdof_direct(idof, n, dofvalue_correction)
            end do
        endif
   
    end do
  
    unbalanced_force_norm = dsqrt(dot_product(rhs,rhs))

end subroutine apply_direct_boundaryconditions


!====================Subroutine FIXDOF =======================
subroutine fixdof_direct(idof, node_number, dofvalue)
    use Types
    use Mesh, only : node, node_list
    use Stiffness
    implicit none

    integer, intent( in )      :: idof            ! Degree of freedom to constrain
    integer, intent( in )      :: node_number     ! Node number to constrain
     
    real( prec ), intent( in )    :: dofvalue     ! Value to apply
            

    ! Local Variables
    integer :: i, idis, ihgt,  mod, n, ncol, nn

    !     Subroutine to modify stiffnes matrix so as to prescribe
    !     IDOFth DOF on node NODE

    !     -- Modify diagonal and RHS
    n = ieqs(idof + node_list(node_number)%dof_index - 1)
    !     --  Modify upper half of stiffness
    do ncol = n + 1, neq
        idis = ncol - n
        ihgt = jpoin(ncol) - jpoin(ncol - 1)
        if ( idis<=ihgt ) then
            nn = jpoin(ncol) - idis + 1
            if ( .not.unsymmetric_stiffness ) rhs(ncol) = rhs(ncol) - aupp(nn)*dofvalue
            aupp(nn) = 0.D0
        end if
    end do
    !     --  Modify lower half of stiffness, or...
    if ( unsymmetric_stiffness ) then
        if ( n>1 ) then
            do i = jpoin(n - 1) + 1, jpoin(n)
                alow(i) = 0.D0
            end do
        end if
      !     --  ... symmetrize equations
    else if ( n>1 ) then
        mod = n
        do i = jpoin(n), jpoin(n - 1) + 1, -1
            mod = mod - 1
            rhs(mod) = rhs(mod) - aupp(i)*dofvalue
            aupp(i) = 0.D0
        end do
    end if

    diag(n) = 1.D0
    rhs(n) = dofvalue

end subroutine fixdof_direct



!====================Subroutine solve_direct =======================
subroutine solve_direct

    use Types
    use ParamIO
    use Mesh, only: node, n_nodes, node_list, dof_increment, correction_norm, length_dofs
    use Boundaryconditions, only: lagrange_multipliers, n_constraints
    use Stiffness
    implicit none
    interface
        subroutine backsubstitution(alow, aupp, diag, rhs, jpoin, neq)
            use Types
            use ParamIO
            implicit none
            integer, intent( in )         :: neq
            integer, intent( in )         :: jpoin(:)
            real( prec ), intent( in )    :: alow(:)
            real( prec ), intent( in )    :: aupp(:)
            real( prec ), intent( in )    :: diag(:)
            real( prec ), intent( inout ) :: rhs(:)
        end subroutine backsubstitution
        subroutine LU_decomposition(unsymmetric_stiffness, alow, aupp, diag, jpoin, neq)
            use Types
            use ParamIO
            implicit none

            integer, intent( in )         :: neq
            integer, intent( in )         :: jpoin(:)
            logical, intent( in )         :: unsymmetric_stiffness
            real( prec ), intent( inout ) :: alow(:)
            real( prec ), intent( inout ) :: aupp(:)
            real( prec ), intent( inout ) :: diag(:)
        end subroutine LU_decomposition
    end interface
 
    integer :: n,k,iof,nc

    if ( unsymmetric_stiffness ) then
        call LU_decomposition(unsymmetric_stiffness, alow, aupp, diag, jpoin, neq)
        call backsubstitution(alow, aupp, diag, rhs, jpoin, neq)
    else
        call LU_decomposition(unsymmetric_stiffness, aupp, aupp, diag, jpoin, neq)
        call backsubstitution(aupp, aupp, diag, rhs, jpoin, neq)
    end if

    do n = 1,n_nodes
        iof = node_list(n)%dof_index
        do k = 1,node_list(n)%n_dof
            dof_increment(iof+k-1) = dof_increment(iof+k-1) + rhs(ieqs(iof+k-1))
        end do
    end do
 
    do nc = 1,n_constraints
        lagrange_multipliers(nc) = lagrange_multipliers(nc) + rhs(ieqs(length_dofs+nc))
    end do
 
    correction_norm = dsqrt(dot_product(rhs,rhs))

end subroutine solve_direct

!=====================Subroutine backsubstitution =========================
subroutine backsubstitution(alow, aupp, diag, rhs, jpoin, neq)
    use Types
    use ParamIO
    implicit none

    integer, intent( in )         :: neq
    integer, intent( in )         :: jpoin(:)
    real( prec ), intent( in )    :: alow(:)
    real( prec ), intent( in )    :: aupp(:)
    real( prec ), intent( in )    :: diag(:)
    real( prec ), intent( inout ) :: rhs(:)

    ! Local Variables
    real( prec ) zero
    integer :: is, j, jh, jr
    logical :: foundzerorhs

    data zero/0.D0/

    !     --- Solution of equations stored in profile form
    !     Coefficient matrix must be decomposed using TRI
    !     before calling SOLV

    !     --- Find first nonzero term in rhs

    foundzerorhs = .true.
    do is = 1, neq
        if ( rhs(is) /= zero ) then
            foundzerorhs = .false.
            exit
        endif
    end do
    if (foundzerorhs) then
        write (IOW, 99001)
        rhs = 0.D0
        return
    endif
    !     --- Reduce RHS
    if ( is < neq ) then
        do j = is + 1, neq
            jr = jpoin(j - 1)
            jh = jpoin(j) - jr
            if ( jh > 0 ) rhs(j) = rhs(j) - dot_product(alow(jr + 1:jr+jh), rhs(j - jh:j-1))
        end do
    end if
    !     --- Multiply by inverse of diagonal elements
    rhs(is:neq) = rhs(is:neq)*diag(is:neq)
    !     --- Back substitution
    if ( neq > 1 ) then
        do j = neq, 2, -1
            jr = jpoin(j - 1)
            jh = jpoin(j) - jr
            if (jh>0) rhs(j-jh:j-1) = rhs(j-jh:j-1) - rhs(j)*aupp(jr+1:jr+jh)
        end do
    end if

99001 format ( // ' ***** SOLVER WARNING ***** '/, &
        ' Zero RHS found in SOLV ')

end subroutine backsubstitution


!=====================Subroutine LU_decomposition =========================
subroutine LU_decomposition(unsymmetric_stiffness, alow, aupp, diag, jpoin, neq)
    use Types
    use ParamIO
    implicit none

    integer, intent( in )         :: neq
    integer, intent( in )         :: jpoin(:)
    logical, intent( in )         :: unsymmetric_stiffness
    real( prec ), intent( inout ) :: alow(:)
    real( prec ), intent( inout ) :: aupp(:)
    real( prec ), intent( inout ) :: diag(:)

    ! Local Variables
    real( prec ) :: daval, dd, dfig, dimn, dimx, one, tol, zero
    integer      :: i, id, idh, ie, ifig, ih, is, j, jd, jh, jr, jrh

    data zero, one/0.D0, 1.D0/, tol/0.5D-07/

    !     Triangular decomposition of a matrix stored in profile form
    !     A decomposed to A = LU

    !     ALOW(I)  Coefficients of stiffness matrix below diagonal,
    !     stored rowwise
    !     Replaced by factor DIAG . U on exit
    !     AUPP(I)   Coefficients above diagonal, stored columnwise
    !     Replaced by L on exit
    !     DIAG(I)  Diagonals of stiffness matrix, replaced by
    !     reciprocal diagonals of U
    !     JPOIN(I) Pointer to last element in each row/column
    !     of ALOW/AUPP respectively
    !     NEQ      No. of equations
    !     IFL      Set to .TRUE for unsymmetric matrices

    !     Detailed description of storage:
    !     For array
    !     |  K11  K12   K13   0   0  |
    !     |  K21  K22   K23  K24  0  |
    !     |  K31  K32   K33  K34 K35 |
    !     |  0    K42   K43  K44 K45 |
    !     |  0    0     K53  K54 K55 |

    !     AUPP =  [K12   K13 K23   K24 K34   K35 K45]
    !     ALOW = [K21   K31 K32   K42 K43   K53 K54]
    !     DIAG = [K11 K22 K33 K44 K55]
    !     JPOIN = [0  1  3  5  7]

    !     --- Set initial values for conditioning check
    dimx = zero
    dfig = zero
    !  do i = 1, neq
    !    dimn = max(dimn, dabs(diag(i)))
    !  end do
    dimn = maxval(dabs(diag))

    !     --- Loop through columns to perform triangular decomposition
    jd = 1
    do j = 1, neq
        jr = jd + 1
        jd = jpoin(j)
        jh = jd - jr
        if ( jh > 0 ) then
            is = j - jh
            ie = j - 1
            !     ---  If diagonal is zero compute a norm for singularity test
            if ( diag(j) == zero ) daval =  sum(dabs(aupp(jr:jr+jh)))
            do i = is, ie
                jr = jr + 1
                id = jpoin(i)
                ih = min(id - jpoin(i - 1), i - is + 1)
                if ( ih > 0 ) then
                    jrh = jr - ih
                    idh = id - ih + 1
                    aupp(jr) = aupp(jr) - dot_product(aupp(jrh:jrh+ih-1), alow(idh:idh+ih-1))
                    if ( unsymmetric_stiffness ) alow(jr) = alow(jr) - dot_product(alow(jrh:jrh+ih-1), aupp(idh:idh+ih-1))
                end if
            end do
        end if
        !     ---   Reduce the diagonal
        if ( jh >= 0 ) then
            dd = diag(j)
            jr = jd - jh
            jrh = j - jh - 1
            call dredu(alow(jr:jr+jh), aupp(jr:jr+jh+1), diag(jrh:jrh+jh+1), jh + 1, unsymmetric_stiffness, diag(j) )
             !     ---   Check for conditioning errors and print warnings
            if ( dabs(diag(j)) < tol*dabs(dd) ) write (IOW, 99001) j
            if ( diag(j) == zero ) then
                if ( j/=neq ) write (IOW, 99003) j
            end if
            if ( dd == zero .and. jh > 0 ) then
                if ( dabs(diag(j)) < tol*daval ) write (IOW, 99004) j
            end if
        end if

        !     ---    Store reciprocal of diagonal, compute condition checks
        if ( diag(j) /= zero ) then
            dimx = dmax1(dimx, dabs(diag(j)))
            dimn = dmin1(dimn, dabs(diag(j)))
            dfig = dmax1(dfig, dabs(dd/diag(j)))
            diag(j) = one/diag(j)
        else
            diag(j) = one/(tol*dimn)
        end if

    end do

    !     ---  Print conditioning information
    dd = zero
    if ( dimn /= zero ) dd = dimx/dimn
    ifig = int(dlog10(dfig) + 0.6)
    if ( IWT == 1 ) write (IOW, 99005) dimx, dimn, dd, ifig


99001 format (/' **** DIRECT SOLVER WARNING 1 **** '/  &
        '  Loss of at least 7 digits in reducing diagonal', ' of equation ', i5)
99003 format (/' **** DIRECT SOLVER WARNING 2 **** '/  &
        '  Reduced diagonal is zero for equation ', i5)
99004 format (/' **** DIRECT SOLVER WARNING 3 **** '/  &
        '  Rank failure for zero unreduced diagonal in ', 'equation', i5)
99005 format ( // ' Direct Solver has completed stiffness decomposition '/  &
        '    Conditioning information: '/  &
        '      Max diagonal in reduced matrix:   ',  &
        e11.4/'      Min diagonal in reduced matrix:   ',  &
        e11.4/'      Ratio:                            ',  &
        e11.4/'      Maximum no. diagonal digits lost: ', i3)

end subroutine LU_decomposition

!========================Subroutine DREDU =========================
subroutine dredu(alow, aupp, diag, jh, ifl, dj)
    use Types
    implicit none

    integer, intent( in )         :: jh
    logical, intent( in )         :: ifl
    real( prec ), intent( inout ) :: alow(jh)
    real( prec ), intent( inout ) :: aupp(jh)
    real( prec ), intent( in )    :: diag(jh)
    real( prec ), intent( inout )   :: dj

    ! Local Variables
    real( prec ) :: ud
  
    integer      :: k

    !     Reduce diagonal element in triangular decomposition
    do k = 1, jh
        ud = aupp(k)*diag(k)
        dj = dj - alow(k)*ud
        aupp(k) = ud
    end do

    !     --- Finish computation of column of alow for unsymmetric matrices
    if ( ifl ) then
        alow(1:jh) = alow(1:jh)*diag(1:jh)
    !    do j = 1, jh
    !      alow(j) = alow(j)*diag(j)
    !    end do
    end if

end subroutine dredu


!========================Subroutine compute_profile ====================
subroutine compute_profile
    use Types
    use ParamIO
    use Mesh, only : n_nodes, n_elements, node, element, node_list, element_list, connectivity, length_dofs
    use Boundaryconditions, only : constraint, nodeset, nodeset_list,node_lists, constraint_list, n_constraints
    use Stiffness, only : node_numbers, node_order_index, neq, jpoin, ieqs
    implicit none

  
    ! Local Variables
    real( prec ) :: bwmn, bwrms
    integer      :: i, ibwmax, ibwmn, ibwrms, ipn, j, jeq, jpold, lmn, nn
    integer      :: mineq, mpc, n, nnode, jh
    integer      :: iofc, iofn, dof, iofd, node1, node2, dof1, dof2, status, ns, dofset

    !     Subroutine to initialize profile storage of global
    !     stiffness matrix
    !     IEQS(J)       Global equation numbers
    !     JPOIN(I)   Pointer to last element in each row/column
    !     of ALOW/AUPP respectively

    !     Compute profile of global arrays

    !
    !     Generate an index table specifying order of node numbers
    !     Array JPOIN is used as temp storage for the index
  
    ! Count # of equations
    n = 0
    do i = 1,n_nodes
        n = n + node_list(i)%n_dof
    end do
    n = n + n_constraints
  
    if (.not.allocated(ieqs)) then
        neq = n
        allocate(ieqs(neq), stat=status)
        allocate(jpoin(neq), stat=status)
        if (status /=0) then
            write(IOW,*) ' Error in subroutine profile_equations '
            write(IOW,*) ' Unable to allocate storage for equation numebers '
            stop
        endif
    else if (n/=neq) then
        neq = n
        deallocate(ieqs)
        deallocate(jpoin)
        allocate(ieqs(neq), stat=status)
        allocate(jpoin(neq), stat=status)
        if (status /=0) then
            write(IOW,*) ' Error in subroutine profile_equations '
            write(IOW,*) ' Unable to allocate storage for equation numebers '
            stop
        endif
    endif

    ! Compute equation numbers
    neq = 0
    do i = 1, n_nodes+n_constraints
        n = node_order_index(i)
        if (n<n_nodes+1) then
            do j = 1, node_list(n)%n_dof
                neq = neq + 1
                ipn = node_list(n)%dof_index + j - 1
                ieqs(ipn) = neq
            end do
        else
            neq = neq + 1
            ieqs(length_dofs+n-n_nodes) = neq
        endif
    end do
    !     ---  Compute column heights
    jpoin = 0
    do lmn = 1, n_elements      !     ---  Loop over elements
        mineq = neq
        nnode = element_list(lmn)%n_nodes
        iofc = element_list(lmn)%connect_index
        do i = 1, nnode           !     ---    Loop over nodes on element
            n = connectivity(i + iofc - 1)
            iofn = node_list(n)%dof_index    !     ---      Find smallest eqn. no. on current element
            do j = 1, node_list(n)%n_dof
                jeq = ieqs(j + iofn - 1)
                mineq = min(mineq, jeq)
            end do
        end do
        !     ---    Current column heights for all other eqs on same element
        do i = 1, nnode
            n = connectivity(i + iofc - 1)
            iofn = node_list(n)%dof_index
            do j = 1, node_list(n)%n_dof
                jeq = ieqs(j + iofn - 1)
                jpold = jpoin(jeq)
                jpoin(jeq) = max(jpold, jeq - mineq)
            end do
        end do
    end do
    !     ---  Loop over constraints
    do mpc = 1, n_constraints
        mineq = neq
        if (constraint_list(mpc)%flag<3) then
            node1 = constraint_list(mpc)%node1
            dof1 = constraint_list(mpc)%dof1
            node2 = constraint_list(mpc)%node2
            dof2 = constraint_list(mpc)%dof2
            jeq = ieqs(node_list(node1)%dof_index+dof1-1)
            mineq = min(mineq,jeq)
            jeq = ieqs(node_list(node2)%dof_index+dof2-1)
            mineq = min(mineq,jeq)
            jeq = ieqs(length_dofs+mpc)
            mineq = min(mineq, jeq)
            !     ---    Current column heights for all other eqs on same constraints
            jeq = ieqs(node_list(node1)%dof_index+dof1-1)
            jpold = jpoin(jeq)
            jpoin(jeq) = max(jpold,jeq-mineq)
            jeq = ieqs(node_list(node2)%dof_index+dof2-1)
            jpold = jpoin(jeq)
            jpoin(jeq) = max(jpold,jeq-mineq)
            jeq = ieqs(length_dofs+mpc)
            jpold = jpoin(jeq)
            jpoin(jeq) = max(jpold, jeq - mineq)
        else
            mineq = neq
            ns = constraint_list(mpc)%node1
            dofset = constraint_list(mpc)%node2
            nnode = nodeset_list(ns)%n_nodes
            iofc = nodeset_list(ns)%index
            iofd = nodeset_list(dofset)%index
            do i = 1, nnode           !     ---    Loop over nodes in set
                n = node_lists(i + iofc - 1)
                dof = node_lists(i + iofd - 1)
                iofn = node_list(n)%dof_index    !     ---      Find smallest eqn. no. on current element
                jeq = ieqs(dof + iofn - 1)
                mineq = min(mineq, jeq)
            end do
            jeq = ieqs(length_dofs+mpc)
            mineq = min(mineq, jeq)
            !     ---    Current column heights for all other eqs on same element
            do i = 1, nnode           !     ---    Loop over nodes in set
                n = node_lists(i + iofc - 1)
                dof = node_lists(i + iofd - 1)
                iofn = node_list(n)%dof_index    !     ---      Find smallest eqn. no. on current element
                jeq = ieqs(dof + iofn - 1)
                jpold = jpoin(jeq)
                jpoin(jeq) = max(jpold, jeq-mineq)
            end do
            jeq = ieqs(length_dofs+mpc)
            jpold = jpoin(jeq)
            jpoin(jeq) = max(jpold, jeq-mineq)
        endif

    end do

    !     ---  Compute diagonal pointers for profile and measure of
    !     size of stiffness matrix

    ibwmax = 0
    bwmn = 0.D0
    bwrms = 0.D0
    jpoin(1) = 0
    do n = 2, neq
        ibwmax = max(ibwmax, jpoin(n))
        bwmn = bwmn + jpoin(n)
        bwrms = bwrms + jpoin(n)*jpoin(n)
        jpoin(n) = jpoin(n) + jpoin(n - 1)
    end do
    ibwmn = int(bwmn/dble(neq) + 0.5D0)
    ibwrms = int(dsqrt(bwrms/dble(neq)) + 0.5D0)

    if ( IWT==1 ) write (IOW, 99002) neq, ibwmax, ibwmn, ibwrms, jpoin(neq)

    !     Check profile for errors
    do j = 2, neq
        nn = jpoin(j)
        if ( nn<0 ) then
            write (IOW, 99004) nn
            stop
        end if
        jh = jpoin(j) - jpoin(j - 1)
        if ( jh>j ) then
            write (IOW, 99005)
            stop
        end if
    end do


99002 format ( // ' Direct Solver Profiler has completed profile computation ', /,  &
        '     Total number of equations ', I10/,  &
        '     Maximum half bandwidth:   ', I10/,  &
        '     Mean half bandwidth:      ', I10/,  &
        '     RMS half bandwidth:       ', I10/,  &
        '     Size of stiffness matrix: ', I10)
99004 format ( // ' ERROR DETECTED IN STIFFNESS PROFILE '/  &
        '   Profile pointer is negative '/  &
        '   Pointer value ', I10)
99005 format ( // ' ERROR IN STIFFNESS PROFILE '/  &
        '   Invalid column height detected in profile ')

end subroutine compute_profile

subroutine allocate_direct_stiffness
    use Types
    use ParamIO

    use Stiffness, only : unsymmetric_stiffness,neq,jpoin,aupp,alow,diag,rhs
    implicit none

    integer :: status

    if (allocated(diag)) deallocate(diag)
    if (allocated(aupp)) deallocate(aupp)
    if (allocated(alow)) deallocate(alow)
    if (allocated(rhs))  deallocate(rhs)

    allocate(diag(neq), stat = status)
    allocate(rhs(neq), stat = status)
    allocate(aupp(jpoin(neq)), stat = status)
    if (unsymmetric_stiffness) allocate(alow(jpoin(neq)), stat = status)
 
    if (status /=0) then
        write(IOW,*) ' Error in subroutine allocate_direct_stiffness'
        write(IOW,*) ' Unable to allocate storage for equation numebers '
        stop
    endif
 
    aupp = 0.d0
    rhs = 0.d0
    diag = 0.d0
    if (unsymmetric_stiffness) alow = 0.d0
 
    return

end subroutine allocate_direct_stiffness
