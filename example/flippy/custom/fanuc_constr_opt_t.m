function nlp = fanuc_constr_opt_t(nlp, bounds, varargin)
    % add aditional custom constraints
    
    plant = nlp.Plant;
    
    
    % event
    % extract the event function object using the index
    event_obj = plant.EventFuncs.deltafinal;
    % impose the NLP constraints (unilateral constraints)
    event_obj.imposeNLPConstraint(nlp);
    % update the upper bound at the last node to be zero (to ensure equality)
    event_cstr_name = event_obj.ConstrExpr.Name;
    updateConstrProp(nlp,event_cstr_name,'last','ub',0);
    
    
    
%     % relative degree 1 output
%     plant.VirtualConstraints.vel.imposeNLPConstraint(nlp, bounds.vel.ep, 0);
    
    % relative degree 2 outputs
    plant.VirtualConstraints.pos.imposeNLPConstraint(nlp, [bounds.pos.kp,bounds.pos.kd], [1,1]);
    % tau boundary [0,1]
%     tau = plant.VirtualConstraints.pos.PhaseFuncs{1};
%     t = SymVariable('t');
%     k = SymVariable('k');
%     T  = SymVariable('t',[2,1]);
%     nNode = SymVariable('nNode');
%     tsubs = T(1) + ((k-1)./(nNode-1)).*(T(2)-T(1));
%     tau_new = subs(tau,t,tsubs);
%     if ~isempty(plant.VirtualConstraints.pos.PhaseParams)
%         p = {SymVariable(tomatrix(plant.VirtualConstraints.pos.PhaseParams(:)))};
%         p_name = plant.VirtualConstraints.pos.PhaseParamName;
%     else
%         p = {};
%         p_name = {};
%     end
    
%     tau_new_fun = SymFunction(['tau_bound_',plant.Name], tau_new, [{T},p],{k,nNode});
%     addNodeConstraint(nlp, tau_new_fun, [{'T'},p_name], 'first', 0, 0, 'Nonlinear',{1,nlp.NumNode});
%     addNodeConstraint(nlp, tau_new_fun, [{'T'},p_name], 'last', 1, 1, 'Nonlinear',{nlp.NumNode,nlp.NumNode});
    
    spatula_link = plant.Links(getLinkIndices(plant, 'spatula'));
    spatula_frame = spatula_link.Reference;
    spatula = CoordinateFrame(...
        'Name','EndEff',...
        'Reference',spatula_frame,...
        'Offset',[0 0.0298709 0.2022645],...
        'R',[0,0,0]... % z-axis is the normal axis, so no rotation required
        );
    p_spatula = getCartesianPosition(plant,spatula);
    x = plant.States.x;
    dx = plant.States.dx;
    ddx = plant.States.ddx;
   
    
    % these are the wrist constraints 
    q_spatula = SymFunction(['q_spatula_' plant.Name],x(end-1),{x});
    addNodeConstraint(nlp, q_spatula, {'x'}, 'first', 0, 0, 'Nonlinear');
    addNodeConstraint(nlp, q_spatula, {'x'}, 'last', pi, pi, 'Nonlinear');   
    
    n_node = nlp.NumNode;
    p_z = p_spatula(3) - 0.5297;
    p_z_func = SymFunction(['endeffclearance_sca_' plant.Name],p_z,{x});
    addNodeConstraint(nlp, p_z_func, {'x'}, n_node, 0.03, 0.03, 'Nonlinear');
    addNodeConstraint(nlp, p_z_func, {'x'}, 1, 0.0, 0.0, 'Nonlinear');
%     addNodeConstraint(nlp, p_z_func, {'x'}, 'all', 0.0, 0.4, 'Nonlinear');
    addNodeConstraint(nlp, p_z_func, {'x'}, round(n_node/2), 0.1, 0.3, 'Nonlinear');
    
    
    p_x = p_spatula(1);
    p_x_func = SymFunction(['endeffx_sca_' plant.Name],p_x,{x});
    addNodeConstraint(nlp, p_x_func, {'x'}, 1, 0.8734, 0.8734, 'Nonlinear');
    addNodeConstraint(nlp, p_x_func, {'x'}, round(n_node), 0.8734, 0.8734, 'Nonlinear');
    
    p_y = p_spatula(2);
    p_y_func = SymFunction(['endeffy_sca_' plant.Name],p_y,{x});
    addNodeConstraint(nlp, p_y_func, {'x'}, 1, 0.0, 0.0, 'Nonlinear');
    addNodeConstraint(nlp, p_y_func, {'x'}, round(n_node), 0.0, 0.0, 'Nonlinear');
%     addNodeConstraint(nlp, p_y_func, {'x'}, round(n_node/3), 0.05, 0.3, 'Nonlinear');
    
    %% these are slipping constraints being added

    v_x = jacobian(p_spatula(1), x)*dx ;
    v_y = jacobian(p_spatula(2), x)*dx ;
    v_z = jacobian(p_spatula(3), x)*dx ;
    
    a_x = jacobian(v_x,dx)*ddx + jacobian(v_x,x)*dx;
    a_y = jacobian(v_y,dx)*ddx + jacobian(v_y,x)*dx;
    a_z = jacobian(v_z,dx)*ddx + jacobian(v_z,x)*dx;

    % get orientation of the end effector in terms of euler angles
    orientation = getEulerAngles(plant,spatula);
    g = 9.81; % acceleration due to gravity - a constant
    mu = 0.26; % coefficient of restitution
    
%     o_x = orientation(1);
    o_x = orientation(1);
    o_y = orientation(2);
    
    % these are the ee constraints on the end effector
    q_endeffx = SymFunction(['q_endeffx_' plant.Name],o_x,{x});
    q_endeffy = SymFunction(['q_endeffy_' plant.Name],o_y,{x});
%     addNodeConstraint(nlp, q_endeffy, {'x'}, 'all', 0, 0, 'Nonlinear');
%     addNodeConstraint(nlp, q_endeff, {'x'}, 'first', 0, 0, 'Nonlinear');
%     addNodeConstraint(nlp, q_endeff, {'x'}, 'last', pi, pi, 'Nonlinear'); 
    
    % these are the slipping constraints
    a_slip_y = a_z*sin(o_x) + a_y*cos(o_x) + g*sin(o_x) ...
                - mu* ( - a_y*sin(o_x) + a_z*cos(o_x) + g*cos(o_x));
    a_slip_x = a_z*sin(o_y)-a_x*cos(o_y)+g*sin(o_y) ...
                - mu* (a_x*sin(o_y) + a_z*cos(o_y) + g*cos(o_y));
            
%             a_z*sin(theta)-a_y*cos(theta)+g*sin(theta) ...
%                 - mu* (a_y*sin(theta) + a_z*cos(theta) + g*cos(theta))
            
    a_slip_y_func = SymFunction(['endeffoy_sca_' plant.Name],a_slip_y,{x,dx,ddx});
    addNodeConstraint(nlp, a_slip_y_func, {'x','dx','ddx'}, 1:round(0.8*n_node), -Inf, 0.0, 'Nonlinear');
            
    a_slip_x_func = SymFunction(['endeffox_sca_' plant.Name],a_slip_x,{x,dx,ddx});
%     addNodeConstraint(nlp, a_slip_x_func, {'x','dx','ddx'}, 1:round(0.8*n_node), -Inf, 0.0, 'Nonlinear');
    
    
end